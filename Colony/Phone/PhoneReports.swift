//
//  PhoneReports.swift
//  Colony
//
//  Reports on iPhone, in the Today style: a hero number for what got done with a
//  plain sentence, metric tiles, one bar chart, and what needs attention.
//

#if os(iOS)
import Charts
import SwiftData
import SwiftUI

struct PhoneReports: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Query private var tasksEverywhere: [TaskItem]
    @Query private var contactsEverywhere: [Contact]
    @State private var period: ReportPeriod = .week

    var body: some View {
        let contacts = contactsEverywhere.inWorkspace()
        let stats = ReportStats(tasks: tasksEverywhere.inWorkspace(), contacts: contacts, period: period)
        let showsSales = !SidebarLayout(preferences: app.preferences).isHidden(.crm)

        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Picker("Period", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                hero(stats)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    MetricTile(title: "Still to do", symbol: "circle.dashed", value: "\(stats.open)",
                               chip: "\(stats.dueSoon) this week", gauge: stats.open == 0 ? 0 : Double(stats.dueSoon) / Double(stats.open),
                               color: ColonyColor.blue.color) { nav.push(.taskList(.all), on: .tasks) }
                    MetricTile(title: "Late", symbol: "exclamationmark.triangle.fill", value: "\(stats.late)",
                               chip: stats.late == 0 ? "on track" : "past due", gauge: stats.open == 0 ? 0 : Double(stats.late) / Double(stats.open),
                               color: ColonyColor.red.color) { nav.push(.taskList(.late), on: .tasks) }
                    if showsSales {
                        MetricTile(title: "Sales won", symbol: "trophy.fill",
                                   value: stats.wonValue > 0 ? PhoneToday.money(stats.wonValue) : "\(stats.wonCount)",
                                   unit: stats.wonValue > 0 ? nil : (stats.wonCount == 1 ? "deal" : "deals"),
                                   chip: stats.winRate.map { "\($0) win rate" }, gauge: contacts.isEmpty ? 0 : Double(stats.wonCount) / Double(contacts.count),
                                   color: ColonyColor.yellow.color) { nav.push(.crm) }
                        let open = contacts.filter { $0.stage.isOpen }
                        MetricTile(title: "In pipeline", symbol: "person.2.fill", value: "\(open.count)",
                                   chip: open.reduce(0) { $0 + $1.dealValue } > 0 ? PhoneToday.money(open.reduce(0) { $0 + $1.dealValue }) : "customers",
                                   gauge: contacts.isEmpty ? 0 : Double(open.count) / Double(contacts.count),
                                   color: ColonyColor.purple.color) { nav.push(.crm) }
                    }
                }

                chart(stats)
                attention(stats)
            }
            .padding(.horizontal, Phone.margin)
            .padding(.top, 4)
            .padding(.bottom, 60)
        }
        .background(Phone.canvas)
        .phoneScrollEdge()
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Hero

    private func hero(_ stats: ReportStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(stats.done)")
                    .appFont(Phone.display(88))
                    .foregroundStyle(ColonyColor.green.color)
                    .contentTransition(.numericText())
                Text(stats.done == 1 ? "task done" : "tasks done")
                    .appFont(Phone.display(28))
                    .foregroundStyle(ColonyColor.green.color)
            }
            (Text(dim(stats) + " ").foregroundStyle(.secondary) + Text(bright(stats)).foregroundStyle(.primary))
                .appFont(.system(size: 22, weight: .bold, design: .rounded))
        }
        .accessibilityElement(children: .combine)
    }

    private func dim(_ stats: ReportStats) -> String {
        guard let previous = stats.previousDone else { return "That's everything you've finished so far." }
        if stats.done == previous { return "The same as the \(period == .week ? "week" : "month") before." }
        let diff = stats.done - previous
        return diff > 0 ? "\(diff) more than the \(period == .week ? "week" : "month") before." : "\(-diff) fewer than the \(period == .week ? "week" : "month") before."
    }

    private func bright(_ stats: ReportStats) -> String {
        if stats.late > 0 { return "Clear the \(stats.late) late task\(stats.late == 1 ? "" : "s") first." }
        if stats.dueSoon > 0 { return "\(stats.dueSoon) due in the next 7 days." }
        return "Nothing is late. Nice."
    }

    // MARK: Chart

    private func chart(_ stats: ReportStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PhoneSectionHeader("Done per \(stats.bucket == .day ? "day" : "month")", subtitle: best(stats))
            PhoneCard {
                let peak = max(stats.days.map(\.count).max() ?? 0, 1)
                Chart(stats.days) { day in
                    // A faint full-height bar behind each day, so empty days still read.
                    BarMark(x: .value("Day", day.date, unit: stats.bucket), y: .value("Track", peak))
                        .foregroundStyle(Phone.well)
                        .clipShape(Capsule())
                    BarMark(x: .value("Day", day.date, unit: stats.bucket), y: .value("Done", day.count))
                        .foregroundStyle(ColonyColor.green.color.gradient)
                        .clipShape(Capsule())
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: stats.bucket, count: stats.days.count > 12 ? 7 : 1)) { _ in
                        AxisValueLabel(format: stats.bucket == .day ? (stats.days.count > 12 ? .dateTime.day() : .dateTime.weekday(.narrow)) : .dateTime.month(.narrow), centered: true)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private func best(_ stats: ReportStats) -> String? {
        guard let top = stats.days.max(by: { $0.count < $1.count }), top.count > 0 else { return "Nothing finished yet." }
        let when = stats.bucket == .day ? DueText.day(top.date) : top.date.formatted(.dateTime.month(.wide))
        return "Best: \(when), with \(top.count)."
    }

    // MARK: Attention

    @ViewBuilder
    private func attention(_ stats: ReportStats) -> some View {
        if !stats.lateTasks.isEmpty || !stats.stuckDeals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PhoneSectionHeader("Needs Attention")
                PhoneRowsCard {
                    ForEach(stats.lateTasks.prefix(5)) { task in
                        PhoneTaskRow(task: task)
                    }
                    ForEach(stats.stuckDeals.prefix(3)) { contact in
                        PhoneRow(
                            icon: AnyView(CustomerAvatar(contact: contact)),
                            title: contact.name,
                            subtitle: "\(contact.stage.title) for over a month",
                            subtitleColor: ColonyColor.orange.color,
                            action: { nav.push(.contact(contact.uuid)) }
                        )
                    }
                }
            }
        }
    }
}
#endif
