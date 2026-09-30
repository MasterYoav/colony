//
//  AgentsSidebar.swift
//  Colony
//
//  The Agents and Automations sections of the sidebar: a featured member in a glass
//  pill (face, name, status, go arrow) over a row of small faces, as in the reference.
//  Every face blinks on its own random clock.
//
//  Both are real (SwiftData, synced through iCloud): agents live in Agents/,
//  automations in Automations/.
//

import SwiftData
import SwiftUI

// MARK: - Preview crew

struct CrewMember: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let role: String
    let color: ColonyColor
}

enum CrewKind: String, Hashable, Codable {
    case agents, automations

    var title: String { self == .agents ? "Agents" : "Automations" }

    /// Agents are round faces; automations are little squircle bots.
    var isRound: Bool { self == .agents }
}

// MARK: - Face

/// A white face with two coloured pill eyes that blink now and then.
struct AgentFace: View {
    let color: Color
    var size: CGFloat = 30
    var isRound = true
    /// Seeds the blink clock so neighbouring faces don't blink in step.
    var seed: Int = 0

    @Environment(\.colorScheme) private var scheme
    @State private var closed = false

    var body: some View {
        let shape = isRound ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: scheme == .dark ? [Color(white: 0.96), Color(white: 0.82)] : [.white, Color(white: 0.9)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay { shape.stroke(Color.black.opacity(0.08), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.12), radius: size * 0.05, y: size * 0.03)
            HStack(spacing: size * 0.12) {
                eye
                eye
            }
        }
        .frame(width: size, height: size)
        .task { await blinkLoop() }
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Capsule()
            .fill(color)
            .frame(width: size * 0.13, height: size * 0.3)
            .scaleEffect(x: 1, y: closed ? 0.14 : 1, anchor: .center)
    }

    /// Blinks every 2.5–6.5 s, sometimes twice in a row. Kept under Reduce Motion: it's a
    /// tiny in-place change, not the sliding or zooming motion that setting guards against.
    private func blinkLoop() async {
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 7919 &+ 17))
        try? await Task.sleep(for: .seconds(Double.random(in: 0.4...3.5, using: &rng)))
        while !Task.isCancelled {
            await blink()
            if Double.random(in: 0...1, using: &rng) < 0.22 {
                try? await Task.sleep(for: .milliseconds(140))
                await blink()
            }
            try? await Task.sleep(for: .seconds(Double.random(in: 2.5...6.5, using: &rng)))
        }
    }

    private func blink() async {
        withAnimation(.easeIn(duration: 0.07)) { closed = true }
        try? await Task.sleep(for: .milliseconds(90))
        withAnimation(.easeOut(duration: 0.1)) { closed = false }
        try? await Task.sleep(for: .milliseconds(100))
    }
}

/// Small deterministic RNG so each face keeps its own rhythm.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Sidebar section

extension Automation {
    func crewMember(_ names: AutomationNames, running: Bool) -> CrewMember {
        CrewMember(id: uuid.uuidString, name: name, status: running ? "Running…" : statusLine(names), role: sentence(names), color: color)
    }

    /// Who the sidebar pill features: whatever's running, then the one on screen, then
    /// what ran most recently among those that are on, then the list's order.
    static func featured(_ automations: [Automation], running: Set<UUID>, open: UUID? = nil) -> [Automation] {
        func rank(_ a: Automation) -> (Int, Double, Int) {
            if running.contains(a.uuid) { return (0, 0, a.sortIndex) }
            if a.uuid == open { return (1, 0, a.sortIndex) }
            if a.isEnabled && a.isComplete { return (2, -(a.lastRunAt?.timeIntervalSince1970 ?? 0), a.sortIndex) }
            return (3, 0, a.sortIndex)
        }
        return automations.sorted { rank($0) < rank($1) }
    }
}

extension Agent {
    var crewMember: CrewMember {
        CrewMember(id: uuid.uuidString, name: name, status: status == .thinking ? "Thinking…" : status.title, role: summary, color: color)
    }

    /// Who the sidebar pill features: whoever needs you, then whoever's busy, then the
    /// one on screen, then the crew's order. Stable otherwise, so it doesn't jump around.
    static func featured(_ agents: [Agent], running: Set<UUID>, open: UUID? = nil) -> [Agent] {
        func rank(_ agent: Agent) -> Int {
            if agent.status == .waiting { return 0 }
            if running.contains(agent.uuid) { return 1 }
            if agent.uuid == open { return 2 }
            return 3
        }
        return agents.sorted { (rank($0), $0.sortIndex) < (rank($1), $1.sortIndex) }
    }
}

struct CrewSidebarSection: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Agent.sortIndex) private var agents: [Agent]
    @Query(sort: \Automation.sortIndex) private var automations: [Automation]
    @Query private var projects: [Project]
    @Query private var channels: [Channel]
    let kind: CrewKind
    @State private var isExpanded = true

    private var ordered: [Agent] {
        guard kind == .agents else { return [] }
        let open: UUID? = if case .agent(let id) = app.destination { id } else { nil }
        return Agent.featured(agents, running: app.agents.running, open: open)
    }

    private var orderedAutomations: [Automation] {
        guard kind == .automations else { return [] }
        let open: UUID? = if case .automation(let id) = app.destination { id } else { nil }
        return Automation.featured(automations, running: app.automations.running, open: open)
    }

    private var names: AutomationNames {
        AutomationNames(
            projects: Dictionary(projects.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a }),
            channels: Dictionary(channels.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a }),
            agents: Dictionary(agents.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a })
        )
    }

    /// Where a member of this crew opens.
    private func destination(_ id: String) -> Destination {
        guard let uuid = UUID(uuidString: id) else { return .crew(kind) }
        return kind == .agents ? .agent(uuid) : .automation(uuid)
    }

    private var members: [CrewMember] {
        if kind == .automations {
            let names = names
            return orderedAutomations.map { $0.crewMember(names, running: app.automations.isRunning($0)) }
        }
        return ordered.map { agent in
            var member = agent.crewMember
            if app.agents.isRunning(agent) { member = CrewMember(id: member.id, name: member.name, status: "Thinking…", role: member.role, color: member.color) }
            return member
        }
    }

    var body: some View {
        let members = members
        let featuredAgent = kind == .agents ? ordered.first : nil
        let featuredAutomation = kind == .automations ? orderedAutomations.first : nil
        let isSelected = app.destination == .crew(kind) || (members.first.map { app.destination == destination($0.id) } ?? false)

        VStack(alignment: .leading, spacing: 6) {
            header
            if isExpanded {
                if let featured = members.first {
                    FeaturedCrewRow(kind: kind, member: featured, isSelected: isSelected, isOff: featuredAutomation.map { !$0.isEnabled || !$0.isComplete } ?? false) {
                        app.go(destination(featured.id))
                    }
                    .contextMenu {
                        if let featuredAgent { AgentMenuItems(agent: featuredAgent) }
                        if let featuredAutomation { AutomationMenuItems(automation: featuredAutomation) }
                    }
                } else {
                    Button { app.present(kind == .agents ? .recruitAgent : .newAutomation) } label: {
                        Label(kind == .agents ? "Recruit an agent" : "New automation", systemImage: kind == .agents ? "person.badge.plus" : "bolt.badge.clock")
                            .appFont(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                faces(Array(members.dropFirst()), agents: Array(ordered.dropFirst()), automations: Array(orderedAutomations.dropFirst()))
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withMotion(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(kind.title)
                        .appFont(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.down")
                        .appFont(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kind.title) section")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            Button { app.present(kind == .agents ? .recruitAgent : .newAutomation) } label: {
                Image(systemName: "plus")
                    .appFont(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(kind == .agents ? "Recruit an agent" : "New automation")
            .accessibilityLabel(kind == .agents ? "Recruit an agent" : "New automation")
        }
        .padding(.horizontal, 8)
    }

    private func faces(_ rest: [CrewMember], agents: [Agent], automations: [Automation]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(rest.prefix(5).enumerated()), id: \.element.id) { index, member in
                let agent = index < agents.count ? agents[index] : nil
                let automation = index < automations.count ? automations[index] : nil
                Button { app.go(destination(member.id)) } label: {
                    AgentFace(color: member.color.color, size: 19, isRound: kind.isRound, seed: index + (kind == .agents ? 1 : 11))
                        .opacity(automation.map { $0.isEnabled && $0.isComplete ? 1 : 0.45 } ?? 1)
                        .overlay(alignment: .topTrailing) {
                            if let automation, app.automations.isRunning(automation) {
                                Circle()
                                    .fill(member.color.color)
                                    .frame(width: 6, height: 6)
                                    .overlay { Circle().strokeBorder(Theme.sidebar, lineWidth: 1) }
                                    .offset(x: 1, y: -1)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if let agent, agent.status == .waiting || agent.unreadCount > 0 || app.agents.isRunning(agent) {
                                Circle()
                                    .fill(agent.status == .waiting ? ColonyColor.orange.color : member.color.color)
                                    .frame(width: 6, height: 6)
                                    .overlay { Circle().strokeBorder(Theme.sidebar, lineWidth: 1) }
                                    .offset(x: 1, y: -1)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("\(member.name) · \(member.status)")
                .accessibilityLabel("\(member.name), \(member.status)")
                .contextMenu {
                    if let agent { AgentMenuItems(agent: agent) }
                    if let automation { AutomationMenuItems(automation: automation) }
                }
            }
            Button { app.go(.crew(kind)) } label: {
                Text(rest.count > 5 ? "+\(rest.count - 5)" : "All")
                    .appFont(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, rest.isEmpty ? 0 : 9)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All \(kind.title.lowercased())")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .transition(.opacity)
    }
}

/// The glass pill: face, name over status, and a go arrow.
private struct FeaturedCrewRow: View {
    let kind: CrewKind
    let member: CrewMember
    let isSelected: Bool
    var isOff = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AgentFace(color: member.color.color, size: 30, isRound: kind.isRound, seed: kind == .agents ? 0 : 10)
                    .opacity(isOff ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(member.name)
                        .appFont(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(member.status)
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: kind == .agents ? "location.north.fill" : "bolt.fill")
                    .appFont(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.icon)
                    .rotationEffect(.degrees(kind == .agents ? -45 : 0))
                    .frame(width: 22)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isSelected ? Theme.glassSelection.opacity(1.6) : (isHovering ? Theme.glassSelection : Theme.glassHover))
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5).blendMode(.plusLighter) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(member.name), \(member.status)")
        .accessibilityHint(kind == .agents ? "Opens the agent" : "Opens the automation")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Collapsed column: the featured face as a rail button.
struct CrewRailButton: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Agent.sortIndex) private var agents: [Agent]
    @Query(sort: \Automation.sortIndex) private var automations: [Automation]
    let kind: CrewKind

    var body: some View {
        let color: ColonyColor = kind == .agents
            ? (Agent.featured(agents, running: app.agents.running).first?.color ?? .blue)
            : (Automation.featured(automations, running: app.automations.running).first?.color ?? .orange)
        let isSelected: Bool = {
            if app.destination == .crew(kind) { return true }
            if kind == .agents, case .agent = app.destination { return true }
            if kind == .automations, case .automation = app.destination { return true }
            return false
        }()
        Button { app.go(.crew(kind)) } label: {
            AgentFace(color: color.color, size: 24, isRound: kind.isRound, seed: kind == .agents ? 0 : 10)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? Theme.glassSelection : .clear)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(kind.title)
        .accessibilityLabel(kind.title)
    }
}
