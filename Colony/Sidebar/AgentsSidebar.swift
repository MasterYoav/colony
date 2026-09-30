//
//  AgentsSidebar.swift
//  Colony
//
//  The Agents and Automations sections of the sidebar: a featured member in a glass
//  pill (face, name, status, go arrow) over a row of small faces, as in the reference.
//  Every face blinks on its own random clock.
//
//  Agents are real (SwiftData, synced through iCloud; see Agents/). Automations are
//  the next phase (docs/ROADMAP.md) and still show a fixed preview crew.
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

    var members: [CrewMember] {
        switch self {
        case .agents: [
            CrewMember(id: "neo", name: "Neo", status: "Waiting", role: "Plans your day from open tasks and due dates", color: .blue),
            CrewMember(id: "ada", name: "Ada", status: "Idle", role: "Drafts follow-ups for customers in Proposal", color: .purple),
            CrewMember(id: "mira", name: "Mira", status: "Idle", role: "Summarises busy channels into Updates", color: .green),
            CrewMember(id: "pax", name: "Pax", status: "Idle", role: "Breaks big tasks into checklists", color: .pink),
            CrewMember(id: "juno", name: "Juno", status: "Idle", role: "Writes the weekly report", color: .teal),
            CrewMember(id: "orla", name: "Orla", status: "Idle", role: "Triages new tasks into projects", color: .orange),
        ]
        case .automations: [
            CrewMember(id: "nudge", name: "Overdue nudge", status: "Daily · 9:00", role: "When a task is overdue, raise its priority and ping you", color: .orange),
            CrewMember(id: "won", name: "Deal won", status: "On stage change", role: "When a customer moves to Won, create an onboarding task list", color: .green),
            CrewMember(id: "review", name: "Ready for review", status: "On status change", role: "When a task hits Review, post it to the project channel", color: .indigo),
            CrewMember(id: "cleanup", name: "Weekly cleanup", status: "Fridays", role: "Archive tasks done for more than 30 days", color: .gray),
        ]
        }
    }
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
    let kind: CrewKind
    @State private var isExpanded = true

    private var ordered: [Agent] {
        guard kind == .agents else { return [] }
        let open: UUID? = if case .agent(let id) = app.destination { id } else { nil }
        return Agent.featured(agents, running: app.agents.running, open: open)
    }

    private var members: [CrewMember] {
        guard kind == .agents else { return kind.members }
        return ordered.map { agent in
            var member = agent.crewMember
            if app.agents.isRunning(agent) { member = CrewMember(id: member.id, name: member.name, status: "Thinking…", role: member.role, color: member.color) }
            return member
        }
    }

    var body: some View {
        let members = members
        let featuredAgent = kind == .agents ? ordered.first : nil
        let isSelected = app.destination == .crew(kind) || (featuredAgent.map { app.destination == .agent($0.uuid) } ?? false)

        VStack(alignment: .leading, spacing: 6) {
            header
            if isExpanded {
                if let featured = members.first {
                    FeaturedCrewRow(kind: kind, member: featured, isSelected: isSelected) {
                        app.go(featuredAgent.map { .agent($0.uuid) } ?? .crew(kind))
                    }
                    .contextMenu {
                        if let featuredAgent { AgentMenuItems(agent: featuredAgent) }
                    }
                } else {
                    Button { app.present(.recruitAgent) } label: {
                        Label("Recruit an agent", systemImage: "person.badge.plus")
                            .appFont(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                faces(Array(members.dropFirst()), agents: Array(ordered.dropFirst()))
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
            if kind == .agents {
                Button { app.present(.recruitAgent) } label: {
                    Image(systemName: "plus")
                        .appFont(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Recruit an agent")
                .accessibilityLabel("Recruit an agent")
            }
        }
        .padding(.horizontal, 8)
    }

    private func faces(_ rest: [CrewMember], agents: [Agent]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(rest.prefix(5).enumerated()), id: \.element.id) { index, member in
                let agent = index < agents.count ? agents[index] : nil
                Button { app.go(agent.map { .agent($0.uuid) } ?? .crew(kind)) } label: {
                    AgentFace(color: member.color.color, size: 19, isRound: kind.isRound, seed: index + (kind == .agents ? 1 : 11))
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
                .contextMenu { if let agent { AgentMenuItems(agent: agent) } }
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
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AgentFace(color: member.color.color, size: 30, isRound: kind.isRound, seed: kind == .agents ? 0 : 10)
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
        .accessibilityHint("Opens \(kind.title)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Collapsed column: the featured face as a rail button.
struct CrewRailButton: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Agent.sortIndex) private var agents: [Agent]
    let kind: CrewKind

    var body: some View {
        let featured = kind == .agents ? Agent.featured(agents, running: app.agents.running).first : nil
        let isSelected: Bool = {
            if app.destination == .crew(kind) { return true }
            if kind == .agents, case .agent = app.destination { return true }
            return false
        }()
        Button { app.go(.crew(kind)) } label: {
            AgentFace(color: featured?.color.color ?? kind.members[0].color.color, size: 24, isRound: kind.isRound, seed: kind == .agents ? 0 : 10)
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

// MARK: - Page

/// Destination page for a crew: who's in it and what each will do. Labelled as a
/// preview until the feature ships.
struct CrewView: View {
    let kind: CrewKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(kind.title)
                            .appFont(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Coming next")
                            .appFont(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(ColonyColor.blue.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ColonyColor.blue.color.opacity(0.12), in: Capsule())
                    }
                    Text(summary)
                        .appFont(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(Array(kind.members.enumerated()), id: \.element.id) { index, member in
                        HStack(alignment: .top, spacing: 12) {
                            AgentFace(color: member.color.color, size: 40, isRound: kind.isRound, seed: index + 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.name)
                                    .appFont(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text(member.role)
                                    .appFont(.system(size: 12.5))
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(Theme.canvas)
    }

    private var summary: String {
        switch kind {
        case .agents: "Assistants that work alongside you in Colony, on your device with Apple Intelligence. These are examples of what's planned; they don't run yet."
        case .automations: "Rules that run when something changes in your workspace. These are examples of what's planned; they don't run yet."
        }
    }
}
