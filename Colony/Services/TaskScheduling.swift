//
//  TaskScheduling.swift
//  Colony
//
//  Two opt-in ways dated tasks reach the rest of the system, both Apple frameworks:
//
//  - Notifications (UserNotifications): each open task with a due date gets a local
//    notification at its due time (9:00 for date-only tasks), with Complete and
//    "Remind me in 1 hour" actions, like Reminders. The system delivers these even
//    when Colony isn't running, so nothing has to stay open in the background.
//  - Calendar (EventKit): dated tasks, and the scheduled automations, appear as events
//    in a "Colony" calendar in the user's iCloud account, next to the rest of their
//    schedule. Colony only writes to its own calendar.
//
//  The on/off switches roam through iCloud (CloudPreferences); each device keeps its own
//  pending notifications and asks its own permission.
//

import EventKit
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Observation
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Notifications

@MainActor
@Observable
final class TaskNotifications: NSObject {
    static let categoryID = "colony.task"
    static let completeAction = "colony.task.complete"
    static let snoozeAction = "colony.task.snooze"
    private static let idPrefix = "colony.task."

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()

    /// Called for Complete / Remind me in 1 hour / a tap on the notification.
    var onAction: ((_ taskID: UUID, _ action: String) -> Void)?
    /// A tap on an agent's notification.
    var onAgent: ((_ agentID: UUID) -> Void)?

    var canNotify: Bool { authorization == .authorized || authorization == .provisional }

    var statusTitle: String {
        switch authorization {
        case .authorized, .provisional: "Allowed"
        case .denied: "Turned off in Settings"
        default: "Not set up"
        }
    }

    override init() {
        super.init()
        guard !CloudStore.isRunningForTests else { return }
        center.delegate = self
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "Complete", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Remind Me in 1 Hour", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [complete, snooze], intentIdentifiers: [], options: [])
        ])
        Task { await refreshAuthorization() }
        // Permission can change in System Settings while Colony is open.
        #if os(macOS)
        let becameActive = NSApplication.didBecomeActiveNotification
        let resigned = NSApplication.didResignActiveNotification
        #else
        let becameActive = UIApplication.didBecomeActiveNotification
        let resigned = UIApplication.willResignActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: resigned, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAppActive = false }
        }
        NotificationCenter.default.addObserver(forName: becameActive, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isAppActive = true
                let was = self.canNotify
                await self.refreshAuthorization()
                if self.canNotify != was { self.onPermissionChange?() }
                self.onBecameActive?()
            }
        }
    }

    /// Lets the scheduler rebuild alerts once permission is granted in System Settings.
    var onPermissionChange: (() -> Void)?
    /// Whether Colony is frontmost; agents skip notifying about the page you're on.
    var isAppActive = true
    var onBecameActive: (() -> Void)?

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestAccess() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Schedules, reschedules or removes the notification for one task.
    func sync(_ task: TaskItem) {
        let id = Self.idPrefix + task.uuid.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard canNotify, !task.isDone, let fire = task.alertDate, fire > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        var body: [String] = []
        if let project = task.project?.name { body.append(task.list.map { "\(project) › \($0.name)" } ?? project) }
        if !task.notes.isEmpty { body.append(task.notes) }
        content.body = body.joined(separator: " · ")
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = task.project?.uuid.uuidString ?? "colony.tasks"
        content.userInfo = ["taskID": task.uuid.uuidString]
        content.interruptionLevel = task.priority == .urgent ? .timeSensitive : .active

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        center.add(request)
    }

    func remove(_ taskID: UUID) {
        let id = Self.idPrefix + taskID.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Rebuilds every pending notification from the tasks (launch, sync from another
    /// device, or the switch turning on). Stale ones for deleted tasks go away.
    func resync(_ tasks: [TaskItem]) {
        center.getPendingNotificationRequests { [weak self] requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            Task { @MainActor in
                guard let self else { return }
                self.center.removePendingNotificationRequests(withIdentifiers: ours)
                guard self.canNotify else { return }
                let upcoming = tasks
                    .filter { !$0.isDone && ($0.alertDate ?? .distantPast) > .now }
                    .sorted { ($0.alertDate ?? .distantFuture) < ($1.alertDate ?? .distantFuture) }
                    .prefix(60)
                upcoming.forEach(self.sync)
            }
        }
    }

    func removeAll() {
        center.getPendingNotificationRequests { [weak self] requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            Task { @MainActor in self?.center.removePendingNotificationRequests(withIdentifiers: ours) }
        }
    }
}

extension TaskNotifications: UNUserNotificationCenterDelegate {
    /// Show the banner even while Colony is in front, as Reminders does.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let raw = response.notification.request.content.userInfo["agentID"] as? String, let id = UUID(uuidString: raw) {
            await MainActor.run { self.onAgent?(id) }
            return
        }
        guard let raw = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: raw) else { return }
        let action = response.actionIdentifier
        await MainActor.run { self.onAction?(id, action) }
    }
}

// MARK: - Calendar

@MainActor
@Observable
final class TaskCalendar {
    static let calendarTitle = "Colony"
    /// Recreated once access is granted: a store opened before that sees no accounts.
    private var store = EKEventStore()
    private(set) var authorization: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var lastError: String?

    var canWrite: Bool { authorization == .fullAccess || authorization == .writeOnly }

    var statusTitle: String {
        switch authorization {
        case .fullAccess: "Connected"
        case .writeOnly: "Connected (add only)"
        case .denied, .restricted: "Access denied"
        default: "Not connected"
        }
    }

    /// Full access lets Colony find and update its events; with write-only access it
    /// can add events but not update them, so full access is what's requested.
    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        // The status can lag the answer by a moment; the answer is authoritative.
        authorization = granted ? .fullAccess : EKEventStore.authorizationStatus(for: .event)
        if granted { store = EKEventStore() }
        return granted
    }

    /// Picks up changes made in System Settings while Colony was running.
    func refreshAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status != authorization else { return }
        if status == .fullAccess { store = EKEventStore() }
        authorization = status
    }

    /// The "Colony" calendar, created in iCloud (or the default account) on first use.
    private func colonyCalendar() -> EKCalendar? {
        guard authorization == .fullAccess else { return nil }
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.cgColor = CGColor(red: 0.36, green: 0.55, blue: 0.98, alpha: 1)
        let sources = store.sources
        calendar.source = sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func event(external id: String?) -> EKEvent? {
        guard let id else { return nil }
        return store.calendarItems(withExternalIdentifier: id).compactMap { $0 as? EKEvent }.first
    }

    /// Creates, updates or removes the task's event. Completed and undated tasks have none.
    func sync(_ task: TaskItem) {
        guard let calendar = colonyCalendar() else { return }
        let existing = event(external: task.calendarEventID)
        guard !task.isDone, let due = task.dueDate else {
            if let existing { try? store.remove(existing, span: .thisEvent, commit: true) }
            task.calendarEventID = nil
            return
        }
        let event = existing ?? EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = task.isFlagged ? "⚑ \(task.title)" : task.title
        event.isAllDay = !task.dueHasTime
        event.startDate = due
        event.endDate = task.dueHasTime ? due.addingTimeInterval(30 * 60) : due
        var notes: [String] = []
        if let project = task.project?.name { notes.append("Project: \(project)") }
        if !task.notes.isEmpty { notes.append(task.notes) }
        notes.append("From Colony")
        event.notes = notes.joined(separator: "\n\n")
        event.url = URL(string: "colony://task/\(task.uuid.uuidString)")
        // Notifications come from Colony itself; no duplicate calendar alert.
        event.alarms = nil
        do {
            try store.save(event, span: .thisEvent, commit: true)
            task.calendarEventID = event.calendarItemExternalIdentifier
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Removes task events whose task no longer exists (deleted here or on another device).
    func sweep(keeping taskIDs: Set<UUID>) {
        guard let calendar = colonyCalendar() else { return }
        let start = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        let end = Calendar.current.date(byAdding: .year, value: 4, to: .now)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
        var changed = false
        for event in events where event.url?.host() == "task" {
            guard let id = event.url.flatMap(Self.itemID).flatMap(UUID.init(uuidString:)), !taskIDs.contains(id) else { continue }
            try? store.remove(event, span: .thisEvent, commit: false)
            changed = true
        }
        if changed { try? store.commit() }
    }

    /// The id in `colony://task/<id>` or `colony://automation/<id>`.
    private static func itemID(_ url: URL) -> String? {
        let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.isEmpty ? nil : id
    }

    func remove(eventID: String?) {
        guard authorization == .fullAccess, let event = event(external: eventID) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    /// Scheduled automations as repeating events, so the plan is visible in Calendar.
    /// Keyed by the automation's id in the event URL; unknown ones are removed.
    func syncAutomations(_ schedules: [AutomationSchedule]) {
        guard let calendar = colonyCalendar() else { return }
        let start = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let end = Calendar.current.date(byAdding: .year, value: 2, to: .now)!
        let existing = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
            .filter { $0.url?.host() == "automation" }
        var byID: [String: EKEvent] = [:]
        for event in existing {
            guard let id = event.url.flatMap(Self.itemID) else { continue }
            if byID[id] == nil { byID[id] = event.hasRecurrenceRules ? (store.event(withIdentifier: event.eventIdentifier) ?? event) : event }
        }
        let wanted = Set(schedules.map(\.id))
        for (id, event) in byID where !wanted.contains(id) {
            try? store.remove(event, span: .futureEvents, commit: false)
        }
        for schedule in schedules {
            let event = byID[schedule.id] ?? EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = "\(schedule.symbol) \(schedule.name)"
            event.notes = "\(schedule.detail)\n\n\(schedule.symbol == "✦" ? "Colony agent" : "Colony automation")"
            event.url = URL(string: "colony://automation/\(schedule.id)")
            event.startDate = schedule.firstRun
            event.endDate = schedule.firstRun.addingTimeInterval(15 * 60)
            event.recurrenceRules = [schedule.rule]
            event.alarms = nil
            try? store.save(event, span: .futureEvents, commit: false)
        }
        do { try store.commit() } catch { lastError = error.localizedDescription }
    }

    /// Deletes the Colony calendar and everything in it (turning the feature off).
    func removeCalendar() {
        guard authorization == .fullAccess,
              let calendar = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle }) else { return }
        try? store.removeCalendar(calendar, commit: true)
    }
}

/// A repeating automation, as it appears in Calendar.
struct AutomationSchedule {
    let id: String
    let name: String
    let detail: String
    let firstRun: Date
    let rule: EKRecurrenceRule
    var symbol: String = "⚙︎"

    /// Scheduled automations that are on, as repeating events at their run time.
    static func automations(_ automations: [Automation]) -> [AutomationSchedule] {
        automations.compactMap { automation -> AutomationSchedule? in
            guard automation.isEnabled, automation.isComplete, !automation.isDeleted,
                  let trigger = automation.trigger, trigger.kind == .schedule, let schedule = trigger.schedule,
                  let (first, rule) = recurrence(schedule) else { return nil }
            let detail = automation.sentence(AutomationNames(context: automation.modelContext ?? ModelContext.placeholder))
            return AutomationSchedule(id: automation.uuid.uuidString, name: automation.name, detail: detail, firstRun: first, rule: rule)
        }
    }

    /// First run and repeat rule for a schedule; nil for hourly (an event every hour
    /// would bury the calendar).
    static func recurrence(_ schedule: AgentSchedule) -> (Date, EKRecurrenceRule)? {
        let cal = Calendar.current
        var parts = DateComponents()
        parts.minute = schedule.minute
        let rule: EKRecurrenceRule
        switch schedule.kind {
        case .hourly:
            return nil
        case .daily:
            parts.hour = schedule.hour
            rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays:
            parts.hour = schedule.hour
            let days = (2...6).map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) }
            rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        case .weekly(let weekday):
            parts.hour = schedule.hour
            parts.weekday = weekday
            rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        }
        var first = cal.nextDate(after: .now, matching: parts, matchingPolicy: .nextTime) ?? .now
        if schedule.kind == .weekdays {
            while !(2...6).contains(cal.component(.weekday, from: first)) {
                first = cal.date(byAdding: .day, value: 1, to: first) ?? first
            }
        }
        return (first, rule)
    }

    /// Scheduled agents, as repeating events at their run time.
    static func agents(_ agents: [Agent]) -> [AutomationSchedule] {
        agents.compactMap { agent -> AutomationSchedule? in
            guard agent.isEnabled, !agent.isDeleted, let schedule = agent.schedule, let (first, rule) = recurrence(schedule) else { return nil }
            return AutomationSchedule(id: "agent-\(agent.uuid.uuidString)", name: agent.name, detail: agent.summary.isEmpty ? "Colony agent" : agent.summary, firstRun: first, rule: rule, symbol: "✦")
        }
    }
}

// MARK: - Coordinator

/// Keeps notifications and the Colony calendar in step with the tasks, whatever changed
/// them: an edit here, a notification action, or a sync from another device. It listens
/// to SwiftData saves and CloudKit imports rather than individual screens, so it keeps
/// working while the window is closed (Mac menu bar mode) or the app is refreshed in the
/// background (iPhone, iPad).
private let log = Logger(subsystem: "yoavperetz.Colony", category: "scheduler")

@MainActor
final class TaskScheduler {
    private weak var app: AppModel?
    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// Last synced state of each task, so only changed tasks touch Calendar.
    private var seen: [UUID: String] = [:]
    /// Agents' schedules as last written to Calendar.
    private var agentScheduleKey: String?

    func attach(_ container: ModelContainer, app: AppModel) {
        guard self.container == nil, !CloudStore.isRunningForTests else { return }
        self.container = container
        self.app = app
        let center = NotificationCenter.default
        for name in [ModelContext.didSave, Notification.Name("NSPersistentStoreRemoteChangeNotification")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        app.notifications.onAction = { [weak self] id, action in self?.handle(id, action) }
        app.notifications.onAgent = { [weak app] id in app?.go(.agent(id)) }
        app.notifications.onPermissionChange = { [weak self] in self?.run(force: true) }
        app.notifications.onBecameActive = { [weak app, weak self] in
            guard let app else { return }
            let was = app.calendar.authorization
            app.calendar.refreshAuthorization()
            if app.calendar.authorization != was { self?.run(force: true) }
        }
        Task {
            await app.notifications.refreshAuthorization()
            run(force: true)
        }
    }

    /// Debounced: a burst of edits (typing a title) becomes one pass.
    func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            run(force: false)
        }
    }

    /// `force` re-syncs everything (launch, a switch turned on).
    func run(force: Bool) {
        guard let app, let context = container?.mainContext else { return }
        let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDeleted }
        log.notice("schedule pass: \(tasks.count) tasks, force \(force), calendar \(app.preferences.showsTasksInCalendar) \(app.calendar.authorization.rawValue)")

        if app.preferences.notifiesTasks {
            app.notifications.resync(tasks)
        } else {
            app.notifications.removeAll()
        }

        guard app.preferences.showsTasksInCalendar, app.calendar.authorization == .fullAccess else {
            seen = [:]
            return
        }
        if force { seen = [:] }
        var current: [UUID: String] = [:]
        for task in tasks {
            let key = task.scheduleKey
            current[task.uuid] = key
            if seen[task.uuid] != key || (task.dueDate != nil && !task.isDone && task.calendarEventID == nil) {
                app.calendar.sync(task)
            }
        }
        if force || Set(seen.keys) != Set(current.keys) {
            app.calendar.sweep(keeping: Set(current.keys))
        }
        seen = current
        if app.preferences.showsAutomationsInCalendar {
            let agents = ((try? context.fetch(FetchDescriptor<Agent>())) ?? []).filter { !$0.isDeleted }
            let automations = ((try? context.fetch(FetchDescriptor<Automation>())) ?? []).filter { !$0.isDeleted }
            let key = agents.map { "\($0.uuid)\($0.scheduleRaw)\($0.isEnabled)\($0.name)" }.sorted().joined()
                + automations.map { "\($0.uuid)\($0.triggerJSON)\($0.stepsJSON)\($0.conditionsJSON)\($0.isEnabled)\($0.name)" }.sorted().joined()
            if force || key != agentScheduleKey {
                agentScheduleKey = key
                app.calendar.syncAutomations(AutomationSchedule.automations(automations) + AutomationSchedule.agents(agents))
            }
        } else if force {
            agentScheduleKey = nil
            app.calendar.syncAutomations([])
        }
    }

    private func handle(_ id: UUID, _ action: String) {
        guard let app, let context = container?.mainContext, let task = context.task(id) else { return }
        switch action {
        case TaskNotifications.completeAction:
            WorkspaceActions(context: context).setStatus(.done, for: task)
            app.syncReminder(for: task)
        case TaskNotifications.snoozeAction:
            WorkspaceActions(context: context).setDue(.now.addingTimeInterval(3600), hasTime: true, for: task)
            app.syncReminder(for: task)
        default:
            app.go(.tasks)
            app.present(.task(id))
        }
        try? context.save()
    }
}

/// Nudges the scheduler as soon as a task's schedule-relevant fields change, without
/// waiting for SwiftData's autosave. Lives invisibly behind the main window.
struct TaskChangeWatcher: View {
    @Environment(AppModel.self) private var app
    @Query private var tasks: [TaskItem]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: tasks.map(\.scheduleKey)) { app.scheduler.schedule() }
    }
}

extension TaskItem {
    /// Everything notifications and Calendar depend on.
    var scheduleKey: String {
        [uuid.uuidString, title, notes, "\(dueDate?.timeIntervalSince1970 ?? -1)", "\(dueHasTime)", "\(isDone)", "\(isFlagged)", "\(priority.rawValue)", project?.name ?? ""].joined(separator: "|")
    }
}
