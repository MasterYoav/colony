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

    /// One line for Settings › Sidebar.
    var detail: String {
        switch self {
        case .home: "Your day at a glance."
        case .updates: "What changed, from you, agents and automations."
        case .inbox: "Channels for notes and conversations."
        case .tasks: "Everything to do, like Reminders."
        case .projects: "Projects and their lists."
        case .crm: "Customers and your sales pipeline."
        case .reports: "How work and sales are going."
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

/// The open workspace's sidebar: item order and what's hidden. Stored per workspace in
/// `CloudPreferences.sidebarSetups` (iCloud key-value storage), so every device shows the
/// same sidebar for the same workspace.
@MainActor
struct SidebarLayout {
    let preferences: CloudPreferences

    /// Every navigation item in the user's order, hidden ones included (for Settings).
    /// Legacy items merge, unknown values and duplicates drop, and anything added in a
    /// newer version is inserted in its default place.
    var allItems: [SidebarNavItem] {
        let stored = preferences.sidebarSetup.order.compactMap(SidebarNavItem.init(stored:))
        guard !stored.isEmpty else { return SidebarNavItem.defaultOrder }
        var seen = Set<SidebarNavItem>()
        var result = stored.filter { seen.insert($0).inserted }
        for item in SidebarNavItem.defaultOrder where !seen.contains(item) {
            let index = SidebarNavItem.defaultOrder.firstIndex(of: item)!
            let before = SidebarNavItem.defaultOrder[..<index].last { result.contains($0) }
            result.insert(item, at: before.flatMap { result.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        }
        return result
    }

    /// The items the sidebar shows.
    var items: [SidebarNavItem] {
        let hidden = Set(preferences.sidebarSetup.hidden)
        return allItems.filter { !hidden.contains($0.rawValue) }
    }

    func isHidden(_ item: SidebarNavItem) -> Bool { preferences.sidebarSetup.hidden.contains(item.rawValue) }
    func isHidden(_ section: SidebarSectionItem) -> Bool { preferences.sidebarSetup.hiddenSections.contains(section.rawValue) }

    func setHidden(_ item: SidebarNavItem, _ hidden: Bool) {
        update { setup in
            setup.hidden.removeAll { $0 == item.rawValue }
            if hidden { setup.hidden.append(item.rawValue) }
        }
    }

    func setHidden(_ section: SidebarSectionItem, _ hidden: Bool) {
        update { setup in
            setup.hiddenSections.removeAll { $0 == section.rawValue }
            if hidden { setup.hiddenSections.append(section.rawValue) }
        }
    }

    /// Moves `item` just before `target` (or to the end when `target` is nil).
    func move(_ item: SidebarNavItem, before target: SidebarNavItem?) {
        guard item != target else { return }
        var list = allItems.filter { $0 != item }
        let index = target.flatMap { list.firstIndex(of: $0) } ?? list.endIndex
        list.insert(item, at: index)
        update { $0.order = list.map(\.rawValue) }
    }

    /// Moves an item one place up or down among all items (Settings › Sidebar).
    func move(_ item: SidebarNavItem, by offset: Int) {
        var list = allItems
        guard let index = list.firstIndex(of: item) else { return }
        let target = index + offset
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        update { $0.order = list.map(\.rawValue) }
    }

    func apply(_ preset: WorkspacePreset) {
        update { $0 = preset.setup }
    }

    /// Back to the default order with everything shown.
    func reset() {
        update { $0 = SidebarSetup() }
    }

    var isCustomized: Bool {
        allItems != SidebarNavItem.defaultOrder || !preferences.sidebarSetup.hidden.isEmpty || !preferences.sidebarSetup.hiddenSections.isEmpty
    }

    private func update(_ change: (inout SidebarSetup) -> Void) {
        var setup = preferences.sidebarSetup
        setup.order = allItems.map(\.rawValue)
        change(&setup)
        withMotion(.snappy(duration: 0.22)) { preferences.sidebarSetup = setup }
    }
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
