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
        let existing = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        guard existing == 0 else {
            preferences.didSeedStarterContent = true
            return
        }
        seed(into: context)
        preferences.didSeedStarterContent = true
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
            context.insert(Message(body: "Try ⌘K to jump anywhere, or ⌘N to capture a task.", authorName: "Colony", isMine: false, channel: general, createdAt: .now.addingTimeInterval(-1800)))
            general.lastReadAt = .distantPast
        }
        actions.createChannel(name: "product", topic: "Roadmap and design reviews")

        actions.createContact(name: "Maya Levin", company: "Northwind", jobTitle: "Head of Ops", email: "maya@northwind.example", stage: .proposal)
        actions.createContact(name: "Daniel Cohen", company: "Blue Harbor", jobTitle: "CTO", stage: .qualified)
        actions.createContact(name: "Noa Shalev", company: "Atlas Studio", jobTitle: "Founder", stage: .won)
        actions.createContact(name: "Eitan Bar", company: "Fjord Labs", stage: .lead)
    }
}
