//
//  SidebarLayout.swift
//  Colony
//
//  User-arranged sidebar. Navigation items and projects can be dragged into a new order.
//  The item layout roams through iCloud key-value storage; project order is stored on
//  the projects themselves (SwiftData + CloudKit), so every device shows the same sidebar.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum SidebarNavItem: String, CaseIterable, Identifiable {
    case home, updates, inbox, tasks, projects, crm, reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .updates: "Updates"
        case .inbox: "Inbox"
        case .tasks: "Tasks"
        case .projects: "Projects"
        case .crm: "CRM"
        case .reports: "Reports"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .updates: "bell"
        case .inbox: "tray"
        case .tasks: "checklist"
        case .projects: "square.stack.3d.up"
        case .crm: "person.2"
        case .reports: "chart.pie"
        }
    }

    var destination: Destination {
        switch self {
        case .home: .home
        case .updates: .updates
        case .inbox: .messages(channel: nil)
        case .tasks: .tasks
        case .projects: .projects
        case .crm: .crm
        case .reports: .reports
        }
    }

    func isSelected(_ destination: Destination) -> Bool {
        switch self {
        case .inbox: if case .messages = destination { return true } else { return false }
        default: return destination == self.destination
        }
    }

    /// Items from older layouts map onto the merged ones, so a synced order survives.
    init?(stored raw: String) {
        switch raw {
        case "myTasks": self = .tasks
        case "pipeline", "contacts": self = .crm
        default: self.init(rawValue: raw)
        }
    }

    static let defaultOrder: [SidebarNavItem] = [.home, .updates, .inbox, .tasks, .projects, .crm, .reports]
}

/// Reads and rewrites the user's order of the sidebar's navigation items, stored in
/// `CloudPreferences` (iCloud key-value storage) so every device shows the same list.
@MainActor
struct SidebarLayout {
    let preferences: CloudPreferences

    /// Stored order, cleaned up: legacy items merged, unknown values and duplicates
    /// dropped, and anything added in a newer version appended in its default place.
    var items: [SidebarNavItem] {
        let stored = (preferences.sidebarPinnedItems + preferences.sidebarWorkspaceItems).compactMap(SidebarNavItem.init(stored:))
        guard !stored.isEmpty else { return SidebarNavItem.defaultOrder }
        var seen = Set<SidebarNavItem>()
        var result = stored.filter { seen.insert($0).inserted }
        for item in SidebarNavItem.defaultOrder where !seen.contains(item) {
            // Insert after its default predecessor when possible.
            let index = SidebarNavItem.defaultOrder.firstIndex(of: item)!
            let before = SidebarNavItem.defaultOrder[..<index].last { result.contains($0) }
            result.insert(item, at: before.flatMap { result.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        }
        return result
    }

    /// Moves `item` just before `target` (or to the end when `target` is nil).
    func move(_ item: SidebarNavItem, before target: SidebarNavItem?) {
        guard item != target else { return }
        var list = items.filter { $0 != item }
        let index = target.flatMap { list.firstIndex(of: $0) } ?? list.endIndex
        list.insert(item, at: index)
        withMotion(.snappy(duration: 0.22)) {
            preferences.sidebarPinnedItems = list.map(\.rawValue)
            preferences.sidebarWorkspaceItems = []
        }
    }

    func reset() {
        withMotion(.snappy(duration: 0.22)) {
            preferences.sidebarPinnedItems = []
            preferences.sidebarWorkspaceItems = []
        }
    }

    var isCustomized: Bool { items != SidebarNavItem.defaultOrder }
}

/// What travels during a drag: a nav item or a project, encoded as plain text so it
/// works with SwiftUI's `draggable`/`dropDestination` on every platform.
enum SidebarDragPayload {
    case nav(SidebarNavItem)
    case project(UUID)

    var string: String {
        switch self {
        case .nav(let item): "colony.sidebar.nav:\(item.rawValue)"
        case .project(let id): "colony.sidebar.project:\(id.uuidString)"
        }
    }

    init?(_ string: String) {
        if let raw = string.stripping(prefix: "colony.sidebar.nav:"), let item = SidebarNavItem(rawValue: raw) {
            self = .nav(item)
        } else if let raw = string.stripping(prefix: "colony.sidebar.project:"), let id = UUID(uuidString: raw) {
            self = .project(id)
        } else {
            return nil
        }
    }
}

private extension String {
    func stripping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

// MARK: - Drag and drop modifiers

extension View {
    /// Makes a sidebar row draggable, with a compact preview that matches the row.
    func sidebarDraggable(_ payload: SidebarDragPayload, symbol: String, title: String) -> some View {
        draggable(payload.string) {
            HStack(spacing: 8) {
                Image(systemName: symbol).appFont(.system(size: 12.5)).foregroundStyle(Theme.icon)
                Text(title).appFont(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.raised, in: .rect(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.strongStroke) }
        }
    }

    /// Accepts a drop on this row and shows an insertion line above it while targeted.
    func sidebarDropTarget(accepts: @escaping (SidebarDragPayload) -> Bool, perform: @escaping (SidebarDragPayload) -> Void) -> some View {
        modifier(SidebarDropTarget(accepts: accepts, perform: perform))
    }
}

private struct SidebarDropTarget: ViewModifier {
    let accepts: (SidebarDragPayload) -> Bool
    let perform: (SidebarDragPayload) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isTargeted {
                    InsertionIndicator().offset(y: -2)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.lazy.compactMap(SidebarDragPayload.init).first, accepts(payload) else { return false }
                perform(payload)
                return true
            } isTargeted: { targeted in
                withMotion(.snappy(duration: 0.12)) { isTargeted = targeted }
            }
    }
}

/// Blue line with a leading dot, the standard macOS "drop goes here" marker.
struct InsertionIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5).frame(width: 6, height: 6)
            Rectangle().fill(Color.accentColor).frame(height: 2)
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}

/// Invisible strip at the end of a group so items can be dropped after the last row
/// (or into a group that has been emptied).
struct SidebarDropTail: View {
    var height: CGFloat = 10
    let accepts: (SidebarDragPayload) -> Bool
    let perform: (SidebarDragPayload) -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(.rect)
            .sidebarDropTarget(accepts: accepts, perform: perform)
    }
}
