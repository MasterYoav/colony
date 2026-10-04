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
        static let workspaces = "workspaces"
        static let sidebarSetups = "sidebarSetups"
        static let currentWorkspace = "currentWorkspaceID"
        static let originalWorkspaceColor = "originalWorkspaceColor"
        static let aiSettings = "aiSettings"
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
    /// Workspaces besides the original one. Roams via iCloud.
    var extraWorkspaces: [WorkspaceInfo] { didSet { writeJSON(extraWorkspaces, Key.workspaces) } }
    /// Each workspace's sidebar (order, hidden items), keyed by workspace ID. Roams via iCloud.
    var sidebarSetups: [String: SidebarSetup] { didSet { writeJSON(sidebarSetups, Key.sidebarSetups) } }
    var originalWorkspaceColor: ColonyColor { didSet { write(originalWorkspaceColor.rawValue, Key.originalWorkspaceColor) } }
    /// Which model runs agents, chosen models, Jev on/off. Keys are in the Keychain, not here.
    var ai: AISettings { didSet { writeJSON(ai, Key.aiSettings) } }
    /// The open workspace. Per device, like an open window.
    var currentWorkspaceID: String {
        didSet {
            local.set(currentWorkspaceID, forKey: Key.currentWorkspace)
            WorkspaceScope.current = currentWorkspaceID
        }
    }

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
        let storedWorkspaces: [WorkspaceInfo] = Self.decode(read(Key.workspaces)) ?? []
        extraWorkspaces = storedWorkspaces
        sidebarSetups = Self.decode(read(Key.sidebarSetups)) ?? [:]
        originalWorkspaceColor = ColonyColor(rawValue: read(Key.originalWorkspaceColor) ?? "") ?? .blue
        ai = Self.decode(read(Key.aiSettings)) ?? AISettings()
        let current = defaults.string(forKey: Key.currentWorkspace) ?? WorkspaceInfo.originalID
        let known = storedWorkspaces.map(\.id)
        let open = (current == WorkspaceInfo.originalID || known.contains(current)) ? current : WorkspaceInfo.originalID
        currentWorkspaceID = open
        WorkspaceScope.current = open

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
        if let value: [WorkspaceInfo] = Self.decode(store.data(forKey: Key.workspaces)), value != extraWorkspaces {
            extraWorkspaces = value
            // The open workspace was deleted on another device.
            if currentWorkspaceID != WorkspaceInfo.originalID, !value.contains(where: { $0.id == currentWorkspaceID }) { currentWorkspaceID = WorkspaceInfo.originalID }
        }
        if let value: [String: SidebarSetup] = Self.decode(store.data(forKey: Key.sidebarSetups)), value != sidebarSetups { sidebarSetups = value }
        if let raw = store.string(forKey: Key.originalWorkspaceColor), let value = ColonyColor(rawValue: raw), value != originalWorkspaceColor { originalWorkspaceColor = value }
        if let value: AISettings = Self.decode(store.data(forKey: Key.aiSettings)), value != ai { ai = value }
    }

    private func write(_ value: Any, _ key: String) {
        local.set(value, forKey: key)
        store?.set(value, forKey: key)
    }

    private func writeJSON<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { write(data, key) }
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
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

// MARK: - Workspaces

extension CloudPreferences {
    /// Every workspace, the original first.
    var workspaces: [WorkspaceInfo] {
        [WorkspaceInfo(id: WorkspaceInfo.originalID, name: workspaceName, colorRaw: originalWorkspaceColor.rawValue, createdAt: .distantPast)]
            + extraWorkspaces.sorted { $0.createdAt < $1.createdAt }
    }

    var currentWorkspace: WorkspaceInfo {
        workspaces.first { $0.id == currentWorkspaceID } ?? workspaces[0]
    }

    /// Renames or recolours a workspace (the original one keeps using `workspaceName`).
    func update(_ workspace: WorkspaceInfo) {
        if workspace.isOriginal {
            if workspaceName != workspace.name { workspaceName = workspace.name }
            if originalWorkspaceColor != workspace.color { originalWorkspaceColor = workspace.color }
        } else if let index = extraWorkspaces.firstIndex(where: { $0.id == workspace.id }) {
            extraWorkspaces[index] = workspace
        }
    }

    /// Name of the open workspace, editable in Settings › General.
    var currentWorkspaceName: String {
        get { currentWorkspace.name }
        set {
            var workspace = currentWorkspace
            workspace.name = newValue
            update(workspace)
        }
    }

    /// Sidebar setup of the open workspace. The original workspace inherits the order
    /// people set by dragging before setups existed.
    var sidebarSetup: SidebarSetup {
        get {
            if let setup = sidebarSetups[currentWorkspaceID] { return setup }
            var setup = SidebarSetup()
            if currentWorkspaceID == WorkspaceInfo.originalID {
                let legacy = sidebarPinnedItems + sidebarWorkspaceItems
                if !legacy.isEmpty { setup.order = legacy }
            }
            return setup
        }
        set { sidebarSetups[currentWorkspaceID] = newValue }
    }
}

