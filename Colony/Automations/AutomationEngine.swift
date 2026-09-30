//
//  AutomationEngine.swift
//  Colony
//
//  Runs automations. Workspace changes (a task created, a deal moved, a message posted)
//  are announced on `AutomationBus` by `WorkspaceActions`, so they fire for edits made
//  by you, by agents and by other automations alike. Time-based triggers (schedules and
//  "becomes overdue") are checked once a minute.
//
//  Changes synced in from another device don't fire here: the device where the change
//  was made runs the automation, and its results sync back. Schedules and overdue
//  checks store their last slot in iCloud so each one runs once across devices.
//
//  Chains are allowed (an automation's task can start another automation) but stop
//  after three hops, and an automation never triggers itself.
//

import Foundation
import Observation
import OSLog
import SwiftData
import UserNotifications

// MARK: - Events

struct AutomationEvent {
    var kind: TriggerKind
    var subjectID: UUID
    var status: TaskStatus?
    var stage: DealStage?
    var channelID: UUID?
    /// How many automations led to this change (0: you did it).
    var depth: Int = 0
    /// The automation whose step caused it, so it doesn't trigger itself.
    var sourceID: UUID?
}

/// Where `WorkspaceActions` announces changes. Nothing listens in unit tests, so
/// announcing is free there.
@MainActor
enum AutomationBus {
    static var handler: ((AutomationEvent) -> Void)?
    /// Set while an automation's steps run, so the changes they make carry the chain.
    static var depth = 0
    static var source: UUID?

    static func post(_ kind: TriggerKind, _ subject: UUID, status: TaskStatus? = nil, stage: DealStage? = nil, channel: UUID? = nil) {
        guard let handler else { return }
        handler(AutomationEvent(kind: kind, subjectID: subject, status: status, stage: stage, channelID: channel, depth: depth, sourceID: source))
    }
}

/// What an automation acts on.
enum AutomationSubject {
    case none
    case task(TaskItem)
    case customer(Contact)
    case message(Message)

    var kind: AutomationSubjectKind {
        switch self {
        case .none: .none
        case .task: .task
        case .customer: .customer
        case .message: .message
        }
    }

    var title: String {
        switch self {
        case .none: "Scheduled run"
        case .task(let task): task.title
        case .customer(let contact): contact.name
        case .message(let message): String(message.body.prefix(60))
        }
    }

    /// Fills {task}, {customer}… in step text.
    func fill(_ text: String, names: AutomationNames) -> String {
        var values: [String: String] = ["{today}": Date.now.formatted(date: .abbreviated, time: .omitted)]
        switch self {
        case .none: break
        case .task(let task):
            values["{task}"] = task.title
            values["{project}"] = task.project?.name ?? "My tasks"
            values["{status}"] = task.status.title
            values["{due}"] = task.dueDate.map { $0.formatted(date: .abbreviated, time: task.dueHasTime ? .shortened : .omitted) } ?? "no date"
        case .customer(let contact):
            values["{customer}"] = contact.name
            values["{company}"] = contact.company.isEmpty ? contact.name : contact.company
            values["{stage}"] = contact.stage.title
        case .message(let message):
            values["{message}"] = message.body
            values["{channel}"] = message.channel?.name ?? "channel"
            values["{author}"] = message.authorName
        }
        var result = text
        for (token, value) in values { result = result.replacingOccurrences(of: token, with: value) }
        return result
    }
}

/// Side effects outside the workspace, swapped out in tests.
struct AutomationEffects {
    var notify: (_ title: String, _ body: String) -> Void = { _, _ in }
    /// Returns false when the agent can't take it (missing, busy, model unavailable).
    var askAgent: (_ agentID: UUID, _ text: String) -> Bool = { _, _ in false }
}

// MARK: - Executor

/// Checks and runs one automation against one subject. Plain and synchronous, so it's
/// unit-tested without the engine. `dryRun` describes each step without changing anything.
@MainActor
struct AutomationExecutor {
    let context: ModelContext
    var effects = AutomationEffects()
    var dryRun = false

    private var actions: WorkspaceActions { WorkspaceActions(context: context) }

    /// Does the trigger fire for this event?
    static func matches(_ trigger: AutomationTrigger, _ event: AutomationEvent) -> Bool {
        guard trigger.kind == event.kind else { return false }
        switch trigger.kind {
        case .taskStatusChanged: return trigger.status == nil || trigger.status == event.status
        case .dealStageChanged: return trigger.stage == nil || trigger.stage == event.stage
        case .messagePosted: return trigger.channelID == nil || trigger.channelID == event.channelID
        default: return true
        }
    }

    /// Does the subject pass one filter? Filters for another kind of subject pass.
    static func passes(_ condition: AutomationCondition, _ subject: AutomationSubject) -> Bool {
        guard condition.isComplete else { return true }
        let needle = ColonyText.trimmed(condition.text).lowercased()
        switch (condition.kind, subject) {
        case (.inProject, .task(let task)): return task.project?.uuid == condition.projectID
        case (.priorityIs, .task(let task)): return task.priority == (condition.priority ?? .high)
        case (.titleContains, .task(let task)): return task.title.lowercased().contains(needle)
        case (.isFlagged, .task(let task)): return task.isFlagged
        case (.companyContains, .customer(let contact)): return contact.company.lowercased().contains(needle)
        case (.dealValueAtLeast, .customer(let contact)): return contact.dealValue >= condition.number
        case (.messageContains, .message(let message)): return message.body.lowercased().contains(needle)
        default: return condition.kind.subject == .none || condition.kind.subject != subject.kind
        }
    }

    func run(_ automation: Automation, subject: AutomationSubject) -> AutomationOutcome {
        let names = AutomationNames(context: context)
        var lines: [String] = []
        for condition in automation.conditions where condition.isComplete {
            guard Self.passes(condition, subject) else {
                return AutomationOutcome(kind: .skipped, title: subject.title, lines: ["Stopped: not true that \(condition.sentence(names))."])
            }
            lines.append("✓ \(condition.sentence(names).prefix(1).uppercased())\(condition.sentence(names).dropFirst())")
        }
        var failed = false
        let previousDepth = AutomationBus.depth, previousSource = AutomationBus.source
        AutomationBus.source = automation.uuid
        AutomationBus.depth = previousDepth + 1
        defer {
            AutomationBus.depth = previousDepth
            AutomationBus.source = previousSource
        }
        for step in automation.steps {
            let (ok, line) = perform(step, subject: subject, names: names)
            lines.append((ok ? "✓ " : "✕ ") + line)
            if !ok { failed = true }
        }
        return AutomationOutcome(kind: failed ? .failed : .ran, title: subject.title, lines: lines)
    }

    /// One step. Returns whether it worked and a line for the run log.
    private func perform(_ step: AutomationStep, subject: AutomationSubject, names: AutomationNames) -> (Bool, String) {
        let text = subject.fill(ColonyText.trimmed(step.text), names: names)
        let would = dryRun ? "Would " : ""
        func cap(_ s: String) -> String { dryRun ? s : s.prefix(1).uppercased() + s.dropFirst() }

        guard step.isComplete else { return (false, "“\(step.kind.title)” isn't set up yet.") }

        // Steps that change the trigger's task.
        if step.kind.needs == .task {
            guard case .task(let task) = subject else { return (false, "“\(step.kind.title)” needs a task, and this run has none.") }
            switch step.kind {
            case .setPriority:
                let priority = step.priority ?? .high
                if !dryRun { task.priority = priority }
                return (true, "\(would)\(cap("set “\(task.title)” to \(priority.title) priority"))")
            case .setStatus:
                let status = step.status ?? .inProgress
                if !dryRun { actions.setStatus(status, for: task) }
                return (true, "\(would)\(cap("move “\(task.title)” to \(status.title)"))")
            case .flagTask:
                if !dryRun { task.isFlagged = true }
                return (true, "\(would)\(cap("flag “\(task.title)”"))")
            case .moveTask:
                guard let id = step.projectID, let project = context.project(id) else { return (false, "The project for “Move it” no longer exists.") }
                if !dryRun { actions.move(task, to: project) }
                return (true, "\(would)\(cap("move “\(task.title)” to \(project.name)"))")
            case .setDue:
                let date = Calendar.current.date(byAdding: .day, value: step.days, to: Calendar.current.startOfDay(for: .now)) ?? .now
                if !dryRun { actions.setDue(date, hasTime: false, for: task) }
                return (true, "\(would)\(cap("make “\(task.title)” due \(date.formatted(date: .abbreviated, time: .omitted))"))")
            default: break
            }
        }

        switch step.kind {
        case .setStage:
            guard case .customer(let contact) = subject else { return (false, "“Move the customer” needs a customer, and this run has none.") }
            let stage = step.stage ?? .qualified
            if !dryRun { actions.setStage(stage, for: contact) }
            return (true, "\(would)\(cap("move \(contact.name) to \(stage.title)"))")

        case .createTask:
            let project = step.projectID.flatMap { context.project($0) }
            let due: Date? = step.days > 0 ? Calendar.current.date(byAdding: .day, value: step.days, to: Calendar.current.startOfDay(for: .now)) : nil
            if !dryRun {
                guard let task = actions.createTask(title: text, project: project) else { return (false, "Couldn't create a task with an empty name.") }
                if let due { actions.setDue(due, hasTime: false, for: task) }
            }
            return (true, "\(would)\(cap("create “\(text)”"))\(project.map { " in \($0.name)" } ?? "")")

        case .postMessage:
            guard let id = step.channelID, let channel = context.channel(id) else { return (false, "The channel for “Post” no longer exists.") }
            if !dryRun { actions.send(text, to: channel, as: "Colony", isMine: false) }
            return (true, "\(would)\(cap("post in #\(channel.name): “\(text)”"))")

        case .postUpdate:
            if !dryRun { actions.log(text, "", symbol: "bolt.fill", color: .orange) }
            return (true, "\(would)\(cap("add “\(text)” to Updates"))")

        case .notify:
            let body = text.isEmpty ? subject.title : text
            if !dryRun { effects.notify("", body) }
            return (true, "\(would)\(cap("notify you: “\(body)”"))")

        case .askAgent:
            guard let id = step.agentID, let agent = context.agent(id) else { return (false, "The agent for “Ask” no longer exists.") }
            if dryRun { return (true, "Would ask \(agent.name): “\(text)”") }
            guard effects.askAgent(id, text) else { return (false, "\(agent.name) couldn't take it (busy, or Apple Intelligence is off).") }
            return (true, "Asked \(agent.name): “\(text)”")

        case .clearCompleted:
            let cutoff = Calendar.current.date(byAdding: .day, value: -max(step.days, 1), to: .now) ?? .now
            let old = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { $0.isDone && ($0.completedAt ?? $0.createdAt) < cutoff }
            if !dryRun { old.forEach(actions.delete) }
            return (true, "\(would)\(cap("clear \(old.count) completed \(old.count == 1 ? "task" : "tasks")"))")

        default:
            return (false, "Unknown step.")
        }
    }

    /// The most recent thing this trigger could have fired for, for the Test button.
    func sampleSubject(for trigger: AutomationTrigger) -> AutomationSubject {
        switch trigger.kind.subject {
        case .none: return .none
        case .task:
            var tasks = (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
            if trigger.kind == .taskOverdue { tasks = tasks.filter(\.isOverdue) + tasks.filter { !$0.isOverdue } }
            if let status = trigger.status, trigger.kind == .taskStatusChanged { tasks = tasks.filter { $0.status == status } + tasks.filter { $0.status != status } }
            return tasks.first.map(AutomationSubject.task) ?? .none
        case .customer:
            var contacts = (try? context.fetch(FetchDescriptor<Contact>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
            if let stage = trigger.stage { contacts = contacts.filter { $0.stage == stage } + contacts.filter { $0.stage != stage } }
            return contacts.first.map(AutomationSubject.customer) ?? .none
        case .message:
            var messages = (try? context.fetch(FetchDescriptor<Message>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
            if let channel = trigger.channelID { messages = messages.filter { $0.channel?.uuid == channel } }
            return messages.first.map(AutomationSubject.message) ?? .none
        }
    }

    /// When a task counts as overdue: its due time, or the start of the next day for
    /// date-only tasks.
    static func overdueMoment(_ task: TaskItem) -> Date? {
        guard let due = task.dueDate else { return nil }
        if task.dueHasTime { return due }
        return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: due))
    }
}

// MARK: - Engine

@MainActor
@Observable
final class AutomationEngine {
    /// Automations running right now (for the flashing bolt).
    private(set) var running: Set<UUID> = []

    private var container: ModelContainer?
    private weak var app: AppModel?
    private var queue: [AutomationEvent] = []
    private var drain: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private let log = Logger(subsystem: "yoavperetz.Colony", category: "automations")
    static let maxDepth = 3
    static let keptRuns = 25

    func attach(_ container: ModelContainer, app: AppModel) {
        guard self.container == nil, !CloudStore.isRunningForTests else { return }
        self.container = container
        self.app = app
        AutomationBus.handler = { [weak self] event in self?.enqueue(event) }
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: Events

    /// Events wait a moment so the rest of the edit (project, due date typed right
    /// after the title) is in place when filters look at it.
    private func enqueue(_ event: AutomationEvent) {
        guard event.depth < Self.maxDepth else {
            log.info("chain stopped at depth \(event.depth)")
            return
        }
        queue.append(event)
        guard drain == nil else { return }
        drain = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.flush()
        }
    }

    private func flush() {
        drain = nil
        let events = queue
        queue.removeAll()
        guard let context = container?.mainContext else { return }
        let automations = enabledAutomations(context)
        guard !automations.isEmpty else { return }
        for event in events {
            guard let subject = subject(for: event, context: context) else { continue }
            for automation in automations where automation.uuid != event.sourceID {
                guard let trigger = automation.trigger, AutomationExecutor.matches(trigger, event) else { continue }
                AutomationBus.depth = event.depth
                execute(automation, subject: subject, context: context)
                AutomationBus.depth = 0
            }
        }
        try? context.save()
    }

    private func subject(for event: AutomationEvent, context: ModelContext) -> AutomationSubject? {
        switch event.kind.subject {
        case .none: return AutomationSubject.none
        case .task: return context.task(event.subjectID).map(AutomationSubject.task)
        case .customer: return context.contact(event.subjectID).map(AutomationSubject.customer)
        case .message:
            let id = event.subjectID
            return (try? context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.uuid == id })))?.first.map(AutomationSubject.message)
        }
    }

    // MARK: Time

    /// Schedules and overdue tasks. Each automation records how far it got, in iCloud,
    /// so another device doesn't repeat the work.
    func tick(now: Date = .now) {
        guard let context = container?.mainContext else { return }
        var changed = false
        for automation in enabledAutomations(context) {
            guard let trigger = automation.trigger else { continue }
            switch trigger.kind {
            case .schedule:
                guard let schedule = trigger.schedule, let slot = schedule.lastSlot(before: now) else { continue }
                guard slot > (automation.lastScheduledSlot ?? automation.createdAt) else { continue }
                automation.lastScheduledSlot = slot
                changed = true
                try? context.save()
                // The Mac was asleep: skip, don't run hours late.
                guard now.timeIntervalSince(slot) < 2 * 3600 else { continue }
                execute(automation, subject: .none, context: context)
            case .taskOverdue:
                let since = automation.lastCheckedAt ?? automation.createdAt
                automation.lastCheckedAt = now
                changed = true
                let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { task in
                    guard !task.isDone, let moment = AutomationExecutor.overdueMoment(task) else { return false }
                    return moment > since && moment <= now
                }
                for task in tasks { execute(automation, subject: .task(task), context: context) }
            default:
                continue
            }
        }
        if changed { try? context.save() }
    }

    // MARK: Running

    @discardableResult
    func execute(_ automation: Automation, subject: AutomationSubject, context: ModelContext) -> AutomationOutcome {
        running.insert(automation.uuid)
        let executor = AutomationExecutor(context: context, effects: effects(for: automation))
        let outcome = executor.run(automation, subject: subject)
        record(outcome, for: automation, context: context)
        if outcome.kind != .skipped {
            automation.lastRunAt = .now
            automation.runCount += 1
        }
        log.info("\(automation.name, privacy: .public): \(outcome.kind.rawValue, privacy: .public)")
        let id = automation.uuid
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.running.remove(id)
        }
        return outcome
    }

    /// Runs the automation now, for real, on the most recent matching item.
    func runNow(_ automation: Automation) -> AutomationOutcome? {
        guard let context = container?.mainContext, let trigger = automation.trigger else { return nil }
        let subject = AutomationExecutor(context: context).sampleSubject(for: trigger)
        if trigger.kind.subject != .none, case .none = subject { return nil }
        let outcome = execute(automation, subject: subject, context: context)
        try? context.save()
        return outcome
    }

    func isRunning(_ automation: Automation) -> Bool { running.contains(automation.uuid) }

    private func record(_ outcome: AutomationOutcome, for automation: Automation, context: ModelContext) {
        context.insert(AutomationRun(title: outcome.title, detail: outcome.lines.joined(separator: "\n"), outcome: outcome.kind, automation: automation))
        let runs = automation.sortedRuns
        if runs.count > Self.keptRuns { runs.dropFirst(Self.keptRuns).forEach(context.delete) }
    }

    private func effects(for automation: Automation) -> AutomationEffects {
        AutomationEffects(
            notify: { [weak self] _, body in self?.notify(automation.name, body) },
            askAgent: { [weak self] id, text in
                guard let self, let app = self.app, app.agents.isAvailable,
                      let agent = self.container?.mainContext.agent(id), !app.agents.isRunning(agent) else { return false }
                app.agents.send(text, to: agent)
                return true
            }
        )
    }

    private func notify(_ title: String, _ body: String) {
        guard let app else { return }
        guard app.notifications.canNotify, !app.isActive else {
            app.show(title, detail: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(240))
        content.sound = .default
        content.threadIdentifier = "colony.automations"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "colony.automation.\(UUID().uuidString)", content: content, trigger: nil))
    }

    private func enabledAutomations(_ context: ModelContext) -> [Automation] {
        ((try? context.fetch(FetchDescriptor<Automation>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [])
            .filter { $0.isEnabled && !$0.isDeleted && $0.isComplete }
    }
}
