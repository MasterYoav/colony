//
//  StarterContent.swift
//  Colony
//
//  Seeds a small starter workspace the very first time Colony runs for an iCloud
//  account. The flag lives in iCloud key-value storage, so a second device signed
//  in to the same account won't seed duplicates.
//

import Foundation
import SwiftData

@MainActor
enum StarterContent {
    static func seedIfNeeded(context: ModelContext, preferences: CloudPreferences) {
        guard !preferences.didSeedStarterContent else { return }
        let existing = context.inWorkspace(Project.self, WorkspaceInfo.originalID).count
        guard existing == 0 else {
            preferences.didSeedStarterContent = true
            return
        }
        WorkspaceScope.run(in: WorkspaceInfo.originalID) { seed(into: context) }
        preferences.didSeedStarterContent = true
    }

    /// Recruits the starter crew from the built-in AGENT.md templates, once per account.
    /// Skips if agents already exist (another device synced them first).
    static func seedAgentsIfNeeded(context: ModelContext, preferences: CloudPreferences) {
        guard !preferences.didSeedStarterAgents else { return }
        preferences.didSeedStarterAgents = true
        guard context.inWorkspace(Agent.self, WorkspaceInfo.originalID).isEmpty else { return }
        WorkspaceScope.run(in: WorkspaceInfo.originalID) { seedAgents(into: context) }
    }

    /// Adds the starter automations, all switched off, once per account.
    static func seedAutomationsIfNeeded(context: ModelContext, preferences: CloudPreferences) {
        guard !preferences.didSeedStarterAutomations else { return }
        preferences.didSeedStarterAutomations = true
        guard context.inWorkspace(Automation.self, WorkspaceInfo.originalID).isEmpty else { return }
        WorkspaceScope.run(in: WorkspaceInfo.originalID) { seedAutomations(into: context) }
    }

    static func seedAutomations(into context: ModelContext) {
        let actions = WorkspaceActions(context: context)
        for id in AutomationRecipes.starterIDs {
            guard let recipe = AutomationRecipes.recipe(id) else { continue }
            actions.createAutomation(from: recipe)
        }
        try? context.save()
    }

    static func seedAgents(into context: ModelContext) {
        let actions = WorkspaceActions(context: context)
        for template in AgentTemplates.starters {
            guard let definition = try? AgentDefinition.parse(template.markdown) else { continue }
            let agent = actions.recruit(definition)
            if let agent {
                context.insert(AgentMessage(role: .agent, body: "Hi, I'm \(agent.name). \(definition.summary) Ask me anything, or pick a suggestion below.", agent: agent))
                agent.lastReadAt = .now.addingTimeInterval(1)
            }
        }
        // Recruiting logs to Updates; the starter crew shouldn't flood it.
        for event in (try? context.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.title == "Agent recruited" }))) ?? [] {
            context.delete(event)
        }
        try? context.save()
    }

    static func seed(into context: ModelContext) {
        let actions = WorkspaceActions(context: context)
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!.addingTimeInterval(17 * 3600) }

        let launch = actions.createProject(name: "Launch", symbol: "calendar", color: .blue, summary: "Ship Colony 1.0 to the App Store.", lists: ["Design", "Build", "QA"])
        let sales = actions.createProject(name: "Sales", symbol: "doc.text.fill", color: .purple, summary: "Pipeline, demos and follow-ups.", lists: ["Outreach", "Demos"])
        let ops = actions.createProject(name: "Operations", symbol: "square.grid.2x2.fill", color: .green, summary: "Keep the lights on.", lists: [])

        if let launch {
            let lists = launch.sortedLists
            actions.createTask(title: "Finalize sidebar visual spec", priority: .high, status: .inProgress, dueDate: day(0), project: launch, list: lists.first)
            actions.createTask(title: "Wire up CloudKit schema", priority: .urgent, status: .review, dueDate: day(1), project: launch, list: lists.dropFirst().first)
            actions.createTask(title: "Test sync across iPhone and Mac", priority: .medium, dueDate: day(3), project: launch, list: lists.last)
            actions.createTask(title: "Write App Store description", priority: .low, dueDate: day(6), project: launch)
        }
        if let sales {
            actions.createTask(title: "Follow up with Northwind", priority: .high, dueDate: day(-1), project: sales, list: sales.sortedLists.first)
            actions.createTask(title: "Prepare pilot demo", priority: .medium, status: .inProgress, dueDate: day(2), project: sales, list: sales.sortedLists.last)
        }
        if let ops {
            let done = actions.createTask(title: "Renew developer account", priority: .medium, project: ops)
            done?.status = .done
        }
        actions.createTask(title: "Review this week's updates", priority: .low, dueDate: day(0))

        if let general = actions.createChannel(name: "general", topic: "Company-wide announcements") {
            context.insert(Message(body: "Welcome to Colony. Everything here is stored in your iCloud account.", authorName: "Colony", isMine: false, channel: general, createdAt: .now.addingTimeInterval(-3600)))
            context.insert(Message(body: "Use Search to jump anywhere, and + to capture a task. On a Mac, ⌘K and ⌘N do the same.", authorName: "Colony", isMine: false, channel: general, createdAt: .now.addingTimeInterval(-1800)))
            general.lastReadAt = .distantPast
        }
        actions.createChannel(name: "product", topic: "Roadmap and design reviews")

        actions.createContact(name: "Maya Levin", company: "Northwind", jobTitle: "Head of Ops", email: "maya@northwind.example", stage: .proposal)
        actions.createContact(name: "Daniel Cohen", company: "Blue Harbor", jobTitle: "CTO", stage: .qualified)
        actions.createContact(name: "Noa Shalev", company: "Atlas Studio", jobTitle: "Founder", stage: .won)
        actions.createContact(name: "Eitan Bar", company: "Fjord Labs", stage: .lead)
    }
}
