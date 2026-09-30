//
//  NowPlayingBar.swift
//  Colony
//
//  The media controller at the bottom of the sidebar, modelled on the reference:
//  a compact glass bar (source, previous, play/pause, next, volume) that grows
//  upward on hover or tap to show the artwork, a scrolling title, artist, times and
//  a scrubber. It drives the device's own player (see NowPlaying).
//

import SwiftUI
#if os(iOS)
import AVKit
#endif

struct NowPlayingBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var isHovering = false
    /// Pinned open by a tap (stays open when the pointer leaves).
    @State private var isPinned = false

    private var player: NowPlaying { app.nowPlaying }

    var body: some View {
        let open = (isExpanded || isPinned) && player.track != nil

        VStack(spacing: 0) {
            if open {
                details
                    .transition(detailsTransition)
            }
            controls
        }
        .padding(.horizontal, 10)
        .padding(.top, open ? 10 : 0)
        .background {
            RoundedRectangle(cornerRadius: open ? 16 : 13, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: open ? 16 : 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
                        .blendMode(.plusLighter)
                }
                .shadow(color: .black.opacity(open ? 0.14 : 0.06), radius: open ? 12 : 4, y: open ? 5 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: open ? 16 : 13, style: .continuous))
        .contentShape(.rect)
        .onHover { hovering in
            isHovering = hovering
            setExpanded(hovering)
        }
        .onTapGesture {
            guard player.track != nil else { return }
            withAnimation(springAnimation) { isPinned.toggle() }
        }
        .animation(springAnimation, value: open)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .onChange(of: player.track == nil) { _, gone in
            if gone { isPinned = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing")
    }

    // MARK: Motion

    /// A soft spring, like the reference: the card grows from the bottom edge and the
    /// details rise into place. Under Reduce Motion it becomes a short fade.
    private var springAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    private var detailsTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.96, anchor: .bottom)),
                removal: .opacity.combined(with: .offset(y: 8))
            )
    }

    private func setExpanded(_ value: Bool) {
        // A short hover delay so sweeping past the bar doesn't pop it open.
        Task {
            if value { try? await Task.sleep(for: .milliseconds(180)) }
            guard value == isHovering else { return }
            withAnimation(springAnimation) { isExpanded = value }
        }
    }

    // MARK: Details (expanded)

    @ViewBuilder
    private var details: some View {
        if let track = player.track {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ArtworkView(data: player.artwork, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: track.title, isActive: player.isPlaying && !reduceMotion)
                            .appFont(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(height: 17)
                        Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                            .appFont(.system(size: 11.5))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    iconButton("arrow.up.forward.app", label: "Open Music", size: 12) { player.openPlayerApp() }
                    iconButton("xmark", label: "Close", size: 11) {
                        withAnimation(springAnimation) {
                            isPinned = false
                            isExpanded = false
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                ProgressRow(duration: track.duration, isPlaying: player.isPlaying, elapsed: player.elapsed(at:)) { seconds in
                    player.seek(to: seconds)
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: Controls (always visible)

    private var controls: some View {
        HStack(spacing: 0) {
            Button { player.openPlayerApp() } label: {
                sourceBadge
            }
            .buttonStyle(.plain)
            .help(sourceName)
            .accessibilityLabel("Open \(sourceName)")

            Spacer(minLength: 4)
            transport("backward.end.fill", label: "Previous") { player.previous() }
            Spacer(minLength: 4)
            playPause
            Spacer(minLength: 4)
            transport("forward.end.fill", label: "Next") { player.next() }
            Spacer(minLength: 4)
            volume
        }
        .frame(height: 38)
        .disabled(player.access == .unavailable)
        .overlay(alignment: .top) {
            if player.access == .denied {
                Text(player.settingsHint)
                    .appFont(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .offset(y: -58)
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
    }

    private var sourceName: String {
        #if os(macOS)
        "Music"
        #else
        "Apple Music"
        #endif
    }

    /// The source app's badge: Apple Music's red-to-pink squircle with a note.
    private var sourceBadge: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.40), Color(red: 0.98, green: 0.18, blue: 0.33)], startPoint: .top, endPoint: .bottom))
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: "music.note")
                    .appFont(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .bottomTrailing) {
                // Live dot while something plays.
                if player.isPlaying {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                        .offset(x: 2, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(springAnimation, value: player.isPlaying)
    }

    private var playPause: some View {
        Button { player.togglePlayPause() } label: {
            ZStack {
                Image(systemName: "pause.fill").opacity(player.isPlaying ? 1 : 0).scaleEffect(player.isPlaying ? 1 : 0.5)
                Image(systemName: "play.fill").opacity(player.isPlaying ? 0 : 1).scaleEffect(player.isPlaying ? 0.5 : 1)
            }
            .appFont(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 34, height: 32)
            .contentShape(.rect)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: player.isPlaying)
        }
        .buttonStyle(PressScaleStyle())
        .help(player.isPlaying ? "Pause" : "Play")
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    @ViewBuilder
    private var volume: some View {
        #if os(macOS)
        transport(player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: player.isMuted ? "Unmute" : "Mute") { player.toggleMute() }
        #elseif os(visionOS)
        // Vision Pro has no output picker to show; open Music for its own controls.
        transport("arrow.up.forward.app", label: "Open Music") { player.openPlayerApp() }
        #else
        // iOS apps can't set the system volume; the AirPlay picker is the Apple way.
        RoutePicker()
            .frame(width: 30, height: 30)
            .accessibilityLabel("Audio output")
        #endif
    }

    private func transport(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(.system(size: 13, weight: .semibold))
                .foregroundStyle(player.track == nil ? Theme.tertiaryText : Theme.icon)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func iconButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Collapsed sidebar: one play/pause button with the artwork as its background
/// ring, so the column still shows and controls what's playing.
struct CollapsedNowPlayingButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let player = app.nowPlaying
        Button { player.togglePlayPause() } label: {
            ZStack {
                if player.track != nil {
                    ArtworkView(data: player.artwork, size: 30)
                        .opacity(0.9)
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.28))
                        .frame(width: 30, height: 30)
                }
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .appFont(.system(size: 12, weight: .bold))
                    .foregroundStyle(player.track != nil ? Color.white : Theme.icon)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 34, height: 34)
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .help(player.track.map { "\($0.title) — \($0.artist)" } ?? "Play music")
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .accessibilityValue(player.track.map { "\($0.title), \($0.artist)" } ?? "")
        .padding(.bottom, 6)
    }
}

// MARK: - Pieces

/// Scales down while pressed, like the system transport controls.
private struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.84 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Elapsed time, a scrubber, and the length. The playhead advances on its own
/// between player updates.
private struct ProgressRow: View {
    let duration: TimeInterval
    let isPlaying: Bool
    let elapsed: (Date) -> TimeInterval
    let onSeek: (TimeInterval) -> Void
    @State private var scrub: Double?
    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: isPlaying ? 0.5 : 60)) { context in
            let current = scrub ?? elapsed(context.date)
            HStack(spacing: 8) {
                Text(NowPlaying.clock(current))
                    .frame(minWidth: 34, alignment: .leading)
                GeometryReader { proxy in
                    let fraction = duration > 0 ? min(1, max(0, current / duration)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.text.opacity(0.14))
                        Capsule().fill(Theme.text.opacity(scrub != nil || isHovering ? 0.85 : 0.55))
                            .frame(width: max(4, proxy.size.width * fraction))
                    }
                    .frame(height: scrub != nil || isHovering ? 6 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                scrub = min(1, max(0, value.location.x / proxy.size.width)) * duration
                            }
                            .onEnded { _ in
                                if let scrub { onSeek(scrub) }
                                scrub = nil
                            }
                    )
                    .onHover { isHovering = $0 }
                    .animation(.easeOut(duration: 0.15), value: isHovering)
                }
                .frame(height: 14)
                Text(duration > 0 ? NowPlaying.clock(duration) : "Live")
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .appFont(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue("\(NowPlaying.clock(current)) of \(NowPlaying.clock(duration))")
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 10 : -10
                onSeek(min(duration, max(0, current + step)))
            }
        }
    }
}

/// Album art, or a note on a soft gradient when the track has none.
private struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = Image(data: data) {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.40), Color(red: 0.60, green: 0.30, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "music.note")
                            .appFont(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .accessibilityHidden(true)
    }
}

/// Text that slides sideways when it doesn't fit, as in the reference, pausing at
/// each end. Static (truncated) when inactive or under Reduce Motion.
private struct MarqueeText: View {
    let text: String
    let isActive: Bool
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// Hebrew and Arabic titles start on the right, so they pin right and scroll the other way.
    private var isRightToLeft: Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: return false
            default: continue
            }
        }
        return false
    }

    var body: some View {
        let overflow = max(0, textWidth - boxWidth)
        let rtl = isRightToLeft
        GeometryReader { proxy in
            Text(text)
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                .offset(x: rtl ? -offset : offset)
                .frame(width: proxy.size.width, alignment: rtl ? .trailing : .leading)
                .onAppear { boxWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, new in boxWidth = new }
        }
        .clipped()
        .mask {
            // Soft edges only while it scrolls.
            LinearGradient(stops: overflow > 0 && isActive ? [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94), .init(color: .clear, location: 1),
            ] : [.init(color: .black, location: 0), .init(color: .black, location: 1)], startPoint: .leading, endPoint: .trailing)
        }
        .task(id: "\(text)|\(isActive)|\(Int(overflow))") {
            offset = 0
            guard isActive, overflow > 1 else { return }
            let travel = Double(overflow) / 28 // ~28 pt per second
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.linear(duration: travel)) { offset = -overflow }
                try? await Task.sleep(for: .seconds(travel + 1.2))
                withAnimation(.easeInOut(duration: 0.5)) { offset = 0 }
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
        .accessibilityLabel(text)
    }
}

#if os(iOS)
/// The system AirPlay / output picker.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .secondaryLabel
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
