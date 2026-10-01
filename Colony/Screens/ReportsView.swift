//
//  ReportsView.swift
//  Colony
//
//  Reports that answer plain questions instead of showing raw charts:
//
//    1. How's it going?      Four numbers: done, open, late, sales won. Each with a line
//                            that says what it means ("3 more than last week").
//    2. Getting things done  Tasks finished per day as simple bars.
//    3. Needs attention      Late tasks and stuck deals, each one click away.
//    4. Projects / Sales     Progress bars, and the pipeline as one stacked bar.
//
//  One period switch (This week / This month / All time) drives everything. Sections
//  for tools the workspace hides (CRM) step aside, and an empty workspace gets a
//  friendly explanation instead of empty charts.
//

import Charts
import SwiftData
import SwiftUI

struct ReportsView: View {
    @Environment(AppModel.self) private var app
    @Query private var tasksEverywhere: [TaskItem]
    private var tasks: [TaskItem] { tasksEverywhere.inWorkspace() }
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace().filter { $0.archivedAt == nil } }
    @Query private var contactsEverywhere: [Contact]
    private var contacts: [Contact] { contactsEverywhere.inWorkspace() }

    @State private var period: ReportPeriod = .week

    private var showsSales: Bool {
        !SidebarLayout(preferences: app.preferences).isHidden(.crm) && !contacts.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if tasks.isEmpty && contacts.isEmpty {
                    emptyState
                } else {
                    let stats = ReportStats(tasks: tasks, contacts: contacts, period: period)
                    summary(stats)
                    progressChart(stats)
                    attention(stats)
                    HStack(alignment: .top, spacing: 16) {
                        if !projects.isEmpty { projectsCard }
                        if showsSales { salesCard(stats) }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.leading, app.preferences.isSidebarCollapsed && isMac ? 22 : 0)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Reports")
    }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleBlock
                Spacer(minLength: 16)
                periodPicker
            }
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                periodPicker
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reports")
                .appFont(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(period.subtitle)
                .appFont(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var periodPicker: some View {
        GlassSegments(options: ReportPeriod.allCases, selection: $period, height: 30, label: \.title)
            .frame(width: 300)
            .accessibilityLabel("Period")
    }

    // MARK: 1. Summary

    private func summary(_ stats: ReportStats) -> some View {
        // Tiles share the row equally; on narrow windows they wrap two per row.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { tiles(stats) }
                .frame(minWidth: showsSales ? 760 : 570)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) { tiles(stats) }
        }
    }

    @ViewBuilder
    private func tiles(_ stats: ReportStats) -> some View {
        Group {
            StatTile(
                symbol: "checkmark.circle.fill", color: ColonyColor.green.color,
                value: "\(stats.done)", title: "Tasks done",
                note: stats.doneComparison
            )
            StatTile(
                symbol: "circle", color: ColonyColor.blue.color,
                value: "\(stats.open)", title: "Still to do",
                note: stats.dueSoon > 0 ? "\(stats.dueSoon) due in the next 7 days" : "Nothing due in the next 7 days"
            ) { app.go(.tasks) }
            StatTile(
                symbol: "exclamationmark.circle.fill", color: stats.late > 0 ? ColonyColor.red.color : Theme.tertiaryText,
                value: "\(stats.late)", title: "Late",
                note: stats.late == 0 ? "You're on top of things" : "Past their due date"
            ) { app.go(.tasks) }
            if showsSales {
                StatTile(
                    symbol: "trophy.fill", color: ColonyColor.orange.color,
                    value: CRMFormat.money(stats.wonValue), title: "Sales won",
                    note: stats.wonCount == 0 ? "No deals won \(period.inPhrase)" : "\(stats.wonCount) \(stats.wonCount == 1 ? "deal" : "deals") \(period.inPhrase)"
                ) { app.go(.crm) }
            }
        }
    }

    // MARK: 2. Done per day

    private func progressChart(_ stats: ReportStats) -> some View {
        ReportCard(title: "Getting things done", subtitle: stats.chartCaption) {
            if stats.days.allSatisfy({ $0.count == 0 }) {
                Text("No tasks finished \(period.inPhrase) yet. Ticked-off tasks show up here.")
                    .appFont(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(stats.days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: stats.bucket),
                        y: .value("Done", day.count)
                    )
                    .foregroundStyle(ColonyColor.green.color.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.secondaryText)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: period == .week ? 7 : 6)) { _ in
                        AxisValueLabel(format: period == .all ? .dateTime.month(.abbreviated) : (period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day()))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Tasks finished per \(stats.bucket == .month ? "month" : "day")")
            }
        }
    }

    // MARK: 3. Needs attention

    @ViewBuilder
    private func attention(_ stats: ReportStats) -> some View {
        let late = stats.lateTasks.prefix(5)
        let stuck = showsSales ? Array(stats.stuckDeals.prefix(3)) : []
        if !late.isEmpty || !stuck.isEmpty {
            ReportCard(title: "Needs attention", subtitle: "The oldest first. Click one to open it.") {
                VStack(spacing: 0) {
                    ForEach(Array(late)) { task in
                        AttentionRow(
                            symbol: "exclamationmark.circle.fill", color: ColonyColor.red.color,
                            title: task.title,
                            detail: [task.project?.name, DueText.label(for: task).map { "was due \($0.prefix(1).lowercased() + $0.dropFirst())" }].compactMap { $0 }.joined(separator: " · ")
                        ) { app.present(.task(task.uuid)) }
                    }
                    ForEach(stuck) { contact in
                        AttentionRow(
                            symbol: "hourglass", color: ColonyColor.orange.color,
                            title: contact.name,
                            detail: "\(contact.stage.title) for a while" + (contact.dealValue > 0 ? " · \(CRMFormat.money(contact.dealValue))" : "")
                        ) { app.go(.crm) }
                    }
                }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(ColonyColor.green.color)
                Text("Nothing needs attention. No late tasks\(showsSales ? " and no stuck deals" : "").")
                    .appFont(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: 4. Projects and sales

    private var projectsCard: some View {
        let active = projects.filter { !$0.allTasks.isEmpty }
        let empty = projects.count - active.count
        return ReportCard(title: "Projects", subtitle: "How much of each project is done." + (empty > 0 ? " \(empty) without tasks \(empty == 1 ? "isn't" : "aren't") shown." : "")) {
            VStack(alignment: .leading, spacing: 14) {
                if active.isEmpty {
                    Text("Add tasks to a project to see its progress here.")
                        .appFont(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(active.prefix(8)) { project in
                    let all = project.allTasks.count
                    let done = project.allTasks.filter(\.isDone).count
                    Button { app.go(.project(project.uuid)) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 16)
                                Text(project.name).appFont(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer()
                                Text(all == 0 ? "No tasks" : "\(done) of \(all)")
                                    .appFont(.system(size: 12.5).monospacedDigit())
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            ProgressBar(value: all == 0 ? 0 : Double(done) / Double(all), color: project.color.color)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(project.name): \(done) of \(all) tasks done")
                }
            }
        }
    }

    private func salesCard(_ stats: ReportStats) -> some View {
        let open = contacts.filter(\.stage.isOpen)
        let openValue = open.reduce(0) { $0 + $1.dealValue }
        return ReportCard(title: "Sales", subtitle: open.isEmpty ? "No open deals." : "\(open.count) open \(open.count == 1 ? "deal" : "deals") worth \(CRMFormat.money(openValue)).") {
            VStack(alignment: .leading, spacing: 14) {
                // One bar, split by stage: where your customers are right now.
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(DealStage.allCases) { stage in
                            let count = contacts.filter { $0.stage == stage }.count
                            if count > 0 {
                                Rectangle()
                                    .fill(stage.color.color)
                                    .frame(width: max(4, (proxy.size.width - 10) * Double(count) / Double(max(contacts.count, 1))))
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 5, style: .continuous))
                }
                .frame(height: 12)
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    ForEach(DealStage.allCases) { stage in
                        let people = contacts.filter { $0.stage == stage }
                        HStack(spacing: 8) {
                            Circle().fill(stage.color.color).frame(width: 8, height: 8)
                            Text(stage.title).appFont(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(people.count)").appFont(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(Theme.text)
                            Text(CRMFormat.money(people.reduce(0) { $0 + $1.dealValue }))
                                .appFont(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if stats.winRate != nil || stats.wonCount > 0 {
                    Text(stats.winRate.map { "You win \($0) of the deals you close." } ?? "")
                        .appFont(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .appFont(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
            Text("Reports fill in as you work")
                .appFont(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Add tasks and tick them off, or add customers, and this page shows how things are going: what got done, what's late, and how sales are doing.")
                .appFont(.system(size: 13.5))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: 460, alignment: .leading)
            Button("Add a task") { app.present(.newTask(project: nil, list: nil)) }
                .buttonStyle(.dialogPrimary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke) }
    }
}

// MARK: - Period

enum ReportPeriod: String, CaseIterable, Identifiable, Hashable {
    case week, month, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "This week"
        case .month: "This month"
        case .all: "All time"
        }
    }

    var subtitle: String {
        switch self {
        case .week: "The last 7 days, worked out on this device from your iCloud data."
        case .month: "The last 30 days, worked out on this device from your iCloud data."
        case .all: "Everything so far, worked out on this device from your iCloud data."
        }
    }

    var inPhrase: String {
        switch self {
        case .week: "this week"
        case .month: "this month"
        case .all: "yet"
        }
    }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }
}

// MARK: - Numbers

/// Everything the page shows, worked out once per render.
@MainActor
struct ReportStats {
    struct Day: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    let period: ReportPeriod
    let done: Int
    let previousDone: Int?
    let open: Int
    let late: Int
    let dueSoon: Int
    let wonCount: Int
    let wonValue: Double
    let winRate: String?
    let days: [Day]
    let bucket: Calendar.Component
    let lateTasks: [TaskItem]
    let stuckDeals: [Contact]

    init(tasks: [TaskItem], contacts: [Contact], period: ReportPeriod, now: Date = .now) {
        let calendar = Calendar.current
        self.period = period
        let today = calendar.startOfDay(for: now)
        let start: Date? = period.days.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: today) }

        let finished = tasks.compactMap { task -> Date? in task.isDone ? (task.completedAt ?? task.createdAt) : nil }
        done = finished.filter { start == nil || $0 >= start! }.count
        if let days = period.days, let start, let previousStart = calendar.date(byAdding: .day, value: -days, to: start) {
            previousDone = finished.filter { $0 >= previousStart && $0 < start }.count
        } else {
            previousDone = nil
        }

        let openTasks = tasks.filter { !$0.isDone }
        open = openTasks.count
        lateTasks = openTasks.filter(\.isOverdue).sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        late = lateTasks.count
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        dueSoon = openTasks.filter { task in
            guard let due = task.dueDate, !task.isOverdue else { return false }
            return due < weekAhead
        }.count

        // Deals have no stage history, so "won" counts deals won and added in the period
        // (all time: every won deal).
        let won = contacts.filter { $0.stage == .won && (start == nil || $0.createdAt >= start!) }
        wonCount = won.count
        wonValue = won.reduce(0) { $0 + $1.dealValue }
        let closedWon = contacts.filter { $0.stage == .won }.count
        let closedLost = contacts.filter { $0.stage == .lost }.count
        winRate = closedWon + closedLost >= 3 ? "\(Int((Double(closedWon) / Double(closedWon + closedLost) * 100).rounded()))%" : nil
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        stuckDeals = contacts.filter { $0.stage.isOpen && $0.stage != .lead && $0.createdAt < monthAgo }.sorted { $0.dealValue > $1.dealValue }

        // Bars: one per day (week/month), one per month (all time, up to 12).
        if let days = period.days {
            bucket = .day
            self.days = (0..<days).reversed().compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                return Day(date: day, count: finished.filter { calendar.isDate($0, inSameDayAs: day) }.count)
            }
        } else {
            bucket = .month
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
            let earliest = finished.min().flatMap { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) } ?? thisMonth
            let months = min(11, max(0, calendar.dateComponents([.month], from: earliest, to: thisMonth).month ?? 0))
            self.days = (0...months).reversed().compactMap { offset in
                guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
                return Day(date: month, count: finished.filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }.count)
            }
        }
    }

    /// "3 more than last week", in words.
    var doneComparison: String {
        guard let previousDone else { return done == 1 ? "1 task finished so far" : "\(done) tasks finished so far" }
        let last = period == .week ? "last week" : "the 30 days before"
        let difference = done - previousDone
        if difference == 0 { return previousDone == 0 ? "Same as \(last)" : "Same as \(last) (\(previousDone))" }
        return difference > 0 ? "\(difference) more than \(last)" : "\(-difference) fewer than \(last)"
    }

    var chartCaption: String {
        let best = days.max { $0.count < $1.count }
        guard let best, best.count > 0 else { return "Tasks you finished, per \(bucket == .month ? "month" : "day")." }
        let when = bucket == .month ? best.date.formatted(.dateTime.month(.wide)) : best.date.formatted(.dateTime.weekday(.wide).day().month())
        return "Tasks you finished, per \(bucket == .month ? "month" : "day"). Best: \(when), with \(best.count)."
    }
}

// MARK: - Pieces

private struct ReportCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).appFont(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).appFont(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke) }
    }
}

/// Big number, what it is, and a line that says what it means.
private struct StatTile: View {
    let symbol: String
    let color: Color
    let value: String
    let title: String
    let note: String
    var action: (() -> Void)? = nil
    @State private var isHovering = false

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).appFont(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Text(title).appFont(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .appFont(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .opacity(isHovering ? 1 : 0)
                }
            }
            Text(value)
                .appFont(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(note)
                .appFont(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isHovering && action != nil ? Theme.text.opacity(0.18) : Theme.stroke) }
        .contentShape(.rect)
        .onHover { isHovering = $0 }

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title): \(value). \(note)")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title): \(value). \(note)")
        }
    }
}

private struct AttentionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).appFont(.system(size: 13)).foregroundStyle(color).frame(width: 18)
                Text(title).appFont(.system(size: 13.5)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 8)
                Text(detail).appFont(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                Image(systemName: "chevron.right").appFont(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .background(isHovering ? Theme.text.opacity(0.05) : .clear, in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(title), \(detail)")
    }
}

private struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.text.opacity(0.08))
                Capsule().fill(color).frame(width: max(value > 0 ? 6 : 0, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
