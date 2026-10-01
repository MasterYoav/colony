//
//  ColonyTests.swift
//  ColonyTests
//

import Foundation
import SwiftData
import Testing
@testable import Colony

@MainActor
struct ColonyTests {
    private func makeContext() -> ModelContext {
        ModelContext(CloudStore.inMemoryContainer())
    }

    @Test func schemaIsCloudKitCompatible() throws {
        // CloudKit mirroring rejects schemas with unique constraints or non-optional
        // relationships. Building a container with the full schema catches regressions.
        let container = CloudStore.inMemoryContainer()
        #expect(container.schema.entities.count == ColonySchema.models.count)
        for entity in container.schema.entities {
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) must be optional for CloudKit")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name) needs an inverse for CloudKit")
            }
            for attribute in entity.attributes {
                #expect(!attribute.options.contains(.unique), "\(entity.name).\(attribute.name) can't be unique under CloudKit")
            }
        }
    }

    @Test func createProjectAddsListsAndLogsActivity() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)

        let project = try #require(actions.createProject(name: "  Launch ", symbol: "calendar", color: .blue, lists: ["March", " ", "April"]))

        #expect(project.name == "Launch")
        #expect(project.sortedLists.map(\.name) == ["March", "April"])
        let events = try context.fetch(FetchDescriptor<ActivityEvent>())
        #expect(events.contains { $0.title == "Project created" })
    }

    @Test func renameTrimsRejectsBlankAndLogs() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let project = try #require(actions.createProject(name: "Launch", symbol: "calendar", color: .blue))

        #expect(actions.rename(project, to: "   ") == false)
        #expect(project.name == "Launch")

        #expect(actions.rename(project, to: "  Launch v2 "))
        #expect(project.name == "Launch v2")
        let events = try context.fetch(FetchDescriptor<ActivityEvent>())
        #expect(events.contains { $0.title == "Project renamed" && $0.detail == "Launch → Launch v2" })
    }

    @Test func projectSettingsEditsDetailsAndLists() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let project = try #require(actions.createProject(name: "Sales", symbol: "doc", color: .purple, lists: ["Demos", "Deals", "Old"]))
        let lists = project.sortedLists
        let old = try #require(lists.last)
        let task = try #require(actions.createTask(title: "Follow up", list: old))

        // Rename "Demos", swap order with "Deals", remove "Old", add "Renewals".
        let drafts = [
            ListDraft(id: lists[1].uuid, name: "Deals"),
            ListDraft(id: lists[0].uuid, name: "Live demos"),
            ListDraft(id: nil, name: "Renewals"),
            ListDraft(id: nil, name: "   "),
        ]
        #expect(actions.update(project, name: "Sales team", symbol: "star.fill", color: .green, summary: "  Q4 ", lists: drafts))

        #expect(project.name == "Sales team")
        #expect(project.symbol == "star.fill")
        #expect(project.color == .green)
        #expect(project.summary == "Q4")
        #expect(project.sortedLists.map(\.name) == ["Deals", "Live demos", "Renewals"])
        // A task in a removed list stays in the project.
        #expect(task.project?.uuid == project.uuid)
        #expect(task.list == nil)
    }

    @Test func projectSettingsRejectsBlankName() throws {
        let actions = WorkspaceActions(context: makeContext())
        let project = try #require(actions.createProject(name: "Ops", symbol: "doc", color: .blue, lists: ["A"]))
        #expect(actions.update(project, name: " ", symbol: "star.fill", color: .red, summary: "", lists: []) == false)
        #expect(project.name == "Ops")
        #expect(project.symbol == "doc")
        #expect(project.sortedLists.count == 1)
    }

    @Test func blankNamesAreRejected() {
        let actions = WorkspaceActions(context: makeContext())
        #expect(actions.createProject(name: "   ", symbol: "folder", color: .blue) == nil)
        #expect(actions.createTask(title: "") == nil)
        #expect(actions.createChannel(name: "  ", topic: "") == nil)
        #expect(actions.createContact(name: "") == nil)
    }

    @Test func tasksCountTowardProjectAndListUntilDone() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let project = try #require(actions.createProject(name: "Sales", symbol: "doc", color: .purple, lists: ["Demos"]))
        let list = try #require(project.sortedLists.first)

        let task = try #require(actions.createTask(title: "Prepare demo", list: list))
        #expect(task.project?.uuid == project.uuid)
        #expect(project.openTaskCount == 1)
        #expect(list.openTaskCount == 1)

        actions.setStatus(.done, for: task)
        #expect(task.completedAt != nil)
        #expect(project.openTaskCount == 0)
        #expect(project.progress == 1)

        actions.toggleDone(task)
        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
    }

    @Test func channelNamesAreSluggedAndUnique() throws {
        let actions = WorkspaceActions(context: makeContext())
        let channel = try #require(actions.createChannel(name: "Customer Success", topic: "Renewals"))
        #expect(channel.name == "customer-success")
        #expect(actions.createChannel(name: "customer success", topic: "dup") == nil)
    }

    @Test func unreadCountsAndSending() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let channel = try #require(actions.createChannel(name: "general", topic: ""))
        channel.lastReadAt = .distantPast
        context.insert(Message(body: "Hi", authorName: "Maya", isMine: false, channel: channel))
        #expect(channel.unreadCount == 1)

        let sent = try #require(actions.send("  Hello team  ", to: channel, as: "Yoav"))
        #expect(sent.body == "Hello team")
        #expect(actions.send("   ", to: channel, as: "Yoav") == nil)
        #expect(channel.unreadCount == 0)
        #expect(channel.sortedMessages.last?.body == "Hello team")
    }

    @Test func appleContactImportIsIdempotent() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let first = try #require(actions.createContact(name: "Lior Stein", company: "Northwind", appleIdentifier: "ABC"))
        let second = try #require(actions.createContact(name: "Lior Stein", company: "Northwind", appleIdentifier: "ABC"))
        #expect(first.uuid == second.uuid)
        #expect(try context.fetchCount(FetchDescriptor<Contact>()) == 1)
        #expect(first.initials == "LS")
    }

    @Test func stageChangesAreLogged() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let contact = try #require(actions.createContact(name: "Noa", stage: .lead))
        actions.setStage(.won, for: contact)
        #expect(contact.stage == .won)
        let events = try context.fetch(FetchDescriptor<ActivityEvent>())
        #expect(events.contains { $0.title == "Deal moved" })

        actions.markAllUpdatesRead()
        #expect(try context.fetch(FetchDescriptor<ActivityEvent>()).allSatisfy(\.isRead))
    }

    @Test func starterContentSeedsOnce() throws {
        let context = makeContext()
        let defaults = try #require(UserDefaults(suiteName: "colony-tests-\(UUID())"))
        let prefs = CloudPreferences(useICloud: false, defaults: defaults)

        StarterContent.seedIfNeeded(context: context, preferences: prefs)
        let projects = try context.fetchCount(FetchDescriptor<Project>())
        #expect(projects == 3)
        #expect(prefs.didSeedStarterContent)

        StarterContent.seedIfNeeded(context: context, preferences: prefs)
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == projects)
    }

    @Test func unknownRawValuesFallBackSafely() {
        let task = TaskItem(title: "x")
        task.statusRaw = "from-a-newer-version"
        task.priorityRaw = "???"
        #expect(task.status == .todo)
        #expect(task.priority == .medium)
    }

    @Test func preferencesPersistLocallyWithoutICloud() throws {
        let defaults = try #require(UserDefaults(suiteName: "colony-tests-\(UUID())"))
        let prefs = CloudPreferences(useICloud: false, defaults: defaults)
        prefs.appearance = .light
        prefs.expandedProjectIDs = ["a", "b"]
        prefs.displayName = "Yoav"

        let reloaded = CloudPreferences(useICloud: false, defaults: defaults)
        #expect(reloaded.appearance == .light)
        #expect(reloaded.expandedProjectIDs == ["a", "b"])
        #expect(reloaded.displayName == "Yoav")
    }

    @Test func oldSidebarLayoutsMigrateToMergedItems() throws {
        let defaults = try #require(UserDefaults(suiteName: "colony-tests-\(UUID())"))
        let prefs = CloudPreferences(useICloud: false, defaults: defaults)
        // A layout synced by an older version: two groups, My tasks + Tasks, Pipeline + Contacts.
        prefs.sidebarPinnedItems = ["inbox", "home", "myTasks"]
        prefs.sidebarWorkspaceItems = ["tasks", "contacts", "pipeline", "reports", "projects"]
        let layout = SidebarLayout(preferences: prefs)
        #expect(layout.items == [.inbox, .home, .updates, .tasks, .crm, .reports, .projects])

        layout.move(.crm, before: .inbox)
        #expect(layout.items.first == .crm)
        #expect(prefs.sidebarSetup.order.first == "crm")

        layout.reset()
        #expect(layout.items == SidebarNavItem.defaultOrder)
        #expect(!layout.isCustomized)
    }

    @Test func dealValueIsNeverNegative() throws {
        let actions = WorkspaceActions(context: makeContext())
        let contact = try #require(actions.createContact(name: "Dana", stage: .proposal))
        actions.setDealValue(12_500, for: contact)
        #expect(contact.dealValue == 12_500)
        actions.setDealValue(-5, for: contact)
        #expect(contact.dealValue == 0)
        #expect(DealStage.proposal.isOpen)
        #expect(!DealStage.won.isOpen && !DealStage.lost.isOpen)
    }
}
