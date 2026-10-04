//
//  PhoneChats.swift
//  Colony
//
//  Channel and agent conversations on iPhone, built like Messages: the name in the
//  navigation bar, bubbles (yours on the right in colour), days as small centred
//  labels, and a glass composer pinned above the keyboard. No desktop header rows.
//

#if os(iOS)
import SwiftData
import SwiftUI

// MARK: - Shared pieces

/// "Today", "Yesterday", "Monday" — centred and quiet, as in Messages.
private struct DayLabel: View {
    let date: Date

    var body: some View {
        Text(Calendar.current.isDateInToday(date) ? "Today" : DueText.day(date))
            .appFont(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

private struct Bubble: View {
    let text: AttributedString
    let isMine: Bool
    let tint: Color

    var body: some View {
        Text(text)
            .appFont(.system(size: 17))
            .foregroundStyle(isMine ? .white : .primary)
            .tint(isMine ? .white : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isMine ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Phone.card),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The text field and send button, floating in glass above the keyboard.
private struct Composer: View {
    let placeholder: String
    @Binding var text: String
    let tint: Color
    var isEnabled = true
    let send: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let canSend = isEnabled && !ColonyText.trimmed(text).isEmpty
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .appFont(.system(size: 17))
                .lineLimit(1...6)
                .focused($focused)
                .disabled(!isEnabled)
                .padding(.leading, 16)
                .padding(.vertical, 11)
            if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .appFont(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(tint.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(5)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Send")
            } else {
                Color.clear.frame(width: 12, height: 44)
            }
        }
        .animation(.snappy(duration: 0.2), value: canSend)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private func copyItem(_ text: String) -> some View {
    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
}

// MARK: - Channel

struct PhoneChannelChat: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable var channel: Channel
    @State private var draft = ""

    var body: some View {
        let messages = channel.sortedMessages
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if messages.isEmpty {
                        ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right", description: Text(channel.topic.isEmpty ? "Say something to start #\(channel.name)." : channel.topic))
                            .padding(.top, 80)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.uuid) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        if previous.map({ !Calendar.current.isDate($0.createdAt, inSameDayAs: message.createdAt) }) ?? true {
                            DayLabel(date: message.createdAt).padding(.top, 10)
                        }
                        let showsAuthor = !message.isMine && (previous?.authorName != message.authorName || previous?.isMine == true)
                        row(message, showsAuthor: showsAuthor)
                            .id(message.uuid)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                if let last = messages.last { withMotion(.snappy) { proxy.scrollTo(last.uuid, anchor: .bottom) } }
            }
        }
        .background(Phone.canvas)
        .safeAreaInset(edge: .bottom) {
            Composer(placeholder: "Message #\(channel.name)", text: $draft, tint: ColonyColor.blue.color, send: send)
        }
        .navigationTitle("#\(channel.name)")
        .navigationSubtitle(channel.topic)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: transcript, subject: Text("#\(channel.name)")) { Label("Share Conversation", systemImage: "square.and.arrow.up") }
                    Button("Mark as Read", systemImage: "checkmark.message") { WorkspaceActions(context: context).markRead(channel) }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
            }
        }
        .onAppear { WorkspaceActions(context: context).markRead(channel) }
        .onChange(of: messages.count) { WorkspaceActions(context: context).markRead(channel) }
    }

    @ViewBuilder
    private func row(_ message: Message, showsAuthor: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine { Spacer(minLength: 56) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                if showsAuthor {
                    Text(message.authorName)
                        .appFont(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                }
                Bubble(text: AttributedString(message.body), isMine: message.isMine, tint: ColonyColor.blue.color)
            }
            if !message.isMine { Spacer(minLength: 56) }
        }
        .contextMenu {
            copyItem(message.body)
            Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { WorkspaceActions(context: context).delete(message) }
        }
    }

    private var transcript: String {
        channel.sortedMessages.map { "\($0.isMine ? "You" : $0.authorName): \($0.body)" }.joined(separator: "\n")
    }

    private func send() {
        guard WorkspaceActions(context: context).send(draft, to: channel, as: app.preferences.displayName) != nil else { return }
        draft = ""
    }
}

// MARK: - Agent

struct PhoneAgentChat: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable var agent: Agent
    @State private var draft = ""
    @State private var showsInfo = false

    var body: some View {
        let messages = agent.sortedMessages
        let running = app.agents.isRunning(agent)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    intro
                    ForEach(Array(messages.enumerated()), id: \.element.uuid) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        if previous.map({ !Calendar.current.isDate($0.createdAt, inSameDayAs: message.createdAt) }) ?? true {
                            DayLabel(date: message.createdAt)
                        }
                        row(message).id(message.uuid)
                    }
                    if running, messages.last?.role != .agent || messages.last?.body.isEmpty == true {
                        thinking.id("typing")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.body) {
                if let last = messages.last { proxy.scrollTo(last.uuid, anchor: .bottom) }
            }
            .onChange(of: running) { withMotion(.snappy) { proxy.scrollTo("typing", anchor: .bottom) } }
        }
        .background(Phone.canvas)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !app.agents.canRun(agent) { unavailable }
                if !agent.prompts.isEmpty, !running, app.agents.canRun(agent), messages.filter({ $0.role == .user }).count < 3 {
                    suggestions
                }
                Composer(
                    placeholder: app.agents.canRun(agent) ? "Message \(agent.name)" : "Not set up yet",
                    text: $draft, tint: agent.color.color,
                    isEnabled: app.agents.canRun(agent) && !running,
                    send: { send(draft) }
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showsInfo = true } label: {
                    VStack(spacing: 0) {
                        Text(agent.name).appFont(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                        Text(running ? "Thinking…" : statusLine)
                            .appFont(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(agent.name), \(running ? "thinking" : statusLine). Show details.")
            }
            if running {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stop", systemImage: "stop.fill") { app.agents.stop(agent) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(agent.schedule == nil ? "Run Now" : "Do Its Scheduled Job Now", systemImage: "play.fill") { app.agents.runNow(agent) }
                        .disabled(!app.agents.canRun(agent) || running)
                    Button("About \(agent.name)", systemImage: "info.circle") { showsInfo = true }
                    Button("Edit AGENT.md…", systemImage: "doc.text") { app.present(.editAgent(agent.uuid)) }
                    ShareLink("Share AGENT.md", item: agent.definition.markdown, subject: Text("\(agent.name) · AGENT.md"))
                    Divider()
                    AgentModelMenu(agent: agent)
                    Button(agent.isEnabled ? "Pause Schedule" : "Resume Schedule", systemImage: agent.isEnabled ? "pause.circle" : "play.circle") { agent.isEnabled.toggle() }
                        .disabled(agent.schedule == nil)
                    Button("Clear Conversation", systemImage: "eraser") { app.agents.clearHistory(agent) }
                    Divider()
                    Button("Remove Agent…", systemImage: "person.badge.minus", role: .destructive) { app.present(.deleteAgent(agent.uuid)) }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showsInfo) { PhoneAgentInfo(agent: agent) }
        .onAppear {
            agent.lastReadAt = .now
            app.agents.refreshAvailability()
        }
        .onChange(of: messages.count) { agent.lastReadAt = .now }
    }

    private var statusLine: String {
        var parts = [agent.isEnabled || agent.schedule == nil ? agent.status.title : "Paused"]
        parts.append(app.agents.provider(for: agent).shortTitle)
        return parts.joined(separator: " · ")
    }

    // A small hello at the top, like a contact card in Messages.
    private var intro: some View {
        VStack(spacing: 8) {
            AgentFace(color: agent.color.color, size: 64, seed: agent.name.count)
                .padding(8)
                .background(agent.color.color.opacity(0.18), in: Circle())
            Text(agent.name).appFont(.system(size: 22, weight: .bold, design: .rounded))
            if let schedule = agent.schedule {
                Label(schedule.label, systemImage: "clock")
                    .appFont(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Phone.card, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private func row(_ message: AgentMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Bubble(text: AttributedString(message.body), isMine: true, tint: agent.color.color)
            }
            .contextMenu { copyItem(message.body) }
        case .agent:
            if !message.body.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    AgentFace(color: agent.color.color, size: 28, seed: agent.name.count)
                    Bubble(text: Self.markdown(message.body), isMine: false, tint: agent.color.color)
                    Spacer(minLength: 40)
                }
                .contextMenu {
                    copyItem(message.body)
                    Button("Delete", systemImage: "trash", role: .destructive) { context.delete(message) }
                }
            }
        case .action:
            let isQuestion = message.symbol == "hand.raised.fill"
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: message.symbol.isEmpty ? "bolt.fill" : message.symbol)
                    .appFont(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isQuestion ? ColonyColor.orange.color : agent.color.color)
                Text(message.body)
                    .appFont(.system(size: 15, weight: isQuestion ? .semibold : .regular))
                    .foregroundStyle(isQuestion ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((isQuestion ? ColonyColor.orange.color : agent.color.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.leading, 36)
            .accessibilityLabel(isQuestion ? "\(agent.name) asks: \(message.body)" : "\(agent.name) did: \(message.body)")
        case .notice:
            Text(message.body)
                .appFont(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
        }
    }

    private var thinking: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AgentFace(color: agent.color.color, size: 28, seed: agent.name.count)
            HStack(spacing: 5) {
                ForEach(0..<3) { _ in Circle().fill(.secondary).frame(width: 7, height: 7) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Phone.card, in: Capsule())
            .phaseAnimator([0.4, 1]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.6) }
        }
        .accessibilityLabel("\(agent.name) is thinking")
    }

    /// Suggestions as a row of glass chips just above the field.
    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(agent.prompts, id: \.self) { prompt in
                    Button { send(prompt) } label: {
                        Label(prompt, systemImage: "sparkle")
                            .appFont(.system(size: 15, weight: .medium))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var unavailable: some View {
        let provider = app.agents.provider(for: agent)
        return HStack(spacing: 10) {
            Image(systemName: provider.symbol).foregroundStyle(ColonyColor.orange.color)
            Text(app.agents.unavailableMessage(for: provider))
                .appFont(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            Button("AI Settings") { app.openSettings(.ai) }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func send(_ text: String) {
        guard app.agents.canRun(agent), !app.agents.isRunning(agent), !ColonyText.trimmed(text).isEmpty else { return }
        app.agents.send(text, to: agent)
        draft = ""
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// The agent's AGENT.md as a readable card sheet: what it does, tools, schedule.
struct PhoneAgentInfo: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let agent: Agent

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        AgentFace(color: agent.color.color, size: 72, seed: agent.name.count)
                        Text(agent.name).appFont(.system(size: 24, weight: .bold, design: .rounded))
                        if !agent.summary.isEmpty {
                            Text(agent.summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Details") {
                    LabeledContent("Runs on", value: app.agents.provider(for: agent).title)
                    LabeledContent("Schedule", value: agent.schedule?.label ?? "When you ask")
                    if let last = agent.lastRunAt {
                        LabeledContent("Last ran", value: last.formatted(.relative(presentation: .named)))
                    }
                }
                Section("Tools") {
                    if agent.tools.isEmpty {
                        Text("Chat only").foregroundStyle(.secondary)
                    }
                    ForEach(agent.tools, id: \.self) { tool in
                        Label(tool.title, systemImage: tool.symbol)
                    }
                }
                Section("Instructions") {
                    Text(agent.instructions)
                        .appFont(.system(size: 15, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section {
                    Button("Edit AGENT.md…") {
                        dismiss()
                        app.present(.editAgent(agent.uuid))
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
