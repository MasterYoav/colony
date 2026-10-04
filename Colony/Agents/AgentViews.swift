//
//  AgentViews.swift
//  Colony
//
//  The Agents page (the whole crew) and one agent's page (chat, what it did, its
//  AGENT.md). Replies come from the on-device model; see AgentRunner.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Crew page

struct AgentsHome: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Agent.sortIndex) private var agentsEverywhere: [Agent]
    private var agents: [Agent] { agentsEverywhere.inWorkspace() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !app.agents.isAvailable {
                    AvailabilityBanner(provider: app.agents.defaultProvider)
                }
                if agents.isEmpty {
                    EmptyStateView(symbol: "person.2.badge.plus", title: "No agents yet", message: "Recruit one from an AGENT.md file or a template.", actionTitle: "Recruit an agent") {
                        app.present(.recruitAgent)
                    }
                    .frame(minHeight: 280)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(Array(agents.enumerated()), id: \.element.uuid) { index, agent in
                            AgentTile(agent: agent, seed: index + 30)
                        }
                        RecruitTile()
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.leading, app.preferences.isSidebarCollapsed && isMac ? 22 : 0)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(Theme.canvas)
        .navigationTitle("Agents")
        .onAppear { app.agents.refreshAvailability() }
    }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agents")
                    .appFont(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Assistants that work in your workspace, on this device with Apple Intelligence. Each one is an AGENT.md file: recruit your own, edit it, or share it.")
                    .appFont(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { app.present(.recruitAgent) } label: {
                Label("Recruit", systemImage: "plus")
            }
            .buttonStyle(.dialogPrimary)
            .help("Recruit an agent from an AGENT.md file (⌥⌘N)")
        }
    }
}

private struct AgentTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let agent: Agent
    let seed: Int
    @State private var isHovering = false

    var body: some View {
        Button { app.go(.agent(agent.uuid)) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    AgentFace(color: agent.color.color, size: 42, seed: seed)
                        .opacity(agent.isEnabled ? 1 : 0.45)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(agent.name)
                                .appFont(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            if agent.unreadCount > 0 {
                                Circle().fill(agent.color.color).frame(width: 7, height: 7)
                                    .accessibilityLabel("\(agent.unreadCount) unread")
                            }
                        }
                        Text(agent.summary.isEmpty ? "No description" : agent.summary)
                            .appFont(.system(size: 12.5))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    AgentStatusBadge(agent: agent)
                    Spacer(minLength: 0)
                    Label(agent.schedule?.label ?? "On request", systemImage: agent.schedule == nil ? "hand.tap" : "clock")
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(isHovering ? Theme.raised : Theme.surface, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isHovering ? Theme.strongStroke : Theme.stroke) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu { AgentMenuItems(agent: agent) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.name), \(app.agents.isRunning(agent) ? "Thinking" : agent.status.title)")
        .accessibilityHint(agent.summary)
    }
}

private struct RecruitTile: View {
    @Environment(AppModel.self) private var app
    @State private var isTargeted = false

    var body: some View {
        Button { app.present(.recruitAgent) } label: {
            VStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .appFont(.system(size: 20))
                Text("Recruit an agent")
                    .appFont(.system(size: 13, weight: .medium))
                Text("From AGENT.md or a template")
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .foregroundStyle(isTargeted ? ColonyColor.blue.color : Theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 118)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isTargeted ? ColonyColor.blue.color : Theme.strongStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recruit an agent")
    }
}

/// Context-menu items shared by tiles, the sidebar and the agent page.
struct AgentMenuItems: View {
    @Environment(AppModel.self) private var app
    let agent: Agent

    var body: some View {
        Button("Open", systemImage: "bubble.left.and.text.bubble.right") { app.go(.agent(agent.uuid)) }
        Button("Run Now", systemImage: "play.fill") { app.agents.runNow(agent) }
            .disabled(!app.agents.canRun(agent) || app.agents.isRunning(agent))
        Divider()
        Button("Edit AGENT.md…", systemImage: "doc.text") { app.present(.editAgent(agent.uuid)) }
        AgentModelMenu(agent: agent)
        Button(agent.isEnabled ? "Pause Schedule" : "Resume Schedule", systemImage: agent.isEnabled ? "pause.circle" : "play.circle") {
            agent.isEnabled.toggle()
        }
        .disabled(agent.schedule == nil)
        Divider()
        Button("Remove Agent…", systemImage: "person.badge.minus", role: .destructive) { app.present(.deleteAgent(agent.uuid)) }
    }
}

struct AgentStatusBadge: View {
    @Environment(AppModel.self) private var app
    let agent: Agent

    var body: some View {
        let running = app.agents.isRunning(agent)
        let status: AgentStatus = running ? .thinking : (agent.status == .thinking ? .idle : agent.status)
        HStack(spacing: 5) {
            Circle()
                .fill(color(status))
                .frame(width: 6, height: 6)
                .opacity(running ? 0.9 : 1)
                .phaseAnimator(running ? [0.35, 1] : [1]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.6) }
            Text(agent.isEnabled || agent.schedule == nil ? status.title : "Paused")
                .appFont(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.text.opacity(0.05), in: Capsule())
    }

    private func color(_ status: AgentStatus) -> Color {
        switch status {
        case .idle: Theme.tertiaryText
        case .thinking: agent.color.color
        case .waiting: ColonyColor.orange.color
        case .done: ColonyColor.green.color
        case .failed: ColonyColor.red.color
        }
    }
}

private struct AvailabilityBanner: View {
    @Environment(AppModel.self) private var app
    let provider: AIProvider

    var body: some View {
        let device = !provider.isCloud
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: device && app.agents.availability == .downloading ? "arrow.down.circle" : provider.symbol)
                .appFont(.system(size: 15))
                .foregroundStyle(ColonyColor.orange.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(device ? app.agents.availability.title : "Connect \(provider.title)")
                    .appFont(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(app.agents.unavailableMessage(for: provider))
                    .appFont(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("AI Settings") { app.openSettings(.ai) }
                .buttonStyle(.dialogSecondary)
        }
        .padding(12)
        .background(ColonyColor.orange.color.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ColonyColor.orange.color.opacity(0.25)) }
    }
}

/// "Runs On" submenu: the default model, this device, or one of the user's AI accounts.
struct AgentModelMenu: View {
    @Environment(AppModel.self) private var app
    let agent: Agent

    var body: some View {
        Menu("Runs On", systemImage: "cpu") {
            Picker("Runs On", selection: Binding(get: { agent.brainRaw }, set: { agent.brainRaw = $0 })) {
                Text("Default (\(app.agents.defaultProvider.shortTitle))").tag("")
                ForEach(AIProvider.allCases) { provider in
                    Text(app.agents.canUse(provider) ? provider.shortTitle : "\(provider.shortTitle) (not set up)")
                        .tag(provider.rawValue)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("AI Settings…", systemImage: "gearshape") { app.openSettings(.ai) }
        }
    }
}

// MARK: - Agent page

struct AgentPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let agent: Agent
    @State private var draft = ""
    @State private var isExporting = false
    @State private var showsInstructions = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !app.agents.canRun(agent) {
                AvailabilityBanner(provider: app.agents.provider(for: agent))
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
            }
            conversation
            composer
        }
        .background(Theme.canvas)
        .navigationTitle(agent.name)
        .onAppear {
            agent.lastReadAt = .now
            focused = true
            app.agents.refreshAvailability()
        }
        .onChange(of: agent.messages?.count) { agent.lastReadAt = .now }
        .fileExporter(isPresented: $isExporting, document: AgentFile(text: agent.definition.markdown), contentType: AgentFile.type, defaultFilename: "\(agent.name).AGENT.md") { result in
            if case .success = result { app.show("Exported \(agent.name)'s AGENT.md") }
        }
        .agentInspector(isPresented: $showsInstructions) {
            AgentInspector(agent: agent)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AgentFace(color: agent.color.color, size: 34, seed: agent.name.count)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .appFont(.headline)
                    .foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    AgentStatusBadge(agent: agent)
                    let provider = app.agents.provider(for: agent)
                    Label(provider.shortTitle, systemImage: provider.symbol)
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .help("Runs on \(provider.title). Change it in the ⋯ menu.")
                    if let schedule = agent.schedule {
                        Label(schedule.label, systemImage: "clock")
                            .appFont(.system(size: 11.5))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
            Spacer()
            if app.agents.isRunning(agent) {
                Button { app.agents.stop(agent) } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.dialogSecondary)
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { app.agents.runNow(agent) } label: { Label("Run now", systemImage: "play.fill") }
                    .buttonStyle(.dialogSecondary)
                    .disabled(!app.agents.canRun(agent))
                    .help("Do its job now, as on a scheduled run")
            }
            Menu {
                Button("Edit AGENT.md…", systemImage: "doc.text") { app.present(.editAgent(agent.uuid)) }
                Button("Export AGENT.md…", systemImage: "square.and.arrow.up") { isExporting = true }
                ShareLink("Share AGENT.md", item: agent.definition.markdown, subject: Text("\(agent.name) · AGENT.md"))
                Divider()
                AgentModelMenu(agent: agent)
                Button(agent.isEnabled ? "Pause Schedule" : "Resume Schedule", systemImage: agent.isEnabled ? "pause.circle" : "play.circle") { agent.isEnabled.toggle() }
                    .disabled(agent.schedule == nil)
                Button("Clear Conversation", systemImage: "eraser") { app.agents.clearHistory(agent) }
                Divider()
                Button("Remove Agent…", systemImage: "person.badge.minus", role: .destructive) { app.present(.deleteAgent(agent.uuid)) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize()
            .accessibilityLabel("More")
            Button { withMotion(.snappy(duration: 0.2)) { showsInstructions.toggle() } } label: {
                Image(systemName: "sidebar.right")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showsInstructions ? agent.color.color : Theme.secondaryText)
            .help("Show AGENT.md")
            .accessibilityLabel(showsInstructions ? "Hide AGENT.md" : "Show AGENT.md")
        }
        .padding(.horizontal, 22)
        .padding(.leading, app.preferences.isSidebarCollapsed && isMac ? 22 : 0)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { SidebarDivider() }
    }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(agent.sortedMessages) { message in
                        AgentMessageRow(message: message, agent: agent)
                            .id(message.uuid)
                    }
                    if app.agents.isRunning(agent), agent.sortedMessages.last?.role != .agent || agent.sortedMessages.last?.body.isEmpty == true {
                        TypingIndicator(color: agent.color.color)
                            .id("typing")
                    }
                    if agent.sortedMessages.filter({ $0.role == .user }).isEmpty, !agent.prompts.isEmpty {
                        suggestions
                    }
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: agent.sortedMessages.last?.body) {
                if let last = agent.sortedMessages.last { proxy.scrollTo(last.uuid, anchor: .bottom) }
            }
            .onChange(of: app.agents.isRunning(agent)) {
                withMotion(.snappy) { proxy.scrollTo("typing", anchor: .bottom) }
            }
        }
    }

    private var suggestions: some View {
        FlowRow(spacing: 8) {
            ForEach(agent.prompts, id: \.self) { prompt in
                Button { send(prompt) } label: {
                    Text(prompt)
                        .appFont(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(agent.color.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(agent.color.color.opacity(0.1), in: Capsule())
                        .overlay { Capsule().strokeBorder(agent.color.color.opacity(0.25)) }
                }
                .buttonStyle(.plain)
                .disabled(!app.agents.canRun(agent) || app.agents.isRunning(agent))
            }
        }
        .padding(.leading, 44)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(app.agents.canRun(agent) ? "Message \(agent.name)" : "\(app.agents.provider(for: agent).shortTitle) isn't set up yet", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .fontRole(.data)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .disabled(!app.agents.canRun(agent))
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .appFont(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(canSend ? agent.color.color : Theme.tertiaryText, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
            .padding(6)
        }
        .glassSurface(.rect(cornerRadius: 18))
        .frame(maxWidth: 760)
        .padding(16)
    }

    private var canSend: Bool {
        app.agents.canRun(agent) && !app.agents.isRunning(agent) && !ColonyText.trimmed(draft).isEmpty
    }

    private func send(_ text: String) {
        guard app.agents.canRun(agent), !app.agents.isRunning(agent), !ColonyText.trimmed(text).isEmpty else { return }
        app.agents.send(text, to: agent)
        draft = ""
        focused = true
    }
}

private struct AgentMessageRow: View {
    @Environment(\.modelContext) private var context
    let message: AgentMessage
    let agent: Agent

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .top, spacing: 12) {
                Spacer(minLength: 60)
                Text(message.body)
                    .appFont(.body)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.raised, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke) }
            }
            .fontRole(.data)
            .contextMenu { copy }
        case .agent:
            if !message.body.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    AgentFace(color: agent.color.color, size: 30, seed: agent.name.count)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(agent.name).appFont(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(message.createdAt, format: .dateTime.hour().minute())
                                .appFont(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Text(Self.markdown(message.body))
                            .appFont(.body)
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                }
                .fontRole(.data)
                .contextMenu { copy }
            }
        case .action:
            let isQuestion = message.symbol == "hand.raised.fill"
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: message.symbol.isEmpty ? "bolt.fill" : message.symbol)
                    .appFont(.system(size: 12))
                    .foregroundStyle(isQuestion ? ColonyColor.orange.color : agent.color.color)
                    .frame(width: 16)
                Text(message.body)
                    .appFont(.system(size: isQuestion ? 13.5 : 12.5, weight: isQuestion ? .medium : .regular))
                    .foregroundStyle(isQuestion ? Theme.text : Theme.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((isQuestion ? ColonyColor.orange.color : agent.color.color).opacity(isQuestion ? 0.1 : 0.06), in: .rect(cornerRadius: 9, style: .continuous))
            .padding(.leading, 42)
            .accessibilityLabel(isQuestion ? "\(agent.name) asks: \(message.body)" : "\(agent.name) did: \(message.body)")
        case .notice:
            Label(message.body, systemImage: "info.circle")
                .appFont(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.leading, 42)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var copy: some View {
        Button("Copy", systemImage: "doc.on.doc") {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.body, forType: .string)
            #else
            UIPasteboard.general.string = message.body
            #endif
        }
        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(message) }
    }

    /// Inline Markdown (bold, italics, code, links); falls back to plain text.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct TypingIndicator: View {
    let color: Color
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: Capsule())
        .padding(.leading, 42)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(280))
                withMotion(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("Thinking")
    }
}

/// Right-hand panel: the agent's AGENT.md, read-only, with its tools and schedule.
private struct AgentInspector: View {
    @Environment(AppModel.self) private var app
    let agent: Agent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AgentCard(definition: agent.definition)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Instructions")
                        .appFont(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Text(agent.instructions)
                        .appFont(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let last = agent.lastRunAt {
                    Label("Last ran \(last.formatted(.relative(presentation: .named)))", systemImage: "clock.arrow.circlepath")
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Button("Edit AGENT.md…") { app.present(.editAgent(agent.uuid)) }
                    .buttonStyle(.dialogSecondary)
            }
            .padding(16)
        }
        .background(Theme.sidebar)
    }
}

private extension View {
    /// A trailing inspector on Mac and iPad; a sheet on visionOS, which has no inspector.
    @ViewBuilder
    func agentInspector<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(visionOS)
        sheet(isPresented: isPresented) { content().frame(minWidth: 420, minHeight: 520) }
        #else
        inspector(isPresented: isPresented) {
            content().inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        #endif
    }
}

/// AGENT.md for the file exporter.
struct AgentFile: FileDocument {
    static let type = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [type, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
