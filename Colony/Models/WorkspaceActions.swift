//
//  WorkspaceActions.swift
//  Colony
//
//  All mutations go through here so every write also records an Updates entry and
//  the rules live in one testable place. SwiftData autosaves and CloudKit mirrors
//  the private store to every device signed in to the same Apple Account.
//

import Foundation
import SwiftData

/// A list row in Project Settings: an existing list (with its id) or a new one.
struct ListDraft: Identifiable, Hashable {
    var id: UUID?
    var name: String
    let key = UUID()
}

@MainActor
struct WorkspaceActions {
    let context: ModelContext

    // MARK: Projects

    @discardableResult
    func createProject(name: String, symbol: String, color: ColonyColor, summary: String = "", lists: [String] = []) -> Project? {
        let name = ColonyText.trimmed(name)
        guard !name.isEmpty else { return nil }
        let nextIndex = ((try? context.fetch(FetchDescriptor<Project>()))?.map(\.sortIndex).max() ?? -1) + 1
        let project = Project(name: name, symbol: symbol, color: color, summary: ColonyText.trimmed(summary), sortIndex: nextIndex)
        context.insert(project)
        for (index, listName) in lists.map(ColonyText.trimmed).filter({ !$0.isEmpty }).enumerated() {
            context.insert(ProjectList(name: listName, project: project, sortIndex: index))
        }
        log("Project created", "\(name) is ready for planning.", symbol: "folder.badge.plus", color: color)
        return project
    }

    /// Renames a project. Returns false (and changes nothing) for an empty name.
    @discardableResult
    func rename(_ project: Project, to name: String) -> Bool {
        let name = ColonyText.trimmed(name)
        guard !name.isEmpty else { return false }
        guard name != project.name else { return true }
        let old = project.name
        project.name = name
        log("Project renamed", "\(old) → \(name)", symbol: "pencil", color: project.color)
        return true
    }

    /// Applies Project Settings: details plus the list edits (rename, add, remove, order).
    /// Tasks in a removed list stay in the project.
    @discardableResult
    func update(_ project: Project, name: String, symbol: String, color: ColonyColor, summary: String, lists: [ListDraft]) -> Bool {
        guard rename(project, to: name) else { return false }
        project.symbol = symbol
        project.colorRaw = color.rawValue
        project.summary = ColonyText.trimmed(summary)

        let kept = lists.filter { !ColonyText.trimmed($0.name).isEmpty }
        let keptIDs = Set(kept.compactMap(\.id))
        for list in project.sortedLists where !keptIDs.contains(list.uuid) {
            context.delete(list)
        }
        for (index, draft) in kept.enumerated() {
            let name = ColonyText.trimmed(draft.name)
            if let id = draft.id, let list = project.sortedLists.first(where: { $0.uuid == id }) {
                if list.name != name { list.name = name }
                if list.sortIndex != index { list.sortIndex = index }
            } else {
                context.insert(ProjectList(name: name, project: project, sortIndex: index))
            }
        }
        save()
        return true
    }

    @discardableResult
    func createList(named name: String, in project: Project) -> ProjectList? {
        let name = ColonyText.trimmed(name)
        guard !name.isEmpty else { return nil }
        let list = ProjectList(name: name, project: project, sortIndex: project.sortedLists.count)
        context.insert(list)
        return list
    }

    /// Moves `project` to sit just before `target` (or to the end when `target` is nil) and
    /// renumbers every project, so the order is stable on all devices after CloudKit merges.
    func move(_ project: Project, before target: Project?) {
        guard project.uuid != target?.uuid else { return }
        var ordered = ((try? context.fetch(FetchDescriptor<Project>())) ?? [])
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
        ordered.removeAll { $0.uuid == project.uuid }
        let index = target.flatMap { t in ordered.firstIndex { $0.uuid == t.uuid } } ?? ordered.endIndex
        ordered.insert(project, at: index)
        for (i, item) in ordered.enumerated() where item.sortIndex != i {
            item.sortIndex = i
        }
        save() // commit now so the order reaches iCloud even if the app is killed
    }

    func delete(_ project: Project) {
        log("Project deleted", project.name, symbol: "trash", color: .gray)
        context.delete(project)
    }

    // MARK: Tasks

    @discardableResult
    func createTask(title: String, notes: String = "", priority: TaskPriority = .medium, status: TaskStatus = .todo, dueDate: Date? = nil, project: Project? = nil, list: ProjectList? = nil) -> TaskItem? {
        let title = ColonyText.trimmed(title)
        guard !title.isEmpty else { return nil }
        let task = TaskItem(title: title, notes: notes, status: status, priority: priority, dueDate: dueDate, project: project ?? list?.project, list: list)
        context.insert(task)
        let place = (project ?? list?.project)?.name ?? "My tasks"
        log("Task created", "\(title) · \(place)", symbol: "checklist", color: (project ?? list?.project)?.color ?? .blue)
        return task
    }

    func setStatus(_ status: TaskStatus, for task: TaskItem) {
        guard task.status != status else { return }
        task.status = status
        if status == .done {
            log("Task completed", task.title, symbol: "checkmark.circle.fill", color: .green)
        }
    }

    func toggleDone(_ task: TaskItem) {
        setStatus(task.isDone ? .todo : .done, for: task)
    }

    func delete(_ task: TaskItem) {
        context.delete(task)
    }

    // MARK: Messaging

    @discardableResult
    func createChannel(name: String, topic: String) -> Channel? {
        let slug = ColonyText.channelSlug(name)
        guard !slug.isEmpty else { return nil }
        let existing = (try? context.fetch(FetchDescriptor<Channel>())) ?? []
        guard !existing.contains(where: { $0.name == slug }) else { return nil }
        let channel = Channel(name: slug, topic: ColonyText.trimmed(topic), sortIndex: existing.count)
        channel.lastReadAt = .now
        context.insert(channel)
        log("Channel created", "#\(slug)", symbol: "number", color: .teal)
        return channel
    }

    @discardableResult
    func send(_ body: String, to channel: Channel, as author: String) -> Message? {
        let body = ColonyText.trimmed(body)
        guard !body.isEmpty else { return nil }
        let message = Message(body: body, authorName: author, isMine: true, channel: channel)
        context.insert(message)
        channel.lastReadAt = .now
        return message
    }

    func markRead(_ channel: Channel) {
        channel.lastReadAt = .now
    }

    func delete(_ message: Message) {
        context.delete(message)
    }

    // MARK: CRM

    @discardableResult
    func createContact(name: String, company: String = "", jobTitle: String = "", email: String = "", phone: String = "", stage: DealStage = .lead, appleIdentifier: String? = nil, imageData: Data? = nil) -> Contact? {
        let name = ColonyText.trimmed(name)
        guard !name.isEmpty else { return nil }
        if let appleIdentifier,
           let existing = try? context.fetch(FetchDescriptor<Contact>(predicate: #Predicate { $0.appleContactIdentifier == appleIdentifier })),
           !existing.isEmpty {
            return existing.first
        }
        let color = ColonyColor.allCases[abs(name.hashValue) % ColonyColor.allCases.count]
        let contact = Contact(name: name, company: ColonyText.trimmed(company), jobTitle: ColonyText.trimmed(jobTitle), email: ColonyText.trimmed(email), phone: ColonyText.trimmed(phone), stage: stage, color: color)
        contact.appleContactIdentifier = appleIdentifier
        contact.imageData = imageData
        context.insert(contact)
        log("Contact added", company.isEmpty ? name : "\(name) · \(company)", symbol: "person.crop.circle.badge.plus", color: .indigo)
        return contact
    }

    func setStage(_ stage: DealStage, for contact: Contact) {
        guard contact.stage != stage else { return }
        contact.stage = stage
        log("Deal moved", "\(contact.name) → \(stage.title)", symbol: "arrow.triangle.branch", color: stage.color)
    }

    /// Removes the contact from Colony only; the person in Apple Contacts is never touched.
    func delete(_ contact: Contact) {
        context.delete(contact)
    }

    // MARK: Updates

    func markAllUpdatesRead() {
        for event in (try? context.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate { !$0.isRead }))) ?? [] {
            event.isRead = true
        }
    }

    func log(_ title: String, _ detail: String, symbol: String, color: ColonyColor) {
        context.insert(ActivityEvent(title: title, detail: detail, symbol: symbol, color: color))
    }

    func save() {
        try? context.save()
    }
}
