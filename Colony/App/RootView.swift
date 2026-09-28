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
                .ignoresSafeArea(edges: .top) // content runs under the hidden title bar
                #endif
            }
        }
        .tint(ColonyColor.blue.color)
        .sheet(item: $app.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(app)
        }
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
                                withAnimation(.snappy) { isDrawerOpen = true }
                            }
                        }
                    }
            }

            if isDrawerOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { isDrawerOpen = false } }
                    .transition(.opacity)
                Sidebar()
                    .frame(maxHeight: .infinity)
                    .background(Theme.sidebar.ignoresSafeArea())
                    .transition(.move(edge: .leading))
            }
        }
        .onChange(of: app.destination) { withAnimation(.snappy) { isDrawerOpen = false } }
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
            case .myTasks: TasksScreen(scope: .mine)
            case .allTasks: TasksScreen(scope: .all)
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
            case .pipeline: PipelineView()
            case .contacts: ContactsView()
            case .reports: ReportsView()
            case .appleServices: AppleServicesView()
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
        Group {
            switch sheet {
            case .newProject: NewProjectSheet()
            case .newTask(let project, let list): NewTaskSheet(projectID: project, listID: list)
            case .newChannel: NewChannelSheet()
            case .newContact: NewContactSheet()
            case .importContacts: ImportContactsSheet()
            case .task(let id): TaskDetailSheet(taskID: id)
            case .commandPalette: CommandPalette()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360)
        #endif
    }
}
