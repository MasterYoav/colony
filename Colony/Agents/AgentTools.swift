//
//  AgentTools.swift
//  Colony
//
//  Foundation Models tools: what the on-device model can call. Each one forwards to
//  AgentWorkspace on the main actor, where the SwiftData context lives.
//

import Foundation
import FoundationModels
import SwiftData

/// Hops to the main actor to run a workspace call for one agent.
nonisolated struct AgentBridge: Sendable {
    let container: ModelContainer
    let agentID: UUID

    func callAsFunction(_ body: @escaping @MainActor @Sendable (AgentWorkspace) -> String) async -> String {
        let (container, agentID) = (container, agentID)
        return await MainActor.run {
            let context = container.mainContext
            let workspace = context.agent(agentID)?.workspaceID ?? WorkspaceInfo.originalID
            let result = WorkspaceScope.run(in: workspace) { body(AgentWorkspace(context: context, agentID: agentID)) }
            try? container.mainContext.save()
            return result
        }
    }
}

enum AgentToolbox {
    /// The Foundation Models tools for the agent's allowed tool list.
    static func tools(for allowed: [AgentTool], bridge: AgentBridge) -> [any Tool] {
        allowed.map { tool -> any Tool in
            switch tool {
            case .listTasks: ListTasksTool(bridge: bridge)
            case .createTask: CreateTaskTool(bridge: bridge)
            case .updateTask: UpdateTaskTool(bridge: bridge)
            case .listProjects: ListProjectsTool(bridge: bridge)
            case .listCustomers: ListCustomersTool(bridge: bridge)
            case .moveCustomer: MoveCustomerTool(bridge: bridge)
            case .readChannel: ReadChannelTool(bridge: bridge)
            case .postMessage: PostMessageTool(bridge: bridge)
            case .listUpdates: ListUpdatesTool(bridge: bridge)
            case .postUpdate: PostUpdateTool(bridge: bridge)
            case .askUser: AskUserTool(bridge: bridge)
            }
        }
    }
}

nonisolated struct ListTasksTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.listTasks.rawValue
    let description = "Lists tasks in the user's workspace with their project, due date, priority and status."

    @Generable
    struct Arguments {
        @Guide(description: "Which tasks: open, today, overdue, upcoming, flagged, urgent, no_project, done (finished this week) or all")
        var filter: String?
        @Guide(description: "Only tasks in this project (its name)")
        var project: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let (filter, project) = (arguments.filter, arguments.project)
        return await bridge { $0.listTasks(filter: filter, project: project) }
    }
}

nonisolated struct CreateTaskTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.createTask.rawValue
    let description = "Creates a task."

    @Generable
    struct Arguments {
        @Guide(description: "Short task title")
        var title: String
        @Guide(description: "Optional details")
        var notes: String?
        @Guide(description: "Project name, if any")
        var project: String?
        @Guide(description: "List inside the project, if any")
        var list: String?
        @Guide(description: "Due date: today, tomorrow, friday, next monday, in 3 days or YYYY-MM-DD, optionally with a time like 14:00")
        var due: String?
        @Guide(description: "low, medium, high or urgent")
        var priority: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        let (title, notes, project, list, due, priority) = (a.title, a.notes, a.project, a.list, a.due, a.priority)
        return await bridge { $0.createTask(title: title, notes: notes, project: project, list: list, due: due, priority: priority) }
    }
}

nonisolated struct UpdateTaskTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.updateTask.rawValue
    let description = "Changes an existing task, found by its title. Only set the fields to change."

    @Generable
    struct Arguments {
        @Guide(description: "The task's current title, exactly as listed")
        var title: String
        @Guide(description: "New title")
        var newTitle: String?
        @Guide(description: "todo, in_progress, review or done")
        var status: String?
        @Guide(description: "low, medium, high or urgent")
        var priority: String?
        @Guide(description: "New due date (today, tomorrow, friday, YYYY-MM-DD, optional time) or none to clear it")
        var due: String?
        @Guide(description: "Move to this project, or none")
        var project: String?
        @Guide(description: "Flag or unflag")
        var flagged: Bool?
    }

    func call(arguments a: Arguments) async throws -> String {
        let (title, newTitle, status, priority, due, project, flagged) = (a.title, a.newTitle, a.status, a.priority, a.due, a.project, a.flagged)
        return await bridge { $0.updateTask(title: title, newTitle: newTitle, status: status, priority: priority, due: due, project: project, flagged: flagged) }
    }
}

nonisolated struct ListProjectsTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.listProjects.rawValue
    let description = "Lists the projects, their lists and how many open tasks each has."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await bridge { $0.listProjects() }
    }
}

nonisolated struct ListCustomersTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.listCustomers.rawValue
    let description = "Lists CRM customers with company, deal stage, deal value and email."

    @Generable
    struct Arguments {
        @Guide(description: "Only this stage: lead, qualified, proposal, negotiation, won or lost")
        var stage: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let stage = arguments.stage
        return await bridge { $0.listCustomers(stage: stage) }
    }
}

nonisolated struct MoveCustomerTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.moveCustomer.rawValue
    let description = "Moves a customer to another deal stage."

    @Generable
    struct Arguments {
        @Guide(description: "Customer name")
        var name: String
        @Guide(description: "lead, qualified, proposal, negotiation, won or lost")
        var stage: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (name, stage) = (arguments.name, arguments.stage)
        return await bridge { $0.moveCustomer(name: name, stage: stage) }
    }
}

nonisolated struct ReadChannelTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.readChannel.rawValue
    let description = "Without a name, lists the channels. With a name, returns that channel's latest messages."

    @Generable
    struct Arguments {
        @Guide(description: "Channel name, without #")
        var name: String?
        @Guide(description: "How many recent messages, up to 40")
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let (name, limit) = (arguments.name, arguments.limit)
        return await bridge { $0.readChannel(name: name, limit: limit) }
    }
}

nonisolated struct PostMessageTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.postMessage.rawValue
    let description = "Posts a message in a channel, signed with your name."

    @Generable
    struct Arguments {
        @Guide(description: "Channel name, without #")
        var channel: String
        @Guide(description: "The message")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (channel, text) = (arguments.channel, arguments.text)
        return await bridge { $0.postMessage(channel: channel, text: text) }
    }
}

nonisolated struct ListUpdatesTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.listUpdates.rawValue
    let description = "Returns the latest entries from Updates, the workspace activity feed."

    @Generable
    struct Arguments {
        @Guide(description: "How many, up to 40")
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let limit = arguments.limit
        return await bridge { $0.listUpdates(limit: limit) }
    }
}

nonisolated struct PostUpdateTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.postUpdate.rawValue
    let description = "Posts a note to Updates, the activity feed the user reads."

    @Generable
    struct Arguments {
        @Guide(description: "Short title")
        var title: String
        @Guide(description: "The note, a few short lines")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (title, text) = (arguments.title, arguments.text)
        return await bridge { $0.postUpdate(title: title, text: text) }
    }
}

nonisolated struct AskUserTool: Tool {
    let bridge: AgentBridge
    let name = AgentTool.askUser.rawValue
    let description = "Asks the user a question when you need a decision or confirmation. Then stop and wait for the answer."

    @Generable
    struct Arguments {
        @Guide(description: "One clear question")
        var question: String
    }

    func call(arguments: Arguments) async throws -> String {
        let question = arguments.question
        return await bridge { $0.askUser(question: question) }
    }
}
