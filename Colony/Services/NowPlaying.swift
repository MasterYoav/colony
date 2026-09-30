//
//  NowPlaying.swift
//  Colony
//
//  The device's own music player, as seen and controlled from the sidebar.
//
//  - iPhone, iPad, Vision Pro: `MPMusicPlayerController.systemMusicPlayer`, the same
//    player Control Center and the Lock Screen drive (the Music app's queue).
//  - Mac: the Music app, through its scripting interface (Apple events). The sandbox
//    only lets Colony talk to Music's playback commands (see Colony-macOS.entitlements),
//    and macOS asks the user once before the first command.
//
//  Nothing is stored or sent anywhere; the state lives in memory while the app runs.
//

import Foundation
import Observation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "yoavperetz.Colony", category: "NowPlaying")

@MainActor
@Observable
final class NowPlaying {
    struct Track: Equatable {
        var id: String
        var title: String
        var artist: String
        var album: String
        /// Seconds; 0 for streams without a length (radio).
        var duration: TimeInterval
    }

    enum Access: Equatable {
        /// Haven't asked yet. The first control press asks.
        case notDetermined
        case granted
        /// The user said no; they can change it in Settings.
        case denied
        /// No music player on this device (the Music app is missing, or a simulator).
        case unavailable
    }

    private(set) var access: Access = .notDetermined
    private(set) var track: Track?
    private(set) var artwork: Data?
    private(set) var isPlaying = false
    /// Mac only: Music's own volume is 0.
    private(set) var isMuted = false
    /// Playhead at `positionDate`; `elapsed(at:)` extrapolates while playing.
    private var position: TimeInterval = 0
    private var positionDate = Date.now

    private let backend: NowPlayingBackend

    init() {
        #if os(macOS)
        backend = MusicAppBackend()
        #else
        backend = SystemMusicPlayerBackend()
        #endif
        backend.onChange = { [weak self] in self?.refresh() }
    }

    // MARK: Reading

    func elapsed(at date: Date) -> TimeInterval {
        let value = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        guard let duration = track?.duration, duration > 0 else { return max(0, value) }
        return min(max(0, value), duration)
    }

    private var pollTask: Task<Void, Never>?

    /// Starts listening. Doesn't prompt: without permission it only notes the state.
    /// Besides the player's own change notifications, it re-reads every few seconds
    /// (a cheap call) so seeks and changes made elsewhere show up too.
    func start() {
        access = backend.access(asking: false)
        backend.startObserving()
        refresh()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                self?.refresh()
            }
        }
    }

    func refresh() {
        Task {
            guard backend.access(asking: false) != .unavailable else {
                access = .unavailable
                return
            }
            let state = await backend.state()
            access = backend.access(asking: false)
            if let state { apply(state) } else { clear() }
        }
    }

    private func apply(_ state: PlayerState) {
        if state.track?.id != track?.id {
            artwork = nil
            if state.track != nil {
                Task { artwork = await backend.artwork() }
            }
        }
        track = state.track
        isPlaying = state.isPlaying
        isMuted = state.isMuted
        position = state.position
        positionDate = .now
    }

    private func clear() {
        track = nil
        artwork = nil
        isPlaying = false
        position = 0
    }

    // MARK: Controls

    func togglePlayPause() {
        perform { backend in
            await backend.send(.togglePlayPause)
        } optimistic: {
            self.position = self.elapsed(at: .now)
            self.positionDate = .now
            self.isPlaying.toggle()
        }
    }

    func next() { perform { await $0.send(.next) } }
    func previous() { perform { await $0.send(.previous) } }

    func seek(to seconds: TimeInterval) {
        perform { await $0.send(.seek(seconds)) } optimistic: {
            self.position = seconds
            self.positionDate = .now
        }
    }

    func toggleMute() {
        perform { await $0.send(.toggleMute) } optimistic: { self.isMuted.toggle() }
    }

    func openPlayerApp() {
        backend.openApp()
    }

    /// Asks for permission if needed, then runs `command` and re-reads the state.
    private func perform(_ command: @escaping (NowPlayingBackend) async -> Void, optimistic: (() -> Void)? = nil) {
        Task {
            if access != .granted {
                access = await backend.requestAccess()
            }
            guard access == .granted else { return }
            optimistic?()
            await command(backend)
            try? await Task.sleep(for: .milliseconds(250))
            refresh()
        }
    }

    // MARK: Formatting

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Where the user changes the permission.
    var settingsHint: String {
        #if os(macOS)
        "Allow Colony to control Music in System Settings › Privacy & Security › Automation."
        #else
        "Allow Colony to access Media & Apple Music in Settings › Privacy & Security."
        #endif
    }
}

// MARK: - Backends

struct PlayerState {
    var track: NowPlaying.Track?
    var isPlaying: Bool
    var position: TimeInterval
    var isMuted: Bool
}

enum PlayerCommand {
    case togglePlayPause, next, previous, toggleMute
    case seek(TimeInterval)
}

@MainActor
protocol NowPlayingBackend: AnyObject {
    var onChange: (() -> Void)? { get set }
    func access(asking: Bool) -> NowPlaying.Access
    func requestAccess() async -> NowPlaying.Access
    func startObserving()
    func state() async -> PlayerState?
    func artwork() async -> Data?
    func send(_ command: PlayerCommand) async
    func openApp()
}

#if os(macOS)
import AppKit
import CoreServices

/// Music.app over Apple events. Every script runs on one serial background queue
/// (NSAppleScript isn't thread-safe and a slow reply mustn't stall the UI).
@MainActor
final class MusicAppBackend: NowPlayingBackend {
    static let bundleID = "com.apple.Music"
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "Colony.MusicScripting", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    /// Volume to restore when un-muting.
    private var volumeBeforeMute = 50

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    private var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil
    }

    /// Last answer macOS gave (a script ran, or was refused). Remembered across launches
    /// so the bar doesn't flash "not allowed" while Music is closed.
    private var known: NowPlaying.Access {
        get {
            switch UserDefaults.standard.string(forKey: "music.access") {
            case "granted": .granted
            case "denied": .denied
            default: .notDetermined
            }
        }
        set {
            UserDefaults.standard.set(newValue == .granted ? "granted" : newValue == .denied ? "denied" : nil, forKey: "music.access")
        }
    }

    func access(asking: Bool) -> NowPlaying.Access {
        isInstalled ? known : .unavailable
    }

    func requestAccess() async -> NowPlaying.Access {
        guard isInstalled else { return .unavailable }
        if !isRunning {
            // Launch Music quietly so there's something to ask about.
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // A harmless read; the first one shows macOS's consent alert.
        _ = await run("tell application \"Music\" to get player state")
        return known
    }

    func startObserving() {
        guard observers.isEmpty else { return }
        // Music broadcasts this on every play, pause, skip and track change.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                MainActor.assumeIsolated { self?.onChange?() }
            })
        }
    }

    func state() async -> PlayerState? {
        guard isRunning else { return nil }
        // Never `tell` Music unless it's running: that would launch it.
        // Properties are read straight off `current track` (not through a saved
        // reference, which the sandbox treats as a library read), each on its own so
        // one refusal doesn't lose the rest.
        let source = """
        tell application "Music"
            set s to player state as string
            set v to 100
            try
                set v to sound volume
            end try
            if s is "stopped" then return {s, v}
            set n to ""
            set a to ""
            set al to ""
            set d to 0
            set p to 0
            set tid to ""
            try
                set n to name of current track
            end try
            try
                set a to artist of current track
            end try
            try
                set al to album of current track
            end try
            try
                set d to duration of current track
            end try
            try
                set p to player position
            end try
            try
                set tid to persistent ID of current track
            end try
            return {s, v, n, a, al, d, p, tid}
        end tell
        """
        guard let list = await run(source), list.numberOfItems >= 2 else { return nil }
        let stateName = list.atIndex(1)?.stringValue ?? "stopped"
        let volume = Int(list.atIndex(2)?.int32Value ?? 50)
        if volume > 0 { volumeBeforeMute = volume }
        guard list.numberOfItems >= 8 else {
            return PlayerState(track: nil, isPlaying: false, position: 0, isMuted: volume == 0)
        }
        let title = list.atIndex(3)?.stringValue ?? ""
        let track = NowPlaying.Track(
            id: (list.atIndex(8)?.stringValue).flatMap { $0.isEmpty ? nil : $0 } ?? title,
            title: title,
            artist: list.atIndex(4)?.stringValue ?? "",
            album: list.atIndex(5)?.stringValue ?? "",
            duration: list.atIndex(6)?.doubleValue ?? 0
        )
        return PlayerState(track: track, isPlaying: stateName == "playing", position: list.atIndex(7)?.doubleValue ?? 0, isMuted: volume == 0)
    }

    func artwork() async -> Data? {
        guard isRunning else { return nil }
        let descriptor = await run("""
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            end try
        end tell
        """)
        guard let data = descriptor?.data, !data.isEmpty else { return nil }
        return data
    }

    func send(_ command: PlayerCommand) async {
        let line: String
        switch command {
        case .togglePlayPause: line = "playpause"
        case .next: line = "next track"
        case .previous: line = "previous track"
        case .seek(let seconds): line = "set player position to \(max(0, seconds))"
        case .toggleMute:
            line = "if sound volume is 0 then\n set sound volume to \(volumeBeforeMute)\n else\n set sound volume to 0\n end if"
        }
        _ = await run("tell application \"Music\"\n\(line)\nend tell")
    }

    func openApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Runs a script off the main thread and records whether macOS allowed it.
    private func run(_ source: String) async -> NSAppleEventDescriptor? {
        let (result, code) = await withCheckedContinuation { (continuation: CheckedContinuation<(NSAppleEventDescriptor?, Int), Never>) in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                let code = (error?[NSAppleScript.errorNumber] as? Int) ?? 0
                if let error { log.error("Music script failed: \(error, privacy: .public)") }
                continuation.resume(returning: (error == nil ? result : nil, code))
            }
        }
        switch code {
        case 0: known = .granted
        case Int(errAEEventNotPermitted), -1744: known = .denied // -1744: consent needed but can't ask
        default: break // Music busy, no current track, etc.
        }
        return result
    }
}

#else
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif

/// The system music player (Music app queue), as Control Center sees it.
@MainActor
final class SystemMusicPlayerBackend: NowPlayingBackend {
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var player: MPMusicPlayerController { .systemMusicPlayer }

    func access(asking: Bool) -> NowPlaying.Access {
        #if targetEnvironment(simulator)
        return .unavailable
        #else
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
        #endif
    }

    func requestAccess() async -> NowPlaying.Access {
        #if targetEnvironment(simulator)
        return .unavailable
        #else
        _ = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
        return access(asking: false)
        #endif
    }

    func startObserving() {
        guard observers.isEmpty, access(asking: false) != .unavailable else { return }
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange, .MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            })
        }
        #if canImport(UIKit)
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        })
        #endif
    }

    func state() async -> PlayerState? {
        guard access(asking: false) == .granted else { return nil }
        let isPlaying = player.playbackState == .playing
        guard let item = player.nowPlayingItem else {
            return PlayerState(track: nil, isPlaying: false, position: 0, isMuted: false)
        }
        let track = NowPlaying.Track(
            id: String(item.persistentID),
            title: item.title ?? "Unknown",
            artist: item.artist ?? "",
            album: item.albumTitle ?? "",
            duration: item.playbackDuration
        )
        return PlayerState(track: track, isPlaying: isPlaying, position: player.currentPlaybackTime.isFinite ? player.currentPlaybackTime : 0, isMuted: false)
    }

    func artwork() async -> Data? {
        #if canImport(UIKit)
        guard let art = player.nowPlayingItem?.artwork, let image = art.image(at: CGSize(width: 120, height: 120)) else { return nil }
        return image.jpegData(compressionQuality: 0.85)
        #else
        return nil
        #endif
    }

    func send(_ command: PlayerCommand) async {
        switch command {
        case .togglePlayPause:
            if player.playbackState == .playing { player.pause() } else { player.play() }
        case .next: player.skipToNextItem()
        case .previous:
            // Like the system: restart the song unless we're at its very start.
            if player.currentPlaybackTime > 3 { player.skipToBeginning() } else { player.skipToPreviousItem() }
        case .seek(let seconds): player.currentPlaybackTime = seconds
        case .toggleMute: break // iOS apps can't set the system volume; the route picker stands in.
        }
    }

    func openApp() {
        #if canImport(UIKit)
        if let url = URL(string: "music://") { UIApplication.shared.open(url) }
        #endif
    }
}
#endif
