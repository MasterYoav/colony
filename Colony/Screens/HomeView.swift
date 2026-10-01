//
//  HomeView.swift
//  Colony
//

import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \TaskItem.createdAt) private var tasksEverywhere: [TaskItem]
    private var tasks: [TaskItem] { tasksEverywhere.inWorkspace() }
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace() }
    @Query(sort: \ActivityEvent.createdAt, order: .reverse) private var eventsEverywhere: [ActivityEvent]
    private var events: [ActivityEvent] { eventsEverywhere.inWorkspace() }
    @Query private var contactsEverywhere: [Contact]
    private var contacts: [Contact] { contactsEverywhere.inWorkspace() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: greeting, subtitle: Date.now.formatted(.dateTime.weekday(.wide).month().day())) {
                    Button("New task", systemImage: "plus") { app.present(.newTask(project: nil, list: nil)) }
                        .buttonStyle(QuietButtonStyle())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    LiveStat(label: "Open tasks", value: Double(openTasks.count), series: openSeries)
                    LiveStat(label: "Done this week", value: Double(doneThisWeek), delta: weekDelta, series: doneSeries)
                    LiveStat(label: "Pipeline", value: Double(contacts.filter { ![.won, .lost].contains($0.stage) }.count), series: DealStage.allCases.map { stage in Double(contacts.filter { $0.stage == stage }.count) })
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        sectionTitle("Due soon", action: "All tasks") { app.go(.tasks) }
                        let due = openTasks.filter { $0.dueDate != nil }.sorted { $0.dueDate! < $1.dueDate! }.prefix(6)
                        if due.isEmpty {
                            Text("Nothing due. Enjoy the calm.")
                                .appFont(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        } else {
                            ForEach(Array(due)) { task in
                                CompactTaskRow(task: task)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Card {
                        sectionTitle("Projects", action: "All") { app.go(.projects) }
                        ForEach(projects.prefix(6)) { project in
                            Button { app.go(.project(project.uuid)) } label: {
                                HStack(spacing: 10) {
                                    ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 20)
                                    Text(project.name).appFont(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                                    Spacer()
                                    ProgressView(value: project.progress)
                                        .frame(width: 70)
                                        .tint(project.color.color)
                                    Text(project.progress, format: .percent.precision(.fractionLength(0)))
                                        .appFont(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.secondaryText)
                                        .frame(width: 36, alignment: .trailing)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Card {
                    sectionTitle("Recent updates", action: "View all") { app.go(.updates) }
                    ForEach(events.prefix(5)) { event in
                        UpdateRow(event: event)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .navigationTitle("Home")
    }

    private var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }

    private var doneThisWeek: Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return tasks.filter { ($0.completedAt ?? .distantPast) >= start }.count
    }

    private var weekDelta: Double? {
        let cal = Calendar.current
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now),
              let lastStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start) else { return nil }
        let last = tasks.filter { ($0.completedAt ?? .distantPast) >= lastStart && ($0.completedAt ?? .distantPast) < thisWeek.start }.count
        guard last > 0 else { return nil }
        return Double(doneThisWeek - last) / Double(last)
    }

    private var doneSeries: [Double] {
        (0..<7).reversed().map { offset in
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            return Double(tasks.filter { $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }.count)
        }
    }

    private var openSeries: [Double] {
        (0..<7).reversed().map { offset in
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            return Double(tasks.filter { $0.createdAt <= day && ($0.completedAt ?? .distantFuture) > day }.count)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let first = app.preferences.displayName.split(separator: " ").first.map(String.init) ?? ""
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return first.isEmpty ? part : "\(part), \(first)"
    }

    private func sectionTitle(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title).appFont(.headline).foregroundStyle(Theme.text)
            Spacer()
            Button(action, action: perform)
                .buttonStyle(.plain)
                .appFont(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

struct CompactTaskRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withMotion(.snappy) { WorkspaceActions(context: context).toggleDone(task) }
                app.syncReminder(for: task)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.green : Theme.secondaryText)
                    .appFont(.system(size: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            Button { app.present(.task(task.uuid)) } label: {
                HStack {
                    Text(task.title)
                        .appFont(.subheadline)
                        .foregroundStyle(task.isDone ? Theme.secondaryText : Theme.text)
                        .strikethrough(task.isDone)
                        .lineLimit(1)
                    Spacer()
                    if let due = task.dueDate {
                        Text(due, format: .dateTime.month(.abbreviated).day())
                            .appFont(.caption)
                            .foregroundStyle(task.isOverdue ? Color.red : Theme.secondaryText)
                    }
                    if let project = task.project {
                        ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 14)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .fontRole(.data)
    }
}

struct UpdateRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.symbol)
                .appFont(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(event.color.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).appFont(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(event.detail).appFont(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
            }
            Spacer()
            Text(event.createdAt, format: .relative(presentation: .named))
                .appFont(.caption)
                .foregroundStyle(Theme.tertiaryText)
            if !event.isRead {
                Circle().fill(Color.blue).frame(width: 6, height: 6).padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
        .fontRole(.data)
    }
}

struct UpdatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityEvent.createdAt, order: .reverse) private var eventsEverywhere: [ActivityEvent]
    private var events: [ActivityEvent] { eventsEverywhere.inWorkspace() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Updates", subtitle: "Everything that changed in your workspace") {
                    Button("Mark all read", systemImage: "checkmark") {
                        WorkspaceActions(context: context).markAllUpdatesRead()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(!events.contains { !$0.isRead })
                }
                if events.isEmpty {
                    EmptyStateView(symbol: "bell", title: "No updates yet", message: "Create tasks, projects and contacts to see activity here.")
                } else {
                    Card {
                        ForEach(events) { event in
                            UpdateRow(event: event)
                            if event.id != events.last?.id { SidebarDivider() }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Updates")
    }
}
