//
//  CloudPreferences.swift
//  Colony
//
//  User preferences stored in the iCloud key-value store (NSUbiquitousKeyValueStore),
//  so they roam across the user's devices. Falls back gracefully to local-only when
//  iCloud is unavailable: the store keeps a local copy either way.
//

import Foundation
import Observation
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

@MainActor
@Observable
final class CloudPreferences {
    private enum Key {
        static let appearance = "appearance"
        static let displayName = "displayName"
        static let workspaceName = "workspaceName"
        static let sidebarCollapsed = "sidebarCollapsed"
        static let expandedProjects = "expandedProjects"
        static let didSeedStarterContent = "didSeedStarterContent"
        static let mirrorsToReminders = "mirrorsToReminders"
    }

    private let store: NSUbiquitousKeyValueStore?
    private let local: UserDefaults
    private var observer: NSObjectProtocol?

    var appearance: AppearancePreference { didSet { write(appearance.rawValue, Key.appearance) } }
    var displayName: String { didSet { write(displayName, Key.displayName) } }
    var workspaceName: String { didSet { write(workspaceName, Key.workspaceName) } }
    var isSidebarCollapsed: Bool { didSet { write(isSidebarCollapsed, Key.sidebarCollapsed) } }
    var expandedProjectIDs: Set<String> { didSet { write(Array(expandedProjectIDs), Key.expandedProjects) } }
    var didSeedStarterContent: Bool { didSet { write(didSeedStarterContent, Key.didSeedStarterContent) } }
    var mirrorsToReminders: Bool { didSet { write(mirrorsToReminders, Key.mirrorsToReminders) } }

    init(useICloud: Bool = true, defaults: UserDefaults = .standard) {
        self.store = useICloud ? NSUbiquitousKeyValueStore.default : nil
        self.local = defaults

        func read<T>(_ key: String) -> T? {
            (useICloud ? NSUbiquitousKeyValueStore.default.object(forKey: key) : nil) as? T ?? defaults.object(forKey: key) as? T
        }

        appearance = AppearancePreference(rawValue: read(Key.appearance) ?? "") ?? .dark
        displayName = read(Key.displayName) ?? CloudPreferences.defaultDisplayName
        workspaceName = read(Key.workspaceName) ?? "Colony"
        isSidebarCollapsed = read(Key.sidebarCollapsed) ?? false
        expandedProjectIDs = Set(read(Key.expandedProjects) as [String]? ?? [])
        didSeedStarterContent = read(Key.didSeedStarterContent) ?? false
        mirrorsToReminders = read(Key.mirrorsToReminders) ?? false

        if let store {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadFromCloud() }
            }
            store.synchronize()
        }
    }

    private func reloadFromCloud() {
        guard let store else { return }
        if let raw = store.string(forKey: Key.appearance), let value = AppearancePreference(rawValue: raw), value != appearance { appearance = value }
        if let value = store.string(forKey: Key.displayName), value != displayName { displayName = value }
        if let value = store.string(forKey: Key.workspaceName), value != workspaceName { workspaceName = value }
        if let value = store.array(forKey: Key.expandedProjects) as? [String], Set(value) != expandedProjectIDs { expandedProjectIDs = Set(value) }
        if store.bool(forKey: Key.didSeedStarterContent), !didSeedStarterContent { didSeedStarterContent = true }
        if store.object(forKey: Key.mirrorsToReminders) != nil { mirrorsToReminders = store.bool(forKey: Key.mirrorsToReminders) }
    }

    private func write(_ value: Any, _ key: String) {
        local.set(value, forKey: key)
        store?.set(value, forKey: key)
    }

    private static var defaultDisplayName: String {
        #if os(macOS)
        let name = NSFullUserName()
        return name.isEmpty ? "Me" : name
        #else
        return "Me"
        #endif
    }
}
