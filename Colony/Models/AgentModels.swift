//
//  AgentModels.swift
//  Colony
//
//  Agents: on-device assistants (Apple Intelligence, Foundation Models) defined by an
//  AGENT.md file. Stored in SwiftData so they, and their conversations, sync through
//  iCloud like everything else. Same CloudKit rules as ColonyModels: defaults on every
//  property, optional relationships with inverses, enums as raw strings.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Agent {
    var uuid: UUID = UUID()
    var name: String = ""
    /// One line: what the agent does. `description` in AGENT.md.
    var summary: String = ""
    var colorRaw: String = ColonyColor.blue.rawValue
    /// The body of AGENT.md: how the agent should behave.
    var instructions: String = ""
    /// Comma-separated `AgentTool` ids.
    var toolsRaw: String = ""
    /// `AgentSchedule` text; empty means it only runs when asked.
    var scheduleRaw: String = ""
    /// Suggested prompts shown in an empty chat, one per line.
    var promptsRaw: String = ""
    var isEnabled: Bool = true
    var statusRaw: String = AgentStatus.idle.rawValue
    var lastRunAt: Date?
    /// The schedule slot last run (by any device), so a slot runs once.
    var lastScheduledSlot: Date?
    var lastReadAt: Date = Date.distantPast
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \AgentMessage.agent)
    var messages: [AgentMessage]? = []

    init(name: String) {
        self.name = name
    }

    var color: ColonyColor {
        get { ColonyColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var status: AgentStatus {
        get { AgentStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    var tools: [AgentTool] {
        get { AgentTool.parseList(toolsRaw) }
        set { toolsRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    var schedule: AgentSchedule? {
        get { AgentSchedule(scheduleRaw) }
        set { scheduleRaw = newValue?.text ?? "" }
    }

    var prompts: [String] {
        get { promptsRaw.split(separator: "\n").map { ColonyText.trimmed(String($0)) }.filter { !$0.isEmpty } }
        set { promptsRaw = newValue.joined(separator: "\n") }
    }

    var sortedMessages: [AgentMessage] {
        (messages ?? []).sorted { ($0.createdAt, $0.sequence) < ($1.createdAt, $1.sequence) }
    }

    var unreadCount: Int {
        (messages ?? []).filter { $0.role == .agent && $0.createdAt > lastReadAt }.count
    }

    /// The definition this agent was built from, for editing and export.
    var definition: AgentDefinition {
        AgentDefinition(name: name, summary: summary, color: color, tools: tools, schedule: schedule, prompts: prompts, instructions: instructions)
    }

    func apply(_ definition: AgentDefinition) {
        name = definition.name
        summary = definition.summary
        color = definition.color
        tools = definition.tools
        schedule = definition.schedule
        prompts = definition.prompts
        instructions = definition.instructions
    }
}

@Model
final class AgentMessage {
    var uuid: UUID = UUID()
    var roleRaw: String = AgentMessageRole.agent.rawValue
    var body: String = ""
    /// SF Symbol for action rows ("Created task …").
    var symbol: String = ""
    var createdAt: Date = Date.now
    /// Breaks ties between messages created in the same instant.
    var sequence: Int = 0
    var agent: Agent?

    init(role: AgentMessageRole, body: String, symbol: String = "", agent: Agent?, sequence: Int = 0) {
        self.roleRaw = role.rawValue
        self.body = body
        self.symbol = symbol
        self.agent = agent
        self.sequence = sequence
    }

    var role: AgentMessageRole { AgentMessageRole(rawValue: roleRaw) ?? .agent }
}

enum AgentMessageRole: String, Codable {
    /// You.
    case user
    /// The agent's reply.
    case agent
    /// Something the agent did with a tool.
    case action
    /// Errors and notices from Colony.
    case notice
}

enum AgentStatus: String, Codable {
    case idle, thinking, waiting, done, failed

    var title: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking…"
        case .waiting: "Waiting for you"
        case .done: "Done"
        case .failed: "Needs attention"
        }
    }
}

// MARK: - Tools

/// What an agent may do in the workspace. Listed in AGENT.md under `tools:`.
enum AgentTool: String, CaseIterable, Identifiable, Codable {
    case listTasks = "list_tasks"
    case createTask = "create_task"
    case updateTask = "update_task"
    case listProjects = "list_projects"
    case listCustomers = "list_customers"
    case moveCustomer = "move_customer"
    case readChannel = "read_channel"
    case postMessage = "post_message"
    case listUpdates = "list_updates"
    case postUpdate = "post_update"
    case askUser = "ask_user"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listTasks: "Read tasks"
        case .createTask: "Create tasks"
        case .updateTask: "Update tasks"
        case .listProjects: "Read projects"
        case .listCustomers: "Read customers"
        case .moveCustomer: "Move customers"
        case .readChannel: "Read channels"
        case .postMessage: "Post in channels"
        case .listUpdates: "Read Updates"
        case .postUpdate: "Post to Updates"
        case .askUser: "Ask you"
        }
    }

    var symbol: String {
        switch self {
        case .listTasks, .listProjects, .listCustomers, .readChannel, .listUpdates: "eye"
        case .createTask: "plus.circle"
        case .updateTask: "pencil.circle"
        case .moveCustomer: "arrow.right.circle"
        case .postMessage: "bubble.left"
        case .postUpdate: "bell"
        case .askUser: "hand.raised"
        }
    }

    /// Changes workspace data (shown differently in the recruit preview).
    var writes: Bool {
        switch self {
        case .createTask, .updateTask, .moveCustomer, .postMessage, .postUpdate: true
        default: false
        }
    }

    /// Tools every agent gets when AGENT.md doesn't list any: look, don't touch.
    static let readOnly: [AgentTool] = [.listTasks, .listProjects, .listCustomers, .readChannel, .listUpdates, .askUser]

    /// Accepts `a, b`, `[a, b]` and YAML `- a` lines; also hyphenated or spaced names.
    static func parseList(_ text: String) -> [AgentTool] {
        parseNames(text).compactMap(AgentTool.init(loose:))
    }

    static func parseNames(_ text: String) -> [String] {
        text.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { ColonyText.trimmed(String($0)).trimmingCharacters(in: CharacterSet(charactersIn: "-*\"' ")) }
            .filter { !$0.isEmpty }
    }

    init?(loose name: String) {
        let key = name.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        guard let tool = AgentTool(rawValue: key) else { return nil }
        self = tool
    }
}

// MARK: - Schedule

/// When an agent runs by itself: `hourly`, `daily 09:00`, `weekdays 08:30`,
/// `mondays 10:00` (any weekday name, singular or plural).
struct AgentSchedule: Equatable, Hashable {
    enum Kind: Equatable, Hashable {
        case hourly
        case daily
        case weekdays
        case weekly(weekday: Int) // 1 = Sunday … 7 = Saturday, as in Calendar
    }

    var kind: Kind
    var hour: Int = 9
    var minute: Int = 0

    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    init(kind: Kind, hour: Int = 9, minute: Int = 0) {
        self.kind = kind
        self.hour = hour
        self.minute = minute
    }

    init?(_ text: String) {
        let parts = text.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard let first = parts.first, !["", "manual", "never", "none"].contains(first) else { return nil }
        var hour = 9, minute = 0
        if parts.count > 1 {
            let time = parts[1].split(separator: ":")
            guard let h = Int(time[0]), (0...23).contains(h) else { return nil }
            hour = h
            if time.count > 1 {
                guard let m = Int(time[1]), (0...59).contains(m) else { return nil }
                minute = m
            }
        }
        switch first {
        case "hourly", "every-hour":
            self.init(kind: .hourly, hour: 0, minute: parts.count > 1 ? minute : 0)
        case "daily", "everyday", "every-day":
            self.init(kind: .daily, hour: hour, minute: minute)
        case "weekdays", "workdays":
            self.init(kind: .weekdays, hour: hour, minute: minute)
        default:
            let singular = first.hasSuffix("s") ? String(first.dropLast()) : first
            guard let index = Self.weekdayNames.firstIndex(where: { $0 == singular || $0.prefix(3) == singular }) else { return nil }
            self.init(kind: .weekly(weekday: index + 1), hour: hour, minute: minute)
        }
    }

    private var time: String { String(format: "%02d:%02d", hour, minute) }

    /// Canonical AGENT.md text.
    var text: String {
        switch kind {
        case .hourly: "hourly"
        case .daily: "daily \(time)"
        case .weekdays: "weekdays \(time)"
        case .weekly(let day): "\(Self.weekdayNames[day - 1])s \(time)"
        }
    }

    /// For people: "Weekdays · 9:00".
    var label: String {
        let clock = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now).map { $0.formatted(date: .omitted, time: .shortened) } ?? time
        switch kind {
        case .hourly: return "Every hour"
        case .daily: return "Daily · \(clock)"
        case .weekdays: return "Weekdays · \(clock)"
        case .weekly(let day): return "\(Self.weekdayNames[day - 1].capitalized)s · \(clock)"
        }
    }

    /// The most recent slot at or before `date`, looking back up to eight days.
    func lastSlot(before date: Date, calendar: Calendar = .current) -> Date? {
        if kind == .hourly {
            var parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            parts.minute = minute
            guard let slot = calendar.date(from: parts) else { return nil }
            return slot <= date ? slot : calendar.date(byAdding: .hour, value: -1, to: slot)
        }
        for back in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: date),
                  let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  slot <= date else { continue }
            let weekday = calendar.component(.weekday, from: slot)
            switch kind {
            case .daily: return slot
            case .weekdays where (2...6).contains(weekday): return slot
            case .weekly(let wanted) where weekday == wanted: return slot
            default: continue
            }
        }
        return nil
    }
}
