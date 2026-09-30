//
//  AgentTests.swift
//  ColonyTests
//
//  AGENT.md parsing, schedules, due-date phrases and the workspace tools agents call.
//  None of these need Apple Intelligence.
//

import Foundation
import SwiftData
import Testing
@testable import Colony

@MainActor
struct AgentTests {
    private func makeContext() -> ModelContext {
        ModelContext(CloudStore.inMemoryContainer())
    }

    // MARK: AGENT.md

    @Test func parsesFrontMatter() throws {
        let definition = try AgentDefinition.parse("""
        ---
        name: Neo
        description: "Plans your day."
        color: Purple
        tools: [list_tasks, update-task, Post Update, launch_rockets]
        schedule: weekdays 08:30
        prompts:
          - Plan my day
          - "What's overdue?"
        mood: sunny
        ---

        You are Neo.
        Be brief.
        """)
        #expect(definition.name == "Neo")
        #expect(definition.summary == "Plans your day.")
        #expect(definition.color == .purple)
        #expect(definition.tools == [.listTasks, .updateTask, .postUpdate])
        #expect(definition.schedule == AgentSchedule(kind: .weekdays, hour: 8, minute: 30))
        #expect(definition.prompts == ["Plan my day", "What's overdue?"])
        #expect(definition.instructions == "You are Neo.\nBe brief.")
        #expect(definition.warnings.count == 2) // launch_rockets, mood
        #expect(definition.warnings.contains { $0.contains("launch_rockets") })
        #expect(definition.warnings.contains { $0.contains("mood") })
    }

    @Test func headingOnlyFileUsesHeadingAsNameAndReadOnlyTools() throws {
        let definition = try AgentDefinition.parse("# Scout\n\nLook around and report.\n")
        #expect(definition.name == "Scout")
        #expect(definition.instructions == "Look around and report.")
        #expect(definition.tools == AgentTool.readOnly)
        #expect(definition.tools.allSatisfy { !$0.writes })
        #expect(definition.schedule == nil)
    }

    @Test func fallsBackToFileName() throws {
        let definition = try AgentDefinition.parse("Summarise things.", fallbackName: "Summariser")
        #expect(definition.name == "Summariser")
    }

    @Test func rejectsBrokenFiles() {
        #expect(throws: AgentDefinition.ParseError.empty) { try AgentDefinition.parse("  \n") }
        #expect(throws: AgentDefinition.ParseError.unterminatedFrontMatter) { try AgentDefinition.parse("---\nname: X\nNo end") }
        #expect(throws: AgentDefinition.ParseError.missingName) { try AgentDefinition.parse("---\ncolor: red\n---\nDo it.") }
        #expect(throws: AgentDefinition.ParseError.missingInstructions) { try AgentDefinition.parse("---\nname: X\n---\n") }
    }

    @Test func badScheduleAndColorWarnButStillParse() throws {
        let definition = try AgentDefinition.parse("---\nname: X\ncolor: chartreuse\nschedule: whenever\n---\nGo.")
        #expect(definition.schedule == nil)
        #expect(definition.warnings.count == 2)
        #expect(ColonyColor.allCases.contains(definition.color))
    }

    @Test func markdownRoundTrips() throws {
        for template in AgentTemplates.all {
            let first = try AgentDefinition.parse(template.markdown)
            var second = try AgentDefinition.parse(first.markdown)
            second.warnings = first.warnings
            #expect(first == second, "\(template.id) doesn't round-trip")
            #expect(first.warnings.isEmpty, "\(template.id): \(first.warnings)")
        }
    }

    // MARK: Schedule

    @Test func scheduleParsing() {
        #expect(AgentSchedule("daily 9:05")?.text == "daily 09:05")
        #expect(AgentSchedule("Fridays 16:00")?.kind == .weekly(weekday: 6))
        #expect(AgentSchedule("mon 10:00")?.kind == .weekly(weekday: 2))
        #expect(AgentSchedule("hourly")?.kind == .hourly)
        #expect(AgentSchedule("manual") == nil)
        #expect(AgentSchedule("daily 25:00") == nil)
    }

    @Test func lastSlot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Wednesday 30 Sep 2026, 10:15 UTC.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10, minute: 15)))
        func slot(_ text: String) -> DateComponents? {
            AgentSchedule(text)?.lastSlot(before: now, calendar: calendar).map { calendar.dateComponents([.day, .hour, .minute], from: $0) }
        }
        #expect(slot("daily 09:00") == DateComponents(day: 30, hour: 9, minute: 0))
        #expect(slot("daily 11:00") == DateComponents(day: 29, hour: 11, minute: 0))
        #expect(slot("fridays 16:00") == DateComponents(day: 25, hour: 16, minute: 0))
        #expect(slot("weekdays 11:00") == DateComponents(day: 29, hour: 11, minute: 0))
        #expect(slot("hourly") == DateComponents(day: 30, hour: 10, minute: 0))
    }

    // MARK: Dates

    @Test func agentDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10))) // Wednesday
        func parts(_ text: String) -> (DateComponents, Bool)? {
            AgentDates.parse(text, now: now, calendar: calendar).map { (calendar.dateComponents([.month, .day, .hour, .minute], from: $0.date), $0.hasTime) }
        }
        #expect(parts("tomorrow")?.0 == DateComponents(month: 10, day: 1, hour: 0, minute: 0))
        #expect(parts("tomorrow")?.1 == false)
        #expect(parts("friday 14:30")?.0 == DateComponents(month: 10, day: 2, hour: 14, minute: 30))
        #expect(parts("friday 14:30")?.1 == true)
        #expect(parts("next friday")?.0.day == 9)
        #expect(parts("2026-10-12 3pm")?.0 == DateComponents(month: 10, day: 12, hour: 15, minute: 0))
        #expect(parts("in 3 days")?.0.day == 3)
        #expect(parts("someday") == nil)
    }

    // MARK: Workspace tools

    @Test func workspaceToolsGoThroughWorkspaceActions() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let sales = try #require(actions.createProject(name: "Sales", symbol: "folder", color: .purple, lists: ["Demos"]))
        actions.createTask(title: "Call Northwind", project: sales)
        let agent = try #require(actions.recruit(try AgentDefinition.parse(AgentTemplates.planner.markdown)))
        let workspace = AgentWorkspace(context: context, agentID: agent.uuid)

        #expect(workspace.listTasks(filter: nil, project: nil).contains("Call Northwind"))
        #expect(workspace.listProjects().contains("Sales: 1 open task; lists: Demos"))

        let created = workspace.createTask(title: "Send deck", notes: nil, project: "sales", list: "Demos", due: "tomorrow 10:00", priority: "high")
        #expect(created.hasPrefix("Created"))
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Send deck" })
        #expect(task.project?.uuid == sales.uuid)
        #expect(task.list?.name == "Demos")
        #expect(task.priority == .high)
        #expect(task.dueHasTime)

        #expect(workspace.updateTask(title: "send deck", newTitle: nil, status: "in progress", priority: nil, due: nil, project: nil, flagged: true).hasPrefix("Updated"))
        #expect(task.status == .inProgress)
        #expect(task.isFlagged)

        #expect(workspace.createTask(title: "X", notes: nil, project: "Nope", list: nil, due: nil, priority: nil).contains("No project"))
        #expect(workspace.updateTask(title: "missing", newTitle: nil, status: "done", priority: nil, due: nil, project: nil, flagged: nil).contains("No task"))

        // Every change is shown in the agent's conversation.
        let rows = agent.sortedMessages.filter { $0.role == .action }.map(\.body)
        #expect(rows.count == 2)
        #expect(rows[0].contains("Created task “Send deck” in Sales"))
    }

    @Test func customersChannelsUpdatesAndAsk() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        actions.createContact(name: "Maya Levin", company: "Northwind", stage: .proposal)
        let channel = try #require(actions.createChannel(name: "general", topic: ""))
        actions.send("Ship it Friday", to: channel, as: "Dana")
        let agent = try #require(actions.recruit(try AgentDefinition.parse(AgentTemplates.followUps.markdown)))
        let workspace = AgentWorkspace(context: context, agentID: agent.uuid)

        #expect(workspace.listCustomers(stage: "proposal").contains("Maya Levin (Northwind) · Proposal"))
        #expect(workspace.moveCustomer(name: "maya", stage: "negotiation").contains("Negotiation"))
        #expect(workspace.readChannel(name: "#general", limit: nil).contains("Ship it Friday"))

        #expect(workspace.postMessage(channel: "general", text: "On it") == "Posted in #general.")
        let posted = try #require(channel.sortedMessages.last)
        #expect(posted.authorName == "Ada")
        #expect(!posted.isMine)

        #expect(workspace.postUpdate(title: "Digest", text: "All quiet") == "Posted to Updates.")
        #expect(workspace.listUpdates(limit: 5).contains("Ada · Digest"))

        _ = workspace.askUser(question: "Move Maya to Won?")
        #expect(agent.status == .waiting)
    }

    @Test func recruitAndDeleteAgent() throws {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let first = try #require(actions.recruit(try AgentDefinition.parse(AgentTemplates.planner.markdown)))
        let second = try #require(actions.recruit(try AgentDefinition.parse(AgentTemplates.digest.markdown)))
        #expect(second.sortIndex == first.sortIndex + 1)
        // A schedule starts from now: the slot that already passed isn't "due".
        #expect(first.lastScheduledSlot == first.schedule?.lastSlot(before: .now))

        context.insert(AgentMessage(role: .user, body: "hi", agent: first))
        try context.save()
        actions.delete(first)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Agent>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AgentMessage>()) == 0)
    }

    @Test func starterAgentsSeedOnce() throws {
        let context = makeContext()
        let preferences = CloudPreferences(useICloud: false, defaults: UserDefaults(suiteName: "agent-tests-\(UUID())")!)
        StarterContent.seedAgentsIfNeeded(context: context, preferences: preferences)
        StarterContent.seedAgentsIfNeeded(context: context, preferences: preferences)
        let agents = try context.fetch(FetchDescriptor<Agent>(sortBy: [SortDescriptor(\.sortIndex)]))
        #expect(agents.map(\.name) == ["Neo", "Ada", "Mira", "Juno"])
        #expect(try context.fetchCount(FetchDescriptor<ActivityEvent>()) == 0)
    }
}
