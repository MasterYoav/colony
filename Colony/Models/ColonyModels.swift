//
//  ColonyModels.swift
//  Colony
//
//  SwiftData models synced to the user's private iCloud database through CloudKit.
//
//  CloudKit rules every model here follows:
//  - Every stored property has a default value or is optional.
//  - Every relationship is optional and declares an inverse.
//  - No `@Attribute(.unique)` (CloudKit can't enforce uniqueness).
//  - Enums are stored as raw strings so older clients can decode newer values.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Project

@Model
final class Project {
    var uuid: UUID = UUID()
    /// The workspace this belongs to ("" = the original one). See Workspaces.swift.
    var workspaceID: String = ""
    var name: String = ""
    var symbol: String = "folder.fill"
    var colorRaw: String = ColonyColor.blue.rawValue
    var summary: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ProjectList.project)
    var lists: [ProjectList]? = []

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.project)
    var tasks: [TaskItem]? = []

    init(name: String, symbol: String = "folder.fill", color: ColonyColor = .blue, summary: String = "", sortIndex: Int = 0) {
        self.workspaceID = WorkspaceScope.stamp
        self.name = name
        self.symbol = symbol
        self.colorRaw = color.rawValue
        self.summary = summary
        self.sortIndex = sortIndex
    }

    var color: ColonyColor {
        get { ColonyColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var sortedLists: [ProjectList] {
        (lists ?? []).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    var allTasks: [TaskItem] { tasks ?? [] }
    var openTaskCount: Int { allTasks.filter { !$0.isDone }.count }

    var progress: Double {
        let all = allTasks
        guard !all.isEmpty else { return 0 }
        return Double(all.filter(\.isDone).count) / Double(all.count)
    }
}

// MARK: - ProjectList (the expandable children under a project in the sidebar)

@Model
final class ProjectList {
    var uuid: UUID = UUID()
    var name: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var project: Project?

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.list)
    var tasks: [TaskItem]? = []

    init(name: String, project: Project?, sortIndex: Int = 0) {
        self.name = name
        self.project = project
        self.sortIndex = sortIndex
    }

    var openTaskCount: Int { (tasks ?? []).filter { !$0.isDone }.count }
}

// MARK: - Task

@Model
final class TaskItem {
    var uuid: UUID = UUID()
    /// The workspace this belongs to ("" = the original one). See Workspaces.swift.
    var workspaceID: String = ""
    var title: String = ""
    var notes: String = ""
    var statusRaw: String = TaskStatus.todo.rawValue
    var priorityRaw: String = TaskPriority.medium.rawValue
    var dueDate: Date?
    var assignedToMe: Bool = true
    var createdAt: Date = Date.now
    var completedAt: Date?
    /// `EKReminder.calendarItemIdentifier` once the task is mirrored into Apple Reminders.
    var reminderIdentifier: String?
    /// Flagged, as in Reminders.
    var isFlagged: Bool = false
    /// Whether `dueDate` carries a time. Date-only tasks notify at 9:00 and show as
    /// all-day events in Calendar. Older tasks always had a time, hence the default.
    var dueHasTime: Bool = true
    /// `EKEvent.calendarItemExternalIdentifier` of the task's event in the Colony
    /// calendar; external so every device finds the same event.
    var calendarEventID: String?

    var project: Project?
    var list: ProjectList?

    init(title: String, notes: String = "", status: TaskStatus = .todo, priority: TaskPriority = .medium, dueDate: Date? = nil, project: Project? = nil, list: ProjectList? = nil) {
        self.workspaceID = WorkspaceScope.stamp
        self.title = title
        self.notes = notes
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.project = project
        self.list = list
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? .now) : nil
        }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var isDone: Bool { status == .done }
    /// Past due: a timed task once its time passes, a date-only task from the next day.
    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueHasTime ? dueDate < .now : dueDate < Calendar.current.startOfDay(for: .now)
    }

    /// When to notify: the due time, or 9:00 on the day for date-only tasks.
    var alertDate: Date? {
        guard let dueDate else { return nil }
        if dueHasTime { return dueDate }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate)
    }
    var isDueToday: Bool { dueDate.map(Calendar.current.isDateInToday) ?? false }
}

// MARK: - Messaging

@Model
final class Channel {
    var uuid: UUID = UUID()
    /// The workspace this belongs to ("" = the original one). See Workspaces.swift.
    var workspaceID: String = ""
    var name: String = ""
    var topic: String = ""
    var symbol: String = "number"
    var createdAt: Date = Date.now
    var lastReadAt: Date = Date.distantPast
    var sortIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Message.channel)
    var messages: [Message]? = []

    init(name: String, topic: String = "", symbol: String = "number", sortIndex: Int = 0) {
        self.workspaceID = WorkspaceScope.stamp
        self.name = name
        self.topic = topic
        self.symbol = symbol
        self.sortIndex = sortIndex
    }

    var sortedMessages: [Message] { (messages ?? []).sorted { $0.createdAt < $1.createdAt } }
    var lastMessage: Message? { (messages ?? []).max { $0.createdAt < $1.createdAt } }
    var unreadCount: Int { (messages ?? []).filter { $0.createdAt > lastReadAt && !$0.isMine }.count }
}

@Model
final class Message {
    var uuid: UUID = UUID()
    var body: String = ""
    var authorName: String = ""
    var isMine: Bool = true
    var createdAt: Date = Date.now
    var isPinned: Bool = false
    var channel: Channel?

    init(body: String, authorName: String, isMine: Bool = true, channel: Channel?, createdAt: Date = .now) {
        self.body = body
        self.authorName = authorName
        self.isMine = isMine
        self.channel = channel
        self.createdAt = createdAt
    }
}

// MARK: - CRM

@Model
final class Contact {
    var uuid: UUID = UUID()
    /// The workspace this belongs to ("" = the original one). See Workspaces.swift.
    var workspaceID: String = ""
    var name: String = ""
    var company: String = ""
    var jobTitle: String = ""
    var email: String = ""
    var phone: String = ""
    var notes: String = ""
    var stageRaw: String = DealStage.lead.rawValue
    var colorRaw: String = ColonyColor.indigo.rawValue
    var isFavorite: Bool = false
    var createdAt: Date = Date.now
    /// Expected deal size in the user's currency; 0 means not set.
    var dealValue: Double = 0
    /// `CNContact.identifier` when the record was imported from Apple Contacts.
    var appleContactIdentifier: String?
    @Attribute(.externalStorage) var imageData: Data?

    init(name: String, company: String = "", jobTitle: String = "", email: String = "", phone: String = "", stage: DealStage = .lead, color: ColonyColor = .indigo) {
        self.workspaceID = WorkspaceScope.stamp
        self.name = name
        self.company = company
        self.jobTitle = jobTitle
        self.email = email
        self.phone = phone
        self.stageRaw = stage.rawValue
        self.colorRaw = color.rawValue
    }

    var stage: DealStage {
        get { DealStage(rawValue: stageRaw) ?? .lead }
        set { stageRaw = newValue.rawValue }
    }

    var color: ColonyColor {
        get { ColonyColor(rawValue: colorRaw) ?? .indigo }
        set { colorRaw = newValue.rawValue }
    }

    var initials: String { ColonyText.initials(for: name) }
}

// MARK: - Activity ("Updates")

@Model
final class ActivityEvent {
    var uuid: UUID = UUID()
    /// The workspace this belongs to ("" = the original one). See Workspaces.swift.
    var workspaceID: String = ""
    var title: String = ""
    var detail: String = ""
    var symbol: String = "sparkles"
    var colorRaw: String = ColonyColor.blue.rawValue
    var createdAt: Date = Date.now
    var isRead: Bool = false

    init(title: String, detail: String, symbol: String, color: ColonyColor) {
        self.workspaceID = WorkspaceScope.stamp
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.colorRaw = color.rawValue
    }

    var color: ColonyColor { ColonyColor(rawValue: colorRaw) ?? .blue }
}

// MARK: - Value types

enum TaskStatus: String, CaseIterable, Identifiable, Codable {
    case todo, inProgress, review, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .review: "In review"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .review: "circle.dotted.circle"
        case .done: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .todo: .secondary
        case .inProgress: .blue
        case .review: .orange
        case .done: .green
        }
    }
}

enum TaskPriority: String, CaseIterable, Identifiable, Codable {
    case low, medium, high, urgent

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .low: "chart.bar.fill"
        case .medium: "chart.bar.fill"
        case .high: "chart.bar.fill"
        case .urgent: "exclamationmark.square.fill"
        }
    }

    var color: Color {
        switch self {
        case .low: .secondary
        case .medium: .blue
        case .high: .orange
        case .urgent: .red
        }
    }
}

enum DealStage: String, CaseIterable, Identifiable, Codable {
    case lead, qualified, proposal, negotiation, won, lost

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .lead: "circle.dashed"
        case .qualified: "circle.lefthalf.filled"
        case .proposal: "doc.text.fill"
        case .negotiation: "arrow.left.arrow.right.circle.fill"
        case .won: "checkmark.circle.fill"
        case .lost: "xmark.circle.fill"
        }
    }

    /// Won and lost deals are closed; everything else is still in the pipeline.
    var isOpen: Bool { self != .won && self != .lost }

    var color: ColonyColor {
        switch self {
        case .lead: .gray
        case .qualified: .blue
        case .proposal: .purple
        case .negotiation: .orange
        case .won: .green
        case .lost: .red
        }
    }
}

enum ColonyColor: String, CaseIterable, Identifiable, Codable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, gray

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.36, green: 0.55, blue: 0.98)
        case .indigo: Color(red: 0.45, green: 0.44, blue: 0.96)
        case .purple: Color(red: 0.74, green: 0.42, blue: 0.95)
        case .pink: Color(red: 0.95, green: 0.40, blue: 0.66)
        case .red: Color(red: 0.94, green: 0.33, blue: 0.33)
        case .orange: Color(red: 0.97, green: 0.52, blue: 0.24)
        case .yellow: Color(red: 0.96, green: 0.78, blue: 0.27)
        case .green: Color(red: 0.30, green: 0.78, blue: 0.47)
        case .teal: Color(red: 0.25, green: 0.72, blue: 0.80)
        case .gray: Color(red: 0.55, green: 0.56, blue: 0.60)
        }
    }
}

enum ColonyText {
    static func initials(for name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func channelSlug(_ name: String) -> String {
        trimmed(name).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
    }
}

/// Every model in the iCloud schema, in one place so the container, previews and tests agree.
enum ColonySchema {
    static let models: [any PersistentModel.Type] = [
        Project.self, ProjectList.self, TaskItem.self, Channel.self, Message.self, Contact.self, ActivityEvent.self,
        Agent.self, AgentMessage.self, Automation.self, AutomationRun.self
    ]
}
