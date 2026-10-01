//
//  WorkspaceTests.swift
//  ColonyTests
//
//  Workspaces keep their data apart; sidebar setups hide and order items per
//  workspace; Reports count the right things.
//

import Foundation
import SwiftData
import Testing
@testable import Colony

@MainActor
@Suite(.serialized)
struct WorkspaceTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(CloudStore.inMemoryContainer())
    }

    private func preferences() -> CloudPreferences {
        let defaults = UserDefaults(suiteName: "colony.tests.\(UUID().uuidString)")!
        return CloudPreferences(useICloud: false, defaults: defaults)
    }

    @Test func recordsAreStampedWithTheOpenWorkspace() throws {
        let context = try makeContext()
        let actions = WorkspaceActions(context: context)
        WorkspaceScope.current = WorkspaceInfo.originalID
        defer { WorkspaceScope.current = WorkspaceInfo.originalID }

        let original = try #require(actions.createProject(name: "Launch", symbol: "folder.fill", color: .blue))
        WorkspaceScope.current = "personal"
        let personal = try #require(actions.createProject(name: "Home", symbol: "house.fill", color: .green))
        _ = actions.createTask(title: "Buy milk", project: personal)

        #expect(original.workspaceID == "")
        #expect(personal.workspaceID == "personal")
        #expect(context.inWorkspace(Project.self).map(\.name) == ["Home"])
        #expect(context.inWorkspace(Project.self, "").map(\.name) == ["Launch"])
        #expect(context.inWorkspace(TaskItem.self).map(\.title) == ["Buy milk"])
        #expect(context.inWorkspace(TaskItem.self, "").isEmpty)
    }

    @Test func runOverridesTheStampAndRestoresIt() {
        WorkspaceScope.current = "a"
        defer { WorkspaceScope.current = WorkspaceInfo.originalID }
        let inside = WorkspaceScope.run(in: "b") { WorkspaceScope.stamp }
        #expect(inside == "b")
        #expect(WorkspaceScope.stamp == "a")
    }

    @Test func childrenFollowTheirParent() throws {
        let context = try makeContext()
        let actions = WorkspaceActions(context: context)
        WorkspaceScope.current = "team"
        defer { WorkspaceScope.current = WorkspaceInfo.originalID }
        let project = try #require(actions.createProject(name: "Site", symbol: "globe", color: .blue, lists: ["Now"]))
        let channel = try #require(actions.createChannel(name: "design", topic: ""))
        let message = try #require(actions.send("Hi", to: channel, as: "Me"))
        #expect(workspaceOf(project.sortedLists[0]) == "team")
        #expect(workspaceOf(message) == "team")
        #expect([message].inWorkspace("team").count == 1)
        #expect([message].inWorkspace("").isEmpty)
    }

    @Test func deletingAWorkspaceRemovesOnlyItsData() throws {
        let context = try makeContext()
        let actions = WorkspaceActions(context: context)
        defer { WorkspaceScope.current = WorkspaceInfo.originalID }
        WorkspaceScope.current = ""
        _ = actions.createProject(name: "Keep", symbol: "folder.fill", color: .blue)
        _ = actions.createContact(name: "Ada")
        WorkspaceScope.current = "temp"
        let gone = try #require(actions.createProject(name: "Gone", symbol: "folder.fill", color: .blue))
        _ = actions.createTask(title: "Gone task", project: gone)
        _ = actions.createContact(name: "Grace")

        actions.deleteWorkspaceData("temp")
        try context.save()
        #expect(context.inWorkspace(Project.self, "temp").isEmpty)
        #expect(context.inWorkspace(TaskItem.self, "temp").isEmpty)
        #expect(context.inWorkspace(Contact.self, "temp").isEmpty)
        #expect(context.inWorkspace(Project.self, "").map(\.name) == ["Keep"])
        #expect(context.inWorkspace(Contact.self, "").map(\.name) == ["Ada"])

        // The original workspace can't be wiped this way.
        actions.deleteWorkspaceData("")
        #expect(context.inWorkspace(Project.self, "").count == 1)
    }

    @Test func sidebarSetupsArePerWorkspace() {
        let prefs = preferences()
        let layout = SidebarLayout(preferences: prefs)
        #expect(layout.items == SidebarNavItem.defaultOrder)

        layout.setHidden(.crm, true)
        layout.setHidden(.agents, true)
        #expect(!layout.items.contains(.crm))
        #expect(layout.allItems.contains(.crm))
        #expect(layout.isHidden(SidebarSectionItem.agents))
        #expect(layout.isCustomized)

        prefs.extraWorkspaces = [WorkspaceInfo(id: "w2", name: "Two", colorRaw: "green", createdAt: .now)]
        prefs.currentWorkspaceID = "w2"
        #expect(SidebarLayout(preferences: prefs).items.contains(.crm))
        #expect(!SidebarLayout(preferences: prefs).isHidden(SidebarSectionItem.agents))

        prefs.currentWorkspaceID = ""
        #expect(!SidebarLayout(preferences: prefs).items.contains(.crm))
        layout.reset()
        #expect(layout.items == SidebarNavItem.defaultOrder)
        #expect(!layout.isCustomized)
    }

    @Test func movingAndPresets() {
        let prefs = preferences()
        let layout = SidebarLayout(preferences: prefs)
        layout.move(.reports, by: -1)
        #expect(layout.allItems.suffix(2) == [.reports, .crm])
        layout.move(.home, by: -1)
        #expect(layout.allItems.first == .home)

        layout.apply(.personal)
        #expect(Set(layout.items) == [.home, .updates, .tasks, .projects])
        #expect(layout.isHidden(SidebarSectionItem.automations))
        #expect(prefs.sidebarSetup.preset == .personal)
        layout.setHidden(.reports, false)
        #expect(prefs.sidebarSetup.preset == nil)
    }

    @Test func legacyOrderCarriesIntoTheOriginalWorkspace() {
        let prefs = preferences()
        prefs.sidebarPinnedItems = ["tasks", "home"]
        let items = SidebarLayout(preferences: prefs).allItems
        #expect(items.first == .tasks)
        #expect(items.firstIndex(of: .home)! < items.firstIndex(of: .updates)!)
        #expect(items.count == SidebarNavItem.allCases.count)
    }

    @Test func workspaceNamesAndSymbols() {
        let prefs = preferences()
        prefs.workspaceName = "Acme"
        prefs.extraWorkspaces = [WorkspaceInfo(id: "x", name: "Personal", colorRaw: "green", createdAt: .now)]
        #expect(prefs.workspaces.map(\.name) == ["Acme", "Personal"])
        prefs.currentWorkspaceID = "x"
        prefs.currentWorkspaceName = "Home"
        #expect(prefs.extraWorkspaces[0].name == "Home")
        #expect(prefs.workspaceName == "Acme")
        #expect(WorkspaceInfo.symbol(for: "Home") == "h.square.fill")
        #expect(WorkspaceInfo.symbol(for: "בית") == "square.fill")
    }

    // MARK: Reports

    @Test func reportCountsDoneOpenAndLate() throws {
        let context = try makeContext()
        let actions = WorkspaceActions(context: context)
        let calendar = Calendar.current
        let now = Date.now
        let done = try #require(actions.createTask(title: "Done today"))
        done.status = .done
        let lastWeek = try #require(actions.createTask(title: "Done last week"))
        lastWeek.status = .done
        lastWeek.completedAt = calendar.date(byAdding: .day, value: -9, to: now)
        let late = try #require(actions.createTask(title: "Late", dueDate: calendar.date(byAdding: .day, value: -2, to: now)))
        let soon = try #require(actions.createTask(title: "Soon", dueDate: calendar.date(byAdding: .day, value: 3, to: now)))
        _ = (late, soon)

        let tasks = context.inWorkspace(TaskItem.self)
        let week = ReportStats(tasks: tasks, contacts: [], period: .week, now: now)
        #expect(week.done == 1)
        #expect(week.previousDone == 1)
        #expect(week.doneComparison == "Same as last week (1)")
        #expect(week.open == 2)
        #expect(week.late == 1)
        #expect(week.lateTasks.map(\.title) == ["Late"])
        #expect(week.dueSoon == 1)
        #expect(week.days.count == 7)
        #expect(week.days.last?.count == 1)

        let all = ReportStats(tasks: tasks, contacts: [], period: .all, now: now)
        #expect(all.done == 2)
        #expect(all.bucket == .month)
        #expect(all.doneComparison == "2 tasks finished so far")
    }

    @Test func reportSales() throws {
        let context = try makeContext()
        let actions = WorkspaceActions(context: context)
        for (name, stage, value) in [("A", DealStage.won, 1000.0), ("B", .won, 500), ("C", .lost, 0), ("D", .proposal, 2000)] {
            let contact = try #require(actions.createContact(name: name, stage: stage))
            contact.dealValue = value
        }
        let stats = ReportStats(tasks: [], contacts: context.inWorkspace(Contact.self), period: .all)
        #expect(stats.wonCount == 2)
        #expect(stats.wonValue == 1500)
        #expect(stats.winRate == "67%")
        #expect(stats.stuckDeals.isEmpty)
    }
}
