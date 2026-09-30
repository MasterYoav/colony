//
//  AutomationModels.swift
//  Colony
//
//  Automations: "when this happens, do that" flows, built from blocks instead of code.
//  One trigger (When), optional filters (Only if) and one or more steps (Then). The
//  flow itself is stored as small JSON strings on the Automation, so it syncs through
//  iCloud with the same CloudKit rules as everything else (defaults on every property,
//  optional relationships with inverses).
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Stored models

@Model
final class Automation {
    var uuid: UUID = UUID()
    var name: String = ""
    var colorRaw: String = ColonyColor.orange.rawValue
    var isEnabled: Bool = true
    /// `AutomationTrigger` as JSON; empty until one is chosen.
    var triggerJSON: String = ""
    /// `[AutomationCondition]` as JSON.
    var conditionsJSON: String = ""
    /// `[AutomationStep]` as JSON.
    var stepsJSON: String = ""
    var lastRunAt: Date?
    /// The schedule slot last run (by any device), so a slot runs once.
    var lastScheduledSlot: Date?
    /// Overdue trigger: tasks that became overdue after this were handled.
    var lastCheckedAt: Date?
    var runCount: Int = 0
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    /// The recipe it was made from, if any.
    var recipeID: String = ""

    @Relationship(deleteRule: .cascade, inverse: \AutomationRun.automation)
    var runs: [AutomationRun]? = []

    init(name: String) {
        self.name = name
    }

    var color: ColonyColor {
        get { ColonyColor(rawValue: colorRaw) ?? .orange }
        set { colorRaw = newValue.rawValue }
    }

    var trigger: AutomationTrigger? {
        get { AutomationJSON.decode(AutomationTrigger.self, triggerJSON) }
        set { triggerJSON = newValue.map(AutomationJSON.encode) ?? "" }
    }

    var conditions: [AutomationCondition] {
        get { AutomationJSON.decode([AutomationCondition].self, conditionsJSON) ?? [] }
        set { conditionsJSON = newValue.isEmpty ? "" : AutomationJSON.encode(newValue) }
    }

    var steps: [AutomationStep] {
        get { AutomationJSON.decode([AutomationStep].self, stepsJSON) ?? [] }
        set { stepsJSON = newValue.isEmpty ? "" : AutomationJSON.encode(newValue) }
    }

    /// Has a trigger and at least one step: it can run.
    var isComplete: Bool { trigger != nil && !steps.isEmpty }

    var sortedRuns: [AutomationRun] {
        (runs ?? []).sorted { $0.startedAt > $1.startedAt }
    }
}

@Model
final class AutomationRun {
    var uuid: UUID = UUID()
    var startedAt: Date = Date.now
    var outcomeRaw: String = AutomationOutcome.Kind.ran.rawValue
    /// What it ran for: a task title, customer name, or "Scheduled run".
    var title: String = ""
    /// One line per step.
    var detail: String = ""
    var isTest: Bool = false
    var automation: Automation?

    init(title: String, detail: String, outcome: AutomationOutcome.Kind, isTest: Bool = false, automation: Automation?) {
        self.title = title
        self.detail = detail
        self.outcomeRaw = outcome.rawValue
        self.isTest = isTest
        self.automation = automation
    }

    var outcome: AutomationOutcome.Kind { AutomationOutcome.Kind(rawValue: outcomeRaw) ?? .ran }
    var lines: [String] { detail.split(separator: "\n").map(String.init) }
}

enum AutomationJSON {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func decode<T: Decodable>(_ type: T.Type, _ text: String) -> T? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Categories

/// Groups blocks in the pickers and gives each its colour.
enum AutomationCategory: String, CaseIterable, Identifiable {
    case tasks, customers, messages, time, notify, agents, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .customers: "Customers"
        case .messages: "Messages"
        case .time: "Time"
        case .notify: "Notifications"
        case .agents: "Agents"
        case .updates: "Updates"
        }
    }

    var color: ColonyColor {
        switch self {
        case .tasks: .blue
        case .customers: .purple
        case .messages: .teal
        case .time: .orange
        case .notify: .red
        case .agents: .indigo
        case .updates: .green
        }
    }
}

/// What a trigger hands to the rest of the flow.
enum AutomationSubjectKind: Equatable {
    case none, task, customer, message

    /// Words you can drop into text fields, e.g. "{task}".
    var tokens: [(token: String, title: String)] {
        switch self {
        case .none: [("{today}", "Today's date")]
        case .task: [("{task}", "Task name"), ("{project}", "Project"), ("{status}", "Status"), ("{due}", "Due date"), ("{today}", "Today's date")]
        case .customer: [("{customer}", "Customer name"), ("{company}", "Company"), ("{stage}", "Stage"), ("{today}", "Today's date")]
        case .message: [("{message}", "Message"), ("{channel}", "Channel"), ("{author}", "Who posted"), ("{today}", "Today's date")]
        }
    }
}

// MARK: - Trigger

enum TriggerKind: String, Codable, CaseIterable, Identifiable {
    case taskCreated, taskStatusChanged, taskOverdue, dealStageChanged, customerAdded, messagePosted, schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taskCreated: "A task is created"
        case .taskStatusChanged: "A task changes status"
        case .taskOverdue: "A task becomes overdue"
        case .dealStageChanged: "A customer changes stage"
        case .customerAdded: "A customer is added"
        case .messagePosted: "Someone posts a message"
        case .schedule: "On a schedule"
        }
    }

    var detail: String {
        switch self {
        case .taskCreated: "Any new task, from you, an agent or another automation."
        case .taskStatusChanged: "Moved to To do, In progress, In review or Done."
        case .taskOverdue: "Its due date or time has passed and it isn't done."
        case .dealStageChanged: "Moved along the pipeline, like Proposal or Won."
        case .customerAdded: "Added by hand or imported from Contacts."
        case .messagePosted: "A new message in a channel."
        case .schedule: "Every hour, every day, on weekdays or once a week."
        }
    }

    var symbol: String {
        switch self {
        case .taskCreated: "plus.circle.fill"
        case .taskStatusChanged: "arrow.triangle.2.circlepath"
        case .taskOverdue: "exclamationmark.circle.fill"
        case .dealStageChanged: "arrow.triangle.branch"
        case .customerAdded: "person.crop.circle.badge.plus"
        case .messagePosted: "bubble.left.fill"
        case .schedule: "clock.fill"
        }
    }

    var category: AutomationCategory {
        switch self {
        case .taskCreated, .taskStatusChanged, .taskOverdue: .tasks
        case .dealStageChanged, .customerAdded: .customers
        case .messagePosted: .messages
        case .schedule: .time
        }
    }

    var subject: AutomationSubjectKind {
        switch self {
        case .taskCreated, .taskStatusChanged, .taskOverdue: .task
        case .dealStageChanged, .customerAdded: .customer
        case .messagePosted: .message
        case .schedule: .none
        }
    }
}

struct AutomationTrigger: Codable, Hashable {
    var kind: TriggerKind
    /// taskStatusChanged: only this status (nil = any change).
    var status: TaskStatus?
    /// dealStageChanged: only this stage (nil = any change).
    var stage: DealStage?
    /// messagePosted: only this channel (nil = any channel).
    var channelID: UUID?
    /// schedule: `AgentSchedule` text, e.g. "weekdays 09:00".
    var scheduleText: String?

    init(kind: TriggerKind, status: TaskStatus? = nil, stage: DealStage? = nil, channelID: UUID? = nil, scheduleText: String? = nil) {
        self.kind = kind
        self.status = status
        self.stage = stage
        self.channelID = channelID
        self.scheduleText = scheduleText
        if kind == .schedule, scheduleText == nil { self.scheduleText = "weekdays 09:00" }
    }

    var schedule: AgentSchedule? { scheduleText.flatMap(AgentSchedule.init) }

    /// "When a task moves to In review".
    func sentence(_ names: AutomationNames) -> String {
        switch kind {
        case .taskCreated: "When a task is created"
        case .taskStatusChanged: status.map { "When a task moves to \($0.title)" } ?? "When a task changes status"
        case .taskOverdue: "When a task becomes overdue"
        case .dealStageChanged: stage.map { "When a customer moves to \($0.title)" } ?? "When a customer changes stage"
        case .customerAdded: "When a customer is added"
        case .messagePosted: channelID.map { "When someone posts in #\(names.channel($0))" } ?? "When someone posts a message"
        case .schedule: schedule.map { Self.scheduleSentence($0) } ?? "On a schedule"
        }
    }

    /// Short, for the sidebar and cards: "Weekdays · 9:00", "When overdue".
    func shortLabel(_ names: AutomationNames) -> String {
        switch kind {
        case .taskCreated: "New task"
        case .taskStatusChanged: status.map { "Task → \($0.title)" } ?? "Task status"
        case .taskOverdue: "Task overdue"
        case .dealStageChanged: stage.map { "Deal → \($0.title)" } ?? "Deal stage"
        case .customerAdded: "New customer"
        case .messagePosted: channelID.map { "#\(names.channel($0))" } ?? "New message"
        case .schedule: schedule?.label ?? "Scheduled"
        }
    }

    static func scheduleSentence(_ schedule: AgentSchedule) -> String {
        let clock = Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now).map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        switch schedule.kind {
        case .hourly: return "Every hour"
        case .daily: return "Every day at \(clock)"
        case .weekdays: return "Every weekday at \(clock)"
        case .weekly(let day): return "Every \(Calendar.current.weekdaySymbols[day - 1]) at \(clock)"
        }
    }
}

// MARK: - Conditions

enum ConditionKind: String, Codable, CaseIterable, Identifiable {
    case inProject, priorityIs, titleContains, isFlagged, companyContains, dealValueAtLeast, messageContains

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inProject: "It's in a project"
        case .priorityIs: "Its priority is"
        case .titleContains: "Its name contains"
        case .isFlagged: "It's flagged"
        case .companyContains: "Their company contains"
        case .dealValueAtLeast: "Deal is worth at least"
        case .messageContains: "The message contains"
        }
    }

    var symbol: String {
        switch self {
        case .inProject: "folder.fill"
        case .priorityIs: "chart.bar.fill"
        case .titleContains: "text.magnifyingglass"
        case .isFlagged: "flag.fill"
        case .companyContains: "building.2.fill"
        case .dealValueAtLeast: "dollarsign.circle.fill"
        case .messageContains: "text.bubble.fill"
        }
    }

    var subject: AutomationSubjectKind {
        switch self {
        case .inProject, .priorityIs, .titleContains, .isFlagged: .task
        case .companyContains, .dealValueAtLeast: .customer
        case .messageContains: .message
        }
    }
}

struct AutomationCondition: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: ConditionKind
    var projectID: UUID?
    var priority: TaskPriority?
    var text: String = ""
    var number: Double = 0

    init(kind: ConditionKind, projectID: UUID? = nil, priority: TaskPriority? = nil, text: String = "", number: Double = 0) {
        self.kind = kind
        self.projectID = projectID
        self.priority = priority ?? (kind == .priorityIs ? .high : nil)
        self.text = text
        self.number = number
    }

    /// "it's in Sales", "its priority is High".
    func sentence(_ names: AutomationNames) -> String {
        switch kind {
        case .inProject: "it's in \(projectID.map(names.project) ?? "a project")"
        case .priorityIs: "its priority is \((priority ?? .high).title)"
        case .titleContains: "its name contains “\(text)”"
        case .isFlagged: "it's flagged"
        case .companyContains: "their company contains “\(text)”"
        case .dealValueAtLeast: "the deal is worth at least \(number.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0))))"
        case .messageContains: "the message contains “\(text)”"
        }
    }

    /// Ready to evaluate (has what it needs).
    var isComplete: Bool {
        switch kind {
        case .inProject: projectID != nil
        case .titleContains, .companyContains, .messageContains: !ColonyText.trimmed(text).isEmpty
        default: true
        }
    }
}

// MARK: - Steps

enum StepKind: String, Codable, CaseIterable, Identifiable {
    case createTask, setPriority, setStatus, flagTask, moveTask, setDue, setStage, postMessage, postUpdate, notify, askAgent, clearCompleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createTask: "Create a task"
        case .setPriority: "Change its priority"
        case .setStatus: "Change its status"
        case .flagTask: "Flag it"
        case .moveTask: "Move it to a project"
        case .setDue: "Set its due date"
        case .setStage: "Move the customer"
        case .postMessage: "Post in a channel"
        case .postUpdate: "Add to Updates"
        case .notify: "Notify me"
        case .askAgent: "Ask an agent"
        case .clearCompleted: "Clear old completed tasks"
        }
    }

    var detail: String {
        switch self {
        case .createTask: "A new task, in a project if you like, with a due date."
        case .setPriority: "Low, Medium, High or Urgent."
        case .setStatus: "To do, In progress, In review or Done."
        case .flagTask: "So it shows in the Flagged list."
        case .moveTask: "Into one of your projects."
        case .setDue: "A number of days from now."
        case .setStage: "To another stage of the pipeline."
        case .postMessage: "A message from Colony in one of your channels."
        case .postUpdate: "A note in Updates, where you see what happened."
        case .notify: "A notification on this device."
        case .askAgent: "Send one of your agents a request; it works on it right away."
        case .clearCompleted: "Delete tasks that were done a while ago."
        }
    }

    var symbol: String {
        switch self {
        case .createTask: "checklist"
        case .setPriority: "chart.bar.fill"
        case .setStatus: "circle.dashed"
        case .flagTask: "flag.fill"
        case .moveTask: "folder.fill"
        case .setDue: "calendar"
        case .setStage: "arrow.triangle.branch"
        case .postMessage: "number"
        case .postUpdate: "bell.fill"
        case .notify: "app.badge.fill"
        case .askAgent: "sparkles"
        case .clearCompleted: "trash.fill"
        }
    }

    var category: AutomationCategory {
        switch self {
        case .createTask, .setPriority, .setStatus, .flagTask, .moveTask, .setDue, .clearCompleted: .tasks
        case .setStage: .customers
        case .postMessage: .messages
        case .postUpdate: .updates
        case .notify: .notify
        case .askAgent: .agents
        }
    }

    /// Steps that change the trigger's task or customer need one.
    var needs: AutomationSubjectKind {
        switch self {
        case .setPriority, .setStatus, .flagTask, .moveTask, .setDue: .task
        case .setStage: .customer
        default: .none
        }
    }

    /// Whether this step can follow a trigger that hands over `subject`.
    func fits(_ subject: AutomationSubjectKind) -> Bool {
        needs == .none || needs == subject
    }

    /// Takes free text (with {tokens}).
    var usesText: Bool { [.createTask, .postMessage, .postUpdate, .notify, .askAgent].contains(self) }
}

struct AutomationStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: StepKind
    var text: String = ""
    var projectID: UUID?
    var channelID: UUID?
    var agentID: UUID?
    var priority: TaskPriority?
    var status: TaskStatus?
    var stage: DealStage?
    /// Due in N days (createTask, setDue) or "older than N days" (clearCompleted).
    var days: Int = 0

    init(kind: StepKind, text: String = "", projectID: UUID? = nil, channelID: UUID? = nil, agentID: UUID? = nil, priority: TaskPriority? = nil, status: TaskStatus? = nil, stage: DealStage? = nil, days: Int? = nil) {
        self.kind = kind
        self.text = text
        self.projectID = projectID
        self.channelID = channelID
        self.agentID = agentID
        self.priority = priority
        self.status = status
        self.stage = stage
        switch kind {
        case .setPriority: self.priority = priority ?? .high
        case .setStatus: self.status = status ?? .inProgress
        case .setStage: self.stage = stage ?? .qualified
        case .setDue: self.days = days ?? 1
        case .clearCompleted: self.days = days ?? 30
        default: self.days = days ?? 0
        }
    }

    /// "raise its priority to High", "create the task “Call {customer}”".
    func sentence(_ names: AutomationNames) -> String {
        switch kind {
        case .createTask:
            let place = projectID.map { " in \(names.project($0))" } ?? ""
            return "create the task “\(text.isEmpty ? "New task" : text)”\(place)\(days > 0 ? ", due in \(Self.days(days))" : "")"
        case .setPriority: return "set its priority to \((priority ?? .high).title)"
        case .setStatus: return "move it to \((status ?? .inProgress).title)"
        case .flagTask: return "flag it"
        case .moveTask: return "move it to \(projectID.map(names.project) ?? "a project")"
        case .setDue: return days == 0 ? "make it due today" : "make it due in \(Self.days(days))"
        case .setStage: return "move the customer to \((stage ?? .qualified).title)"
        case .postMessage: return "post “\(text)” in #\(channelID.map(names.channel) ?? "a channel")"
        case .postUpdate: return "add “\(text)” to Updates"
        case .notify: return text.isEmpty ? "notify me" : "notify me: “\(text)”"
        case .askAgent: return "ask \(agentID.map(names.agent) ?? "an agent") “\(text)”"
        case .clearCompleted: return "clear tasks completed more than \(Self.days(days)) ago"
        }
    }

    static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    var isComplete: Bool {
        switch kind {
        case .createTask, .postUpdate: !ColonyText.trimmed(text).isEmpty
        case .postMessage: channelID != nil && !ColonyText.trimmed(text).isEmpty
        case .moveTask: projectID != nil
        case .askAgent: agentID != nil && !ColonyText.trimmed(text).isEmpty
        default: true
        }
    }
}

// MARK: - Names

/// Turns the ids stored in a flow into names, for sentences. Missing ones read as
/// "a project" etc., so a deleted channel doesn't break the flow's description.
struct AutomationNames {
    var projects: [UUID: String] = [:]
    var channels: [UUID: String] = [:]
    var agents: [UUID: String] = [:]

    init(projects: [UUID: String] = [:], channels: [UUID: String] = [:], agents: [UUID: String] = [:]) {
        self.projects = projects
        self.channels = channels
        self.agents = agents
    }

    init(context: ModelContext) {
        for p in (try? context.fetch(FetchDescriptor<Project>())) ?? [] { projects[p.uuid] = p.name }
        for c in (try? context.fetch(FetchDescriptor<Channel>())) ?? [] { channels[c.uuid] = c.name }
        for a in (try? context.fetch(FetchDescriptor<Agent>())) ?? [] { agents[a.uuid] = a.name }
    }

    func project(_ id: UUID) -> String { projects[id] ?? "a project" }
    func channel(_ id: UUID) -> String { channels[id] ?? "a channel" }
    func agent(_ id: UUID) -> String { agents[id] ?? "an agent" }
}

extension Automation {
    /// The whole flow as one sentence: "When a task becomes overdue, if it's in Sales,
    /// set its priority to Urgent and notify me." Words like {task} read as [Task name].
    func sentence(_ names: AutomationNames) -> String {
        var text = rawSentence(names)
        let subject = trigger?.kind.subject ?? .none
        for kind in [subject, .task, .customer, .message, .none] {
            for token in kind.tokens { text = text.replacingOccurrences(of: token.token, with: "[\(token.title)]") }
        }
        return text
    }

    private func rawSentence(_ names: AutomationNames) -> String {
        guard let trigger else { return "Choose what starts this automation." }
        var text = trigger.sentence(names)
        let conditions = conditions.filter(\.isComplete)
        if !conditions.isEmpty {
            text += ", if " + Self.join(conditions.map { $0.sentence(names) })
        }
        let steps = steps
        if steps.isEmpty { return text + ", …" }
        return text + ", " + Self.join(steps.map { $0.sentence(names) }) + "."
    }

    static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0: ""
        case 1: parts[0]
        default: parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        }
    }

    /// For the sidebar: "Off", "Ran 5 min ago", or what starts it.
    func statusLine(_ names: AutomationNames) -> String {
        if !isComplete { return "Not set up" }
        if !isEnabled { return "Off" }
        return trigger?.shortLabel(names) ?? ""
    }
}

// MARK: - Outcome

struct AutomationOutcome {
    enum Kind: String {
        case ran, skipped, failed
    }

    var kind: Kind
    /// What it ran for.
    var title: String
    /// One line per filter/step, for the run log and the test sheet.
    var lines: [String]
}
