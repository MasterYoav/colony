//
//  Workspaces.swift
//  Colony
//
//  Several workspaces in one iCloud account: a team space, a personal one, a side
//  project. Each top-level record (projects, tasks, channels, customers, updates, agents,
//  automations) carries the `workspaceID` it belongs to; lists, messages and runs follow
//  their parent. The original workspace has the empty ID, so data from before
//  workspaces existed belongs to it without a migration.
//
//  The list of workspaces and each one's sidebar setup roam through iCloud key-value
//  storage; which workspace is open is remembered per device.
//

import SwiftData
import SwiftUI

/// A workspace's name and look. The original workspace isn't stored here; its name is
/// `CloudPreferences.workspaceName`.
struct WorkspaceInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colorRaw: String
    var createdAt: Date

    static let originalID = ""

    var color: ColonyColor {
        get { ColonyColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var isOriginal: Bool { id == Self.originalID }

    /// "a.square.fill" for "Acme"; a plain square for names that don't start with a–z.
    static func symbol(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).lowercased().first, first.isASCII, first.isLetter else { return "square.fill" }
        return "\(first).square.fill"
    }
}

/// Which workspace new records are stamped with and lists are filtered by.
/// Set from `CloudPreferences.currentWorkspaceID`; agents and automations temporarily
/// switch it to their own workspace while they run (`run(in:)`).
nonisolated enum WorkspaceScope {
    nonisolated(unsafe) static var current = WorkspaceInfo.originalID
    nonisolated(unsafe) private static var override: String?

    /// The workspace a record created right now belongs to.
    static var stamp: String { override ?? current }

    static func run<T>(in id: String, _ body: () throws -> T) rethrows -> T {
        let previous = override
        override = id
        defer { override = previous }
        return try body()
    }
}

/// Records that belong to one workspace.
protocol WorkspaceScoped: AnyObject {
    var workspaceID: String { get set }
}

extension Project: WorkspaceScoped {}
extension TaskItem: WorkspaceScoped {}
extension Channel: WorkspaceScoped {}
extension Contact: WorkspaceScoped {}
extension ActivityEvent: WorkspaceScoped {}
extension Agent: WorkspaceScoped {}
extension Automation: WorkspaceScoped {}

extension Array where Element: WorkspaceScoped {
    /// Only the records in `workspace` (the open one by default).
    func inWorkspace(_ workspace: String = WorkspaceScope.stamp) -> [Element] {
        filter { $0.workspaceID == workspace }
    }
}

extension Array where Element == Message {
    func inWorkspace(_ workspace: String = WorkspaceScope.stamp) -> [Element] {
        filter { ($0.channel?.workspaceID ?? WorkspaceInfo.originalID) == workspace }
    }
}

/// The workspace any record belongs to (children follow their parent).
func workspaceOf(_ model: any PersistentModel) -> String {
    switch model {
    case let scoped as any WorkspaceScoped: scoped.workspaceID
    case let list as ProjectList: list.project?.workspaceID ?? WorkspaceInfo.originalID
    case let message as Message: message.channel?.workspaceID ?? WorkspaceInfo.originalID
    case let message as AgentMessage: message.agent?.workspaceID ?? WorkspaceInfo.originalID
    case let run as AutomationRun: run.automation?.workspaceID ?? WorkspaceInfo.originalID
    default: WorkspaceInfo.originalID
    }
}

extension ModelContext {
    /// All records of a type in one workspace (the open one by default).
    func inWorkspace<T: PersistentModel & WorkspaceScoped>(_ type: T.Type, _ workspace: String = WorkspaceScope.stamp, sortBy: [SortDescriptor<T>] = []) -> [T] {
        ((try? fetch(FetchDescriptor<T>(sortBy: sortBy))) ?? []).filter { !$0.isDeleted && $0.workspaceID == workspace }
    }
}

// MARK: - What a workspace is for

/// Starting points for a new workspace (and presets in Settings › Sidebar): which
/// sidebar items it shows. Everything stays one click away in ⌘K and Settings.
enum WorkspacePreset: String, CaseIterable, Identifiable {
    case everything, personal, sales, team

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .personal: "Personal"
        case .sales: "Sales"
        case .team: "Team"
        }
    }

    var detail: String {
        switch self {
        case .everything: "Every tool Colony has."
        case .personal: "Tasks and projects, nothing else."
        case .sales: "Customers, follow-ups and reports."
        case .team: "Projects, channels and updates."
        }
    }

    var symbol: String {
        switch self {
        case .everything: "square.grid.2x2.fill"
        case .personal: "person.fill"
        case .sales: "chart.line.uptrend.xyaxis"
        case .team: "person.3.fill"
        }
    }

    var color: ColonyColor {
        switch self {
        case .everything: .blue
        case .personal: .green
        case .sales: .orange
        case .team: .purple
        }
    }

    var setup: SidebarSetup {
        switch self {
        case .everything: SidebarSetup()
        case .personal: SidebarSetup(hidden: [.inbox, .crm, .reports], hiddenSections: [.agents, .automations])
        case .sales: SidebarSetup(order: [.home, .crm, .tasks, .inbox, .reports, .updates, .projects], hidden: [.projects], hiddenSections: [])
        case .team: SidebarSetup(order: [.home, .updates, .inbox, .projects, .tasks, .reports, .crm], hidden: [.crm], hiddenSections: [])
        }
    }
}

/// Sections below the navigation items that can be shown or hidden too.
enum SidebarSectionItem: String, CaseIterable, Identifiable, Codable {
    case agents, automations, nowPlaying

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .automations: "Automations"
        case .nowPlaying: "Music player"
        }
    }

    var symbol: String {
        switch self {
        case .agents: "sparkles"
        case .automations: "bolt.fill"
        case .nowPlaying: "music.note"
        }
    }

    var detail: String {
        switch self {
        case .agents: "Your on-device assistants."
        case .automations: "“When this happens, do that” flows."
        case .nowPlaying: "What's playing, at the bottom of the sidebar."
        }
    }
}

/// One workspace's sidebar: the order of the navigation items and what's hidden.
struct SidebarSetup: Codable, Hashable {
    var order: [String] = SidebarNavItem.defaultOrder.map(\.rawValue)
    var hidden: [String] = []
    var hiddenSections: [String] = []

    init() {}

    init(order: [SidebarNavItem] = SidebarNavItem.defaultOrder, hidden: [SidebarNavItem], hiddenSections: [SidebarSectionItem]) {
        self.order = order.map(\.rawValue)
        self.hidden = hidden.map(\.rawValue)
        self.hiddenSections = hiddenSections.map(\.rawValue)
    }

    /// Which preset this matches, if any (for the checkmark in Settings).
    var preset: WorkspacePreset? {
        WorkspacePreset.allCases.first { preset in
            let setup = preset.setup
            return Set(setup.hidden) == Set(hidden) && Set(setup.hiddenSections) == Set(hiddenSections)
        }
    }
}
