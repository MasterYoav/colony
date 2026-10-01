//
//  RemindersList.swift
//  Colony
//
//  The task list, laid out like Apple's Reminders: coloured smart-list tiles, a big
//  coloured title with its count, "N Completed · Clear / Show", sections with
//  disclosure headers, and rows you edit in place. Selecting a row opens its notes
//  and a chip bar (date, time, flag, priority, project) with ⓘ for the full editor.
//  A blank row at the end of each section adds a task; Return adds the next one.
//

import SwiftData
import SwiftUI

// MARK: - Smart lists

enum SmartList: String, CaseIterable, Identifiable {
    case today, scheduled, all, flagged, urgent, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .all: "All"
        case .flagged: "Flagged"
        case .urgent: "Urgent"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .today: "calendar.day.timeline.left"
        case .scheduled: "calendar"
        case .all: "tray.fill"
        case .flagged: "flag.fill"
        case .urgent: "alarm.fill"
        case .completed: "checkmark"
        }
    }

    /// Tile colours, after Reminders.
    var color: Color {
        switch self {
        case .today: Color(red: 0.23, green: 0.52, blue: 0.97)
        case .scheduled: Color(red: 0.93, green: 0.33, blue: 0.33)
        case .all: Color(red: 0.36, green: 0.37, blue: 0.40)
        case .flagged: Color(red: 0.96, green: 0.58, blue: 0.20)
        case .urgent: Color(red: 0.91, green: 0.33, blue: 0.53)
        case .completed: Color(red: 0.50, green: 0.52, blue: 0.56)
        }
    }

    /// Open tasks that belong here (Completed lists done ones).
    func includes(_ task: TaskItem) -> Bool {
        switch self {
        case .today:
            guard let due = task.dueDate else { return false }
            return due < Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        case .scheduled: return task.dueDate != nil
        case .all: return true
        case .flagged: return task.isFlagged
        case .urgent: return task.priority == .urgent
        case .completed: return true
        }
    }
}

/// A run of rows under one header. New tasks added in it get its defaults.
struct TaskSection: Identifiable {
    let id: String
    var title: String?
    var color: Color
    var tasks: [TaskItem]
    var project: Project?
    var list: ProjectList?
    var dueDefault: Date?
    var flaggedDefault = false
    var priorityDefault: TaskPriority = .medium
    var acceptsNew = true
    /// Rows show which project they're in (mixed views like Today).
    var showsProject = false
}

enum TaskFocus: Hashable {
    case title(UUID)
    case newTask(String)
}

// MARK: - Dates

enum DueText {
    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        if (2...6).contains(days) { return date.formatted(.dateTime.weekday(.wide)) }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func label(for task: TaskItem) -> String? {
        guard let due = task.dueDate else { return nil }
        return task.dueHasTime ? "\(day(due)), \(time(due))" : day(due)
    }
}

// MARK: - Screen body

/// Everything under the header: sections of rows, or the empty state.
struct RemindersList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let sections: [TaskSection]
    let accent: Color
    @Binding var selection: UUID?
    var focus: FocusState<TaskFocus?>.Binding
    /// Rows ticked a moment ago stay visible briefly, as in Reminders.
    @Binding var lingering: Set<UUID>
    @State private var collapsed: Set<String> = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                if let title = section.title {
                    sectionHeader(section, title: title)
                }
                if !collapsed.contains(section.id) {
                    ForEach(section.tasks) { task in
                        TaskReminderRow(
                            task: task,
                            tint: section.color,
                            showsProject: section.showsProject,
                            isSelected: selection == task.uuid,
                            focus: focus,
                            select: { select(task) },
                            onReturn: { addAfter(task, in: section) },
                            onComplete: { complete(task) }
                        )
                    }
                    if section.acceptsNew {
                        NewTaskRow(section: section, focus: focus) { title in
                            create(title, in: section)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: TaskSection, title: String) -> some View {
        let isCollapsed = collapsed.contains(section.id)
        return Button {
            withMotion(.snappy(duration: 0.2)) {
                if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
            }
        } label: {
            HStack {
                Text(title)
                    .appFont(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(section.color)
                if isCollapsed, !section.tasks.isEmpty {
                    Text("\(section.tasks.count)")
                        .appFont(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .appFont(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .padding(.top, 18)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) section")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }

    private func select(_ task: TaskItem) {
        guard selection != task.uuid else { return }
        selection = task.uuid
        focus.wrappedValue = .title(task.uuid)
    }

    private func complete(_ task: TaskItem) {
        let actions = WorkspaceActions(context: context)
        if task.isDone {
            actions.setStatus(.todo, for: task)
        } else {
            actions.setStatus(.done, for: task)
            lingering.insert(task.uuid)
            let id = task.uuid
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                _ = withMotion(.easeOut(duration: 0.25)) { lingering.remove(id) }
            }
        }
        app.syncReminder(for: task)
    }

    @discardableResult
    private func create(_ title: String, in section: TaskSection) -> TaskItem? {
        let actions = WorkspaceActions(context: context)
        guard let task = actions.createTask(title: title, priority: section.priorityDefault, project: section.project, list: section.list) else { return nil }
        if let due = section.dueDefault { actions.setDue(due, hasTime: false, for: task) }
        task.isFlagged = section.flaggedDefault
        app.syncReminder(for: task)
        return task
    }

    /// Return in a title: Reminders starts a new blank task right below.
    private func addAfter(_ task: TaskItem, in section: TaskSection) {
        if ColonyText.trimmed(task.title).isEmpty { return }
        selection = nil
        if section.acceptsNew { focus.wrappedValue = .newTask(section.id) } else { focus.wrappedValue = nil }
    }
}

// MARK: - Row

struct TaskReminderRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskItem
    let tint: Color
    let showsProject: Bool
    let isSelected: Bool
    var focus: FocusState<TaskFocus?>.Binding
    let select: () -> Void
    let onReturn: () -> Void
    let onComplete: () -> Void
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace() }
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CheckCircle(isDone: task.isDone, tint: tint, action: onComplete)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                title
                if isSelected || !task.notes.isEmpty {
                    notes
                }
                if !isSelected, let meta = metaLine {
                    meta
                }
                if isSelected {
                    ChipBar(task: task, projects: projects)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if task.isFlagged {
                Image(systemName: "flag.fill")
                    .appFont(.system(size: 12))
                    .foregroundStyle(SmartList.flagged.color)
                    .padding(.top, 3)
                    .accessibilityLabel("Flagged")
            }
            if isSelected || isHovering {
                Button { app.present(.task(task.uuid)) } label: {
                    Image(systemName: "info.circle")
                        .appFont(.system(size: 16))
                        .foregroundStyle(isSelected ? Color.accentColor : Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Show details")
                .accessibilityLabel("Show details")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Theme.selection.opacity(0.7) : .clear)
        }
        .overlay(alignment: .bottom) {
            // Hairline under the text, not under the circle, as in Reminders.
            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 38).opacity(isSelected ? 0 : 1)
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .opacity(task.isDone ? 0.55 : 1)
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .onChange(of: focus.wrappedValue) { old, new in
            // Leaving an emptied title deletes the task, like Reminders.
            if old == .title(task.uuid), new != .title(task.uuid), ColonyText.trimmed(task.title).isEmpty {
                WorkspaceActions(context: context).delete(task)
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        if isSelected {
            TextField("Title", text: $task.title)
                .textFieldStyle(.plain)
                .appFont(.system(size: 14.5), role: .data)
                .foregroundStyle(Theme.text)
                .focused(focus, equals: .title(task.uuid))
                .onSubmit(onReturn)
        } else {
            Text(task.title.isEmpty ? " " : task.title)
                .appFont(.system(size: 14.5), role: .data)
                .foregroundStyle(task.isDone ? Theme.secondaryText : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(PriorityPrefix(marks: priorityMarks, tint: tint))
        }
    }

    @ViewBuilder
    private var notes: some View {
        if isSelected {
            TextField("Notes", text: $task.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .appFont(.system(size: 12.5), role: .data)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1...8)
        } else {
            Text(task.notes)
                .appFont(.system(size: 12.5), role: .data)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(3)
        }
    }

    private var metaLine: Text? {
        var pieces: [Text] = []
        if let label = DueText.label(for: task) {
            pieces.append(Text(label).foregroundStyle(task.isOverdue ? Color.red : Theme.secondaryText))
        }
        if showsProject, let project = task.project {
            pieces.append(Text(task.list.map { "\(project.name) › \($0.name)" } ?? project.name).foregroundStyle(Theme.tertiaryText))
        }
        guard !pieces.isEmpty else { return nil }
        let joined = pieces.dropFirst().reduce(pieces[0]) { $0 + Text("  ") + $1 }
        return joined.font(.system(size: 12))
    }

    private var priorityMarks: String? {
        switch task.priority {
        case .urgent: "!!!"
        case .high: "!!"
        default: nil
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button(task.isFlagged ? "Unflag" : "Flag", systemImage: task.isFlagged ? "flag.slash" : "flag") {
            WorkspaceActions(context: context).toggleFlag(task)
        }
        Menu("Priority") {
            ForEach(TaskPriority.allCases.reversed()) { priority in
                Toggle(priority.title, isOn: Binding(get: { task.priority == priority }, set: { _ in task.priority = priority; app.syncReminder(for: task) }))
            }
        }
        Menu("Due") {
            Button("Today") { setDue(Calendar.current.startOfDay(for: .now)) }
            Button("Tomorrow") { setDue(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))) }
            Button("Next Week") { setDue(Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))) }
            if task.dueDate != nil {
                Divider()
                Button("No Date") { setDue(nil) }
            }
        }
        Menu("Move To") {
            Button("No project") { WorkspaceActions(context: context).move(task, to: nil) }
            ForEach(projects) { project in
                if project.sortedLists.isEmpty {
                    Button(project.name) { WorkspaceActions(context: context).move(task, to: project) }
                } else {
                    Menu(project.name) {
                        Button(project.name) { WorkspaceActions(context: context).move(task, to: project) }
                        ForEach(project.sortedLists) { list in
                            Button(list.name) { WorkspaceActions(context: context).move(task, to: project, list: list) }
                        }
                    }
                }
            }
        }
        Button("Show Details", systemImage: "info.circle") { app.present(.task(task.uuid)) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            app.reminders.removeMirror(for: task)
            WorkspaceActions(context: context).delete(task)
        }
    }

    private func setDue(_ date: Date?) {
        WorkspaceActions(context: context).setDue(date, hasTime: false, for: task)
        app.syncReminder(for: task)
    }
}

/// "!!! Title" with the marks in the list colour.
private struct PriorityPrefix: ViewModifier {
    let marks: String?
    let tint: Color

    func body(content: Content) -> some View {
        if let marks {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(marks)
                    .appFont(.system(size: 14.5, weight: .bold), role: .data)
                    .foregroundStyle(tint)
                    .accessibilityLabel(marks == "!!!" ? "Urgent" : "High priority")
                content
            }
        } else {
            content
        }
    }
}

/// The round checkbox: an outline, or a ring with a filled centre when done.
struct CheckCircle: View {
    let isDone: Bool
    let tint: Color
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? tint : Theme.tertiaryText, lineWidth: 1.5)
                Circle()
                    .fill(tint)
                    .padding(4)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: isDone)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Completed" : "Not completed")
        .accessibilityHint("Toggles completion")
        .sensoryFeedback(.success, trigger: isDone) { _, new in new }
    }
}

/// The blank row at the end of a section.
private struct NewTaskRow: View {
    let section: TaskSection
    var focus: FocusState<TaskFocus?>.Binding
    let create: (String) -> TaskItem?
    @State private var text = ""

    var body: some View {
        let isFocused = focus.wrappedValue == .newTask(section.id)
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Theme.tertiaryText.opacity(isFocused ? 1 : 0.6), style: StrokeStyle(lineWidth: 1.5, dash: isFocused ? [] : [2, 2.5]))
                .frame(width: 20, height: 20)
            TextField(section.tasks.isEmpty ? "New task" : "", text: $text, prompt: Text("New task").foregroundStyle(Theme.tertiaryText))
                .textFieldStyle(.plain)
                .appFont(.system(size: 14.5), role: .data)
                .focused(focus, equals: .newTask(section.id))
                .onSubmit {
                    guard create(text) != nil else { return }
                    text = ""
                    // Stay in the blank row for the next one.
                    focus.wrappedValue = .newTask(section.id)
                }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .contentShape(.rect)
        .onTapGesture { focus.wrappedValue = .newTask(section.id) }
        .accessibilityLabel("New task in \(section.title ?? "this list")")
    }
}

// MARK: - Chip bar

/// Date, time, flag, priority and project for the selected row.
private struct ChipBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskItem
    let projects: [Project]
    @State private var isPickingDate = false
    @State private var isPickingTime = false

    var body: some View {
        HStack(spacing: 8) {
            // Date
            Chip(
                symbol: "calendar",
                title: task.dueDate.map(DueText.day) ?? "Add Date",
                isActive: task.dueDate != nil,
                tint: task.isOverdue ? .red : .accentColor,
                onClear: task.dueDate == nil ? nil : { setDue(nil, hasTime: false) }
            ) { isPickingDate = true }
                .popover(isPresented: $isPickingDate, arrowEdge: .bottom) { datePopover }

            // Time (only once there's a date)
            if let due = task.dueDate {
                Chip(
                    symbol: "clock",
                    title: task.dueHasTime ? DueText.time(due) : "Add Time",
                    isActive: task.dueHasTime,
                    tint: .accentColor,
                    onClear: task.dueHasTime ? { setDue(due, hasTime: false) } : nil
                ) { isPickingTime = true }
                    .popover(isPresented: $isPickingTime, arrowEdge: .bottom) { timePopover(due) }
            }

            // Flag
            Chip(symbol: task.isFlagged ? "flag.fill" : "flag", title: nil, isActive: task.isFlagged, tint: SmartList.flagged.color) {
                WorkspaceActions(context: context).toggleFlag(task)
            }
            .accessibilityLabel(task.isFlagged ? "Unflag" : "Flag")

            // Priority
            Menu {
                ForEach(TaskPriority.allCases.reversed()) { priority in
                    Toggle(priority.title, isOn: Binding(get: { task.priority == priority }, set: { _ in
                        task.priority = priority
                        app.syncReminder(for: task)
                    }))
                }
            } label: {
                ChipLabel(symbol: "exclamationmark", title: task.priority == .medium ? nil : task.priority.title, isActive: task.priority == .high || task.priority == .urgent, tint: task.priority.color)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Priority: \(task.priority.title)")

            // Project
            Menu {
                Button("No project") { WorkspaceActions(context: context).move(task, to: nil) }
                ForEach(projects) { project in
                    Button(project.name) { WorkspaceActions(context: context).move(task, to: project) }
                }
            } label: {
                ChipLabel(symbol: "folder", title: task.project?.name, isActive: task.project != nil, tint: task.project?.color.color ?? .accentColor)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Project: \(task.project?.name ?? "none")")
        }
    }

    private var datePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                quick("Today", 0)
                quick("Tomorrow", 1)
                quick("Next Week", 7)
            }
            DatePicker(
                "Date",
                selection: Binding(get: { task.dueDate ?? .now }, set: { setDue($0, hasTime: task.dueDate != nil && task.dueHasTime) }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(width: 250)
        }
        .padding(12)
    }

    private func timePopover(_ due: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                "Time",
                selection: Binding(get: { task.dueHasTime ? due : (Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due) }, set: { setDue($0, hasTime: true) }),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            if task.dueHasTime {
                Button("Remove Time") {
                    setDue(due, hasTime: false)
                    isPickingTime = false
                }
            }
        }
        .padding(12)
    }

    private func quick(_ title: String, _ days: Int) -> some View {
        Button(title) {
            let day = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: .now))!
            if task.dueHasTime, let due = task.dueDate {
                let time = Calendar.current.dateComponents([.hour, .minute], from: due)
                setDue(Calendar.current.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day), hasTime: true)
            } else {
                setDue(day, hasTime: false)
            }
            isPickingDate = false
        }
        .buttonStyle(QuietButtonStyle())
    }

    private func setDue(_ date: Date?, hasTime: Bool) {
        WorkspaceActions(context: context).setDue(date, hasTime: hasTime, for: task)
        app.syncReminder(for: task)
    }
}

private struct Chip: View {
    let symbol: String
    let title: String?
    let isActive: Bool
    let tint: Color
    var onClear: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                ChipLabel(symbol: symbol, title: title, isActive: isActive, tint: tint, trailingPad: onClear == nil)
            }
            .buttonStyle(.plain)
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .appFont(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 22, height: 26)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
            }
        }
        .background(Theme.selection, in: Capsule())
    }
}

private struct ChipLabel: View {
    let symbol: String
    let title: String?
    let isActive: Bool
    let tint: Color
    var trailingPad = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .appFont(.system(size: 11.5, weight: .semibold))
            if let title {
                Text(title)
                    .appFont(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isActive ? tint : Theme.secondaryText)
        .padding(.leading, 10)
        .padding(.trailing, trailingPad ? 10 : 2)
        .frame(minWidth: 30, minHeight: 26)
        .background {
            if trailingPad { Capsule().fill(Theme.selection) }
        }
        .contentShape(Capsule())
    }
}

// MARK: - Smart list tiles

struct SmartListTiles: View {
    @Binding var selection: SmartList?
    let counts: [SmartList: Int]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(SmartList.allCases) { list in
                let isSelected = selection == list
                Button { selection = list } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: list.symbol)
                                .appFont(.system(size: 15, weight: .semibold))
                            Spacer()
                            // Completed has no count, but keeps the same height.
                            Text("\(counts[list] ?? 0)")
                                .appFont(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                                .opacity(list == .completed ? 0 : 1)
                                .accessibilityHidden(list == .completed)
                        }
                        Text(list.title)
                            .appFont(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(LinearGradient(colors: [list.color.opacity(0.92), list.color], startPoint: .top, endPoint: .bottom))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(.white.opacity(isSelected ? 0.85 : 0), lineWidth: 2)
                    }
                    .shadow(color: list.color.opacity(isSelected ? 0.35 : 0), radius: 6, y: 2)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(list.title), \(counts[list] ?? 0)")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
