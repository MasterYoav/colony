//
//  CloudStore.swift
//  Colony
//
//  Colony keeps everything in iCloud:
//  - Records (projects, tasks, channels, messages, contacts, activity) live in a
//    SwiftData store mirrored to the user's *private* CloudKit database.
//  - Small preferences (appearance, display name, sidebar state) live in the iCloud
//    key-value store so they follow the user to every device.
//  No third-party backend is involved.
//

import CloudKit
import CoreData
#if targetEnvironment(simulator)
import MachO
#endif
#if os(macOS)
import Security
#endif
import Foundation
import Observation
import SwiftData

enum CloudStore {
    static let containerIdentifier = "iCloud.yoavperetz.Colony"

    /// Launch arguments used by tests and previews.
    static var isRunningForTests: Bool {
        ProcessInfo.processInfo.arguments.contains("-colony-in-memory")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    enum Mode: Equatable {
        case iCloud
        case localFallback(String)
        case inMemory
    }

    /// Builds the model container. Tries the CloudKit-backed store first; if the
    /// build lacks the iCloud entitlement (e.g. an unsigned local build) it falls
    /// back to an on-device store so the app still runs, and reports why.
    static func makeContainer() -> (ModelContainer, Mode) {
        let schema = Schema(ColonySchema.models)

        if isRunningForTests {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return (try! ModelContainer(for: schema, configurations: config), .inMemory)
        }

        // Without the CloudKit entitlement, CloudKit traps (CKContainer init) instead of
        // throwing, so check first and fall back to an on-device store.
        guard hasCloudKitEntitlement else {
            let config = ModelConfiguration("Colony-Local", schema: schema, cloudKitDatabase: .none)
            do {
                return (try ModelContainer(for: schema, configurations: config), .localFallback("This build isn't signed for iCloud"))
            } catch {
                fatalError("Colony could not open its data store: \(error)")
            }
        }

        do {
            let config = ModelConfiguration(
                "Colony",
                schema: schema,
                cloudKitDatabase: .private(containerIdentifier)
            )
            return (try ModelContainer(for: schema, configurations: config), .iCloud)
        } catch {
            let config = ModelConfiguration("Colony-Local", schema: schema, cloudKitDatabase: .none)
            do {
                return (try ModelContainer(for: schema, configurations: config), .localFallback(error.localizedDescription))
            } catch {
                fatalError("Colony could not open its data store: \(error)")
            }
        }
    }

    /// Whether this build is signed with the iCloud (CloudKit) entitlement.
    static var hasCloudKitEntitlement: Bool {
        let key = "com.apple.developer.icloud-services"
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? [String]
        else { return false }
        return value.contains("CloudKit")
        #elseif targetEnvironment(simulator)
        // Simulator builds carry their entitlements in the executable's __entitlements section.
        return simulatorEntitlements.contains(key)
        #else
        // Device builds can't run unsigned; the entitlement ships with the provisioning profile.
        return true
        #endif
    }

    #if targetEnvironment(simulator)
    private static var simulatorEntitlements: String {
        guard let header = _dyld_get_image_header(0) else { return "" }
        var size: UInt = 0
        let raw = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        guard let data = getsectiondata(raw, "__TEXT", "__entitlements", &size), size > 0 else { return "" }
        return String(decoding: UnsafeBufferPointer(start: data, count: Int(size)), as: UTF8.self)
    }
    #endif

    static func inMemoryContainer() -> ModelContainer {
        let schema = Schema(ColonySchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: config)
    }
}

/// Watches the iCloud account so the UI can say whether data is syncing.
@MainActor
@Observable
final class ICloudStatus {
    enum State: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case localOnly(String)
        case error(String)

        var title: String {
            switch self {
            case .checking: "Checking iCloud…"
            case .available: "Synced with iCloud"
            case .noAccount: "Not signed in to iCloud"
            case .restricted: "iCloud is restricted"
            case .temporarilyUnavailable: "iCloud temporarily unavailable"
            case .localOnly: "Saved on this device only"
            case .error: "iCloud error"
            }
        }

        var symbol: String {
            switch self {
            case .checking: "icloud"
            case .available: "checkmark.icloud"
            case .noAccount, .restricted: "icloud.slash"
            case .temporarilyUnavailable, .error: "exclamationmark.icloud"
            case .localOnly: "internaldrive"
            }
        }

        var isHealthy: Bool { self == .available }
    }

    private(set) var state: State = .checking
    /// Last CloudKit mirroring failure (setup/import/export), even if the account itself is fine.
    private(set) var syncError: String?
    private(set) var lastSyncedAt: Date?
    private let mode: CloudStore.Mode
    private var observer: NSObjectProtocol?
    private var eventObserver: NSObjectProtocol?

    /// What the UI shows: account problems first, then mirroring problems.
    var displayState: State {
        if state == .available, let syncError { return .error(syncError) }
        return state
    }

    init(mode: CloudStore.Mode) {
        self.mode = mode
        switch mode {
        case .localFallback(let reason): state = .localOnly(reason)
        case .inMemory: state = .localOnly("Running in memory")
        case .iCloud:
            observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            // SwiftData's CloudKit mirroring runs on NSPersistentCloudKitContainer and posts
            // its setup/import/export events here. Surface failures instead of hiding them.
            eventObserver = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                      event.endDate != nil else { return }
                let message = event.error.map(ICloudStatus.describe)
                MainActor.assumeIsolated {
                    self?.syncError = message
                    if message == nil { self?.lastSyncedAt = .now }
                }
            }
            Task { await refresh() }
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        return switch ck.code {
        case .badContainer: "The iCloud container isn't set up yet (\(CloudStore.containerIdentifier))."
        case .notAuthenticated: "Sign in to iCloud to sync."
        case .quotaExceeded: "Your iCloud storage is full."
        case .networkUnavailable, .networkFailure: "Offline. Changes will sync when you're back online."
        case .permissionFailure, .missingEntitlement: "Colony doesn't have permission to use iCloud."
        default: ck.localizedDescription
        }
    }

    func refresh() async {
        guard mode == .iCloud else { return }
        do {
            let status = try await CKContainer(identifier: CloudStore.containerIdentifier).accountStatus()
            state = switch status {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            case .temporarilyUnavailable: .temporarilyUnavailable
            case .couldNotDetermine: .error("Could not determine account status")
            @unknown default: .error("Unknown account status")
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
