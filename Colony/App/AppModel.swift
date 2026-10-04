//
//  AppModel.swift
//  Colony
//
//  App-wide UI state: the current destination, which sheet is open, toasts and
//  the Apple service wrappers. Data itself lives in SwiftData (see ColonyModels).
//

import Foundation
import Observation
import SwiftData
import SwiftUI

enum Destination: Hashable, Codable {
    case home
    case updates
    case messages(channel: UUID?)
    case tasks
    case projects
    case crm
    case reports
    case project(UUID)
    case list(project: UUID, list: UUID)
    case crew(CrewKind)
    case agent(UUID)
    case automation(UUID)
    case settings

    /// The rail icon that lights up for this destination.
    var railItem: RailItem {
        switch self {
        case .home: .home
        case .updates: .updates
        case .messages: .messages
        case .tasks: .tasks
        case .projects, .project, .list: .projects
        case .crm: .people
        case .reports, .crew, .agent, .automation: .home
        case .settings: .settings
        }
    }
}

enum RailItem: String, CaseIterable, Identifiable {
    case home, search, updates, projects, messages, tasks, people, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .updates: "Updates"
        case .projects: "Projects"
        case .messages: "Messages"
        case .tasks: "Tasks"
        case .people: "People"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .updates: "bell"
        case .projects: "folder"
        case .messages: "bubble.left"
        case .tasks: "list.clipboard"
        case .people: "person.2"
        case .settings: "slider.horizontal.3"
        }
    }

    var destination: Destination? {
        switch self {
        case .home: .home
        case .search: nil
        case .updates: .updates
        case .projects: .projects
        case .messages: .messages(channel: nil)
        case .tasks: .tasks
        case .people: .crm
        case .settings: .settings
        }
    }
}

enum ActiveSheet: Identifiable, Hashable {
    case newProject
    case projectSettings(UUID)
    case newTask(project: UUID?, list: UUID?)
    case newChannel
    case newContact
    case importContacts
    case task(UUID)
    case deleteProject(UUID)
    case deleteTask(UUID)
    case deleteContact(UUID)
    case connectReminders
    case connectContacts
    case recruitAgent
    case editAgent(UUID)
    case deleteAgent(UUID)
    case newAutomation
    case deleteAutomation(UUID)
    case newWorkspace
    case deleteWorkspace(String)
    case newList(project: UUID?)

    var id: String {
        switch self {
        case .newProject: "newProject"
        case .projectSettings(let id): "projectSettings-\(id)"
        case .newTask(let p, let l): "newTask-\(p?.uuidString ?? "")-\(l?.uuidString ?? "")"
        case .newChannel: "newChannel"
        case .newContact: "newContact"
        case .importContacts: "importContacts"
        case .task(let id): "task-\(id)"
        case .deleteProject(let id): "deleteProject-\(id)"
        case .deleteTask(let id): "deleteTask-\(id)"
        case .deleteContact(let id): "deleteContact-\(id)"
        case .connectReminders: "connectReminders"
        case .connectContacts: "connectContacts"
        case .recruitAgent: "recruitAgent"
        case .editAgent(let id): "editAgent-\(id)"
        case .deleteAgent(let id): "deleteAgent-\(id)"
        case .newAutomation: "newAutomation"
        case .deleteAutomation(let id): "deleteAutomation-\(id)"
        case .newWorkspace: "newWorkspace"
        case .deleteWorkspace(let id): "deleteWorkspace-\(id)"
        case .newList(let p): "newList-\(p?.uuidString ?? "")"
        }
    }

    /// Dialog width on Mac, iPad and Vision Pro. iPhone uses a full-width sheet.
    var dialogWidth: CGFloat {
        switch self {
        case .deleteProject, .deleteTask, .deleteContact, .deleteAgent, .deleteAutomation, .deleteWorkspace, .newList: 420
        case .newWorkspace: 520
        case .newAutomation: 620
        case .recruitAgent, .editAgent: 640
        case .connectReminders, .connectContacts: 420
        case .newChannel: 460
        case .newProject, .projectSettings: 520
        case .newTask, .newContact, .importContacts: 540
        case .task: 580
        }
    }
}

struct ToastMessage: Equatable {
    var message: String
    var detail: String?
    var style: ToastKind = .success

    enum ToastKind { case info, success, warning, error }
}

@MainActor
@Observable
final class AppModel {
    var destination: Destination = .home
    /// Which CRM view is showing (table or pipeline board); kept across visits.
    var crmTab: CRMTab = .customers
    /// Customer to open in the CRM detail panel (set when jumping from ⌘K).
    var crmSelection: UUID?
    /// The settings page on screen, with browser-style history for the back/forward pill.
    private(set) var settingsSection: SettingsSection = .profile
    private var settingsBackStack: [SettingsSection] = []
    private var settingsForwardStack: [SettingsSection] = []
    /// The dialog on screen (new project, task detail, confirmations…). Only one at a time.
    var sheet: ActiveSheet?
    var isCommandPalettePresented = false
    var toast: ToastMessage?
    var isToastPresented = false

    let preferences: CloudPreferences
    let iCloud: ICloudStatus
    let contacts = ContactsService()
    let reminders = RemindersService()
    /// The device's music player, shown in the sidebar.
    let nowPlaying = NowPlaying()
    let notifications = TaskNotifications()
    let calendar = TaskCalendar()
    let scheduler = TaskScheduler()
    /// Runs agents on the on-device model.
    let agents = AgentRunner()
    /// The user's AI accounts (API keys in the Keychain) for agents and Jev.
    let ai = AIAccounts()
    /// Runs automations when the workspace changes or their time comes.
    let automations = AutomationEngine()
    /// Colony is the frontmost app (for skipping notifications about what you're looking at).
    var isActive: Bool { notifications.isAppActive }

    init(preferences: CloudPreferences, iCloud: ICloudStatus) {
        self.preferences = preferences
        self.iCloud = iCloud
    }

    func go(_ destination: Destination) {
        withMotion(.snappy(duration: 0.22)) { self.destination = destination }
    }

    // MARK: Settings navigation

    /// Opens Settings on `section`, recording the page left behind for Back.
    func openSettings(_ section: SettingsSection) {
        if destination != .settings { go(.settings) }
        guard section != settingsSection else { return }
        settingsBackStack.append(settingsSection)
        settingsForwardStack.removeAll()
        settingsSection = section
    }

    var canGoBackInSettings: Bool { !settingsBackStack.isEmpty }
    var canGoForwardInSettings: Bool { !settingsForwardStack.isEmpty }

    func settingsBack() {
        guard let previous = settingsBackStack.popLast() else { return }
        settingsForwardStack.append(settingsSection)
        settingsSection = previous
    }

    func settingsForward() {
        guard let next = settingsForwardStack.popLast() else { return }
        settingsBackStack.append(settingsSection)
        settingsSection = next
    }

    /// The one way to open or close the sidebar, so every entry point (toggle button,
    /// ⌃⌘S, command palette) animates the width the same way.
    func toggleSidebar() {
        withMotion(Theme.sidebarAnimation) {
            preferences.isSidebarCollapsed.toggle()
        }
    }

    func toggleCommandPalette() {
        withMotion(.snappy(duration: 0.18)) {
            if isCommandPalettePresented {
                isCommandPalettePresented = false
            } else {
                sheet = nil
                isCommandPalettePresented = true
            }
        }
    }

    /// Opens a dialog, closing the command palette first.
    func present(_ dialog: ActiveSheet) {
        isCommandPalettePresented = false
        sheet = dialog
    }

    func show(_ message: String, detail: String? = nil, style: ToastMessage.ToastKind = .success) {
        toast = ToastMessage(message: message, detail: detail, style: style)
        isToastPresented = true
    }

    func isExpanded(_ project: Project) -> Bool {
        preferences.expandedProjectIDs.contains(project.uuid.uuidString)
    }

    func toggleExpanded(_ project: Project) {
        let key = project.uuid.uuidString
        withMotion(.snappy(duration: 0.2)) {
            if preferences.expandedProjectIDs.contains(key) {
                preferences.expandedProjectIDs.remove(key)
            } else {
                preferences.expandedProjectIDs.insert(key)
            }
        }
    }

    /// Mirrors a task into Apple Reminders when the user has opted in.
    func syncReminder(for task: TaskItem) {
        guard preferences.mirrorsToReminders, reminders.canWrite else { return }
        reminders.mirror(task)
    }
}

extension ModelContext {
    func project(_ id: UUID) -> Project? {
        try? fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.uuid == id })).first
    }

    func list(_ id: UUID) -> ProjectList? {
        try? fetch(FetchDescriptor<ProjectList>(predicate: #Predicate { $0.uuid == id })).first
    }

    func task(_ id: UUID) -> TaskItem? {
        try? fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.uuid == id })).first
    }

    func contact(_ id: UUID) -> Contact? {
        try? fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.uuid == id })).first
    }

    func channel(_ id: UUID) -> Channel? {
        try? fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.uuid == id })).first
    }

    func agent(_ id: UUID) -> Agent? {
        try? fetch(FetchDescriptor<Agent>(predicate: #Predicate { $0.uuid == id })).first
    }
}
