//
//  TasksScreen.swift
//  Colony
//
//  One screen serves My tasks, All tasks, a project, and a project list.
//  Rows are Swift Pieces `TaskRow`s (swipe to snooze/delete, animated check) with a
//  context menu for pointer users.
//

import SwiftData
import SwiftUI

enum TaskScope {
    case mine
    case all
    case project(Project)
    case list(Project, ProjectList)

    var title: String {
        switch self {
        case .mine: "My tasks"
        case .all: "All tasks"
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
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var allTasks: [TaskItem]
    let scope: TaskScope

    @State private var layout: Layout = .list
    @State private var filter: Set<String> = ["Open"]
    @State private var quickTitle = ""
    @FocusState private var quickFocused: Bool

    enum Layout: String, CaseIterable { case list = "List", board = "Board" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)

            if layout == .list {
                listBody
            } else {
                BoardView(tasks: scoped)
            }
        }
        .navigationTitle(scope.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if let project = scope.project {
                    ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if case .list(let project, _) = scope {
                        Button(project.name) { app.go(.project(project.uuid)) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(scope.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
                GlassSegments(options: Layout.allCases, selection: $layout, height: 32, label: { $0.rawValue }, systemImage: { $0 == .list ? "list.bullet" : "rectangle.split.3x1" })
                    .frame(width: 190)
                Button("New task", systemImage: "plus") {
                    app.present(.newTask(project: scope.project?.uuid, list: scope.list?.uuid))
                }
                .buttonStyle(QuietButtonStyle())
            }

            if let project = scope.project, !project.summary.isEmpty, scope.list == nil {
                Text(project.summary).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }

            if layout == .list {
                FilterRail(options: filterOptions, selection: $filter, counts: counts)
            }
        }
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                quickAdd
                let visible = filtered
                if visible.isEmpty {
                    EmptyStateView(symbol: "checklist", title: "No tasks here", message: "Capture one above, or press ⌘N from anywhere.")
                }
                ForEach(visible) { task in
                    TaskListRow(task: task)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .foregroundStyle(Theme.secondaryText)
            TextField("Add a task and press Return", text: $quickTitle)
                .textFieldStyle(.plain)
                .focused($quickFocused)
                .onSubmit(addQuickTask)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(quickFocused ? Theme.strongStroke : Theme.stroke) }
        .padding(.bottom, 4)
    }

    private func addQuickTask() {
        guard let task = WorkspaceActions(context: context).createTask(title: quickTitle, project: scope.project, list: scope.list) else { return }
        app.syncReminder(for: task)
        quickTitle = ""
        quickFocused = true
    }

    private var scoped: [TaskItem] {
        switch scope {
        case .mine: allTasks.filter(\.assignedToMe)
        case .all: allTasks
        case .project(let p): allTasks.filter { $0.project?.uuid == p.uuid }
        case .list(_, let l): allTasks.filter { $0.list?.uuid == l.uuid }
        }
    }

    private let filterOptions = ["Open", "Today", "Overdue", "Done"]

    private var counts: [String: Int] {
        let s = scoped
        return [
            "Open": s.filter { !$0.isDone }.count,
            "Today": s.filter { $0.isDueToday && !$0.isDone }.count,
            "Overdue": s.filter(\.isOverdue).count,
            "Done": s.filter(\.isDone).count
        ]
    }

    private var filtered: [TaskItem] {
        let chosen = filter.first ?? "Open"
        let base: [TaskItem] = switch chosen {
        case "Today": scoped.filter { $0.isDueToday && !$0.isDone }
        case "Overdue": scoped.filter(\.isOverdue)
        case "Done": scoped.filter(\.isDone)
        default: scoped.filter { !$0.isDone }
        }
        return base.sorted {
            ($0.dueDate ?? .distantFuture, $1.priority.sortRank) < ($1.dueDate ?? .distantFuture, $0.priority.sortRank)
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
            .font(.caption.weight(.medium))
            .foregroundStyle(priority.color)
            .padding(.horizontal, 8)
            .frame(height: 22)
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
                Text(status.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(items.count)").font(.caption).foregroundStyle(Theme.secondaryText)
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
                            .frame(height: 64)
                            .overlay { Text("Drop here").font(.caption).foregroundStyle(Theme.tertiaryText) }
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
                    withAnimation(.snappy) { WorkspaceActions(context: context).setStatus(status, for: task) }
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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    PriorityChip(priority: task.priority)
                    if let due = task.dueDate {
                        Label(due.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? Color.red : Theme.secondaryText)
                    }
                    Spacer()
                    if let project = task.project {
                        ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 16)
                    }
                }
            }
            .padding(12)
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
    @Query(sort: \Project.sortIndex) private var projects: [Project]

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
                                    Text("\(project.openTaskCount) open").font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                                Text(project.name).font(.headline).foregroundStyle(Theme.text)
                                Text(project.summary.isEmpty ? "No description" : project.summary)
                                    .font(.subheadline)
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
