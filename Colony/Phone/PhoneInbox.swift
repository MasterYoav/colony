//
//  PhoneInbox.swift
//  Colony
//
//  Inbox (channels, like Messages) and Updates, Crew (agents and automations), and
//  Search with a Browse grid for everything that isn't a tab.
//

#if os(iOS)
import SwiftData
import SwiftUI

// MARK: - Inbox

struct PhoneInbox: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Query(sort: \Channel.sortIndex) private var channelsEverywhere: [Channel]
    @Query(sort: \ActivityEvent.createdAt, order: .reverse) private var eventsEverywhere: [ActivityEvent]

    var body: some View {
        let channels = channelsEverywhere.inWorkspace()
            .sorted { ($0.lastMessage?.createdAt ?? $0.createdAt) > ($1.lastMessage?.createdAt ?? $1.createdAt) }
        let layout = SidebarLayout(preferences: app.preferences)
        let unreadUpdates = eventsEverywhere.inWorkspace().filter { !$0.isRead }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !layout.isHidden(.updates) {
                    PhoneRowsCard {
                        PhoneRow(
                            icon: AnyView(CircleIcon(symbol: "bell.fill", color: ColonyColor.red.color, size: 40)),
                            title: "Updates",
                            subtitle: eventsEverywhere.inWorkspace().first?.title ?? "What changed, from you, agents and automations",
                            action: { nav.push(.updates) }
                        ) {
                            if unreadUpdates > 0 { UnreadBadge(count: unreadUpdates) }
                            Image(systemName: "chevron.right").appFont(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }

                if !layout.isHidden(.inbox) {
                    VStack(alignment: .leading, spacing: 12) {
                        PhoneSectionHeader("Channels")
                        if channels.isEmpty {
                            PhoneCard { Text("Create a channel for notes and conversations.").foregroundStyle(.secondary) }
                        } else {
                            PhoneRowsCard {
                                ForEach(channels) { channel in
                                    ChannelRow(channel: channel)
                                }
                            }
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
        .navigationTitle("Inbox")
        .toolbar { PhoneRootToolbar() }
    }
}

private struct ChannelRow: View {
    @Environment(PhoneNavigator.self) private var nav
    let channel: Channel

    var body: some View {
        let last = channel.lastMessage
        PhoneRow(
            icon: AnyView(CircleIcon(symbol: channel.symbol == "number" ? "number" : channel.symbol, color: ColonyColor.indigo.color, size: 40)),
            title: channel.name,
            subtitle: last.map { "\($0.isMine ? "You" : $0.authorName): \($0.body)" } ?? (channel.topic.isEmpty ? "No messages yet" : channel.topic),
            action: { nav.push(.channel(channel.uuid)) }
        ) {
            VStack(alignment: .trailing, spacing: 6) {
                Text(last.map { Self.time($0.createdAt) } ?? " ").appFont(.system(size: 14)).foregroundStyle(.secondary)
                if channel.unreadCount > 0 { UnreadBadge(count: channel.unreadCount) }
            }
        }
    }

    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : DueText.day(date)
    }
}

private struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .appFont(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(ColonyColor.blue.color, in: Capsule())
            .accessibilityLabel("\(count) unread")
    }
}

// MARK: - Updates

struct PhoneUpdates: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityEvent.createdAt, order: .reverse) private var eventsEverywhere: [ActivityEvent]

    var body: some View {
        let events = Array(eventsEverywhere.inWorkspace().prefix(200))
        let days = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.createdAt) }

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if events.isEmpty {
                    PhoneCard { Text("Changes from you, agents and automations appear here.").foregroundStyle(.secondary) }
                }
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        PhoneSectionHeader(DueText.day(day))
                        PhoneRowsCard {
                            ForEach(days[day] ?? []) { event in
                                PhoneRow(
                                    icon: AnyView(CircleIcon(symbol: event.symbol, color: event.color.color, size: 40)),
                                    title: event.title,
                                    subtitle: [event.detail, event.createdAt.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · ")
                                ) {
                                    if !event.isRead { Circle().fill(ColonyColor.blue.color).frame(width: 9, height: 9) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Phone.margin)
            .padding(.bottom, 40)
        }
        .background(Phone.canvas)
        .navigationTitle("Updates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark All Read", systemImage: "checkmark.circle") { WorkspaceActions(context: context).markAllUpdatesRead() }
                    .disabled(!events.contains { !$0.isRead })
            }
        }
    }
}

// MARK: - Crew

struct PhoneCrew: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Environment(\.modelContext) private var context
    @Query(sort: \Agent.sortIndex) private var agentsEverywhere: [Agent]
    @Query(sort: \Automation.sortIndex) private var automationsEverywhere: [Automation]
    var only: CrewKind?

    var body: some View {
        let layout = SidebarLayout(preferences: app.preferences)
        let agents = agentsEverywhere.inWorkspace()
        let automations = automationsEverywhere.inWorkspace()
        let names = AutomationNames(context: context)

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if only != .automations && !layout.isHidden(.agents) {
                    VStack(alignment: .leading, spacing: 14) {
                        PhoneSectionHeader("Agents", subtitle: app.agents.isAvailable ? "Runs on \(app.agents.defaultProvider.title)" : app.agents.unavailableMessage(for: app.agents.defaultProvider))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 18) {
                            ForEach(agents) { agent in
                                Button { nav.push(.agent(agent.uuid)) } label: {
                                    VStack(spacing: 8) {
                                        AgentFace(color: agent.color.color, size: 70, seed: agent.name.count)
                                            .padding(7)
                                            .background(agent.color.color.opacity(0.2), in: Circle())
                                        VStack(spacing: 1) {
                                            Text(agent.name).appFont(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                                            Text(app.agents.isRunning(agent) ? "Thinking…" : agent.status.title)
                                                .appFont(.system(size: 14)).foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu { AgentMenuItems(agent: agent) }
                            }
                            Button { app.present(.recruitAgent) } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .appFont(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 84, height: 84)
                                        .overlay { Circle().strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
                                        .background(Phone.card, in: Circle())
                                    VStack(spacing: 1) {
                                        Text("Recruit").appFont(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                                        Text("New agent").appFont(.system(size: 14)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Recruit an agent")
                        }
                    }
                }

                if only != .agents && !layout.isHidden(.automations) {
                    VStack(alignment: .leading, spacing: 12) {
                        PhoneSectionHeader("Automations", subtitle: "Colony does routine work for you.")
                        if automations.isEmpty {
                            PhoneCard { Text("Start from a recipe with +.").foregroundStyle(.secondary) }
                        } else {
                            PhoneRowsCard {
                                ForEach(automations) { automation in
                                    AutomationRow(automation: automation, sentence: automation.sentence(names))
                                }
                            }
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
        .navigationTitle(only?.title ?? "Crew")
        .toolbar { if only == nil { PhoneRootToolbar() } }
    }
}

private struct AutomationRow: View {
    @Environment(PhoneNavigator.self) private var nav
    @Environment(\.modelContext) private var context
    let automation: Automation
    let sentence: String

    var body: some View {
        PhoneRow(
            icon: AnyView(
                Image(systemName: automation.trigger?.kind.symbol ?? "bolt.fill")
                    .appFont(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(automation.color.color.gradient, in: Circle())
                    .opacity(automation.isEnabled ? 1 : 0.5)
            ),
            title: automation.name,
            subtitle: sentence,
            action: { nav.push(.automation(automation.uuid)) }
        ) {
            Toggle(automation.name, isOn: Binding(
                get: { automation.isEnabled },
                set: { WorkspaceActions(context: context).setEnabled($0, for: automation) }
            ))
            .labelsHidden()
            .disabled(!automation.isComplete)
        }
    }
}

// MARK: - Search

struct PhoneSearch: View {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav
    @Query private var tasksEverywhere: [TaskItem]
    @Query private var projectsEverywhere: [Project]
    @Query private var contactsEverywhere: [Contact]
    @Query private var channelsEverywhere: [Channel]
    @Query private var agentsEverywhere: [Agent]
    @State private var query = ""

    var body: some View {
        let q = ColonyText.trimmed(query).lowercased()
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if q.isEmpty {
                    browse
                } else {
                    results(q)
                }
            }
            .padding(.horizontal, Phone.margin)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Phone.canvas)
        .phoneScrollEdge()
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Tasks, projects, customers…")
    }

    // MARK: Browse (Maps "Places" circles)

    private struct Shortcut: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let color: Color
        let action: () -> Void
    }

    private var shortcuts: [Shortcut] {
        let layout = SidebarLayout(preferences: app.preferences)
        var items: [Shortcut] = []
        if !layout.isHidden(.crm) { items.append(Shortcut(id: "crm", title: "Customers", symbol: "person.2.fill", color: ColonyColor.purple.color) { nav.push(.crm) }) }
        if !layout.isHidden(.reports) { items.append(Shortcut(id: "reports", title: "Reports", symbol: "chart.pie.fill", color: ColonyColor.teal.color) { nav.push(.reports) }) }
        items.append(Shortcut(id: "today", title: "Today", symbol: "sun.max.fill", color: ColonyColor.blue.color) { nav.push(.taskList(.today), on: .tasks) })
        items.append(Shortcut(id: "flagged", title: "Flagged", symbol: "flag.fill", color: ColonyColor.orange.color) { nav.push(.taskList(.flagged), on: .tasks) })
        if !layout.isHidden(.updates) { items.append(Shortcut(id: "updates", title: "Updates", symbol: "bell.fill", color: ColonyColor.red.color) { nav.push(.updates, on: .inbox) }) }
        items.append(Shortcut(id: "settings", title: "Settings", symbol: "gearshape.fill", color: Color(white: 0.45)) { nav.showsSettings = true })
        return items
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhoneSectionHeader("Browse")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                ForEach(shortcuts) { item in
                    Button(action: item.action) {
                        VStack(spacing: 8) {
                            CircleIcon(symbol: item.symbol, color: item.color, size: 76)
                            Text(item.title).appFont(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ q: String) -> some View {
        let tasks = tasksEverywhere.inWorkspace().filter { $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) }.prefix(20)
        let projects = projectsEverywhere.inWorkspace().filter { $0.name.lowercased().contains(q) }
        let contacts = contactsEverywhere.inWorkspace().filter { ($0.name + " " + $0.company).lowercased().contains(q) }.prefix(10)
        let channels = channelsEverywhere.inWorkspace().filter { $0.name.lowercased().contains(q) }
        let agents = agentsEverywhere.inWorkspace().filter { $0.name.lowercased().contains(q) }

        if tasks.isEmpty && projects.isEmpty && contacts.isEmpty && channels.isEmpty && agents.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        if !projects.isEmpty || !channels.isEmpty || !agents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PhoneSectionHeader("Places")
                PhoneRowsCard {
                    ForEach(projects) { project in
                        PhoneRow(icon: AnyView(CircleIcon(symbol: project.symbol, color: project.color.color)), title: project.name, subtitle: "Project · \(project.openTaskCount) open", action: { nav.push(.taskList(.project(project.uuid)), on: .tasks) })
                    }
                    ForEach(channels) { channel in
                        PhoneRow(icon: AnyView(CircleIcon(symbol: "number", color: ColonyColor.indigo.color)), title: channel.name, subtitle: "Channel", action: { nav.push(.channel(channel.uuid), on: .inbox) })
                    }
                    ForEach(agents) { agent in
                        PhoneRow(icon: AnyView(AgentFace(color: agent.color.color, size: 40, seed: agent.name.count)), title: agent.name, subtitle: "Agent", action: { nav.push(.agent(agent.uuid), on: .crew) })
                    }
                }
            }
        }
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PhoneSectionHeader("Tasks")
                PhoneRowsCard {
                    ForEach(Array(tasks)) { task in PhoneTaskRow(task: task) }
                }
            }
        }
        if !contacts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PhoneSectionHeader("Customers")
                PhoneRowsCard {
                    ForEach(Array(contacts)) { contact in
                        PhoneRow(
                            icon: AnyView(
                                Text(contact.initials)
                                    .appFont(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(contact.color.color.gradient, in: Circle())
                            ),
                            title: contact.name,
                            subtitle: [contact.company, contact.stage.title].filter { !$0.isEmpty }.joined(separator: " · "),
                            action: { nav.push(.crm) }
                        )
                    }
                }
            }
        }
    }
}
#endif
