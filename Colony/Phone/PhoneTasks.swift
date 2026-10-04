//
//  PhoneTasks.swift
//  Colony
//
//  Tasks on iPhone, like Reminders: smart tiles with counts, My Lists as a card of
//  coloured circles, and a list screen with a coloured large title, completion
//  circles, swipe actions and an inline "New Task" row.
//

#if os(iOS)
import SwiftData
import SwiftUI

enum PhoneTaskFilter: Hashable {
    case today, scheduled, flagged, all, late, completed
    case project(UUID)
    case list(UUID, UUID)

    static let smart: [PhoneTaskFilter] = [.today, .scheduled, .flagged, .all]

    var title: String {
        switch self {
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .flagged: "Flagged"
        case .all: "All"
        case .late: "Late"
        case .completed: "Completed"
        case .project, .list: ""
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .scheduled: "calendar"
        case .flagged: "flag.fill"
        case .all: "tray.fill"
        case .late: "exclamationmark.triangle.fill"
        case .completed: "checkmark"
        case .project, .list: "list.bullet"
        }
    }

    var color: Color {
        switch self {
        case .today: ColonyColor.blue.color
        case .scheduled: ColonyColor.red.color
        case .flagged: ColonyColor.orange.color
        case .all: Color(white: 0.45)
        case .late: ColonyColor.red.color
        case .completed: Color(white: 0.45)
        case .project, .list: ColonyColor.blue.color
        }
    }

    func matches(_ task: TaskItem, now: Date = .now) -> Bool {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        switch self {
        case .today: return !task.isDone && (task.dueDate ?? .distantFuture) < endOfToday
        case .scheduled: return !task.isDone && task.dueDate != nil
        case .flagged: return !task.isDone && task.isFlagged
        case .all: return !task.isDone
        case .late: return !task.isDone && task.isOverdue
        case .completed: return task.isDone
        case .project(let id): return !task.isDone && task.project?.uuid == id
        case .list(_, let id): return !task.isDone && task.list?.uuid == id
        }
    }
}

// MARK: - Home

struct PhoneTasksHome: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Query private var tasksEverywhere: [TaskItem]
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]

    var body: some View {
        let tasks = tasksEverywhere.inWorkspace()
        let projects = projectsEverywhere.inWorkspace().filter { $0.archivedAt == nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(PhoneTaskFilter.smart, id: \.self) { filter in
                        SmartTile(filter: filter, count: tasks.filter { filter.matches($0) }.count) {
                            nav.push(.taskList(filter))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    PhoneSectionHeader("My Lists")
                    if projects.isEmpty {
                        PhoneCard {
                            Text("Projects you create show up here.").foregroundStyle(.secondary)
                        }
                    } else {
                        PhoneRowsCard {
                            ForEach(projects) { project in
                                ProjectRow(project: project)
                            }
                        }
                    }
                }

                let done = tasks.filter(\.isDone).count
                if done > 0 {
                    PhoneRowsCard {
                        PhoneRow(
                            icon: AnyView(CircleIcon(symbol: "checkmark", color: Color(white: 0.45), size: 40)),
                            title: "Completed",
                            action: { nav.push(.taskList(.completed)) }
                        ) {
                            Text("\(done)").appFont(.system(size: 17)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").appFont(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, Phone.margin)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Phone.canvas)
        .phoneScrollEdge()
        .navigationTitle("Tasks")
        .toolbar { PhoneRootToolbar() }
    }
}

/// Reminders' smart-list tile: icon top-left, big count top-right, title below.
private struct SmartTile: View {
    let filter: PhoneTaskFilter
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    CircleIcon(symbol: filter.symbol, color: filter.color, size: 36)
                    Spacer()
                    Text("\(count)")
                        .appFont(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                Text(filter.title)
                    .appFont(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Phone.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title), \(count)")
    }
}

private struct ProjectRow: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Environment(\.modelContext) private var context
    let project: Project

    var body: some View {
        PhoneRow(
            icon: AnyView(CircleIcon(symbol: project.symbol, color: project.color.color, size: 40)),
            title: project.name,
            subtitle: project.sortedLists.isEmpty ? nil : project.sortedLists.map(\.name).joined(separator: " · "),
            action: { nav.push(.taskList(.project(project.uuid))) }
        ) {
            Text("\(project.openTaskCount)").appFont(.system(size: 17)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").appFont(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .contextMenu {
            Button("New Task", systemImage: "plus") { app.present(.newTask(project: project.uuid, list: nil)) }
            Button("New List", systemImage: "list.bullet") { app.present(.newList(project: project.uuid)) }
            Button("Project Settings…", systemImage: "gearshape") { app.present(.projectSettings(project.uuid)) }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { app.present(.deleteProject(project.uuid)) }
        }
    }
}

// MARK: - List

struct PhoneTaskList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var tasksEverywhere: [TaskItem]
    let filter: PhoneTaskFilter
    @State private var lingering: Set<UUID> = []
    @State private var draft = ""
    @FocusState private var adding: Bool

    var body: some View {
        let shown = tasksEverywhere.inWorkspace().filter { filter.matches($0) || lingering.contains($0.uuid) }
        let groups = sections(shown)

        List {
            Section {
                header(count: shown.filter { !$0.isDone }.count)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            .listRowSeparator(.hidden)

            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.tasks) { task in
                        PhoneTaskRow(task: task, accent: accent, inList: true) { ticked in
                            guard ticked else { return }
                            lingering.insert(task.uuid)
                            Task {
                                try? await Task.sleep(for: .seconds(1.4))
                                withMotion(.snappy) { _ = lingering.remove(task.uuid) }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    }
                    if group.title == groups.last?.title, filter != .completed { newTaskRow }
                } header: {
                    if !group.title.isEmpty {
                        Text(group.title)
                            .appFont(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(group.isWarning ? ColonyColor.red.color : .primary)
                            .textCase(nil)
                            .padding(.leading, -16)
                    }
                }
            }

            if groups.isEmpty && filter != .completed {
                Section { newTaskRow }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.horizontal, Phone.margin, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Phone.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title).appFont(.system(size: 17, weight: .semibold)).opacity(0)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New Task", systemImage: "plus") { adding = true }
                    if case .project(let id) = filter {
                        Button("New List", systemImage: "list.bullet") { app.present(.newList(project: id)) }
                        Button("Project Settings…", systemImage: "gearshape") { app.present(.projectSettings(id)) }
                    }
                    if filter == .completed {
                        Button("Clear Completed", systemImage: "trash", role: .destructive) {
                            let n = WorkspaceActions(context: context).clearCompleted(shown)
                            app.show("Cleared \(n) completed task\(n == 1 ? "" : "s")")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
    }

    private var newTaskRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus.circle.fill")
                .appFont(.system(size: 24))
                .foregroundStyle(accent)
                .frame(width: 40)
            TextField("New Task", text: $draft)
                .appFont(.system(size: 17))
                .focused($adding)
                .submitLabel(.done)
                .onSubmit(add)
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 16))
    }

    // MARK: Header

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appFont(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(2)
                Spacer()
                Text("\(count)")
                    .appFont(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
            }
            if let subtitle {
                Text(subtitle)
                    .appFont(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var project: Project? {
        switch filter {
        case .project(let id), .list(let id, _): context.project(id)
        default: nil
        }
    }

    private var list: ProjectList? {
        if case .list(_, let id) = filter { return context.list(id) }
        return nil
    }

    private var title: String {
        if let list { return list.name }
        if let project { return project.name }
        return filter.title
    }

    private var subtitle: String? {
        if list != nil { return project?.name }
        if filter == .today { return Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
        return nil
    }

    private var accent: Color { project?.color.color ?? filter.color }

    // MARK: Sections

    private struct Group { let title: String; let tasks: [TaskItem]; var isWarning = false }

    private func sections(_ tasks: [TaskItem]) -> [Group] {
        let sorted = tasks.sorted { ($0.dueDate ?? .distantFuture, $0.priority.rank, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.priority.rank, $1.createdAt) }
        switch filter {
        case .completed:
            let byDone = tasks.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return [Group(title: "", tasks: byDone)].filter { !$0.tasks.isEmpty }
        case .project:
            guard let project else { return [] }
            var groups: [Group] = []
            let loose = sorted.filter { $0.list == nil }
            if !loose.isEmpty { groups.append(Group(title: project.sortedLists.isEmpty ? "" : "Tasks", tasks: loose)) }
            for list in project.sortedLists {
                let items = sorted.filter { $0.list?.uuid == list.uuid }
                if !items.isEmpty { groups.append(Group(title: list.name, tasks: items)) }
            }
            return groups
        case .scheduled:
            let byDay = Dictionary(grouping: sorted) { Calendar.current.startOfDay(for: $0.dueDate ?? .now) }
            return byDay.keys.sorted().map { day in
                let late = day < Calendar.current.startOfDay(for: .now)
                return Group(title: late ? "Late" : DueText.day(day), tasks: byDay[day] ?? [], isWarning: late)
            }
            .reduce(into: [Group]()) { result, group in
                // Merge all late days into one "Late" section.
                if group.isWarning, let i = result.firstIndex(where: \.isWarning) {
                    result[i] = Group(title: "Late", tasks: result[i].tasks + group.tasks, isWarning: true)
                } else {
                    result.append(group)
                }
            }
        default:
            let late = sorted.filter(\.isOverdue)
            let rest = sorted.filter { !$0.isOverdue }
            return [Group(title: late.isEmpty ? "" : "Late", tasks: late, isWarning: true), Group(title: late.isEmpty ? "" : "Next", tasks: rest)]
                .filter { !$0.tasks.isEmpty }
        }
    }

    // MARK: Add

    private func add() {
        let title = ColonyText.trimmed(draft)
        guard !title.isEmpty else { adding = false; return }
        let actions = WorkspaceActions(context: context)
        let task = actions.createTask(title: title, project: project, list: list)
        if let task {
            switch filter {
            case .today: actions.setDue(Calendar.current.startOfDay(for: .now), hasTime: false, for: task)
            case .flagged: actions.toggleFlag(task)
            default: break
            }
        }
        draft = ""
        adding = true
    }
}

// MARK: - Row

/// One task: completion circle, title, due/project line, flag. Tap opens the editor;
/// swipe to complete, flag or delete.
struct PhoneTaskRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let task: TaskItem
    var accent: Color?
    var inList = false
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        let color = accent ?? task.project?.color.color ?? ColonyColor.blue.color
        HStack(alignment: .top, spacing: 14) {
            Button(action: toggle) {
                PhoneCheckCircle(isOn: task.isDone, color: color)
                    .padding(.top, 1)
                    .frame(width: 40, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark as not done" : "Complete")

            Button { app.present(.task(task.uuid)) } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .appFont(.system(size: 17, weight: inList ? .regular : .semibold))
                            .foregroundStyle(task.isDone ? .secondary : .primary)
                            .strikethrough(task.isDone && !inList)
                            .multilineTextAlignment(.leading)
                        if !detail.isEmpty {
                            Text(detail)
                                .appFont(.system(size: 15))
                                .foregroundStyle(task.isOverdue ? ColonyColor.red.color : .secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    if task.priority == .urgent || task.priority == .high {
                        Text(task.priority == .urgent ? "!!!" : "!!")
                            .appFont(.system(size: 15, weight: .bold))
                            .foregroundStyle(color)
                    }
                    if task.isFlagged {
                        Image(systemName: "flag.fill").foregroundStyle(ColonyColor.orange.color)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .padding(.vertical, inList ? 10 : 13)
        .swipeActions(edge: .leading) {
            Button(task.isDone ? "Undo" : "Done", systemImage: "checkmark", action: toggle).tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { WorkspaceActions(context: context).delete(task) }
            Button(task.isFlagged ? "Unflag" : "Flag", systemImage: "flag") { WorkspaceActions(context: context).toggleFlag(task) }
                .tint(.orange)
        }
        .contextMenu {
            Button(task.isFlagged ? "Unflag" : "Flag", systemImage: "flag") { WorkspaceActions(context: context).toggleFlag(task) }
            Button("Due Tomorrow", systemImage: "sunrise") {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
                WorkspaceActions(context: context).setDue(tomorrow, hasTime: false, for: task)
            }
            Button("Details", systemImage: "info.circle") { app.present(.task(task.uuid)) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { WorkspaceActions(context: context).delete(task) }
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        var parts: [String] = []
        if let due = DueText.label(for: task) { parts.append(due) }
        if !inList, let project = task.project?.name { parts.append(project) }
        if inList, let list = task.list?.name, task.project != nil { parts.append(list) }
        return parts.joined(separator: " · ")
    }

    private func toggle() {
        let willBeDone = !task.isDone
        withMotion(.snappy) { WorkspaceActions(context: context).toggleDone(task) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onToggle?(willBeDone)
    }
}
#endif
