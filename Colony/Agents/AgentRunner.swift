//
//  AgentRunner.swift
//  Colony
//
//  Runs agents on the device's own language model (Apple Intelligence, Foundation
//  Models). Nothing leaves the device: prompts, workspace data and replies stay local;
//  the conversation itself syncs through the user's iCloud like the rest of Colony.
//
//  - Chat: a message from the user starts a turn; the reply streams in.
//  - Schedule: agents with `schedule:` run by themselves while Colony is open (on Mac
//    that includes menu-bar mode). Each slot runs once; the slot is saved in the agent
//    so another device doesn't repeat it.
//  - When an agent asks something or finishes a scheduled run while you're elsewhere,
//    you get a notification (if notifications are allowed).
//

import Foundation
import FoundationModels
import Observation
import OSLog
import SwiftData
import UserNotifications

@MainActor
@Observable
final class AgentRunner {
    enum Availability: Equatable {
        case available
        case notEligible
        case turnedOff
        case downloading
        case unknown

        var title: String {
            switch self {
            case .available: "Apple Intelligence is ready"
            case .notEligible: "This device doesn't support Apple Intelligence"
            case .turnedOff: "Apple Intelligence is turned off"
            case .downloading: "Apple Intelligence is getting ready"
            case .unknown: "Apple Intelligence isn't available"
            }
        }

        var message: String {
            switch self {
            case .available: "Agents run on this device. Nothing you or they write is sent anywhere."
            case .notEligible: "Agents need a device with Apple Intelligence. You can still recruit and edit them here, and they'll run on your devices that support it."
            case .turnedOff: "Turn on Apple Intelligence in System Settings to let agents run on this device."
            case .downloading: "The on-device model is still downloading. Agents will be able to run once it's done."
            case .unknown: "The on-device model can't be used right now. Try again later."
            }
        }
    }

    private(set) var availability: Availability = .unknown
    /// Agents with a turn in progress.
    private(set) var running: Set<UUID> = []

    private var container: ModelContainer?
    private weak var app: AppModel?
    private var sessions: [UUID: (session: LanguageModelSession, signature: String)] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var clock: Task<Void, Never>?
    private let log = Logger(subsystem: "yoavperetz.Colony", category: "agents")

    var isAvailable: Bool { availability == .available }

    func attach(_ container: ModelContainer, app: AppModel) {
        guard self.container == nil else { return }
        self.container = container
        self.app = app
        refreshAvailability()
        guard !CloudStore.isRunningForTests else { return }
        resetStaleStatus()
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                self?.refreshAvailability()
                self?.runDueSchedules()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refreshAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: availability = .notEligible
            case .appleIntelligenceNotEnabled: availability = .turnedOff
            case .modelNotReady: availability = .downloading
            @unknown default: availability = .unknown
            }
        }
    }

    func isRunning(_ agent: Agent) -> Bool { running.contains(agent.uuid) }

    // MARK: Chat

    /// Adds the user's message and starts the agent's reply.
    func send(_ text: String, to agent: Agent) {
        let text = ColonyText.trimmed(text)
        guard !text.isEmpty, let context = container?.mainContext else { return }
        context.insert(AgentMessage(role: .user, body: text, agent: agent, sequence: nextSequence(agent)))
        agent.lastReadAt = .now
        try? context.save()
        start(agent, prompt: text, trigger: .chat)
    }

    /// Runs the agent's scheduled job now, as if its time had come.
    func runNow(_ agent: Agent) {
        start(agent, prompt: scheduledPrompt(for: agent, at: .now), trigger: .manual)
    }

    func stop(_ agent: Agent) {
        tasks[agent.uuid]?.cancel()
    }

    /// Clears the conversation and the model's memory of it.
    func clearHistory(_ agent: Agent) {
        stop(agent)
        guard let context = container?.mainContext else { return }
        for message in agent.messages ?? [] { context.delete(message) }
        sessions[agent.uuid] = nil
        agent.status = .idle
        try? context.save()
    }

    func forget(_ agent: Agent) {
        stop(agent)
        sessions[agent.uuid] = nil
    }

    // MARK: Runs

    private enum Trigger { case chat, schedule, manual }

    private func start(_ agent: Agent, prompt: String, trigger: Trigger) {
        guard let container, !running.contains(agent.uuid) else { return }
        guard isAvailable else {
            note(availability.message, to: agent)
            return
        }
        guard agent.isEnabled || trigger == .chat else { return }

        let id = agent.uuid
        running.insert(id)
        agent.status = .thinking
        agent.lastRunAt = .now
        try? container.mainContext.save()

        tasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.turn(agentID: id, prompt: prompt, trigger: trigger, container: container)
            self.running.remove(id)
            self.tasks[id] = nil
        }
    }

    private func turn(agentID: UUID, prompt: String, trigger: Trigger, container: ModelContainer) async {
        let context = container.mainContext
        guard let agent = fetch(agentID) else { return }
        let session = session(for: agent, container: container)
        var reply: AgentMessage?

        do {
            let stream = session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.4))
            for try await snapshot in stream {
                try Task.checkCancellation()
                let text = snapshot.content
                guard !ColonyText.trimmed(text).isEmpty else { continue }
                if reply == nil, let agent = fetch(agentID) {
                    let message = AgentMessage(role: .agent, body: "", agent: agent, sequence: nextSequence(agent))
                    context.insert(message)
                    reply = message
                }
                reply?.body = text
            }
            guard let agent = fetch(agentID) else { return }
            if agent.status != .waiting { agent.status = .done }
            reply?.body = ColonyText.trimmed(reply?.body ?? "")
            // After ask_user the model often just repeats the question; it's already shown.
            if agent.status == .waiting, let body = reply?.body, Self.sameText(body, lastQuestion(agent)) {
                reply.map(context.delete)
                reply = nil
            }
            try? context.save()
            if trigger != .chat || agent.status == .waiting {
                notify(agent, text: agent.status == .waiting ? lastQuestion(agent) : reply?.body ?? "Finished.")
            }
            log.info("agent \(agent.name, privacy: .public) finished (\(String(describing: trigger), privacy: .public))")
        } catch is CancellationError {
            finish(agentID, status: .idle, notice: "Stopped.")
        } catch let error as LanguageModelSession.GenerationError {
            // The session can't continue after these; start fresh next time.
            sessions[agentID] = nil
            finish(agentID, status: .failed, notice: Self.describe(error))
            log.error("agent run failed: \(String(describing: error), privacy: .public)")
        } catch {
            sessions[agentID] = nil
            finish(agentID, status: .failed, notice: error.localizedDescription)
            log.error("agent run failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func finish(_ agentID: UUID, status: AgentStatus, notice: String) {
        guard let agent = fetch(agentID) else { return }
        agent.status = status
        note(notice, to: agent)
    }

    private func note(_ text: String, to agent: Agent) {
        guard let context = container?.mainContext else { return }
        context.insert(AgentMessage(role: .notice, body: text, agent: agent, sequence: nextSequence(agent)))
        try? context.save()
    }

    /// One session per agent, kept while Colony runs so the model remembers the chat.
    /// Rebuilt when the agent's definition changes; seeded with recent history.
    private func session(for agent: Agent, container: ModelContainer) -> LanguageModelSession {
        let signature = [agent.name, agent.instructions, agent.toolsRaw].joined(separator: "\u{1F}")
        if let cached = sessions[agent.uuid], cached.signature == signature {
            return cached.session
        }
        let bridge = AgentBridge(container: container, agentID: agent.uuid)
        let tools = AgentToolbox.tools(for: agent.tools, bridge: bridge)
        let session = LanguageModelSession(tools: tools, instructions: instructions(for: agent))
        sessions[agent.uuid] = (session, signature)
        return session
    }

    func instructions(for agent: Agent) -> String {
        let now = Date.now
        let today = now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        let time = now.formatted(date: .omitted, time: .shortened)
        let toolNames = agent.tools.map(\.rawValue).joined(separator: ", ")
        var text = """
        You are \(agent.name), an assistant inside Colony, the user's workspace app (projects, tasks, channels, customers).
        Today is \(today), \(time). The user is \(app?.preferences.displayName ?? "the user").
        \(toolNames.isEmpty ? "You have no tools; answer from the conversation only." : "Use your tools (\(toolNames)) to look things up before answering; never invent tasks, customers or messages.")
        Keep replies short and plain: a few lines or a short list. Don't use Markdown headings.

        """
        text += agent.instructions
        // Earlier conversation (from this or another device) so a new session has context.
        let history = agent.sortedMessages.filter { $0.role == .user || $0.role == .agent }.suffix(8)
        if !history.isEmpty {
            text += "\n\nEarlier conversation, most recent last:\n"
            text += history.map { "\($0.role == .user ? "User" : agent.name): \($0.body.prefix(300))" }.joined(separator: "\n")
        }
        return text
    }

    // MARK: Schedule

    private func scheduledPrompt(for agent: Agent, at date: Date) -> String {
        "It's \(date.formatted(date: .abbreviated, time: .shortened)). This is your \(agent.schedule.map { "scheduled run (\($0.label))" } ?? "run") — do your job now as your instructions describe, then reply with a short summary of what you did."
    }

    /// Runs each enabled, scheduled agent whose latest slot hasn't run yet. Slots older
    /// than two hours are skipped (the Mac was asleep), not run late.
    func runDueSchedules(now: Date = .now) {
        guard isAvailable, let context = container?.mainContext else { return }
        let agents = ((try? context.fetch(FetchDescriptor<Agent>())) ?? []).filter { $0.isEnabled && !$0.isDeleted }
        for agent in agents {
            guard let schedule = agent.schedule, let slot = schedule.lastSlot(before: now) else { continue }
            guard slot > (agent.lastScheduledSlot ?? agent.createdAt) else { continue }
            agent.lastScheduledSlot = slot
            try? context.save()
            guard now.timeIntervalSince(slot) < 2 * 3600 else { continue }
            start(agent, prompt: scheduledPrompt(for: agent, at: slot), trigger: .schedule)
        }
    }

    // MARK: Helpers

    private func resetStaleStatus() {
        guard let context = container?.mainContext else { return }
        for agent in (try? context.fetch(FetchDescriptor<Agent>())) ?? [] where agent.status == .thinking {
            agent.status = .idle
        }
    }

    private func fetch(_ id: UUID) -> Agent? {
        try? container?.mainContext.fetch(FetchDescriptor<Agent>(predicate: #Predicate { $0.uuid == id })).first
    }

    private func nextSequence(_ agent: Agent) -> Int {
        (agent.messages ?? []).map(\.sequence).max().map { $0 + 1 } ?? 0
    }

    private func lastQuestion(_ agent: Agent) -> String {
        agent.sortedMessages.last { $0.role == .action && $0.symbol == "hand.raised.fill" }?.body ?? "Needs your input."
    }

    /// A local notification when the agent needs you or finished on its own, unless
    /// you're looking at that agent right now.
    private func notify(_ agent: Agent, text: String) {
        guard let app, app.notifications.canNotify else { return }
        if app.destination == .agent(agent.uuid), app.isActive { return }
        let content = UNMutableNotificationContent()
        content.title = agent.status == .waiting ? "\(agent.name) needs you" : agent.name
        content.body = String(text.prefix(240))
        content.sound = .default
        content.threadIdentifier = "colony.agent.\(agent.uuid.uuidString)"
        content.userInfo = ["agentID": agent.uuid.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "colony.agent.\(UUID().uuidString)", content: content, trigger: nil))
    }

    static func sameText(_ a: String, _ b: String) -> Bool {
        let clean = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        return !clean(a).isEmpty && clean(a) == clean(b)
    }

    static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize: "The conversation got too long for the on-device model. Colony started a fresh session; send your message again."
        case .guardrailViolation: "Apple Intelligence declined this request because of its safety guidelines. Try rephrasing it."
        case .unsupportedLanguageOrLocale: "The on-device model doesn't support this language yet."
        case .assetsUnavailable: "The on-device model isn't available right now. Try again in a moment."
        case .rateLimited: "Too many requests at once. Try again in a moment."
        case .concurrentRequests: "The agent is still busy with another request."
        default: "The on-device model couldn't answer (\(error.localizedDescription))."
        }
    }
}
