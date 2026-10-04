//
//  PhoneRoot.swift
//  Colony
//
//  The iPhone app: a native Liquid Glass tab bar (Today, Tasks, Inbox, Crew, Search),
//  one NavigationStack per tab, and Settings as a sheet from the profile picture — the
//  way Maps, Fitness and Health are built. Calls to `app.go(_:)` from anywhere (⌘K,
//  notifications, links inside screens) are routed onto the right tab and stack.
//

#if os(iOS)
import SwiftData
import SwiftUI

enum PhoneTab: Hashable {
    case today, tasks, inbox, crew, search
}

/// A screen pushed onto a tab's stack.
enum PhoneRoute: Hashable {
    case taskList(PhoneTaskFilter)
    case channel(UUID)
    case updates
    case agent(UUID)
    case automation(UUID)
    case agents
    case automations
    case crm
    case reports
    case projects
    case contact(UUID)

    var destination: Destination {
        switch self {
        case .taskList(.project(let id)): .project(id)
        case .taskList(.list(let project, let list)): .list(project: project, list: list)
        case .taskList: .tasks
        case .channel(let id): .messages(channel: id)
        case .updates: .updates
        case .agent(let id): .agent(id)
        case .automation(let id): .automation(id)
        case .agents: .crew(.agents)
        case .automations: .crew(.automations)
        case .crm, .contact: .crm
        case .reports: .reports
        case .projects: .projects
        }
    }
}

@MainActor
@Observable
final class PhoneNavigator {
    var tab: PhoneTab = .today
    var paths: [PhoneTab: [PhoneRoute]] = [:]
    var showsSettings = false

    func path(_ tab: PhoneTab) -> Binding<[PhoneRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: PhoneRoute, on tab: PhoneTab? = nil) {
        let target = tab ?? self.tab
        self.tab = target
        if paths[target]?.last != route { paths[target, default: []].append(route) }
    }

    func root(_ tab: PhoneTab) {
        self.tab = tab
        paths[tab] = []
    }

    /// The destination on screen, mirrored into `app.destination`.
    var current: Destination {
        if let route = paths[tab]?.last { return route.destination }
        switch tab {
        case .today: return .home
        case .tasks: return .tasks
        case .inbox: return .messages(channel: nil)
        case .crew: return .crew(.agents)
        case .search: return .home
        }
    }
}

struct PhoneRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var nav = PhoneNavigator()
    /// Set when we write `app.destination` ourselves, so the change isn't routed again.
    @State private var echo: Destination?

    var body: some View {
        @Bindable var nav = nav
        let layout = SidebarLayout(preferences: app.preferences)
        let showsInbox = !layout.isHidden(.inbox) || !layout.isHidden(.updates)
        let showsTasks = !layout.isHidden(.tasks) || !layout.isHidden(.projects)
        let showsCrew = !layout.isHidden(.agents) || !layout.isHidden(.automations)

        TabView(selection: $nav.tab) {
            Tab("Today", systemImage: "sun.max.fill", value: PhoneTab.today) {
                stack(.today) { PhoneToday() }
            }
            if showsTasks {
                Tab("Tasks", systemImage: "checklist", value: PhoneTab.tasks) {
                    stack(.tasks) { PhoneTasksHome() }
                }
            }
            if showsInbox {
                Tab("Inbox", systemImage: "tray.fill", value: PhoneTab.inbox) {
                    stack(.inbox) { PhoneInbox() }
                }
                .badge(unread)
            }
            if showsCrew {
                Tab("Crew", systemImage: "person.2.fill", value: PhoneTab.crew) {
                    stack(.crew) { PhoneCrew() }
                }
            }
            Tab(value: PhoneTab.search, role: .search) {
                stack(.search) { PhoneSearch() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(nav)
        .sheet(isPresented: $nav.showsSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { nav.showsSettings = false }
                        }
                    }
            }
            .environment(app)
        }
        #if DEBUG
        // Screenshot runs: `-PhoneScreen tasks` etc. opens a screen at launch.
        .task {
            switch UserDefaults.standard.string(forKey: "PhoneScreen") ?? "" {
            case "tasks": nav.root(.tasks)
            case "today-list": nav.push(.taskList(.today), on: .tasks)
            case "scheduled": nav.push(.taskList(.scheduled), on: .tasks)
            case "inbox": nav.root(.inbox)
            case "updates": nav.push(.updates, on: .inbox)
            case "crew": nav.root(.crew)
            case "search": nav.root(.search)
            case "crm": nav.push(.crm)
            case "reports": nav.push(.reports)
            case "settings": nav.showsSettings = true
            case "channel": if let c = try? context.fetch(FetchDescriptor<Channel>()).inWorkspace().first { nav.push(.channel(c.uuid), on: .inbox) }
            case "agent": if let a = try? context.fetch(FetchDescriptor<Agent>()).inWorkspace().first { nav.push(.agent(a.uuid), on: .crew) }
            case "automation": if let a = try? context.fetch(FetchDescriptor<Automation>()).inWorkspace().first { nav.push(.automation(a.uuid), on: .crew) }
            case "contact": if let c = try? context.fetch(FetchDescriptor<Contact>()).inWorkspace().first { nav.push(.contact(c.uuid)) }
            case "task": if let t = try? context.fetch(FetchDescriptor<TaskItem>()).inWorkspace().first { app.present(.task(t.uuid)) }
            case "newTask": app.present(.newTask(project: nil, list: nil))
            case "newProject": app.present(.newProject)
            case "newChannel": app.present(.newChannel)
            case "newContact": app.present(.newContact)
            case "newAutomation": app.present(.newAutomation)
            case "recruit": app.present(.recruitAgent)
            case "newWorkspace": app.present(.newWorkspace)
            case "newList": app.present(.newList(project: nil))
            default: break
            }
        }
        #endif
        .onChange(of: app.destination) { _, destination in
            if destination == echo { echo = nil; return }
            route(destination)
        }
        .onChange(of: nav.current) { _, current in
            guard current != app.destination else { return }
            echo = current
            app.destination = current
        }
    }

    @Query private var channelsEverywhere: [Channel]
    @Query private var eventsEverywhere: [ActivityEvent]
    /// Matches what the Inbox shows: unread messages plus unread updates.
    private var unread: Int {
        channelsEverywhere.inWorkspace().reduce(0) { $0 + $1.unreadCount }
            + eventsEverywhere.inWorkspace().filter { !$0.isRead }.count
    }

    private func stack<Content: View>(_ tab: PhoneTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: nav.path(tab)) {
            content()
                .navigationDestination(for: PhoneRoute.self) { PhoneRouteView(route: $0) }
        }
    }

    /// Shows a destination requested with `app.go(_:)`.
    private func route(_ destination: Destination) {
        switch destination {
        case .home: nav.root(.today)
        case .tasks, .projects: nav.root(.tasks)
        case .project(let id): nav.root(.tasks); nav.push(.taskList(.project(id)), on: .tasks)
        case .list(let project, let list): nav.root(.tasks); nav.push(.taskList(.list(project, list)), on: .tasks)
        case .messages(let channel):
            nav.root(.inbox)
            if let channel { nav.push(.channel(channel), on: .inbox) }
        case .updates: nav.root(.inbox); nav.push(.updates, on: .inbox)
        case .crew: nav.root(.crew)
        case .agent(let id): nav.root(.crew); nav.push(.agent(id), on: .crew)
        case .automation(let id): nav.root(.crew); nav.push(.automation(id), on: .crew)
        case .crm: nav.push(.crm)
        case .reports: nav.push(.reports)
        case .settings:
            nav.showsSettings = true
            // Settings is a sheet; the page underneath stays what it was.
            echo = nav.current
            app.destination = nav.current
        }
    }
}

/// Renders a pushed screen. Deep screens shared with Mac and iPad keep their own
/// content; the navigation bar supplies Back and the title.
struct PhoneRouteView: View {
    @Environment(\.modelContext) private var context
    let route: PhoneRoute

    var body: some View {
        switch route {
        case .taskList(let filter): PhoneTaskList(filter: filter)
        case .channel(let id):
            if let channel = context.channel(id) { PhoneChannelChat(channel: channel) }
        case .updates: PhoneUpdates()
        case .agent(let id):
            if let agent = context.agent(id) { PhoneAgentChat(agent: agent) }
        case .automation(let id):
            if let automation = context.automation(id) {
                AutomationEditor(automation: automation)
                    .navigationTitle(automation.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .agents: PhoneCrew(only: .agents)
        case .automations: PhoneCrew(only: .automations)
        case .crm:
            PhoneCRM()
        case .contact(let id):
            if let contact = context.contact(id) { PhoneContactPage(contact: contact) }
        case .reports:
            PhoneReports()
        case .projects: PhoneTasksHome()
        }
    }
}

// MARK: - Shared toolbar

/// The top-right glass controls every tab root shares: + menu and the profile picture
/// (Settings), like Maps.
struct PhoneRootToolbar: ToolbarContent {
    @Environment(AppModel.self) private var app
    @Environment(PhoneNavigator.self) private var nav

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            PhoneWorkspaceMenu()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("New Task", systemImage: "checklist") { app.present(.newTask(project: nil, list: nil)) }
                Button("New List", systemImage: "list.bullet") { app.present(.newList(project: nil)) }
                Button("New Project", systemImage: "square.stack.3d.up") { app.present(.newProject) }
                Divider()
                Button("New Channel", systemImage: "number") { app.present(.newChannel) }
                Button("New Automation", systemImage: "bolt") { app.present(.newAutomation) }
                Button("Recruit Agent", systemImage: "person.badge.plus") { app.present(.recruitAgent) }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New")
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button { nav.showsSettings = true } label: {
                ProfileAvatar(size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings and profile")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Workspace switcher: the workspace name in a glass capsule.
struct PhoneWorkspaceMenu: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Picker("Workspace", selection: Binding(get: { app.preferences.currentWorkspaceID }, set: { app.switchWorkspace(to: $0) })) {
                ForEach(app.preferences.workspaces) { workspace in
                    Text(workspace.name).tag(workspace.id)
                }
            }
            Divider()
            Button("New Workspace…", systemImage: "plus") { app.present(.newWorkspace) }
            Button("Customize Tabs", systemImage: "slider.horizontal.3") { app.openSettings(.sidebar) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(app.preferences.currentWorkspace.color.color).frame(width: 9, height: 9)
                Text(app.preferences.currentWorkspace.name)
                    .appFont(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down").appFont(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 6)
            .fixedSize()
        }
        .accessibilityLabel("Workspace: \(app.preferences.currentWorkspace.name)")
    }
}
#endif
