//
//  AgentWorkspace.swift
//  Colony
//
//  What an agent can see and do, as plain functions over the SwiftData context. The
//  Foundation Models tools (AgentTools.swift) are thin wrappers around these, so the
//  behaviour is testable without a language model.
//
//  Every change goes through WorkspaceActions (same logs, same rules as the UI) and is
//  recorded in the agent's conversation as an action row, so you can see what it did.
//

import Foundation
import SwiftData

@MainActor
struct AgentWorkspace {
    let context: ModelContext
    let agentID: UUID

    private var actions: WorkspaceActions { WorkspaceActions(context: context) }

    var agent: Agent? {
        try? context.fetch(FetchDescriptor<Agent>(predicate: #Predicate { $0.uuid == agentID })).first
    }

    private var agentName: String { agent?.name ?? "Agent" }

    // MARK: Tasks

    func listTasks(filter rawFilter: String?, project projectName: String?) -> String {
        var tasks = fetch(TaskItem.self)
        let filter = (rawFilter ?? "open").lowercased().replacingOccurrences(of: " ", with: "_")
        if let projectName, !projectName.isEmpty {
            guard let project = findProject(projectName) else { return "No project called “\(projectName)”. Projects: \(projectNames())." }
            tasks = tasks.filter { $0.project?.uuid == project.uuid }
        }
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(for: .now).addingTimeInterval(86_400)
        let weekAhead = endOfToday.addingTimeInterval(6 * 86_400)
        switch filter {
        case "all": break
        case "done", "completed":
            let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
            tasks = tasks.filter { $0.isDone && ($0.completedAt ?? .distantPast) > weekAgo }
        case "today": tasks = tasks.filter { !$0.isDone && ($0.dueDate.map { $0 < endOfToday } ?? false) }
        case "overdue": tasks = tasks.filter(\.isOverdue)
        case "upcoming": tasks = tasks.filter { !$0.isDone && ($0.dueDate.map { $0 >= endOfToday && $0 < weekAhead } ?? false) }
        case "flagged": tasks = tasks.filter { !$0.isDone && $0.isFlagged }
        case "urgent": tasks = tasks.filter { !$0.isDone && ($0.priority == .urgent || $0.priority == .high) }
        case "no_project", "loose", "inbox": tasks = tasks.filter { !$0.isDone && $0.project == nil }
        default: tasks = tasks.filter { !$0.isDone }
        }
        tasks.sort { ($0.dueDate ?? .distantFuture, $1.priority.sortRank) < ($1.dueDate ?? .distantFuture, $0.priority.sortRank) }
        guard !tasks.isEmpty else { return "No \(filter == "open" ? "open" : filter.replacingOccurrences(of: "_", with: " ")) tasks." }
        let shown = tasks.prefix(25).map(describe)
        let more = tasks.count > 25 ? "\n…and \(tasks.count - 25) more." : ""
        return "\(tasks.count) task\(tasks.count == 1 ? "" : "s"):\n" + shown.joined(separator: "\n") + more
    }

    func createTask(title: String, notes: String?, project projectName: String?, list listName: String?, due: String?, priority: String?) -> String {
        let title = ColonyText.trimmed(title)
        guard !title.isEmpty else { return "A task needs a title." }
        var project: Project?
        if let projectName, !projectName.isEmpty {
            guard let found = findProject(projectName) else { return "No project called “\(projectName)”. Projects: \(projectNames())." }
            project = found
        }
        let list = listName.flatMap { name in project?.sortedLists.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } }
        let level = priority.flatMap { TaskPriority(rawValue: $0.lowercased()) } ?? .medium
        guard let task = actions.createTask(title: title, notes: notes ?? "", priority: level, project: project, list: list) else {
            return "Couldn't create the task."
        }
        var dueText = ""
        if let due, !due.isEmpty {
            if let parsed = AgentDates.parse(due) {
                actions.setDue(parsed.date, hasTime: parsed.hasTime, for: task)
                dueText = ", due \(DueText.label(for: task) ?? due)"
            } else {
                dueText = " (couldn't read the due date “\(due)”, so it has none)"
            }
        }
        record("Created task “\(title)”\(project.map { " in \($0.name)" } ?? "")\(dueText)", symbol: "plus.circle.fill")
        return "Created: \(describe(task))"
    }

    func updateTask(title: String, newTitle: String?, status: String?, priority: String?, due: String?, project projectName: String?, flagged: Bool?) -> String {
        guard let task = findTask(title) else { return "No task matching “\(title)”. Call list_tasks to see the exact titles." }
        var changes: [String] = []
        if let newTitle, !ColonyText.trimmed(newTitle).isEmpty, newTitle != task.title {
            task.title = ColonyText.trimmed(newTitle)
            changes.append("renamed to “\(task.title)”")
        }
        if let status, !status.isEmpty {
            let key = status.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
            let map: [String: TaskStatus] = ["todo": .todo, "open": .todo, "inprogress": .inProgress, "doing": .inProgress, "review": .review, "inreview": .review, "done": .done, "complete": .done, "completed": .done]
            guard let value = map[key] else { return "Unknown status “\(status)”. Use todo, in_progress, review or done." }
            actions.setStatus(value, for: task)
            changes.append("status \(value.title.lowercased())")
        }
        if let priority, !priority.isEmpty {
            guard let value = TaskPriority(rawValue: priority.lowercased()) else { return "Unknown priority “\(priority)”. Use low, medium, high or urgent." }
            task.priority = value
            changes.append("priority \(value.title.lowercased())")
        }
        if let due, !due.isEmpty {
            if ["none", "no date", "clear", "remove"].contains(due.lowercased()) {
                actions.setDue(nil, hasTime: false, for: task)
                changes.append("no due date")
            } else if let parsed = AgentDates.parse(due) {
                actions.setDue(parsed.date, hasTime: parsed.hasTime, for: task)
                changes.append("due \(DueText.label(for: task) ?? due)")
            } else {
                return "Couldn't read the due date “\(due)”. Try today, tomorrow, friday, 2026-10-02 or 2026-10-02 14:00."
            }
        }
        if let projectName, !projectName.isEmpty {
            if ["none", "no project"].contains(projectName.lowercased()) {
                actions.move(task, to: nil)
                changes.append("moved out of its project")
            } else if let project = findProject(projectName) {
                actions.move(task, to: project)
                changes.append("moved to \(project.name)")
            } else {
                return "No project called “\(projectName)”. Projects: \(projectNames())."
            }
        }
        if let flagged, flagged != task.isFlagged {
            task.isFlagged = flagged
            changes.append(flagged ? "flagged" : "unflagged")
        }
        guard !changes.isEmpty else { return "Nothing to change on “\(task.title)”." }
        record("Updated “\(task.title)”: \(changes.joined(separator: ", "))", symbol: "pencil.circle.fill")
        return "Updated: \(describe(task))"
    }

    // MARK: Projects

    func listProjects() -> String {
        let projects = fetch(Project.self).filter { $0.archivedAt == nil }.sorted { $0.sortIndex < $1.sortIndex }
        guard !projects.isEmpty else { return "There are no projects." }
        return projects.map { project in
            let lists = project.sortedLists.map(\.name)
            return "- \(project.name): \(project.openTaskCount) open task\(project.openTaskCount == 1 ? "" : "s")"
                + (lists.isEmpty ? "" : "; lists: \(lists.joined(separator: ", "))")
                + (project.summary.isEmpty ? "" : ". \(project.summary)")
        }.joined(separator: "\n")
    }

    // MARK: Customers

    func listCustomers(stage: String?) -> String {
        var customers = fetch(Contact.self)
        if let stage, !stage.isEmpty {
            guard let value = DealStage(rawValue: stage.lowercased()) else { return "Unknown stage “\(stage)”. Stages: \(DealStage.allCases.map(\.rawValue).joined(separator: ", "))." }
            customers = customers.filter { $0.stage == value }
        }
        guard !customers.isEmpty else { return "No customers\(stage.map { " in \($0)" } ?? "")." }
        customers.sort { ($0.stage.sortRank, $0.name) < ($1.stage.sortRank, $1.name) }
        return customers.prefix(30).map { contact in
            var line = "- \(contact.name)"
            if !contact.company.isEmpty { line += " (\(contact.company))" }
            line += " · \(contact.stage.title)"
            if contact.dealValue > 0 { line += " · \(contact.dealValue.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0))))" }
            if !contact.email.isEmpty { line += " · \(contact.email)" }
            return line
        }.joined(separator: "\n")
    }

    func moveCustomer(name: String, stage: String) -> String {
        guard let contact = findCustomer(name) else { return "No customer matching “\(name)”." }
        guard let value = DealStage(rawValue: stage.lowercased()) else { return "Unknown stage “\(stage)”. Stages: \(DealStage.allCases.map(\.rawValue).joined(separator: ", "))." }
        guard contact.stage != value else { return "\(contact.name) is already in \(value.title)." }
        actions.setStage(value, for: contact)
        record("Moved \(contact.name) to \(value.title)", symbol: "arrow.right.circle.fill")
        return "\(contact.name) is now in \(value.title)."
    }

    // MARK: Channels

    func readChannel(name: String?, limit: Int?) -> String {
        let channels = fetch(Channel.self).sorted { $0.sortIndex < $1.sortIndex }
        guard let name, !name.isEmpty else {
            guard !channels.isEmpty else { return "There are no channels." }
            return "Channels:\n" + channels.map { channel in
                let last = channel.lastMessage.map { " · last message \($0.createdAt.formatted(.relative(presentation: .named)))" } ?? " · no messages"
                return "- #\(channel.name)\(channel.topic.isEmpty ? "" : " (\(channel.topic))")\(last)"
            }.joined(separator: "\n")
        }
        guard let channel = findChannel(name) else { return "No channel called “\(name)”. Channels: \(channels.map { "#\($0.name)" }.joined(separator: ", "))." }
        let count = min(max(limit ?? 20, 1), 40)
        let messages = channel.sortedMessages.suffix(count)
        guard !messages.isEmpty else { return "#\(channel.name) has no messages." }
        return "Last \(messages.count) in #\(channel.name):\n" + messages.map { message in
            "- \(message.authorName.isEmpty ? "Someone" : message.authorName) (\(message.createdAt.formatted(date: .abbreviated, time: .shortened))): \(message.body.prefix(400))"
        }.joined(separator: "\n")
    }

    func postMessage(channel name: String, text: String) -> String {
        guard let channel = findChannel(name) else { return "No channel called “\(name)”." }
        guard actions.send(text, to: channel, as: agentName, isMine: false) != nil else { return "The message was empty." }
        record("Posted in #\(channel.name): “\(text.prefix(120))”", symbol: "bubble.left.fill")
        return "Posted in #\(channel.name)."
    }

    // MARK: Updates

    func listUpdates(limit: Int?) -> String {
        var descriptor = FetchDescriptor<ActivityEvent>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = min(max(limit ?? 15, 1), 40)
        let events = (try? context.fetch(descriptor)) ?? []
        guard !events.isEmpty else { return "No updates yet." }
        return events.map { "- \($0.createdAt.formatted(date: .abbreviated, time: .shortened)): \($0.title) — \($0.detail.prefix(200))" }.joined(separator: "\n")
    }

    func postUpdate(title: String, text: String) -> String {
        let title = ColonyText.trimmed(title)
        let text = ColonyText.trimmed(text)
        guard !title.isEmpty || !text.isEmpty else { return "The update was empty." }
        actions.log("\(agentName) · \(title.isEmpty ? "Note" : title)", text, symbol: "sparkles", color: agent?.color ?? .blue)
        record("Posted to Updates: \(title.isEmpty ? String(text.prefix(80)) : title)", symbol: "bell.fill")
        return "Posted to Updates."
    }

    // MARK: Ask

    /// Leaves a question for the user and marks the agent as waiting. The run ends
    /// after this; the user's reply starts the next turn.
    func askUser(question: String) -> String {
        record(ColonyText.trimmed(question), symbol: "hand.raised.fill")
        agent?.status = .waiting
        return "Your question is shown to the user. Stop here and wait for their reply; don't repeat the question."
    }

    // MARK: Helpers

    /// Adds an action row to the agent's conversation.
    func record(_ text: String, symbol: String) {
        guard let agent else { return }
        let next = (agent.messages ?? []).map(\.sequence).max().map { $0 + 1 } ?? 0
        context.insert(AgentMessage(role: .action, body: text, symbol: symbol, agent: agent, sequence: next))
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter { !$0.isDeleted }
    }

    private func describe(_ task: TaskItem) -> String {
        var parts = ["“\(task.title)”"]
        if let project = task.project { parts.append(task.list.map { "\(project.name) › \($0.name)" } ?? project.name) }
        if let due = DueText.label(for: task) { parts.append("due \(due)\(task.isOverdue ? " (overdue)" : "")") }
        if task.priority != .medium { parts.append("\(task.priority.title.lowercased()) priority") }
        if task.status != .todo { parts.append(task.status.title.lowercased()) }
        if task.isFlagged { parts.append("flagged") }
        return "- " + parts.joined(separator: " · ")
    }

    private func projectNames() -> String {
        fetch(Project.self).map(\.name).joined(separator: ", ")
    }

    private func findProject(_ name: String) -> Project? {
        best(fetch(Project.self), name, \.name)
    }

    private func findTask(_ title: String) -> TaskItem? {
        let tasks = fetch(TaskItem.self)
        // Prefer open tasks when titles repeat.
        return best(tasks.filter { !$0.isDone }, title, \.title) ?? best(tasks, title, \.title)
    }

    private func findCustomer(_ name: String) -> Contact? {
        best(fetch(Contact.self), name, \.name)
    }

    private func findChannel(_ name: String) -> Channel? {
        best(fetch(Channel.self), name.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), \.name)
    }

    /// Exact (case-insensitive) match, else the only item containing the text.
    private func best<T>(_ items: [T], _ query: String, _ key: KeyPath<T, String>) -> T? {
        let query = ColonyText.trimmed(query).trimmingCharacters(in: CharacterSet(charactersIn: "“”\"'"))
        guard !query.isEmpty else { return nil }
        if let exact = items.first(where: { $0[keyPath: key].localizedCaseInsensitiveCompare(query) == .orderedSame }) { return exact }
        let partial = items.filter { $0[keyPath: key].localizedCaseInsensitiveContains(query) }
        return partial.count == 1 ? partial[0] : nil
    }
}

extension DealStage {
    var sortRank: Int { DealStage.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Dates

/// Due dates as agents write them: today, tomorrow, friday, next monday, in 3 days,
/// 2026-10-02, optionally followed by a time (14:00, 2pm).
enum AgentDates {
    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> (date: Date, hasTime: Bool)? {
        var words = text.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: " at ", with: " ")
            .split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        // Trailing time.
        var time: (hour: Int, minute: Int)?
        if let last = words.last, let parsed = parseTime(last) {
            time = parsed
            words.removeLast()
        } else if words.count >= 2, ["am", "pm"].contains(words.last!), let parsed = parseTime(words[words.count - 2] + words.last!) {
            time = parsed
            words.removeLast(2)
        }
        let today = calendar.startOfDay(for: now)
        var day: Date?
        let phrase = words.joined(separator: " ")
        switch phrase {
        case "", "today", "tonight": day = today
        case "tomorrow": day = calendar.date(byAdding: .day, value: 1, to: today)
        case "next week": day = calendar.date(byAdding: .day, value: 7, to: today)
        default:
            if words.count == 3, words[0] == "in", let count = Int(words[1]) {
                let unit: Calendar.Component? = words[2].hasPrefix("day") ? .day : words[2].hasPrefix("week") ? .weekOfYear : nil
                if let unit { day = calendar.date(byAdding: unit, value: count, to: today) }
            } else if let weekday = weekdayIndex(words.last!), words.count <= 2, words.count == 1 || words[0] == "next" || words[0] == "this" {
                var parts = DateComponents()
                parts.weekday = weekday
                day = calendar.nextDate(after: today, matching: parts, matchingPolicy: .nextTime)
                if words.first == "next", let found = day, calendar.dateComponents([.day], from: today, to: found).day ?? 0 < 7 {
                    day = calendar.date(byAdding: .day, value: 7, to: found)
                }
            } else if words.count == 1, let date = isoDate(words[0], calendar: calendar) {
                day = date
            }
        }
        guard let day else { return nil }
        if let time, let dated = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) {
            return (dated, true)
        }
        return (day, false)
    }

    private static func parseTime(_ word: String) -> (hour: Int, minute: Int)? {
        var text = word
        var offset = 0
        if text.hasSuffix("am") || text.hasSuffix("pm") {
            offset = text.hasSuffix("pm") ? 12 : 0
            text = String(text.dropLast(2))
            let pieces = text.split(separator: ":")
            guard let h = Int(pieces[0]), (1...12).contains(h) else { return nil }
            let m = pieces.count > 1 ? Int(pieces[1]) ?? -1 : 0
            guard (0...59).contains(m) else { return nil }
            return ((h % 12) + offset, m)
        }
        let pieces = text.split(separator: ":")
        guard pieces.count == 2, let h = Int(pieces[0]), let m = Int(pieces[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private static func weekdayIndex(_ word: String) -> Int? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return names.firstIndex { $0 == word || $0.prefix(3) == word }.map { $0 + 1 }
    }

    private static func isoDate(_ word: String, calendar: Calendar) -> Date? {
        let pieces = word.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }
}
