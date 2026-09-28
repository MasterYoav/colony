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
    case myTasks
    case projects
    case allTasks
    case pipeline
    case contacts
    case reports
    case project(UUID)
    case list(project: UUID, list: UUID)
    case appleServices
    case settings

    /// The rail icon that lights up for this destination.
    var railItem: RailItem {
        switch self {
        case .home: .home
        case .updates: .updates
        case .messages: .messages
        case .myTasks, .allTasks: .tasks
        case .projects, .project, .list: .projects
        case .pipeline, .contacts: .people
        case .reports: .home
        case .appleServices: .appleServices
        case .settings: .settings
        }
    }
}

enum RailItem: String, CaseIterable, Identifiable {
    case home, search, updates, projects, messages, tasks, people, appleServices, settings

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
        case .appleServices: "Apple services"
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
        case .appleServices: "puzzlepiece.extension"
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
        case .tasks: .myTasks
        case .people: .contacts
        case .appleServices: .appleServices
        case .settings: .settings
        }
    }
}

enum ActiveSheet: Identifiable, Hashable {
    case newProject
    case newTask(project: UUID?, list: UUID?)
    case newChannel
    case newContact
    case importContacts
    case task(UUID)
    case commandPalette

    var id: String {
        switch self {
        case .newProject: "newProject"
        case .newTask(let p, let l): "newTask-\(p?.uuidString ?? "")-\(l?.uuidString ?? "")"
        case .newChannel: "newChannel"
        case .newContact: "newContact"
        case .importContacts: "importContacts"
        case .task(let id): "task-\(id)"
        case .commandPalette: "commandPalette"
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
    var sheet: ActiveSheet?
    var toast: ToastMessage?
    var isToastPresented = false

    let preferences: CloudPreferences
    let iCloud: ICloudStatus
    let contacts = ContactsService()
    let reminders = RemindersService()

    init(preferences: CloudPreferences, iCloud: ICloudStatus) {
        self.preferences = preferences
        self.iCloud = iCloud
    }

    func go(_ destination: Destination) {
        withAnimation(.snappy(duration: 0.22)) { self.destination = destination }
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
        withAnimation(.snappy(duration: 0.2)) {
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

    func channel(_ id: UUID) -> Channel? {
        try? fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.uuid == id })).first
    }
}
