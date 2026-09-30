//
//  AutomationTests.swift
//  ColonyTests
//
//  Triggers, filters, steps, sentences and recipes, without the engine's clock.
//

import Foundation
import SwiftData
import Testing
@testable import Colony

@MainActor
struct AutomationTests {
    private func makeContext() -> ModelContext {
        ModelContext(CloudStore.inMemoryContainer())
    }

    private func automation(_ context: ModelContext, trigger: AutomationTrigger, conditions: [AutomationCondition] = [], steps: [AutomationStep]) -> Automation {
        let automation = WorkspaceActions(context: context).createAutomation(name: "Test")
        automation.trigger = trigger
        automation.conditions = conditions
        automation.steps = steps
        return automation
    }

    // MARK: Storage

    @Test func flowRoundTripsThroughJSON() {
        let context = makeContext()
        let project = UUID()
        let a = automation(context, trigger: AutomationTrigger(kind: .taskStatusChanged, status: .review),
                           conditions: [AutomationCondition(kind: .inProject, projectID: project)],
                           steps: [AutomationStep(kind: .setPriority, priority: .urgent), AutomationStep(kind: .notify, text: "Hi {task}")])
        #expect(a.trigger == AutomationTrigger(kind: .taskStatusChanged, status: .review))
        #expect(a.conditions.first?.projectID == project)
        #expect(a.steps.map(\.kind) == [.setPriority, .notify])
        #expect(a.steps.first?.priority == .urgent)
        #expect(a.isComplete)
    }

    @Test func newAutomationsStartOffWithUniqueNames() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let first = actions.createAutomation()
        let second = actions.createAutomation()
        #expect(first.name == "New automation")
        #expect(second.name == "New automation 2")
        #expect(!first.isEnabled)
        #expect(!first.isComplete)
        #expect(second.sortIndex == first.sortIndex + 1)
    }

    // MARK: Matching

    @Test func triggersMatchTheirEventAndChoice() {
        let any = AutomationTrigger(kind: .taskStatusChanged)
        let review = AutomationTrigger(kind: .taskStatusChanged, status: .review)
        let event = AutomationEvent(kind: .taskStatusChanged, subjectID: UUID(), status: .done)
        #expect(AutomationExecutor.matches(any, event))
        #expect(!AutomationExecutor.matches(review, event))
        #expect(!AutomationExecutor.matches(AutomationTrigger(kind: .taskCreated), event))
        let won = AutomationTrigger(kind: .dealStageChanged, stage: .won)
        #expect(AutomationExecutor.matches(won, AutomationEvent(kind: .dealStageChanged, subjectID: UUID(), stage: .won)))
        #expect(!AutomationExecutor.matches(won, AutomationEvent(kind: .dealStageChanged, subjectID: UUID(), stage: .lost)))
    }

    @Test func workspaceChangesAnnounceEvents() {
        let context = makeContext()
        var events: [AutomationEvent] = []
        AutomationBus.handler = { events.append($0) }
        defer { AutomationBus.handler = nil }
        let actions = WorkspaceActions(context: context)
        let task = actions.createTask(title: "Ship")!
        actions.setStatus(.review, for: task)
        let contact = actions.createContact(name: "Ada")!
        actions.setStage(.won, for: contact)
        let channel = actions.createChannel(name: "general", topic: "")!
        actions.send("hello", to: channel, as: "Me")
        #expect(events.map(\.kind) == [.taskCreated, .taskStatusChanged, .customerAdded, .dealStageChanged, .messagePosted])
        #expect(events[1].status == .review)
        #expect(events[3].stage == .won)
        #expect(events[4].channelID == channel.uuid)
    }

    // MARK: Filters

    @Test func filtersStopRunsThatDontMatch() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let sales = actions.createProject(name: "Sales", symbol: "folder", color: .blue)!
        let inSales = actions.createTask(title: "Call Ada", project: sales)!
        let elsewhere = actions.createTask(title: "Water plants")!
        let a = automation(context, trigger: AutomationTrigger(kind: .taskCreated),
                           conditions: [AutomationCondition(kind: .inProject, projectID: sales.uuid)],
                           steps: [AutomationStep(kind: .flagTask)])
        let executor = AutomationExecutor(context: context)
        #expect(executor.run(a, subject: .task(elsewhere)).kind == .skipped)
        #expect(!elsewhere.isFlagged)
        #expect(executor.run(a, subject: .task(inSales)).kind == .ran)
        #expect(inSales.isFlagged)
    }

    @Test func textFiltersIgnoreCase() {
        let context = makeContext()
        let task = WorkspaceActions(context: context).createTask(title: "URGENT: invoice")!
        #expect(AutomationExecutor.passes(AutomationCondition(kind: .titleContains, text: "urgent"), .task(task)))
        #expect(!AutomationExecutor.passes(AutomationCondition(kind: .titleContains, text: "refund"), .task(task)))
        // Unfinished filters don't block.
        #expect(AutomationExecutor.passes(AutomationCondition(kind: .titleContains, text: "  "), .task(task)))
    }

    // MARK: Steps

    @Test func stepsChangeTheTaskAndFillWords() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let channel = actions.createChannel(name: "general", topic: "")!
        let task = actions.createTask(title: "Draft proposal")!
        var notified: [String] = []
        let a = automation(context, trigger: AutomationTrigger(kind: .taskOverdue), steps: [
            AutomationStep(kind: .setPriority, priority: .urgent),
            AutomationStep(kind: .setStatus, status: .inProgress),
            AutomationStep(kind: .setDue, days: 2),
            AutomationStep(kind: .postMessage, text: "“{task}” in {project} is late", channelID: channel.uuid),
            AutomationStep(kind: .notify, text: "{task} is overdue"),
        ])
        let executor = AutomationExecutor(context: context, effects: AutomationEffects(notify: { _, body in notified.append(body) }))
        let outcome = executor.run(a, subject: .task(task))
        #expect(outcome.kind == .ran)
        #expect(task.priority == .urgent)
        #expect(task.status == .inProgress)
        #expect(task.dueDate == Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: .now)))
        let message = channel.messages?.first
        #expect(message?.body == "“Draft proposal” in My tasks is late")
        #expect(message?.isMine == false)
        #expect(message?.authorName == "Colony")
        #expect(notified == ["Draft proposal is overdue"])
        #expect(outcome.lines.count == 5)
    }

    @Test func dryRunChangesNothing() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let task = actions.createTask(title: "Draft")!
        let before = (try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0
        var notified = 0
        let a = automation(context, trigger: AutomationTrigger(kind: .taskCreated), steps: [
            AutomationStep(kind: .setPriority, priority: .urgent),
            AutomationStep(kind: .createTask, text: "Review {task}"),
            AutomationStep(kind: .notify, text: "hi"),
        ])
        let outcome = AutomationExecutor(context: context, effects: AutomationEffects(notify: { _, _ in notified += 1 }), dryRun: true).run(a, subject: .task(task))
        #expect(outcome.kind == .ran)
        #expect(outcome.lines.allSatisfy { $0.contains("Would") })
        #expect(outcome.lines[1].contains("Review Draft"))
        #expect(task.priority == .medium)
        #expect(((try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0) == before)
        #expect(notified == 0)
    }

    @Test func taskStepsFailWithoutATask() {
        let context = makeContext()
        let a = automation(context, trigger: AutomationTrigger(kind: .schedule), steps: [AutomationStep(kind: .flagTask), AutomationStep(kind: .postUpdate, text: "Weekly check")])
        let outcome = AutomationExecutor(context: context).run(a, subject: .none)
        #expect(outcome.kind == .failed)
        #expect(outcome.lines.first?.hasPrefix("✕") == true)
        // Later steps still run.
        let updates = (try? context.fetch(FetchDescriptor<ActivityEvent>())) ?? []
        #expect(updates.contains { $0.title == "Weekly check" })
    }

    @Test func clearCompletedRemovesOnlyOldDoneTasks() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let old = actions.createTask(title: "Old")!
        actions.setStatus(.done, for: old)
        old.completedAt = Calendar.current.date(byAdding: .day, value: -40, to: .now)
        let recent = actions.createTask(title: "Recent")!
        actions.setStatus(.done, for: recent)
        let open = actions.createTask(title: "Open")!
        let a = automation(context, trigger: AutomationTrigger(kind: .schedule), steps: [AutomationStep(kind: .clearCompleted, days: 30)])
        _ = AutomationExecutor(context: context).run(a, subject: .none)
        try? context.save()
        let titles = Set(((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).map(\.title))
        #expect(titles == ["Recent", "Open"])
        _ = open
    }

    @Test func stepsAnnounceTheirChangesAsAChain() {
        let context = makeContext()
        var events: [AutomationEvent] = []
        AutomationBus.handler = { events.append($0) }
        defer { AutomationBus.handler = nil }
        let contact = WorkspaceActions(context: context).createContact(name: "Ada")!
        events.removeAll()
        let a = automation(context, trigger: AutomationTrigger(kind: .dealStageChanged, stage: .won), steps: [AutomationStep(kind: .createTask, text: "Onboard {customer}")])
        _ = AutomationExecutor(context: context).run(a, subject: .customer(contact))
        #expect(events.count == 1)
        #expect(events.first?.kind == .taskCreated)
        #expect(events.first?.depth == 1)
        #expect(events.first?.sourceID == a.uuid)
        #expect(AutomationBus.depth == 0)
    }

    @Test func askAgentUsesTheAgentEffect() {
        let context = makeContext()
        let agent = Agent(name: "Neo")
        context.insert(agent)
        var asked: [(UUID, String)] = []
        let a = automation(context, trigger: AutomationTrigger(kind: .schedule), steps: [AutomationStep(kind: .askAgent, text: "Plan my day", agentID: agent.uuid)])
        let outcome = AutomationExecutor(context: context, effects: AutomationEffects(askAgent: { id, text in asked.append((id, text)); return true })).run(a, subject: .none)
        #expect(outcome.kind == .ran)
        #expect(asked.first?.0 == agent.uuid)
        #expect(asked.first?.1 == "Plan my day")
    }

    // MARK: Time

    @Test func overdueMomentFollowsDueKind() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let timed = actions.createTask(title: "Timed")!
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        actions.setDue(at, hasTime: true, for: timed)
        #expect(AutomationExecutor.overdueMoment(timed) == at)
        let dateOnly = actions.createTask(title: "Day")!
        actions.setDue(at, hasTime: false, for: dateOnly)
        #expect(AutomationExecutor.overdueMoment(dateOnly) == Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: at)))
    }

    @Test func turningOnStartsFromNow() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let a = actions.createAutomation(from: AutomationRecipes.recipe("weekly-cleanup"))
        a.lastCheckedAt = .distantPast
        a.lastScheduledSlot = .distantPast
        actions.setEnabled(true, for: a)
        #expect(a.isEnabled)
        #expect(a.lastCheckedAt! > .now.addingTimeInterval(-5))
        #expect(a.lastScheduledSlot == a.trigger?.schedule?.lastSlot(before: .now))
    }

    // MARK: Words

    @Test func sentenceReadsLikeEnglish() {
        let context = makeContext()
        let project = UUID()
        let a = automation(context, trigger: AutomationTrigger(kind: .taskOverdue),
                           conditions: [AutomationCondition(kind: .inProject, projectID: project)],
                           steps: [AutomationStep(kind: .setPriority, priority: .urgent), AutomationStep(kind: .notify, text: "Late")])
        let names = AutomationNames(projects: [project: "Sales"])
        #expect(a.sentence(names) == "When a task becomes overdue, if it's in Sales, set its priority to Urgent and notify me: “Late”.")
        a.steps = [AutomationStep(kind: .notify, text: "{task} is late")]
        #expect(a.sentence(names) == "When a task becomes overdue, if it's in Sales, notify me: “[Task name] is late”.")
        a.steps = []
        #expect(a.sentence(names) == "When a task becomes overdue, if it's in Sales, …")
        a.trigger = nil
        #expect(a.sentence(names) == "Choose what starts this automation.")
    }

    @Test func stepsOnlyFitTriggersThatGiveThemSomething() {
        #expect(StepKind.setPriority.fits(.task))
        #expect(!StepKind.setPriority.fits(.customer))
        #expect(!StepKind.setStage.fits(.none))
        #expect(StepKind.notify.fits(.none))
        #expect(StepKind.createTask.fits(.message))
    }

    @Test func everyRecipeIsCompleteAndUsable() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        _ = actions.createChannel(name: "general", topic: "")
        let neo = Agent(name: "Neo")
        context.insert(neo)
        _ = actions.createProject(name: "Sales", symbol: "folder", color: .purple)
        for recipe in AutomationRecipes.all {
            let a = actions.createAutomation(from: recipe)
            #expect(a.isComplete, "\(recipe.id)")
            #expect(a.steps.allSatisfy { $0.isComplete }, "\(recipe.id)")
            #expect(a.steps.allSatisfy { $0.kind.fits(recipe.trigger.kind.subject) }, "\(recipe.id)")
            #expect(!a.isEnabled)
            #expect(a.name == recipe.name)
        }
        #expect(AutomationRecipes.starterIDs.allSatisfy { AutomationRecipes.recipe($0) != nil })
    }

    @Test func duplicateCopiesTheFlowWithNewIDs() {
        let context = makeContext()
        let actions = WorkspaceActions(context: context)
        let a = actions.createAutomation(from: AutomationRecipes.recipe("overdue-nudge"))
        let copy = actions.duplicate(a)
        #expect(copy.name == "Overdue nudge copy")
        #expect(copy.steps.map(\.kind) == a.steps.map(\.kind))
        #expect(Set(copy.steps.map(\.id)).isDisjoint(with: Set(a.steps.map(\.id))))
        #expect(copy.trigger == a.trigger)
    }
}
