//
//  PhoneToday.swift
//  Colony
//
//  Today: one hero number (what's left today) on an arc, a plain sentence about the
//  day, four metric tiles, then Up Next, Projects, Crew and Updates — Incredible's
//  Today screen and Maps' home sheet, with Colony's data.
//

#if os(iOS)
import SwiftData
import SwiftUI

struct PhoneToday: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Environment(\.modelContext) private var context
    @Query private var tasksEverywhere: [TaskItem]
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    @Query(sort: \Agent.sortIndex) private var agentsEverywhere: [Agent]
    @Query(sort: \ActivityEvent.createdAt, order: .reverse) private var eventsEverywhere: [ActivityEvent]
    @Query private var contactsEverywhere: [Contact]
    @Query private var channelsEverywhere: [Channel]

    var body: some View {
        let day = TodayStats(tasks: tasksEverywhere.inWorkspace())
        let layout = SidebarLayout(preferences: app.preferences)

        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                hero(day)
                tiles(day, layout: layout)
                upNext(day)
                if !projects.isEmpty && !layout.isHidden(.projects) { projectsSection }
                if !agents.isEmpty && !layout.isHidden(.agents) { crewSection }
                if !events.isEmpty && !layout.isHidden(.updates) { updatesSection }
            }
            .padding(.horizontal, Phone.margin)
            .padding(.bottom, 40)
        }
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "PhoneScrollBottom") ? .bottom : .top)
        .background(Phone.canvas)
        .phoneScrollEdge()
        .toolbar { PhoneRootToolbar() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var projects: [Project] { projectsEverywhere.inWorkspace().filter { $0.archivedAt == nil } }
    private var agents: [Agent] { agentsEverywhere.inWorkspace() }
    private var events: [ActivityEvent] { Array(eventsEverywhere.inWorkspace().prefix(30)) }

    // MARK: Hero

    private func hero(_ day: TodayStats) -> some View {
        VStack(spacing: 6) {
            ZStack {
                ArcGauge(progress: day.progress, color: day.color)
                    .frame(height: 250)
                Text("\(day.left)")
                    .appFont(Phone.display(day.left > 99 ? 76 : 104))
                    .foregroundStyle(day.color)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.top, 40)
            }
            .frame(height: 250)
            .padding(.bottom, 8)
            Button { nav.push(.taskList(.today), on: .tasks) } label: {
                HStack(spacing: 6) {
                    Text(day.headline)
                    Image(systemName: "chevron.right")
                }
                .appFont(Phone.display(34))
                .foregroundStyle(day.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.left) \(day.headline). Open Today.")

            // Dim then bright, as Incredible writes it.
            (Text(day.dimSentence + " ").foregroundStyle(.secondary) + Text(day.brightSentence).foregroundStyle(.primary))
                .appFont(.system(size: 23, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(1)
                .padding(.top, 18)
        }
        .padding(.top, 8)
    }

    // MARK: Tiles

    private func tiles(_ day: TodayStats, layout: SidebarLayout) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            MetricTile(
                title: "Done this week", symbol: "checkmark.circle.fill", value: "\(day.doneThisWeek)",
                chip: day.weekChange, chipSymbol: day.weekChangeSymbol,
                gauge: Double(day.doneThisWeek) / Double(max(day.doneLastWeek, 10, day.doneThisWeek)),
                color: ColonyColor.green.color
            ) { nav.push(.taskList(.completed), on: .tasks) }
            MetricTile(
                title: "Late", symbol: "exclamationmark.triangle.fill", value: "\(day.late)",
                chip: day.oldestLate, gauge: day.open == 0 ? 0 : Double(day.late) / Double(day.open),
                color: ColonyColor.red.color
            ) { nav.push(.taskList(.late), on: .tasks) }
            MetricTile(
                title: "Coming up", symbol: "calendar", value: "\(day.thisWeek)",
                chip: "next 7 days", gauge: day.open == 0 ? 0 : Double(day.thisWeek) / Double(day.open),
                color: ColonyColor.blue.color
            ) { nav.push(.taskList(.scheduled), on: .tasks) }
            if !layout.isHidden(.crm) {
                let pipeline = contactsEverywhere.inWorkspace()
                let open = pipeline.filter { $0.stage.isOpen }
                let won = pipeline.filter { $0.stage == .won }
                MetricTile(
                    title: "Open deals", symbol: "person.2.fill", value: Self.money(open.reduce(0) { $0 + $1.dealValue }),
                    chip: "\(won.count) won", gauge: pipeline.isEmpty ? 0 : Double(won.count) / Double(max(won.count + open.count, 1)),
                    color: ColonyColor.purple.color
                ) { nav.push(.crm) }
            } else {
                let unread = channelsEverywhere.inWorkspace().reduce(0) { $0 + $1.unreadCount }
                MetricTile(
                    title: "Unread", symbol: "tray.fill", value: "\(unread)", chip: "messages",
                    gauge: unread == 0 ? 0 : 0.6, color: ColonyColor.orange.color
                ) { nav.root(.inbox) }
            }
        }
    }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").notation(.compactName).precision(.significantDigits(1...3)))
    }

    // MARK: Up next

    @ViewBuilder
    private func upNext(_ day: TodayStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PhoneSectionHeader("Up Next", action: { nav.push(.taskList(.today), on: .tasks) })
            if day.next.isEmpty {
                PhoneCard {
                    HStack(spacing: 14) {
                        CircleIcon(symbol: "checkmark", color: ColonyColor.green.color, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All clear").appFont(.system(size: 17, weight: .semibold))
                            Text("Nothing due. Add a task with +.").appFont(.system(size: 15)).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                PhoneRowsCard {
                    ForEach(day.next) { task in
                        PhoneTaskRow(task: task)
                    }
                }
            }
        }
    }

    // MARK: Projects (Maps "Places")

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhoneSectionHeader("Projects", action: { nav.root(.tasks) })
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(projects) { project in
                        Button { nav.push(.taskList(.project(project.uuid)), on: .tasks) } label: {
                            VStack(spacing: 8) {
                                CircleIcon(symbol: project.symbol, color: project.color.color, size: 68)
                                VStack(spacing: 1) {
                                    Text(project.name)
                                        .appFont(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(project.openTaskCount == 0 ? "Done" : "\(project.openTaskCount) left")
                                        .appFont(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                            }
                            .frame(width: 80)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Phone.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Phone.margin)
        }
    }

    // MARK: Crew

    private var crewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhoneSectionHeader("Crew", action: { nav.root(.crew) })
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(agents) { agent in
                        Button { nav.push(.agent(agent.uuid), on: .crew) } label: {
                            VStack(spacing: 8) {
                                AgentFace(color: agent.color.color, size: 56, seed: agent.name.count)
                                    .padding(6)
                                    .background(agent.color.color.opacity(0.18), in: Circle())
                                VStack(spacing: 1) {
                                    Text(agent.name).appFont(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                                    Text(app.agents.isRunning(agent) ? "Thinking…" : agent.status.title)
                                        .appFont(.system(size: 14)).foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Phone.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Phone.margin)
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhoneSectionHeader("Updates", action: { nav.push(.updates, on: .inbox) })
            PhoneRowsCard {
                ForEach(EventGroup.group(events)) { group in
                    PhoneRow(
                        icon: AnyView(CircleIcon(symbol: group.first.symbol, color: group.first.color.color, size: 40)),
                        title: group.title,
                        subtitle: group.subtitle
                    )
                }
            }
        }
    }
}

// MARK: - Grouped updates

/// Neighbouring updates with the same title ("Customer added" ×4) shown as one row.
struct EventGroup: Identifiable {
    let events: [ActivityEvent]
    var id: UUID { first.uuid }
    var first: ActivityEvent { events[0] }

    var title: String { events.count == 1 ? first.title : "\(first.title) ×\(events.count)" }

    var subtitle: String {
        let when = first.createdAt.formatted(.relative(presentation: .named)).capitalizedFirst
        if events.count == 1, !first.detail.isEmpty { return first.detail }
        return when
    }

    static func group(_ events: [ActivityEvent], limit: Int = 4) -> [EventGroup] {
        var groups: [[ActivityEvent]] = []
        for event in events {
            if let last = groups.last?.last, last.title == event.title { groups[groups.count - 1].append(event) } else { groups.append([event]) }
        }
        return groups.prefix(limit).map(EventGroup.init)
    }
}

// MARK: - Stats

struct TodayStats {
    let left: Int
    let doneToday: Int
    let late: Int
    let open: Int
    let thisWeek: Int
    let doneThisWeek: Int
    let doneLastWeek: Int
    let oldestLateDate: Date?
    let next: [TaskItem]

    init(tasks: [TaskItem], now: Date = .now) {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let open = tasks.filter { !$0.isDone }
        let dueToday = open.filter { ($0.dueDate ?? .distantFuture) < endOfToday }
        left = dueToday.count
        doneToday = tasks.filter { $0.isDone && ($0.completedAt.map(cal.isDateInToday) ?? false) }.count
        let lateTasks = open.filter(\.isOverdue)
        late = lateTasks.count
        oldestLateDate = lateTasks.compactMap(\.dueDate).min()
        self.open = open.count
        let weekAhead = cal.date(byAdding: .day, value: 7, to: endOfToday)!
        thisWeek = open.filter { ($0.dueDate ?? .distantFuture) < weekAhead && ($0.dueDate ?? .distantPast) >= endOfToday }.count
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now)!
        doneThisWeek = tasks.filter { ($0.completedAt ?? .distantPast) > weekAgo }.count
        doneLastWeek = tasks.filter { ($0.completedAt ?? .distantPast) > twoWeeksAgo && ($0.completedAt ?? .distantPast) <= weekAgo }.count
        // Late first, then by due time, then flagged/urgent undated ones.
        next = Array(dueToday.sorted { ($0.dueDate ?? .distantFuture, $0.priority.rank) < ($1.dueDate ?? .distantFuture, $1.priority.rank) }.prefix(5))
    }

    var progress: Double {
        let total = left + doneToday
        return total == 0 ? 1 : Double(doneToday) / Double(total)
    }

    var color: Color {
        if late > 0 { return ColonyColor.orange.color }
        if left == 0 { return ColonyColor.green.color }
        return ColonyColor.blue.color
    }

    var headline: String {
        left == 0 ? "All done" : (left == 1 ? "Task today" : "Tasks today")
    }

    var dimSentence: String {
        if left == 0 && doneToday == 0 { return "Nothing is due today." }
        if left == 0 { return "You finished all \(doneToday) task\(doneToday == 1 ? "" : "s") for today." }
        if doneToday == 0 { return "\(left) task\(left == 1 ? " is" : "s are") waiting for you today." }
        return "You've done \(doneToday) of \(left + doneToday) today."
    }

    var brightSentence: String {
        if late > 0, let first = next.first(where: \.isOverdue) {
            return late == 1 ? "Start with “\(first.title)”, it's late." : "\(late) are late; start with “\(first.title)”."
        }
        if let first = next.first { return "Next up: “\(first.title)”." }
        if thisWeek > 0 { return "\(thisWeek) coming up this week. Enjoy the breather." }
        return "Enjoy the quiet, or plan something new."
    }

    /// "+1 vs last wk".
    var weekChange: String? {
        let diff = doneThisWeek - doneLastWeek
        if diff == 0 { return doneThisWeek == 0 ? nil : "same as last wk" }
        return "\(diff > 0 ? "+" : "−")\(abs(diff)) vs last wk"
    }

    var weekChangeSymbol: String? { nil }

    var oldestLate: String? {
        guard let date = oldestLateDate else { return late == 0 ? "on track" : nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return days <= 0 ? "since today" : "\(days)d oldest"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension TaskPriority {
    /// Sort order: urgent first.
    var rank: Int {
        switch self {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }
}
#endif
