//
//  AgentDefinition.swift
//  Colony
//
//  The AGENT.md format. An agent is a Markdown file: optional YAML-style front matter
//  for its settings, and a body with its instructions.
//
//      ---
//      name: Neo
//      description: Plans your day from open tasks and due dates.
//      color: blue
//      tools: list_tasks, update_task, post_update
//      schedule: weekdays 09:00
//      prompts:
//        - Plan my day
//        - What's overdue?
//      ---
//
//      You are Neo, a calm planner. Each morning…
//
//  Without front matter, the first `# Heading` is the name and the rest is the
//  instructions (read-only tools). See docs/AGENTS.md for the full reference.
//

import Foundation

struct AgentDefinition: Equatable {
    var name: String
    var summary: String = ""
    var color: ColonyColor = .blue
    var tools: [AgentTool] = AgentTool.readOnly
    var schedule: AgentSchedule?
    var prompts: [String] = []
    var instructions: String

    /// Problems that don't stop recruiting (unknown tools, bad schedule…).
    var warnings: [String] = []

    enum ParseError: LocalizedError, Equatable {
        case empty
        case unterminatedFrontMatter
        case missingName
        case missingInstructions

        var errorDescription: String? {
            switch self {
            case .empty: "The file is empty."
            case .unterminatedFrontMatter: "The front matter starts with --- but never ends with a second ---."
            case .missingName: "Give the agent a name: `name:` in the front matter, or a # Heading."
            case .missingInstructions: "Add instructions below the front matter: what the agent should do."
            }
        }
    }

    static let knownKeys: Set<String> = ["name", "description", "color", "colour", "tools", "schedule", "prompts"]

    // MARK: Parse

    static func parse(_ markdown: String, fallbackName: String? = nil) throws -> AgentDefinition {
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        guard !ColonyText.trimmed(text).isEmpty else { throw ParseError.empty }

        var fields: [String: String] = [:]
        var order: [String] = []
        var body = text
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, ColonyText.trimmed(first).isEmpty { lines.removeFirst() }

        if lines.first.map({ ColonyText.trimmed($0) }) == "---" {
            guard let end = lines.dropFirst().firstIndex(where: { ColonyText.trimmed($0) == "---" }) else {
                throw ParseError.unterminatedFrontMatter
            }
            let front = Array(lines[1..<end])
            body = lines[(end + 1)...].joined(separator: "\n")
            var currentKey: String?
            for line in front {
                let trimmed = ColonyText.trimmed(line)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                // Continuation of a list (`  - item`) or of a multi-line value.
                if let key = currentKey, line.first == " " || line.first == "\t" || trimmed.hasPrefix("- ") {
                    fields[key, default: ""] += (fields[key, default: ""].isEmpty ? "" : "\n") + trimmed
                    continue
                }
                guard let colon = trimmed.firstIndex(of: ":") else { continue }
                let key = trimmed[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                let value = ColonyText.trimmed(String(trimmed[trimmed.index(after: colon)...]))
                fields[key] = unquote(value)
                order.append(key)
                currentKey = key
            }
        }

        var definition = AgentDefinition(name: "", instructions: "")
        var warnings: [String] = []

        // Name: front matter, else first heading, else the file name.
        var instructions = body
        if let name = fields["name"], !name.isEmpty {
            definition.name = name
        } else if let heading = firstHeading(in: body) {
            definition.name = heading.title
            instructions = heading.remainder
        } else if let fallbackName, !fallbackName.isEmpty {
            definition.name = fallbackName
        }
        definition.name = String(ColonyText.trimmed(definition.name).prefix(40))
        guard !definition.name.isEmpty else { throw ParseError.missingName }

        definition.instructions = ColonyText.trimmed(instructions)
        guard !definition.instructions.isEmpty else { throw ParseError.missingInstructions }

        definition.summary = String(ColonyText.trimmed(fields["description"] ?? "").prefix(140))

        if let raw = fields["color"] ?? fields["colour"], !raw.isEmpty {
            if let color = ColonyColor(rawValue: raw.lowercased()) {
                definition.color = color
            } else {
                warnings.append("Unknown color “\(raw)”; using \(Self.color(for: definition.name).title.lowercased()). Colors: \(ColonyColor.allCases.map(\.rawValue).joined(separator: ", ")).")
                definition.color = Self.color(for: definition.name)
            }
        } else {
            definition.color = Self.color(for: definition.name)
        }

        if let raw = fields["tools"] {
            let names = AgentTool.parseNames(raw)
            let known = names.compactMap(AgentTool.init(loose:))
            let unknown = names.filter { AgentTool(loose: $0) == nil }
            if !unknown.isEmpty {
                warnings.append("Unknown tool\(unknown.count == 1 ? "" : "s") ignored: \(unknown.joined(separator: ", ")).")
            }
            var unique: [AgentTool] = []
            for tool in known where !unique.contains(tool) { unique.append(tool) }
            definition.tools = unique
        }

        if let raw = fields["schedule"], !raw.isEmpty {
            let lowered = raw.lowercased()
            if let schedule = AgentSchedule(raw) {
                definition.schedule = schedule
            } else if !["manual", "never", "none"].contains(lowered) {
                warnings.append("Couldn't read the schedule “\(raw)”; the agent will only run when asked. Try `daily 09:00`, `weekdays 08:30`, `mondays 10:00` or `hourly`.")
            }
        }

        if let raw = fields["prompts"] {
            definition.prompts = raw.split(separator: "\n")
                .map { unquote(ColonyText.trimmed(String($0)).trimmingCharacters(in: CharacterSet(charactersIn: "- "))) }
                .filter { !$0.isEmpty }
                .prefix(4)
                .map { String($0.prefix(80)) }
        }

        let unknownKeys = order.filter { !knownKeys.contains($0) }
        if !unknownKeys.isEmpty {
            warnings.append("Ignored setting\(unknownKeys.count == 1 ? "" : "s"): \(unknownKeys.joined(separator: ", ")).")
        }
        definition.warnings = warnings
        return definition
    }

    // MARK: Write

    /// The agent as an AGENT.md file. Parsing it gives the same definition back.
    var markdown: String {
        var front = ["---", "name: \(name)"]
        if !summary.isEmpty { front.append("description: \(summary)") }
        front.append("color: \(color.rawValue)")
        front.append("tools: \(tools.map(\.rawValue).joined(separator: ", "))")
        front.append("schedule: \(schedule?.text ?? "manual")")
        if !prompts.isEmpty {
            front.append("prompts:")
            front += prompts.map { "  - \($0)" }
        }
        front.append("---")
        return front.joined(separator: "\n") + "\n\n" + instructions + "\n"
    }

    /// Stable colour from the name, for files that don't pick one.
    static func color(for name: String) -> ColonyColor {
        let palette: [ColonyColor] = [.blue, .purple, .green, .pink, .teal, .orange, .indigo, .red, .yellow]
        let sum = name.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(sum) % palette.count]
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func firstHeading(in body: String) -> (title: String, remainder: String)? {
        var lines = body.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { !ColonyText.trimmed($0).isEmpty }) else { return nil }
        let line = ColonyText.trimmed(lines[index])
        guard line.hasPrefix("# ") else { return nil }
        let title = ColonyText.trimmed(String(line.dropFirst(2)))
        lines.remove(at: index)
        return (title, lines.joined(separator: "\n"))
    }
}

// MARK: - Starter templates

/// Built-in AGENT.md files: the starter crew and the templates in the recruit dialog.
enum AgentTemplates {
    struct Template: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let markdown: String
    }

    static let all: [Template] = [planner, followUps, digest, weeklyReport, triage, blank]

    /// Recruited automatically the first time, so the section isn't empty.
    static let starters: [Template] = [planner, followUps, digest, weeklyReport]

    static let planner = Template(id: "planner", title: "Daily planner", symbol: "sun.max", markdown: """
    ---
    name: Neo
    description: Plans your day from open tasks and due dates.
    color: blue
    tools: list_tasks, list_projects, update_task, post_update, ask_user
    schedule: weekdays 09:00
    prompts:
      - Plan my day
      - What's overdue?
      - What should I do next?
    ---

    You are Neo, a calm, practical day planner.

    When asked to plan the day, or on your scheduled run:
    1. Call list_tasks with filter "overdue", then "today", then "upcoming".
    2. Pick at most five tasks for today: overdue and urgent first, then what's due soonest.
    3. Post one Update titled "Today's plan" listing them in order, one short line each.
    4. Reply with the same plan in a few lines.

    Only change a task when the user asks you to. Never mark a task as done yourself.
    """)

    static let followUps = Template(id: "followups", title: "Customer follow-ups", symbol: "person.2", markdown: """
    ---
    name: Ada
    description: Finds customers who need a follow-up and adds tasks for them.
    color: purple
    tools: list_customers, list_tasks, create_task, move_customer, ask_user
    prompts:
      - Who needs a follow-up?
      - Add follow-up tasks for my proposals
    ---

    You are Ada, who keeps deals moving.

    Look at customers in the Proposal and Negotiation stages with list_customers.
    For each one without an open task mentioning their name, suggest a follow-up.
    Create a task only when the user asks, titled "Follow up with <name>", due tomorrow,
    in the Sales project if it exists.

    Before moving a customer to another stage, call ask_user to confirm.
    Keep replies short: one line per customer.
    """)

    static let digest = Template(id: "digest", title: "Channel digest", symbol: "bubble.left.and.text.bubble.right", markdown: """
    ---
    name: Mira
    description: Summarises busy channels into Updates.
    color: green
    tools: read_channel, post_update, post_message
    prompts:
      - Summarise my channels
      - What did I miss?
    ---

    You are Mira, who reads channels so the user doesn't have to.

    Call read_channel without a name to see the channels, then read the ones with
    recent messages. Summarise each in two or three short bullet points: decisions,
    open questions, and anything that needs the user.

    Post the summary as one Update titled "Channel digest" when asked, and only post
    in a channel when the user tells you exactly what to say.
    """)

    static let weeklyReport = Template(id: "weekly", title: "Weekly report", symbol: "chart.bar.doc.horizontal", markdown: """
    ---
    name: Juno
    description: Writes the weekly report every Friday afternoon.
    color: teal
    tools: list_tasks, list_customers, list_updates, post_update
    schedule: fridays 16:00
    prompts:
      - Write this week's report
    ---

    You are Juno, who writes a short, honest weekly report.

    Use list_tasks with filter "done" for what got finished, "overdue" for what slipped,
    list_customers for deals that moved, and list_updates for anything notable.

    Post one Update titled "Weekly report" with three sections: Done, Slipped, Next week.
    At most four lines per section. Reply with the same report.
    """)

    static let triage = Template(id: "triage", title: "Task triage", symbol: "tray.and.arrow.down", markdown: """
    ---
    name: Orla
    description: Sorts tasks without a project into the right place.
    color: orange
    tools: list_tasks, list_projects, update_task, ask_user
    prompts:
      - Triage my loose tasks
    ---

    You are Orla, who keeps the task list tidy.

    Call list_tasks with filter "no_project", and list_projects. For each loose task,
    suggest the best project and a priority. Ask the user with ask_user before moving
    more than three tasks at once. Use update_task to move them once confirmed.
    """)

    static let blank = Template(id: "blank", title: "Blank", symbol: "doc", markdown: """
    ---
    name: New agent
    description: What this agent does, in one line.
    color: pink
    tools: list_tasks, list_projects, ask_user
    schedule: manual
    ---

    You are a helpful assistant in Colony.

    Describe here, in plain language, what you want the agent to do, step by step,
    and what it must never do.
    """)
}
