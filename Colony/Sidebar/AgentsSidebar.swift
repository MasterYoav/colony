//
//  AgentsSidebar.swift
//  Colony
//
//  The Agents and Automations sections of the sidebar: a featured member in a glass
//  pill (face, name, status, go arrow) over a row of small faces, as in the reference.
//  Every face blinks on its own random clock.
//
//  Agents and Automations are the next two phases (see docs/ROADMAP.md). Until then
//  the sections show a fixed preview crew and lead to pages that say so.
//

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

struct CrewSidebarSection: View {
    @Environment(AppModel.self) private var app
    let kind: CrewKind
    @State private var isExpanded = true

    var body: some View {
        let members = kind.members
        let featured = members[0]
        let rest = Array(members.dropFirst())
        let isSelected = app.destination == .crew(kind)

        VStack(alignment: .leading, spacing: 6) {
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
            .padding(.horizontal, 8)
            .accessibilityLabel("\(kind.title) section")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                FeaturedCrewRow(kind: kind, member: featured, isSelected: isSelected) {
                    app.go(.crew(kind))
                }

                Button { app.go(.crew(kind)) } label: {
                    HStack(spacing: 1) {
                        ForEach(Array(rest.prefix(5).enumerated()), id: \.element.id) { index, member in
                            AgentFace(color: member.color.color, size: 19, isRound: kind.isRound, seed: index + (kind == .agents ? 1 : 11))
                        }
                        if rest.count > 5 {
                            Text("+\(rest.count - 5)")
                                .appFont(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.leading, 9)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All \(kind.title.lowercased()): \(rest.map(\.name).joined(separator: ", "))")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
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
    let kind: CrewKind

    var body: some View {
        let isSelected = app.destination == .crew(kind)
        Button { app.go(.crew(kind)) } label: {
            AgentFace(color: kind.members[0].color.color, size: 24, isRound: kind.isRound, seed: kind == .agents ? 0 : 10)
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
