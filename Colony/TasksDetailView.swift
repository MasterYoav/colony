//
//  TasksDetailView.swift
//  Colony
//
//  Created by Yoav Peretz on 18/06/2026.
//

import SwiftUI

struct WorkOverview: View {
    @Binding var store: WorkspaceStore
    let createTask: (String) -> Void
    @State private var searchText = ""
    @State private var newGroupName = ""
    @State private var isAddingGroup = false

    private var filteredTasks: [ColonyTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return store.tasks
        }

        return store.tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query) ||
            task.owner.localizedCaseInsensitiveContains(query) ||
            task.category.localizedCaseInsensitiveContains(query) ||
            task.priority.localizedCaseInsensitiveContains(query) ||
            task.dueDate.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TaskBoardSearchBar(
                text: $searchText,
                resultCount: filteredTasks.count,
                accentColor: store.selectedTheme.accentColor
            )

            VStack(alignment: .leading, spacing: 18) {
                ForEach(store.taskCategories, id: \.self) { category in
                    let tasks = filteredTasks.filter { $0.category == category }

                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tasks.isEmpty {
                        TaskGroupTable(
                            title: category,
                            tasks: tasks,
                            selectedTaskID: selectedTask?.id,
                            accentColor: categoryAccentColor(for: category)
                        ) { taskID in
                            store.selectedTaskID = taskID
                        } updateStatus: { taskID, status in
                            store.updateTaskStatus(taskID: taskID, status: status)
                        } createTask: {
                            createTask(category)
                        }
                    }
                }

                NewTaskGroupRow(
                    name: $newGroupName,
                    isAdding: $isAddingGroup,
                    accentColor: store.selectedTheme.accentColor,
                    createGroup: createGroup
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var selectedTask: ColonyTask? {
        store.selectedTask
    }

    private func categoryAccentColor(for category: String) -> Color {
        switch category {
        case "SharePoint":
            return .blue
        case "AI Tools Integration & Research":
            return .purple
        case "Infrastructure":
            return .green
        default:
            return store.selectedTheme.accentColor
        }
    }

    private func createGroup() {
        store.createTaskGroup(name: newGroupName)
        newGroupName = ""
        isAddingGroup = false
    }
}

private struct TaskBoardSearchBar: View {
    @Binding var text: String
    let resultCount: Int
    let accentColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search tasks, owners, groups, urgency, or dates", text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Text("\(resultCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12), in: Capsule())

                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct NewTaskGroupRow: View {
    @Binding var name: String
    @Binding var isAdding: Bool
    let accentColor: Color
    let createGroup: () -> Void

    private var canCreateGroup: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAdding {
                HStack(spacing: 10) {
                    TextField("New group", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(accentColor.opacity(0.6), lineWidth: 1)
                        }

                    Button("Create", action: createGroup)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canCreateGroup)

                    Button("Cancel") {
                        name = ""
                        isAdding = false
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Button {
                    isAdding = true
                } label: {
                    Label("New Group", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
            }
        }
    }
}

private struct TaskGroupTable: View {
    let title: String
    let tasks: [ColonyTask]
    let selectedTaskID: ColonyTask.ID?
    let accentColor: Color
    let selectTask: (ColonyTask.ID) -> Void
    let updateStatus: (ColonyTask.ID, TaskStatus) -> Void
    let createTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(accentColor)

                Text("\(tasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())

                Spacer()

                Button(action: createTask) {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(accentColor)
            }

            VStack(spacing: 0) {
                TaskTableHeader()

                if tasks.isEmpty {
                    EmptyTaskGroupRow(createTask: createTask)
                } else {
                    ForEach(tasks) { task in
                        TaskTableRow(
                            task: task,
                            isSelected: task.id == selectedTaskID,
                            accentColor: accentColor
                        ) {
                            selectTask(task.id)
                        } updateStatus: { status in
                            updateStatus(task.id, status)
                        }

                        if task.id != tasks.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 5)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.8), lineWidth: 1)
            }
        }
    }
}

private struct EmptyTaskGroupRow: View {
    let createTask: () -> Void

    var body: some View {
        Button(action: createTask) {
            Label("No tasks yet. Add the first task.", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }
}

private struct TaskTableHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Urgency")
                .frame(width: 86)
            Text("Person")
                .frame(width: 88)
            Text("Status")
                .frame(width: 158)
            Text("Date")
                .frame(width: 120)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }
}

private struct TaskTableRow: View {
    let task: ColonyTask
    let isSelected: Bool
    let accentColor: Color
    let select: () -> Void
    let updateStatus: (TaskStatus) -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .stroke(.secondary.opacity(0.65), lineWidth: 2)
                    .frame(width: 20, height: 20)

                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            UrgencyPill(priority: task.priority)
                .frame(width: 86)

            OwnerBadge(owner: task.owner)
                .frame(width: 88)

            Picker("Status", selection: statusBinding) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.boardTitle).tag(status)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 146)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .background(task.status.boardColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.white)

            Text(task.dueDate)
                .font(.subheadline.weight(.semibold))
                .frame(width: 120)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? accentColor.opacity(0.12) : Color.clear)
        .onTapGesture(perform: select)
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { updateStatus($0) }
        )
    }
}

private struct UrgencyPill: View {
    let priority: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minWidth: 70)
            .background(color.opacity(0.18), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
    }

    private var title: String {
        switch priority {
        case "High", "Urgent":
            return "Urgent"
        case "Medium", "Mid":
            return "Mid"
        default:
            return "Low"
        }
    }

    private var color: Color {
        switch title {
        case "Urgent":
            return .red
        case "Mid":
            return .orange
        default:
            return .yellow
        }
    }

    private var foregroundColor: Color {
        title == "Low" ? .yellow : color
    }
}

private struct TaskDetailPanel: View {
    let task: ColonyTask
    let accentColor: Color
    let updateStatus: (TaskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: task.status.systemImage)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                        .frame(width: 34, height: 34)
                        .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(task.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }

                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Status", selection: statusBinding) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.boardTitle).tag(status)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                TaskDetailRow(title: "Owner", detail: task.owner, systemImage: "person.crop.circle", color: .blue)
                TaskDetailRow(title: "Urgency", detail: urgencyTitle, systemImage: "flag", color: urgencyColor)
                TaskDetailRow(title: "Due date", detail: task.dueDate, systemImage: "calendar", color: .green)
                TaskDetailRow(title: "Updates", detail: "No blockers reported", systemImage: "bubble.left.and.bubble.right", color: .purple)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Execution context")
                    .font(.subheadline.weight(.semibold))

                Text(nextAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
            } label: {
                Label("Open task thread", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { updateStatus($0) }
        )
    }

    private var nextAction: String {
        switch task.status {
        case .planned:
            return "Confirm the scope, owner, and expected output before moving this into active work."
        case .active:
            return "Keep the next update close to the task so the team can follow progress from chat and CRM."
        case .review:
            return "Review the outcome, capture any follow-up work, and keep the record connected to the original thread."
        }
    }

    private var urgencyTitle: String {
        switch task.priority {
        case "High", "Urgent":
            return "Urgent"
        case "Medium", "Mid":
            return "Mid"
        default:
            return "Low"
        }
    }

    private var urgencyColor: Color {
        switch urgencyTitle {
        case "Urgent":
            return .red
        case "Mid":
            return .orange
        default:
            return .yellow
        }
    }
}

private struct TaskDetailRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OwnerBadge: View {
    let owner: String

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.blue.gradient, in: Circle())
    }

    private var initials: String {
        let initials = owner
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()

        return initials.isEmpty ? "?" : initials.uppercased()
    }
}

private extension TaskStatus {
    var boardTitle: String {
        switch self {
        case .planned: "Future"
        case .active: "Working on it"
        case .review: "Done"
        }
    }

    var boardColor: Color {
        switch self {
        case .planned: .gray.opacity(0.45)
        case .active: .orange
        case .review: .green
        }
    }
}
