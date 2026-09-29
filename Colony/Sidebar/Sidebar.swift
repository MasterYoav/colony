//
//  Sidebar.swift
//  Colony
//
//  Single sidebar modelled on the reference design:
//  ┌──────────────────────────┐
//  │ ● ● ●  workspace ▾  [◧]  │
//  │ [⌘ Command          /]   │
//  │ ⌂ Home                   │
//  │ ── WORKSPACE ───── ⋯ +   │
//  │ ── PROJECTS ────── ⋯ +   │
//  │    Project ▾             │
//  │       List          23   │
//  │ (YP) Name     ☾  ☁  ⚙   │
//  └──────────────────────────┘
//  It collapses to an icon-only column with the same footer stacked vertically.
//

import SwiftData
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let collapsed = app.preferences.isSidebarCollapsed
        // Both panels stay mounted; the column's width animates between them and they
        // crossfade, so opening and closing is one continuous motion rather than a swap.
        // The fades are staggered: the outgoing panel is gone before the incoming one
        // appears, so the two icon columns never show on top of each other.
        ZStack(alignment: .topLeading) {
            SidebarPanel()
                .animation(fade(showing: !collapsed)) { $0.opacity(collapsed ? 0 : 1) }
                .allowsHitTesting(!collapsed)
                .accessibilityHidden(collapsed)
            CollapsedPanel()
                .animation(fade(showing: collapsed)) { $0.opacity(collapsed ? 1 : 0) }
                .allowsHitTesting(collapsed)
                .accessibilityHidden(!collapsed)
        }
        .frame(width: collapsed ? Theme.collapsedPanelWidth : Theme.panelWidth(for: typeSize), alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .background(Theme.sidebar)
    }

    private func fade(showing: Bool) -> Animation {
        showing ? .easeOut(duration: 0.16).delay(0.14) : .easeIn(duration: 0.1)
    }
}

enum SidebarMetrics {
    /// With the sidebar collapsed on macOS, its toggle sits in the title bar just past the
    /// collapsed column (x 84…114). Content next to it starts at x 79, so anything placed
    /// in the title-bar row must start this far in to clear the toggle (plus a 10pt gap).
    static func titleBarLeading(collapsed: Bool) -> CGFloat {
        #if os(macOS)
        collapsed ? (Theme.collapsedPanelWidth + 6 + 30) - (Theme.collapsedPanelWidth + 1) + 10 : 0
        #else
        0
        #endif
    }

    /// Height of the row that shares space with the macOS traffic lights.
    static var titleBarHeight: CGFloat {
        #if os(macOS)
        28
        #else
        0
        #endif
    }

    /// Leading space the traffic lights occupy on macOS.
    static var trafficLightsWidth: CGFloat {
        #if os(macOS)
        70
        #else
        0
        #endif
    }
}

struct RailButton: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    var showsDot: Bool = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appFont(.system(size: 15, weight: .regular))
                .foregroundStyle(tint ?? (isSelected ? Theme.text : Theme.icon))
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? Theme.selection : (isHovering ? Theme.hover : .clear))
                }
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: -8, y: 8)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }
}

// MARK: - Expanded panel

struct SidebarPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query(filter: #Predicate<ActivityEvent> { !$0.isRead }) private var unreadUpdates: [ActivityEvent]
    @Query private var channels: [Channel]
    @Query(filter: #Predicate<TaskItem> { $0.statusRaw != "done" }) private var openTasks: [TaskItem]

    @State private var isProjectsExpanded = true
    @State private var isProjectsRowExpanded = false
    /// The project whose sidebar row is being renamed in place.
    @State private var renamingID: UUID?

    private var layout: SidebarLayout { SidebarLayout(preferences: app.preferences) }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Everything above Projects is fixed; only the project list scrolls.
            VStack(alignment: .leading, spacing: 0) {
                    workspaceSwitcher
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    VStack(spacing: 2) {
                        ForEach(layout.items) { item in
                            navRow(item)
                        }
                        SidebarDropTail(height: 8, accepts: acceptsNav) { drop($0, before: nil) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                    SidebarDivider()

                    SidebarSection(title: "Projects", isExpanded: $isProjectsExpanded, scrollsContent: true, onAdd: { app.present(.newProject) }, menu: {
                        Button("Expand all", systemImage: "chevron.down") {
                            app.preferences.expandedProjectIDs = Set(projects.map(\.uuid.uuidString))
                        }
                        Button("Collapse all", systemImage: "chevron.up") {
                            app.preferences.expandedProjectIDs = []
                        }
                    }) {
                        if projects.isEmpty {
                            Button { app.present(.newProject) } label: {
                                Label("Create a project", systemImage: "plus")
                                    .appFont(.system(size: 13))
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(projects) { project in
                            projectRows(project)
                        }
                        if !projects.isEmpty {
                            SidebarDropTail(accepts: acceptsProject) { dropProject($0, before: nil) }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            SidebarFooter(axis: .horizontal)
        }
        .frame(width: Theme.panelWidth(for: typeSize))
        .background(Theme.sidebar)
    }

    // MARK: Rows

    @ViewBuilder
    private func navRow(_ item: SidebarNavItem) -> some View {
        SidebarRow(symbol: item.symbol, title: item.title, count: count(for: item), isSelected: item.isSelected(app.destination), trailing: trailing(for: item)) {
            app.go(item.destination)
        }
        .sidebarDraggable(.nav(item), symbol: item.symbol, title: item.title)
        .sidebarDropTarget(accepts: acceptsNav) { drop($0, before: item) }
        .contextMenu { navMenu(item) }

        if item == .projects, isProjectsRowExpanded {
            ForEach(projects.prefix(5)) { project in
                SidebarChildRow(title: project.name, count: project.openTaskCount, isSelected: app.destination == .project(project.uuid)) {
                    app.go(.project(project.uuid))
                }
            }
        }
    }

    @ViewBuilder
    private func navMenu(_ item: SidebarNavItem) -> some View {
        switch item {
        case .tasks: Button("New task", systemImage: "plus") { app.present(.newTask(project: nil, list: nil)) }
        case .crm:
            Button("New customer", systemImage: "person.crop.circle.badge.plus") { app.present(.newContact) }
            Button("Import from Contacts", systemImage: "person.crop.rectangle.stack") { app.present(app.contacts.canRead ? .importContacts : .connectContacts) }
        case .inbox: Button("New channel", systemImage: "number") { app.present(.newChannel) }
        case .projects: Button("New project", systemImage: "folder.badge.plus") { app.present(.newProject) }
        default: EmptyView()
        }
        if layout.isCustomized {
            Divider()
            Button("Reset sidebar order", systemImage: "arrow.counterclockwise") { layout.reset() }
        }
    }

    private func count(for item: SidebarNavItem) -> Int? {
        switch item {
        case .updates: unreadUpdates.count
        case .inbox: unreadMessages
        case .tasks: openTasks.count
        default: nil
        }
    }

    private func trailing(for item: SidebarNavItem) -> SidebarTrailing {
        switch item {
        case .tasks: .add { app.present(.newTask(project: nil, list: nil)) }
        case .projects: .chevron(isProjectsRowExpanded) { withMotion(.snappy(duration: 0.2)) { isProjectsRowExpanded.toggle() } }
        default: .none
        }
    }

    // MARK: Drag and drop

    private func acceptsNav(_ payload: SidebarDragPayload) -> Bool {
        if case .nav = payload { return true }
        return false
    }

    private func acceptsProject(_ payload: SidebarDragPayload) -> Bool {
        if case .project = payload { return true }
        return false
    }

    private func drop(_ payload: SidebarDragPayload, before target: SidebarNavItem?) {
        guard case .nav(let item) = payload else { return }
        layout.move(item, before: target)
    }

    private func dropProject(_ payload: SidebarDragPayload, before target: Project?) {
        guard case .project(let id) = payload, let project = context.project(id) else { return }
        withMotion(.snappy(duration: 0.22)) {
            WorkspaceActions(context: context).move(project, before: target)
        }
    }

    private var unreadMessages: Int { channels.reduce(0) { $0 + $1.unreadCount } }

    /// Title-bar row: Command field beside the traffic lights, collapse toggle on the right.
    private var header: some View {
        HStack(spacing: 6) {
            CommandField { app.toggleCommandPalette() }
            SidebarToggleButton()
        }
        .padding(.leading, headerLeadingInset)
        .padding(.trailing, 8)
        .frame(minHeight: headerHeight, alignment: .center)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private var workspaceSwitcher: some View {
        Menu {
            Button("Workspace settings", systemImage: "gearshape") { app.openSettings(.general) }
            Button("Apple services", systemImage: "puzzlepiece.extension") { app.openSettings(.iCloud) }
            Divider()
            Button("New project", systemImage: "folder.badge.plus") { app.present(.newProject) }
            Button("New channel", systemImage: "number") { app.present(.newChannel) }
        } label: {
            WorkspaceSwitcherLabel(name: app.preferences.workspaceName)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Workspace: \(app.preferences.workspaceName)")
    }

    /// On macOS the header shares the title-bar row with the traffic lights.
    private var headerHeight: CGFloat {
        #if os(macOS)
        SidebarMetrics.titleBarHeight + 12
        #else
        52
        #endif
    }

    private var headerLeadingInset: CGFloat {
        #if os(macOS)
        SidebarMetrics.trafficLightsWidth + 6
        #else
        14
        #endif
    }

    @ViewBuilder
    private func projectRows(_ project: Project) -> some View {
        let expanded = app.isExpanded(project)
        if renamingID == project.uuid {
            InlineRenameRow(
                glyph: ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 17),
                initial: project.name
            ) { newName in
                if let newName, WorkspaceActions(context: context).rename(project, to: newName) {
                    WorkspaceActions(context: context).save()
                }
                renamingID = nil
            }
        } else {
        SidebarRow(
            glyph: ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 17),
            title: project.name,
            isSelected: app.destination == .project(project.uuid),
            trailing: project.sortedLists.isEmpty ? .none : .disclosure(expanded) { app.toggleExpanded(project) }
        ) {
            app.go(.project(project.uuid))
        }
        .sidebarDraggable(.project(project.uuid), symbol: project.symbol, title: project.name)
        .sidebarDropTarget(accepts: acceptsProject) { dropProject($0, before: project) }
        .contextMenu {
            Button("New task", systemImage: "plus") { app.present(.newTask(project: project.uuid, list: nil)) }
            Button("Rename", systemImage: "pencil") { renamingID = project.uuid }
            Button("Project Settings…", systemImage: "slider.horizontal.3") { app.present(.projectSettings(project.uuid)) }
            Divider()
            Button("Delete project…", systemImage: "trash", role: .destructive) {
                app.present(.deleteProject(project.uuid))
            }
        }

        }

        if expanded {
            ForEach(project.sortedLists) { list in
                SidebarChildRow(title: list.name, count: list.openTaskCount, isSelected: app.destination == .list(project: project.uuid, list: list.uuid)) {
                    app.go(.list(project: project.uuid, list: list.uuid))
                }
            }
        }
    }
}

/// A sidebar row in rename mode: the title becomes a field. Return saves, Esc or
/// clicking elsewhere cancels (`nil`), matching Finder.
struct InlineRenameRow<Glyph: View>: View {
    let glyph: Glyph
    let initial: String
    let onDone: (String?) -> Void
    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            glyph.frame(width: 18)
            TextField("Project name", text: $text)
                .textFieldStyle(.plain)
                .appFont(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit { finish(text) }
                .onKeyPress(.escape) { finish(nil); return .handled }
                .onChange(of: text) { _, new in if new.count > 40 { text = String(new.prefix(40)) } }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: Theme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(Theme.field)
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
        }
        .onAppear {
            text = initial
            Task { await DialogTextField.claimFocus { focused = true } isFocused: { focused } }
        }
        .onChange(of: focused) { _, isFocused in
            // Clicking away keeps what was typed, like Finder.
            if !isFocused { finish(text) }
        }
        .accessibilityLabel("Rename project")
    }

    private func finish(_ value: String?) {
        guard !finished else { return }
        finished = true
        onDone(value)
    }
}

// MARK: - Collapsed panel (icon-only)

struct CollapsedPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.sortIndex) private var projects: [Project]

    private var layout: SidebarLayout { SidebarLayout(preferences: app.preferences) }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // The toggle lives in the title bar, right of the traffic lights
            // (`CollapsedSidebarToggle` in RootView); the column starts below them.
            Color.clear.frame(height: topInset + 8)
            #else
            SidebarToggleButton()
                .frame(height: 44)
            #endif

            VStack(spacing: 6) {
                RailButton(symbol: "command", title: "Command Center (⌘K)", isSelected: app.isCommandPalettePresented) { app.toggleCommandPalette() }
                    .padding(.top, 2)
                ForEach(layout.items) { item in navIcon(item) }
                SidebarDropTail(height: 6, accepts: acceptsNav) { drop($0, before: nil) }

                SidebarDivider().padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)

            // As in the expanded panel, only the projects scroll.
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(projects) { project in
                        Button { app.go(.project(project.uuid)) } label: {
                            ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 18)
                                .frame(width: 34, height: 34)
                                .background {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(app.destination == .project(project.uuid) ? Theme.selection : .clear)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(project.name)
                        .accessibilityLabel(project.name)
                        .sidebarDraggable(.project(project.uuid), symbol: project.symbol, title: project.name)
                        .sidebarDropTarget(accepts: acceptsProject) { payload in
                            guard case .project(let id) = payload, let moved = context.project(id) else { return }
                            withMotion(.snappy(duration: 0.22)) { WorkspaceActions(context: context).move(moved, before: project) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)

            SidebarFooter(axis: .vertical)
        }
        .frame(width: Theme.collapsedPanelWidth)
        .background(Theme.sidebar)
    }

    private func navIcon(_ item: SidebarNavItem) -> some View {
        RailButton(symbol: item.symbol, title: item.title, isSelected: item.isSelected(app.destination)) { app.go(item.destination) }
            .sidebarDraggable(.nav(item), symbol: item.symbol, title: item.title)
            .sidebarDropTarget(accepts: acceptsNav) { drop($0, before: item) }
    }

    private func acceptsNav(_ payload: SidebarDragPayload) -> Bool {
        if case .nav = payload { return true }
        return false
    }

    private func acceptsProject(_ payload: SidebarDragPayload) -> Bool {
        if case .project = payload { return true }
        return false
    }

    private func drop(_ payload: SidebarDragPayload, before target: SidebarNavItem?) {
        guard case .nav(let item) = payload else { return }
        layout.move(item, before: target)
    }

    /// Title-bar row height on macOS; the toggle sits just below the traffic lights.
    private var topInset: CGFloat {
        #if os(macOS)
        SidebarMetrics.titleBarHeight
        #else
        0
        #endif
    }
}

// MARK: - Building blocks

struct SidebarToggleButton: View {
    @Environment(AppModel.self) private var app
    @State private var isHovering = false

    var body: some View {
        Button {
            app.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .appFont(.system(size: 14))
                .foregroundStyle(isHovering ? Theme.text : Theme.secondaryText)
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(app.preferences.isSidebarCollapsed ? "Expand sidebar (⌃⌘S)" : "Collapse sidebar (⌃⌘S)")
        .accessibilityLabel(app.preferences.isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
    }
}

struct WorkspaceSwitcherLabel: View {
    let name: String
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 22, height: 22)
            Text(name)
                .appFont(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .appFont(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 34)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isHovering ? Theme.hover : .clear)
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

struct CommandField: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The label wins over the shortcut hint: when the title-bar row is tight the
            // ⌘K hint drops out instead of truncating "Command".
            ViewThatFits(in: .horizontal) {
                content(showsHint: true)
                content(showsHint: false)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .frame(maxWidth: .infinity)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.strongStroke)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Command Center (⌘K)")
        .accessibilityLabel("Open command palette")
    }

    private func content(showsHint: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "command")
                .appFont(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text("Command")
                .appFont(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            if showsHint {
                Text("⌘K")
                    .appFont(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize()
            }
        }
    }
}

enum SidebarTrailing {
    case none
    case add(() -> Void)
    /// Chevron that rotates; used for inline expansion.
    case chevron(Bool, () -> Void)
    /// Boxed chevron used on projects, matching the reference (filled box when expanded).
    case disclosure(Bool, () -> Void)
}

struct SidebarRow<Glyph: View>: View {
    let glyph: Glyph
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    var trailing: SidebarTrailing = .none
    let action: () -> Void
    @State private var isHovering = false

    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 18

    var body: some View {
        HStack(spacing: 10) {
            glyph
                .frame(width: glyphWidth)
            Text(title)
                .appFont(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailingView
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .frame(minHeight: Theme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isSelected ? Theme.selection : (isHovering ? Theme.hover : .clear))
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
    }

    @ViewBuilder
    private var trailingView: some View {
        HStack(spacing: 6) {
            if let count, count > 0 {
                CountBadge(count: count)
            }
            switch trailing {
            case .none:
                EmptyView()
            case .add(let add):
                Button(action: add) {
                    Image(systemName: "plus")
                        .appFont(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(title)")
            case .chevron(let expanded, let toggle):
                Button(action: toggle) {
                    Image(systemName: "chevron.down")
                        .appFont(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse \(title)" : "Expand \(title)")
            case .disclosure(let expanded, let toggle):
                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .appFont(.system(size: 9, weight: .bold))
                        .foregroundStyle(expanded ? Theme.text : Theme.secondaryText)
                        .frame(width: 18, height: 18)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(expanded ? Theme.selection : .clear)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse \(title)" : "Expand \(title)")
            }
        }
    }
}

extension SidebarRow where Glyph == SidebarIcon {
    init(symbol: String, title: String, count: Int? = nil, isSelected: Bool, trailing: SidebarTrailing = .none, action: @escaping () -> Void) {
        self.init(glyph: SidebarIcon(symbol: symbol), title: title, count: count, isSelected: isSelected, trailing: trailing, action: action)
    }
}

struct SidebarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .appFont(.system(size: 13.5))
            .foregroundStyle(Theme.icon)
    }
}

/// Indented child row (project lists), no icon, count on the right.
struct SidebarChildRow: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(title)
                .appFont(.system(size: 13.5))
                .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 { CountBadge(count: count) }
        }
        .padding(.leading, 36)
        .padding(.trailing, 8)
        .frame(minHeight: Theme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isSelected ? Theme.selection : (isHovering ? Theme.hover : .clear))
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
    }
}

/// Small underlined count like "44" in the reference.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .appFont(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .underline(true, color: Theme.tertiaryText)
            .accessibilityLabel("\(count)")
    }
}

struct SidebarSection<Content: View, MenuContent: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    /// The header stays put and only the rows scroll (used by Projects, the one list that grows).
    var scrollsContent = false
    let onAdd: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    withMotion(.snappy(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .appFont(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        Text(title.uppercased())
                            .appFont(.system(size: 11, weight: .semibold))
                            .kerning(0.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) section")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                Spacer()

                Menu {
                    menu()
                } label: {
                    Image(systemName: "ellipsis")
                        .appFont(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("\(title) options")

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .appFont(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(title)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if isExpanded {
                if scrollsContent {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2, content: content)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 16)
                    }
                    .scrollIndicators(.automatic)
                    .scrollBounceBehavior(.basedOnSize)
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 2, content: content)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .clipped()
    }
}

struct SidebarDivider: View {
    var body: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1)
    }
}

/// Bottom of the sidebar: account, appearance, iCloud status and settings.
/// Horizontal in the expanded panel, stacked in the collapsed column.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var app
    let axis: Axis

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 2) {
                    accountButton(showsName: true)
                    Spacer(minLength: 4)
                    controls
                }
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    controls
                    accountButton(showsName: false)
                        .padding(.top, 4)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .top) { SidebarDivider() }
    }

    @ViewBuilder
    private var controls: some View {
        let cloud = app.iCloud.displayState
        RailButton(symbol: app.preferences.appearance == .light ? "moon" : "sun.max", title: "Toggle appearance", isSelected: false) {
            app.preferences.appearance = app.preferences.appearance == .light ? .dark : .light
        }
        if axis == .horizontal {
            RailButton(
                symbol: cloud.symbol,
                title: "iCloud: \(cloud.title)",
                isSelected: false,
                tint: cloud.isHealthy ? nil : .orange
            ) {
                app.openSettings(.iCloud)
            }
            RailButton(symbol: RailItem.settings.symbol, title: "Settings", isSelected: app.destination == .settings) {
                app.go(.settings)
            }
        } else {
            // Collapsed: no separate iCloud button; sync status rides on Settings as a small cloud.
            RailButton(symbol: RailItem.settings.symbol, title: "Settings · iCloud: \(cloud.title)", isSelected: app.destination == .settings) {
                app.go(.settings)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: cloud.isHealthy ? "icloud.fill" : "exclamationmark.icloud.fill")
                    .appFont(.system(size: 9, weight: .semibold))
                    .foregroundStyle(cloud.isHealthy ? Color.green : Color.orange)
                    .shadow(color: Theme.sidebar, radius: 0.5)
                    .shadow(color: Theme.sidebar, radius: 0.5)
                    .offset(x: 1, y: -1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func accountButton(showsName: Bool) -> some View {
        Button { app.openSettings(.profile) } label: {
            HStack(spacing: 8) {
                ProfileAvatar(size: 28, squircle: true)
                if showsName {
                    Text(app.preferences.displayName)
                        .appFont(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(app.preferences.displayName)
        .accessibilityLabel("Account: \(app.preferences.displayName)")
    }
}
