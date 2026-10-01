//
//  AutomationRecipes.swift
//  Colony
//
//  Ready-made automations: the easiest way in. Each recipe is a complete flow; picking
//  one fills in what it can from the workspace (a channel, an agent) and opens it for
//  a look before it's switched on.
//

import Foundation
import SwiftData

struct AutomationRecipe: Identifiable {
    let id: String
    let name: String
    let pitch: String
    let color: ColonyColor
    let trigger: AutomationTrigger
    var conditions: [AutomationCondition] = []
    /// Built with the workspace, so steps can point at a real channel or agent.
    let steps: (_ context: ModelContext) -> [AutomationStep]
}

@MainActor
enum AutomationRecipes {
    static let all: [AutomationRecipe] = [
        AutomationRecipe(
            id: "overdue-nudge", name: "Overdue nudge",
            pitch: "When a task is overdue, make it urgent and tell me.",
            color: .orange, trigger: AutomationTrigger(kind: .taskOverdue),
            steps: { _ in [
                AutomationStep(kind: .setPriority, priority: .urgent),
                AutomationStep(kind: .notify, text: "{task} is overdue"),
            ] }
        ),
        AutomationRecipe(
            id: "deal-won", name: "Deal won",
            pitch: "When a customer is won, start their onboarding.",
            color: .green, trigger: AutomationTrigger(kind: .dealStageChanged, stage: .won),
            steps: { context in [
                AutomationStep(kind: .createTask, text: "Kick off onboarding with {customer}", projectID: project(named: "Sales", context), days: 1),
                AutomationStep(kind: .postUpdate, text: "{customer} is won 🎉"),
            ] }
        ),
        AutomationRecipe(
            id: "ready-for-review", name: "Ready for review",
            pitch: "When a task moves to In review, post it in a channel.",
            color: .indigo, trigger: AutomationTrigger(kind: .taskStatusChanged, status: .review),
            steps: { context in [
                AutomationStep(kind: .postMessage, text: "{task} ({project}) is ready for review", channelID: channel(context)),
            ] }
        ),
        AutomationRecipe(
            id: "weekly-cleanup", name: "Weekly cleanup",
            pitch: "Every Friday, clear tasks finished over a month ago.",
            color: .gray, trigger: AutomationTrigger(kind: .schedule, scheduleText: "fridays 17:00"),
            steps: { _ in [AutomationStep(kind: .clearCompleted, days: 30)] }
        ),
        AutomationRecipe(
            id: "welcome-customer", name: "Say hello",
            pitch: "When a customer is added, remind me to reach out.",
            color: .purple, trigger: AutomationTrigger(kind: .customerAdded),
            steps: { _ in [AutomationStep(kind: .createTask, text: "Say hello to {customer}", days: 2)] }
        ),
        AutomationRecipe(
            id: "urgent-flag", name: "Flag urgent work",
            pitch: "When an urgent task is created, flag it and tell me.",
            color: .red, trigger: AutomationTrigger(kind: .taskCreated),
            conditions: [AutomationCondition(kind: .priorityIs, priority: .urgent)],
            steps: { _ in [
                AutomationStep(kind: .flagTask),
                AutomationStep(kind: .notify, text: "New urgent task: {task}"),
            ] }
        ),
        AutomationRecipe(
            id: "morning-plan", name: "Morning plan",
            pitch: "Every weekday at 9, ask an agent to plan my day.",
            color: .blue, trigger: AutomationTrigger(kind: .schedule, scheduleText: "weekdays 09:00"),
            steps: { context in [AutomationStep(kind: .askAgent, text: "Plan my day", agentID: agent(context))] }
        ),
        AutomationRecipe(
            id: "keyword-alert", name: "Keyword alert",
            pitch: "When a message says “urgent”, notify me.",
            color: .teal, trigger: AutomationTrigger(kind: .messagePosted),
            conditions: [AutomationCondition(kind: .messageContains, text: "urgent")],
            steps: { _ in [AutomationStep(kind: .notify, text: "{author} in #{channel}: {message}")] }
        ),
    ]

    static func recipe(_ id: String) -> AutomationRecipe? { all.first { $0.id == id } }

    /// The seeded starters, all switched off until you turn them on.
    static let starterIDs = ["overdue-nudge", "deal-won", "ready-for-review", "weekly-cleanup"]

    private static func project(named name: String, _ context: ModelContext) -> UUID? {
        context.inWorkspace(Project.self).first { $0.name == name && $0.archivedAt == nil }?.uuid
    }

    /// #general if there is one, otherwise the first channel.
    private static func channel(_ context: ModelContext) -> UUID? {
        let channels = context.inWorkspace(Channel.self, sortBy: [SortDescriptor(\.sortIndex)])
        return (channels.first { $0.name == "general" } ?? channels.first)?.uuid
    }

    /// Neo, the planner, if recruited; otherwise the first agent.
    private static func agent(_ context: ModelContext) -> UUID? {
        let agents = context.inWorkspace(Agent.self, sortBy: [SortDescriptor(\.sortIndex)])
        return (agents.first { $0.name == "Neo" } ?? agents.first)?.uuid
    }
}
