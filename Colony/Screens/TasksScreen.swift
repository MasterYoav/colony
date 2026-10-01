//
//  TasksScreen.swift
//  Colony
//
//  One screen serves Tasks (everything), a project, and a project list.
//  Rows are Swift Pieces `TaskRow`s (swipe to snooze/delete, animated check) with a
//  context menu for pointer users.
//

import SwiftData
import SwiftUI

enum TaskScope {
    case all
    case project(Project)
    case list(Project, ProjectList)

    var title: String {
        switch self {
        case .all: "Tasks"
        case .project(let p): p.name
        case .list(_, let l): l.name
        }
    }

    var project: Project? {
        switch self {
        case .project(let p), .list(let p, _): p
        default: nil
        }
    }

    var list: ProjectList? {
        if case .list(_, let l) = self { return l }
        return nil
    }
}

struct TasksScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var allTasksEverywhere: [TaskItem]
    private var allTasks: [TaskItem] { allTasksEverywhere.inWorkspace() }
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace() }
    let scope: TaskScope

    @State private var layout: Layout = .list
    @State private var smart: SmartList = .today
    @State private var showsCompleted = false
    @State private var selection: UUID?
    @State private var lingering: Set<UUID> = []
    @State private var confirmsClear = false
    @FocusState private var focus: TaskFocus?

    enum Layout: String, CaseIterable { case list = "List", board = "Board" }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 28)
                .padding(.leading, app.preferences.isSidebarCollapsed && isMac ? 22 : 0)
                .padding(.top, 14)

            if layout == .list {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if case .all = scope {
                            SmartListTiles(selection: Binding(get: { smart }, set: { new in
                                guard let new else { return }
                                selection = nil
                                smart = new
                                showsCompleted = new == .completed
                            }), counts: smartCounts)
                            .padding(.bottom, 22)
                        }
                        titleBlock
                        RemindersList(sections: sections, accent: accent, selection: $selection, focus: $focus, lingering: $lingering)
                        if sections.allSatisfy({ $0.tasks.isEmpty }) && !sections.contains(where: \.acceptsNew) {
                            Text("Nothing here yet.")
                                .appFont(.body)
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.leading, app.preferences.isSidebarCollapsed && isMac ? 22 : 0)
                    .padding(.top, 8)
                    .padding(.bottom, 60)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                    .contentShape(.rect)
                    // Click on empty space: deselect, like Reminders.
                    .onTapGesture { deselect() }
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
            } else {
                BoardView(tasks: scoped)
                    .padding(.top, 12)
            }
        }
        .navigationTitle(scope.title)
        .onKeyPress(.escape) {
            guard selection != nil || focus != nil else { return .ignored }
            deselect()
            return .handled
        }
        .onChange(of: scope.title) { selection = nil }
        .confirmationDialog("Clear \(completedCount) completed task\(completedCount == 1 ? "" : "s")?", isPresented: $confirmsClear) {
            Button("Clear", role: .destructive) {
                let done = visibleScope.filter(\.isDone)
                done.forEach(app.reminders.removeMirror)
                withMotion(.snappy) { WorkspaceActions(context: context).clearCompleted(done) }
            }
        } message: {
            Text("They're deleted from every device.")
        }
    }

    // MARK: Header

    /// Top row: layout switch, project settings, new task (the + in Reminders).
    private var toolbar: some View {
        HStack(spacing: 8) {
            if case .list(let project, _) = scope {
                Button { app.go(.project(project.uuid)) } label: {
                    Label(project.name, systemImage: "chevron.left")
                        .appFont(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            GlassSegments(options: Layout.allCases, selection: $layout, height: 30, label: { $0.rawValue }, systemImage: { $0 == .list ? "list.bullet" : "rectangle.split.3x1" })
                .frame(width: 170)
            if let project = scope.project {
                Button { app.present(.projectSettings(project.uuid)) } label: {
                    Image(systemName: "slider.horizontal.3")
                        .appFont(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(QuietButtonStyle())
                .help("Project settings")
                .accessibilityLabel("Project settings")
            }
            // A small menu, like right-clicking: New Task or New List.
            Menu {
                Button("New Task", systemImage: "checklist") { startNewTask() }
                Button("New List", systemImage: "list.bullet.rectangle") { app.present(.newList(project: scope.project?.uuid)) }
            } label: {
                Image(systemName: "plus")
                    .appFont(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(QuietButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("New task or list")
            .accessibilityLabel("Add")
        }
    }

    /// Big coloured title with the open count, then "N Completed · Clear" and Show/Hide.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let project = scope.project, scope.list == nil {
                    ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 26)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                }
                Text(title)
                    .appFont(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Spacer()
                if !(isAll && smart == .completed) {
                    Text("\(openCount)")
                        .appFont(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(openCount) open")
                }
            }
            if let project = scope.project, !project.summary.isEmpty, scope.list == nil {
                Text(project.summary).appFont(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            if !(isAll && smart == .completed) {
                HStack(spacing: 6) {
                    Text("\(completedCount) Completed")
                        .foregroundStyle(Theme.secondaryText)
                    if completedCount > 0 {
                        Text("·").foregroundStyle(Theme.tertiaryText)
                        Button("Clear") { confirmsClear = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(accent)
                    }
                    Spacer()
                    if completedCount > 0 {
                        Button(showsCompleted ? "Hide" : "Show") {
                            withMotion(.snappy(duration: 0.25)) { showsCompleted.toggle() }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                    }
                }
                .appFont(.system(size: 13.5, weight: .medium))
                .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1).offset(y: 4) }
    }

    // MARK: Data

    private var isAll: Bool {
        if case .all = scope { return true }
        return false
    }

    private var title: String {
        isAll ? smart.title : scope.title
    }

    private var accent: Color {
        if isAll { return smart.color }
        return scope.project?.color.color ?? .accentColor
    }

    private var scoped: [TaskItem] {
        switch scope {
        case .all: allTasks
        case .project(let p): allTasks.filter { $0.project?.uuid == p.uuid }
        case .list(_, let l): allTasks.filter { $0.list?.uuid == l.uuid }
        }
    }

    /// The tasks the title counts: the scope, narrowed to the smart list on the Tasks page.
    private var visibleScope: [TaskItem] {
        isAll ? scoped.filter(smart.includes) : scoped
    }

    private var openCount: Int { visibleScope.filter { !$0.isDone }.count }
    private var completedCount: Int { visibleScope.filter(\.isDone).count }

    private var smartCounts: [SmartList: Int] {
        var counts: [SmartList: Int] = [:]
        for list in SmartList.allCases where list != .completed {
            counts[list] = allTasks.filter { !$0.isDone && list.includes($0) }.count
        }
        return counts
    }

    /// Open tasks, plus ones ticked a moment ago, plus completed ones when shown.
    private func shown(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { !$0.isDone || showsCompleted || lingering.contains($0.uuid) }
    }

    private var sections: [TaskSection] {
        switch scope {
        case .list(let project, let list):
            return [TaskSection(id: list.uuid.uuidString, title: nil, color: project.color.color, tasks: shown(scoped), project: project, list: list)]
        case .project(let project):
            // Tasks outside any list first, then one section per list, like Reminders' groups.
            let loose = TaskSection(id: "loose", title: nil, color: project.color.color, tasks: shown(scoped.filter { $0.list == nil }), project: project)
            let lists = project.sortedLists.map { list in
                TaskSection(id: list.uuid.uuidString, title: list.name, color: project.color.color, tasks: shown(scoped.filter { $0.list?.uuid == list.uuid }), project: project, list: list)
            }
            return [loose] + lists
        case .all:
            return smartSections
        }
    }

    private var smartSections: [TaskSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let color = smart.color
        switch smart {
        case .today:
            let tasks = shown(allTasks.filter(SmartList.today.includes)).sorted(by: byDue)
            return [TaskSection(id: "today", title: nil, color: color, tasks: tasks, dueDefault: today, showsProject: true)]
        case .scheduled:
            let tasks = shown(allTasks.filter { $0.dueDate != nil }).sorted(by: byDue)
            var result: [TaskSection] = []
            let overdue = tasks.filter { ($0.dueDate ?? .now) < today }
            if !overdue.isEmpty {
                result.append(TaskSection(id: "overdue", title: "Overdue", color: .red, tasks: overdue, acceptsNew: false, showsProject: true))
            }
            // Today, tomorrow and the rest of the week always show, so there's somewhere to add.
            var days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }
            let later = Set(tasks.compactMap { $0.dueDate.map(cal.startOfDay) }.filter { $0 >= days.last!.addingTimeInterval(86_400) })
            days += later.sorted()
            for day in days {
                let items = tasks.filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
                let name = cal.isDateInToday(day) ? "Today" : cal.isDateInTomorrow(day) ? "Tomorrow" : DueText.day(day)
                result.append(TaskSection(id: "day-\(Int(day.timeIntervalSince1970))", title: name, color: color, tasks: items, dueDefault: day, showsProject: true))
            }
            return result
        case .all:
            var result: [TaskSection] = projects.map { project in
                TaskSection(id: project.uuid.uuidString, title: project.name, color: project.color.color, tasks: shown(allTasks.filter { $0.project?.uuid == project.uuid }), project: project)
            }
            result.append(TaskSection(id: "none", title: "No project", color: color, tasks: shown(allTasks.filter { $0.project == nil })))
            return result
        case .flagged:
            return [TaskSection(id: "flagged", title: nil, color: color, tasks: shown(allTasks.filter(\.isFlagged)), flaggedDefault: true, showsProject: true)]
        case .urgent:
            return [TaskSection(id: "urgent", title: nil, color: color, tasks: shown(allTasks.filter { $0.priority == .urgent }), priorityDefault: .urgent, showsProject: true)]
        case .completed:
            let done = allTasks.filter(\.isDone).sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            var groups: [TaskSection] = projects.compactMap { project in
                let items = done.filter { $0.project?.uuid == project.uuid }
                return items.isEmpty ? nil : TaskSection(id: project.uuid.uuidString, title: project.name, color: project.color.color, tasks: items, acceptsNew: false)
            }
            let loose = done.filter { $0.project == nil }
            if !loose.isEmpty { groups.append(TaskSection(id: "none", title: "No project", color: color, tasks: loose, acceptsNew: false)) }
            return groups
        }
    }

    private func byDue(_ a: TaskItem, _ b: TaskItem) -> Bool {
        (a.dueDate ?? .distantFuture, b.priority.sortRank) < (b.dueDate ?? .distantFuture, a.priority.sortRank)
    }

    // MARK: Actions

    private func deselect() {
        selection = nil
        focus = nil
    }

    /// + focuses the blank row of the first section that takes new tasks.
    private func startNewTask() {
        layout = .list
        if isAll, smart == .completed { smart = .today }
        selection = nil
        if let section = sections.first(where: \.acceptsNew) {
            focus = .newTask(section.id)
        }
    }
}

extension TaskPriority {
    var sortRank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .urgent: 3
        }
    }

    var piece: TaskRow.Priority {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high, .urgent: .high
        }
    }
}

struct TaskListRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let task: TaskItem

    var body: some View {
        TaskRow(
            task.title,
            status: statusBinding,
            due: dueLabel,
            priority: task.priority.piece,
            tint: task.project?.color.color,
            style: pieceStyle,
            onTap: { app.present(.task(task.uuid)) },
            onSnooze: snooze,
            onDelete: { withAnimation { WorkspaceActions(context: context).delete(task) } }
        )
        .fontRole(.data)
        .contextMenu {
            Menu("Status") {
                ForEach(TaskStatus.allCases) { status in
                    Button(status.title, systemImage: status.symbol) {
                        WorkspaceActions(context: context).setStatus(status, for: task)
                        app.syncReminder(for: task)
                    }
                }
            }
            Button("Snooze until tomorrow", systemImage: "moon.zzz", action: snooze)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                WorkspaceActions(context: context).delete(task)
            }
        }
    }

    private var pieceStyle: TaskRow.Style {
        var style = TaskRow.Style()
        style.surface = Theme.surface
        style.text = Theme.text
        style.muted = Theme.secondaryText
        style.cornerRadius = 14
        return style
    }

    private var dueLabel: String? {
        var parts: [String] = []
        if let due = task.dueDate {
            parts.append(task.isOverdue ? "Overdue · " + due.formatted(.dateTime.month(.abbreviated).day()) : due.formatted(.relative(presentation: .named)))
        }
        if let project = task.project { parts.append(task.list.map { "\(project.name) › \($0.name)" } ?? project.name) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var statusBinding: Binding<TaskRow.Status> {
        Binding {
            task.isDone ? .completed : .open
        } set: { newValue in
            switch newValue {
            case .completed: WorkspaceActions(context: context).setStatus(.done, for: task)
            case .open: WorkspaceActions(context: context).setStatus(.todo, for: task)
            case .snoozed: snooze()
            }
            app.syncReminder(for: task)
        }
    }

    private func snooze() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!.addingTimeInterval(9 * 3600)
        task.dueDate = tomorrow
        app.syncReminder(for: task)
        app.show("Snoozed until tomorrow", detail: task.title, style: .info)
    }
}

struct PriorityChip: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.title)
            .appFont(.caption.weight(.medium))
            .foregroundStyle(priority.color)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(priority.color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Board

struct BoardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let tasks: [TaskItem]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(TaskStatus.allCases) { status in
                    column(status)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    private func column(_ status: TaskStatus) -> some View {
        let items = tasks.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.symbol).foregroundStyle(status.color)
                Text(status.title).appFont(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(items.count)").appFont(.caption).foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { task in
                        BoardCard(task: task)
                            .draggable(task.uuid.uuidString)
                    }
                    if items.isEmpty {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .frame(minHeight: 64)
                            .overlay { Text("Drop here").appFont(.caption).foregroundStyle(Theme.tertiaryText) }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke) }
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init(uuidString:)) {
                if let task = context.task(id) {
                    withMotion(.snappy) { WorkspaceActions(context: context).setStatus(status, for: task) }
                    app.syncReminder(for: task)
                }
            }
            return true
        }
    }
}

struct BoardCard: View {
    @Environment(AppModel.self) private var app
    let task: TaskItem

    var body: some View {
        Button { app.present(.task(task.uuid)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .appFont(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    PriorityChip(priority: task.priority)
                    if let due = task.dueDate {
                        Label(due.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                            .appFont(.caption)
                            .foregroundStyle(task.isOverdue ? Color.red : Theme.secondaryText)
                    }
                    Spacer()
                    if let project = task.project {
                        ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 16)
                    }
                }
            }
            .padding(12)
            .fontRole(.data)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Projects overview

struct ProjectsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Projects", subtitle: "\(projects.count) active") {
                    Button("New project", systemImage: "plus") { app.present(.newProject) }
                        .buttonStyle(QuietButtonStyle())
                }
                if projects.isEmpty {
                    EmptyStateView(symbol: "folder", title: "No projects", message: "Projects group tasks into lists and sync across your devices.", actionTitle: "Create project") { app.present(.newProject) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(projects) { project in
                        Button { app.go(.project(project.uuid)) } label: {
                            Card {
                                HStack {
                                    ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 28)
                                    Spacer()
                                    Text("\(project.openTaskCount) open").appFont(.caption).foregroundStyle(Theme.secondaryText)
                                }
                                Text(project.name).appFont(.headline).foregroundStyle(Theme.text)
                                Text(project.summary.isEmpty ? "No description" : project.summary)
                                    .appFont(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(2, reservesSpace: true)
                                ProgressView(value: project.progress).tint(project.color.color)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Projects")
    }
}
