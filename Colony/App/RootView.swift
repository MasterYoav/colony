//
//  RootView.swift
//  Colony
//

import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isDrawerOpen = false

    var body: some View {
        @Bindable var app = app

        Group {
            if sizeClass == .compact {
                compactLayout
            } else {
                HStack(spacing: 0) {
                    Sidebar()
                    Rectangle().fill(Theme.stroke).frame(width: 1)
                    DestinationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.canvas)
                }
                #if os(macOS)
                .overlay(alignment: .topLeading) {
                    if app.preferences.isSidebarCollapsed {
                        CollapsedSidebarToggle()
                    }
                }
                .ignoresSafeArea(edges: .top) // content runs under the hidden title bar
                #endif
            }
        }
        .background { TaskChangeWatcher() }
        .tint(ColonyColor.blue.color)
        .modifier(CommandPaletteHost())
        .modifier(DialogPresenter())
        .toast(
            isPresented: $app.isToastPresented,
            message: app.toast?.message ?? "",
            detail: app.toast?.detail,
            style: toastStyle,
            position: .bottom
        )
    }

    private var toastStyle: Toast.Style {
        switch app.toast?.style ?? .info {
        case .info: .info
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }

    /// iPhone: detail full screen, sidebar slides in as a drawer.
    private var compactLayout: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                DestinationView()
                    .background(Theme.canvas)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button("Menu", systemImage: "sidebar.left") {
                                withMotion(.snappy) { isDrawerOpen = true }
                            }
                        }
                    }
            }

            if isDrawerOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { withMotion(.snappy) { isDrawerOpen = false } }
                    .transition(.opacity)
                Sidebar()
                    .frame(maxHeight: .infinity)
                    .background(Theme.sidebar.ignoresSafeArea())
                    .transition(.move(edge: .leading))
            }
        }
        .onChange(of: app.destination) { withMotion(.snappy) { isDrawerOpen = false } }
    }
}

struct DestinationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            switch app.destination {
            case .home: HomeView()
            case .updates: UpdatesView()
            case .messages(let channelID): MessagesView(channelID: channelID)
            case .tasks: TasksScreen(scope: .all)
            case .projects: ProjectsView()
            case .project(let id):
                if let project = context.project(id) {
                    TasksScreen(scope: .project(project))
                } else {
                    missing
                }
            case .list(let projectID, let listID):
                if let list = context.list(listID), let project = context.project(projectID) {
                    TasksScreen(scope: .list(project, list))
                } else {
                    missing
                }
            case .crm: CRMView()
            case .reports: ReportsView()
            case .crew(.agents): AgentsHome()
            case .crew: AutomationsHome()
            case .automation(let id):
                if let automation = context.automation(id) {
                    AutomationEditor(automation: automation)
                        .id(id)
                } else {
                    missing
                }
            case .agent(let id):
                if let agent = context.agent(id) {
                    AgentPage(agent: agent)
                } else {
                    missing
                }
            case .settings: SettingsView()
            }
        }
        .id(app.destination)
        .transition(.opacity)
    }

    private var missing: some View {
        EmptyStateView(symbol: "questionmark.folder", title: "Not found", message: "This item was deleted on another device.", actionTitle: "Go home") {
            app.go(.home)
        }
    }
}

struct SheetHost: View {
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .newProject: ProjectFormSheet(mode: .create)
        case .projectSettings(let id): ProjectFormSheet(mode: .edit(id))
        case .newTask(let project, let list): NewTaskSheet(projectID: project, listID: list)
        case .newChannel: NewChannelSheet()
        case .newContact: NewContactSheet()
        case .importContacts: ImportContactsSheet()
        case .task(let id): TaskDetailSheet(taskID: id)
        case .deleteProject(let id): DeleteProjectDialog(projectID: id)
        case .deleteTask(let id): DeleteTaskDialog(taskID: id)
        case .deleteContact(let id): DeleteContactDialog(contactID: id)
        case .connectReminders: PermissionDialog(kind: .reminders)
        case .connectContacts: PermissionDialog(kind: .contacts)
        case .recruitAgent: RecruitAgentDialog(editing: nil)
        case .editAgent(let id): RecruitAgentDialog(editing: id)
        case .deleteAgent(let id): DeleteAgentDialog(agentID: id)
        case .newAutomation: NewAutomationDialog()
        case .deleteAutomation(let id): DeleteAutomationDialog(automationID: id)
        }
    }
}

/// Centred in-window dialogs on Mac, iPad and Vision Pro; a native sheet on iPhone,
/// where a floating card would be cramped. Both paths render the same `SheetHost`.
struct DialogPresenter: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        @Bindable var app = app
        if sizeClass == .compact {
            content.sheet(item: $app.sheet) { sheet in
                SheetHost(sheet: sheet)
                    .environment(\.dialogDismiss, DialogDismissAction { app.sheet = nil })
                    .environment(app)
                    .presentationDetents([.large])
                    .presentationBackground(Theme.raised)
            }
        } else {
            content.dialogOverlay(item: $app.sheet, width: \.dialogWidth) { sheet in
                SheetHost(sheet: sheet)
            }
        }
    }
}

#if os(macOS)
/// When the sidebar is collapsed, its toggle sits in the title bar just right of the
/// traffic lights (which are centred in the collapsed column), on the same line.
struct CollapsedSidebarToggle: View {
    var body: some View {
        SidebarToggleButton()
            // Traffic lights are 16pt tall at y 8, so their centre is y 16; the toggle is 30pt.
            .padding(.top, 16 - 15)
            .padding(.leading, Theme.collapsedPanelWidth + 6)
            .transition(.asymmetric(
                insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.14)),
                removal: .opacity.animation(.easeIn(duration: 0.1))
            ))
    }
}
#endif
