//
//  Sidebar.swift
//  Colony
//
//  Two-part sidebar modelled on the reference design:
//  ┌──────┬──────────────────────────┐
//  │ rail │ workspace ▾        [◧]   │
//  │  ⌂   │ [⌘ Command          /]   │
//  │  ⌕   │ ⌂ Home                   │
//  │  …   │ ── WORKSPACE ───── ⋯ +   │
//  │      │ ── PROJECTS ────── ⋯ +   │
//  │  ☀   │    Project ▾             │
//  │  ◉   │       List          23   │
//  └──────┴──────────────────────────┘
//  The panel collapses to an icon-only column (third/fifth state in the reference).
//

import SwiftData
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var app
    var showsRail: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            if showsRail {
                SidebarRail()
                Rectangle().fill(Theme.stroke).frame(width: 1)
            }
            if app.preferences.isSidebarCollapsed {
                CollapsedPanel()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                SidebarPanel()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(Theme.sidebar)
        .animation(.snappy(duration: 0.25), value: app.preferences.isSidebarCollapsed)
    }
}

// MARK: - Rail

struct SidebarRail: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<ActivityEvent> { !$0.isRead }) private var unreadUpdates: [ActivityEvent]

    private let primary: [RailItem] = [.home, .search, .updates, .projects, .messages, .tasks, .people, .appleServices]

    var body: some View {
        VStack(spacing: 6) {
            Button { app.go(.home) } label: {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colony home")
            .padding(.top, railTopInset)
            .padding(.bottom, 8)

            ForEach(primary) { item in
                RailButton(
                    symbol: item.symbol,
                    title: item.title,
                    isSelected: item != .search && app.destination.railItem == item,
                    showsDot: item == .updates && !unreadUpdates.isEmpty
                ) {
                    if item == .search {
                        app.sheet = .commandPalette
                    } else if let destination = item.destination {
                        app.go(destination)
                    }
                }
            }

            Spacer(minLength: 12)

            RailButton(symbol: app.preferences.appearance == .light ? "moon" : "sun.max", title: "Toggle appearance", isSelected: false) {
                app.preferences.appearance = app.preferences.appearance == .light ? .dark : .light
            }
            RailButton(symbol: app.iCloud.displayState.symbol, title: app.iCloud.displayState.title, isSelected: false) {
                app.go(.settings)
            }
            RailButton(symbol: RailItem.settings.symbol, title: "Settings", isSelected: app.destination == .settings) {
                app.go(.settings)
            }

            Button { app.go(.settings) } label: {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.avatarGradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(ColonyText.initials(for: app.preferences.displayName))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account: \(app.preferences.displayName)")
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: Theme.railWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.rail)
    }

    private var railTopInset: CGFloat {
        #if os(macOS)
        34 // clears the traffic lights
        #else
        12
        #endif
    }
}

struct RailButton: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    var showsDot: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isSelected ? Theme.text : Theme.icon)
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
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query(filter: #Predicate<ActivityEvent> { !$0.isRead }) private var unreadUpdates: [ActivityEvent]
    @Query private var channels: [Channel]
    @Query private var contacts: [Contact]
    @Query(filter: #Predicate<TaskItem> { $0.statusRaw != "done" && $0.assignedToMe }) private var myOpenTasks: [TaskItem]

    @State private var isWorkspaceExpanded = true
    @State private var isProjectsExpanded = true
    @State private var isProjectsRowExpanded = false
    @State private var projectPendingDeletion: Project?
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommandField { app.sheet = .commandPalette }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                    VStack(spacing: 2) {
                        SidebarRow(symbol: "house", title: "Home", isSelected: app.destination == .home) { app.go(.home) }
                        SidebarRow(symbol: "bell", title: "Updates", count: unreadUpdates.count, isSelected: app.destination == .updates) { app.go(.updates) }
                        SidebarRow(symbol: "tray", title: "Inbox", count: unreadMessages, isSelected: app.destination.railItem == .messages) { app.go(.messages(channel: nil)) }
                        SidebarRow(symbol: "list.clipboard", title: "My tasks", isSelected: app.destination == .myTasks, trailing: .add { app.sheet = .newTask(project: nil, list: nil) }) { app.go(.myTasks) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)

                    SidebarDivider()

                    SidebarSection(title: "Workspace", isExpanded: $isWorkspaceExpanded, onAdd: { app.sheet = .newProject }, menu: {
                        Button("New channel", systemImage: "number") { app.sheet = .newChannel }
                        Button("New contact", systemImage: "person.crop.circle.badge.plus") { app.sheet = .newContact }
                        Button("Import from Contacts", systemImage: "person.crop.rectangle.stack") { app.sheet = .importContacts }
                    }) {
                        SidebarRow(symbol: "square.stack.3d.up", title: "Projects", isSelected: app.destination == .projects, trailing: .chevron(isProjectsRowExpanded) {
                            withAnimation(.snappy(duration: 0.2)) { isProjectsRowExpanded.toggle() }
                        }) { app.go(.projects) }
                        if isProjectsRowExpanded {
                            ForEach(projects.prefix(5)) { project in
                                SidebarChildRow(title: project.name, count: project.openTaskCount, isSelected: app.destination == .project(project.uuid)) {
                                    app.go(.project(project.uuid))
                                }
                            }
                        }
                        SidebarRow(symbol: "checklist", title: "Tasks", isSelected: app.destination == .allTasks, trailing: .add { app.sheet = .newTask(project: nil, list: nil) }) { app.go(.allTasks) }
                        SidebarRow(symbol: "square.grid.2x2", title: "Pipeline", isSelected: app.destination == .pipeline) { app.go(.pipeline) }
                        SidebarRow(symbol: "person.2", title: "Contacts", count: contacts.count, isSelected: app.destination == .contacts) { app.go(.contacts) }
                        SidebarRow(symbol: "chart.pie", title: "Reports", isSelected: app.destination == .reports) { app.go(.reports) }
                    }

                    SidebarDivider()

                    SidebarSection(title: "Projects", isExpanded: $isProjectsExpanded, onAdd: { app.sheet = .newProject }, menu: {
                        Button("Expand all", systemImage: "chevron.down") {
                            app.preferences.expandedProjectIDs = Set(projects.map(\.uuid.uuidString))
                        }
                        Button("Collapse all", systemImage: "chevron.up") {
                            app.preferences.expandedProjectIDs = []
                        }
                    }) {
                        if projects.isEmpty {
                            Button { app.sheet = .newProject } label: {
                                Label("Create a project", systemImage: "plus")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(projects) { project in
                            projectRows(project)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .scrollIndicators(.never)

            SyncFooter()
        }
        .frame(width: Theme.panelWidth)
        .background(Theme.sidebar)
        .confirmSheet(
            isPresented: $isConfirmingDelete,
            systemImage: "trash",
            title: "Delete \(projectPendingDeletion?.name ?? "project")?",
            message: "Its lists are removed from every device signed in to your iCloud account. Tasks stay in My tasks.",
            confirmTitle: "Delete project",
            isDestructive: true
        ) {
            if let project = projectPendingDeletion {
                if case .project(let id) = app.destination, id == project.uuid { app.go(.projects) }
                WorkspaceActions(context: context).delete(project)
            }
            projectPendingDeletion = nil
        }
    }

    private var unreadMessages: Int { channels.reduce(0) { $0 + $1.unreadCount } }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Workspace settings", systemImage: "gearshape") { app.go(.settings) }
                Button("Apple services", systemImage: "puzzlepiece.extension") { app.go(.appleServices) }
                Divider()
                Button("New project", systemImage: "folder.badge.plus") { app.sheet = .newProject }
                Button("New channel", systemImage: "number") { app.sheet = .newChannel }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.brandGradient)
                        .frame(width: 22, height: 22)
                    Text(app.preferences.workspaceName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)

            SidebarToggleButton()
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, headerTopInset)
        .frame(height: 52 + headerTopInset, alignment: .center)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private var headerTopInset: CGFloat {
        #if os(macOS)
        22
        #else
        0
        #endif
    }

    @ViewBuilder
    private func projectRows(_ project: Project) -> some View {
        let expanded = app.isExpanded(project)
        SidebarRow(
            glyph: ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 17),
            title: project.name,
            isSelected: app.destination == .project(project.uuid),
            trailing: project.sortedLists.isEmpty ? .none : .disclosure(expanded) { app.toggleExpanded(project) }
        ) {
            app.go(.project(project.uuid))
        }
        .contextMenu {
            Button("New task", systemImage: "plus") { app.sheet = .newTask(project: project.uuid, list: nil) }
            Button(expanded ? "Collapse" : "Expand", systemImage: expanded ? "chevron.up" : "chevron.down") { app.toggleExpanded(project) }
            Divider()
            Button("Delete project", systemImage: "trash", role: .destructive) {
                projectPendingDeletion = project
                isConfirmingDelete = true
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

// MARK: - Collapsed panel (icon-only)

struct CollapsedPanel: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Project.sortIndex) private var projects: [Project]

    var body: some View {
        VStack(spacing: 0) {
            SidebarToggleButton()
                .padding(.top, topInset)
                .frame(height: 52 + topInset)

            ScrollView {
                VStack(spacing: 6) {
                    iconButton("command", "Command") { app.sheet = .commandPalette }
                        .padding(.top, 10)
                    iconButton("house", "Home", selected: app.destination == .home) { app.go(.home) }
                    iconButton("bell", "Updates", selected: app.destination == .updates) { app.go(.updates) }
                    iconButton("tray", "Inbox", selected: app.destination.railItem == .messages) { app.go(.messages(channel: nil)) }
                    iconButton("list.clipboard", "My tasks", selected: app.destination == .myTasks) { app.go(.myTasks) }

                    SidebarDivider().padding(.vertical, 6)

                    iconButton("square.stack.3d.up", "Projects", selected: app.destination == .projects) { app.go(.projects) }
                    iconButton("checklist", "Tasks", selected: app.destination == .allTasks) { app.go(.allTasks) }
                    iconButton("square.grid.2x2", "Pipeline", selected: app.destination == .pipeline) { app.go(.pipeline) }
                    iconButton("person.2", "Contacts", selected: app.destination == .contacts) { app.go(.contacts) }
                    iconButton("chart.pie", "Reports", selected: app.destination == .reports) { app.go(.reports) }

                    SidebarDivider().padding(.vertical, 6)

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
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .frame(width: Theme.collapsedPanelWidth)
        .background(Theme.sidebar)
    }

    private var topInset: CGFloat {
        #if os(macOS)
        22
        #else
        0
        #endif
    }

    private func iconButton(_ symbol: String, _ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        RailButton(symbol: symbol, title: title, isSelected: selected, action: action)
    }
}

// MARK: - Building blocks

struct SidebarToggleButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.preferences.isSidebarCollapsed.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14))
                .foregroundStyle(app.preferences.isSidebarCollapsed ? Theme.text : Theme.secondaryText)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(app.preferences.isSidebarCollapsed ? Theme.selection : .clear)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: [.command, .control])
        .help(app.preferences.isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityLabel(app.preferences.isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
    }
}

struct CommandField: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text("Command")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("/")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.strongStroke)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Open command palette")
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

    var body: some View {
        HStack(spacing: 10) {
            glyph
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailingView
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.rowHeight)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(title)")
            case .chevron(let expanded, let toggle):
                Button(action: toggle) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
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
                        .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 13.5))
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
                .font(.system(size: 13.5))
                .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 { CountBadge(count: count) }
        }
        .padding(.leading, 36)
        .padding(.trailing, 8)
        .frame(height: Theme.rowHeight)
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
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .underline(true, color: Theme.tertiaryText)
            .accessibilityLabel("\(count)")
    }
}

struct SidebarSection<Content: View, MenuContent: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let onAdd: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(0.4)
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
                        .font(.system(size: 11, weight: .bold))
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
                        .font(.system(size: 11, weight: .semibold))
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
                VStack(alignment: .leading, spacing: 2, content: content)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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

/// Bottom card that replaces the reference's "Upgrade plan" promo with iCloud sync status.
struct SyncFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button { app.go(.settings) } label: {
            HStack(spacing: 8) {
                Image(systemName: app.iCloud.displayState.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(app.iCloud.displayState.isHealthy ? Color.green : Color.orange)
                Text(app.iCloud.displayState.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glassSurface(.rect(cornerRadius: 10), style: .standard)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(12)
        .overlay(alignment: .top) { SidebarDivider() }
        .accessibilityLabel("iCloud status: \(app.iCloud.displayState.title)")
    }
}
