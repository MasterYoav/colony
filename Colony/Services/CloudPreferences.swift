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
        static let didSeedStarterAgents = "didSeedStarterAgents"
        static let didSeedStarterAutomations = "didSeedStarterAutomations"
        static let mirrorsToReminders = "mirrorsToReminders"
        static let notifiesTasks = "notifiesTasks"
        static let runsInMenuBar = "runsInMenuBar"
        static let tasksInCalendar = "tasksInCalendar"
        static let automationsInCalendar = "automationsInCalendar"
        static let sidebarPinned = "sidebarPinnedItems"
        static let sidebarWorkspace = "sidebarWorkspaceItems"
        static let uiFont = "uiFontFamily"
        static let dataFont = "dataFontFamily"
        static let avatarImage = "avatarImage"
        static let avatarColor = "avatarColor"
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
    /// Starter agents are recruited once per iCloud account (separate flag so existing
    /// workspaces get them too).
    var didSeedStarterAgents: Bool { didSet { write(didSeedStarterAgents, Key.didSeedStarterAgents) } }
    /// The starter automations (switched off) were added once for this account.
    var didSeedStarterAutomations: Bool { didSet { write(didSeedStarterAutomations, Key.didSeedStarterAutomations) } }
    var mirrorsToReminders: Bool { didSet { write(mirrorsToReminders, Key.mirrorsToReminders) } }
    /// Notify at each task's due time. Each device still asks its own permission.
    var notifiesTasks: Bool { didSet { write(notifiesTasks, Key.notifiesTasks) } }
    /// Mac: keep Colony in the menu bar after its window closes. Per device.
    var runsInMenuBar: Bool { didSet { local.set(runsInMenuBar, forKey: Key.runsInMenuBar) } }
    /// Put dated tasks, and scheduled automations, in a "Colony" calendar.
    var showsTasksInCalendar: Bool { didSet { write(showsTasksInCalendar, Key.tasksInCalendar) } }
    var showsAutomationsInCalendar: Bool { didSet { write(showsAutomationsInCalendar, Key.automationsInCalendar) } }
    /// Sidebar order the user set by dragging (raw values of `SidebarNavItem`). Roams via iCloud.
    var sidebarPinnedItems: [String] { didSet { write(sidebarPinnedItems, Key.sidebarPinned) } }
    var sidebarWorkspaceItems: [String] { didSet { write(sidebarWorkspaceItems, Key.sidebarWorkspace) } }
    /// Font family names for the app chrome and for the user's content. Empty means the
    /// system font. Roams via iCloud; a family missing on a device falls back to system.
    var uiFontFamily: String { didSet { write(uiFontFamily, Key.uiFont) } }
    var dataFontFamily: String { didSet { write(dataFontFamily, Key.dataFont) } }
    /// Profile photo as a small square JPEG (≤ 320 px, a few tens of KB), so it fits
    /// comfortably in iCloud key-value storage and appears on every device. `nil` = monogram.
    var avatarImageData: Data? { didSet { writeOptional(avatarImageData, Key.avatarImage) } }
    /// Monogram background when there's no photo.
    var avatarColor: ColonyColor { didSet { write(avatarColor.rawValue, Key.avatarColor) } }

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
        didSeedStarterAgents = read(Key.didSeedStarterAgents) ?? false
        didSeedStarterAutomations = read(Key.didSeedStarterAutomations) ?? false
        mirrorsToReminders = read(Key.mirrorsToReminders) ?? false
        notifiesTasks = read(Key.notifiesTasks) ?? false
        runsInMenuBar = defaults.bool(forKey: Key.runsInMenuBar)
        showsTasksInCalendar = read(Key.tasksInCalendar) ?? false
        showsAutomationsInCalendar = read(Key.automationsInCalendar) ?? false
        sidebarPinnedItems = read(Key.sidebarPinned) ?? []
        sidebarWorkspaceItems = read(Key.sidebarWorkspace) ?? []
        uiFontFamily = read(Key.uiFont) ?? ""
        dataFontFamily = read(Key.dataFont) ?? ""
        avatarImageData = read(Key.avatarImage)
        avatarColor = ColonyColor(rawValue: read(Key.avatarColor) ?? "") ?? .purple

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
        if store.bool(forKey: Key.didSeedStarterAgents), !didSeedStarterAgents { didSeedStarterAgents = true }
        if store.object(forKey: Key.mirrorsToReminders) != nil { mirrorsToReminders = store.bool(forKey: Key.mirrorsToReminders) }
        if store.object(forKey: Key.notifiesTasks) != nil, store.bool(forKey: Key.notifiesTasks) != notifiesTasks { notifiesTasks = store.bool(forKey: Key.notifiesTasks) }
        if store.object(forKey: Key.tasksInCalendar) != nil, store.bool(forKey: Key.tasksInCalendar) != showsTasksInCalendar { showsTasksInCalendar = store.bool(forKey: Key.tasksInCalendar) }
        if store.object(forKey: Key.automationsInCalendar) != nil, store.bool(forKey: Key.automationsInCalendar) != showsAutomationsInCalendar { showsAutomationsInCalendar = store.bool(forKey: Key.automationsInCalendar) }
        if let value = store.array(forKey: Key.sidebarPinned) as? [String], value != sidebarPinnedItems { sidebarPinnedItems = value }
        if let value = store.array(forKey: Key.sidebarWorkspace) as? [String], value != sidebarWorkspaceItems { sidebarWorkspaceItems = value }
        if let value = store.string(forKey: Key.uiFont), value != uiFontFamily { uiFontFamily = value }
        if let value = store.string(forKey: Key.dataFont), value != dataFontFamily { dataFontFamily = value }
        let photo = store.data(forKey: Key.avatarImage)
        if photo != avatarImageData { avatarImageData = photo }
        if let raw = store.string(forKey: Key.avatarColor), let value = ColonyColor(rawValue: raw), value != avatarColor { avatarColor = value }
    }

    private func write(_ value: Any, _ key: String) {
        local.set(value, forKey: key)
        store?.set(value, forKey: key)
    }

    private func writeOptional(_ value: Any?, _ key: String) {
        if let value {
            write(value, key)
        } else {
            local.removeObject(forKey: key)
            store?.removeObject(forKey: key)
        }
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
