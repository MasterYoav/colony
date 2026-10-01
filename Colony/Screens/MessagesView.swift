//
//  MessagesView.swift
//  Colony
//
//  Channels and messages are stored in the private iCloud database, so a thread
//  written on the Mac is on the iPhone moments later.
//

import SwiftData
import SwiftUI

struct MessagesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Channel.sortIndex) private var channelsEverywhere: [Channel]
    private var channels: [Channel] { channelsEverywhere.inWorkspace() }
    let channelID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            channelList
                .frame(width: 240)
                .background(Theme.sidebar)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            if let channel = selected {
                ChannelThread(channel: channel)
                    .id(channel.uuid)
            } else {
                EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "No channels", message: "Create a channel to start a conversation.", actionTitle: "New channel") {
                    app.present(.newChannel)
                }
            }
        }
        .navigationTitle(selected.map { "#\($0.name)" } ?? "Messages")
    }

    private var selected: Channel? {
        if let channelID, let match = channels.first(where: { $0.uuid == channelID }) { return match }
        return channels.first
    }

    private var channelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Channels").appFont(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button { app.present(.newChannel) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityLabel("New channel")
            }
            .padding(.leading, max(16, SidebarMetrics.titleBarLeading(collapsed: app.preferences.isSidebarCollapsed)))
            .padding(.trailing, 12)
            #if os(macOS)
            // Same line as the traffic lights and the sidebar toggle (centre y 16).
            .frame(height: 32)
            .padding(.bottom, 8)
            #else
            .padding(.top, 22)
            .padding(.bottom, 10)
            #endif

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(channels) { channel in
                        SidebarRow(
                            symbol: channel.symbol,
                            title: channel.name,
                            count: channel.unreadCount,
                            isSelected: channel.uuid == selected?.uuid
                        ) {
                            app.go(.messages(channel: channel.uuid))
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

struct ChannelThread: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let channel: Channel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: channel.symbol).foregroundStyle(Theme.secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name).appFont(.headline).foregroundStyle(Theme.text)
                    if !channel.topic.isEmpty {
                        Text(channel.topic).appFont(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                ShareLink(item: transcript, subject: Text("#\(channel.name)")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .help("Share transcript")
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) { SidebarDivider() }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(channel.sortedMessages) { message in
                            MessageBubble(message: message)
                                .id(message.uuid)
                        }
                    }
                    .padding(22)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: channel.messages?.count) {
                    if let last = channel.sortedMessages.last { withAnimation { proxy.scrollTo(last.uuid, anchor: .bottom) } }
                }
            }

            composer
        }
        .onAppear { WorkspaceActions(context: context).markRead(channel) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message #\(channel.name)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .fontRole(.data)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .appFont(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(ColonyText.trimmed(draft).isEmpty ? Theme.tertiaryText : ColonyColor.blue.color, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(ColonyText.trimmed(draft).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
            .padding(6)
        }
        .glassSurface(.rect(cornerRadius: 18))
        .padding(16)
    }

    private func send() {
        guard WorkspaceActions(context: context).send(draft, to: channel, as: app.preferences.displayName) != nil else { return }
        draft = ""
        focused = true
    }

    private var transcript: String {
        channel.sortedMessages.map { "[\($0.createdAt.formatted(date: .abbreviated, time: .shortened))] \($0.authorName): \($0.body)" }.joined(separator: "\n")
    }
}

struct MessageBubble: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    let message: Message
    @State private var isPinned = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isMine {
                ProfileAvatar(size: 32)
            } else {
                AvatarView(name: message.authorName, color: ColonyColor.purple.color, size: 32)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(message.authorName).appFont(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(message.createdAt, format: .dateTime.hour().minute())
                        .appFont(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                Text(message.body)
                    .appFont(.body)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            ReactionToggle(isOn: $isPinned, systemImage: "pin", size: 13, style: .init(isContained: false))
                .opacity(isPinned ? 1 : 0.55)
                .accessibilityLabel(isPinned ? "Unpin message" : "Pin message")
        }
        .fontRole(.data)
        .contextMenu {
            Button("Delete message", systemImage: "trash", role: .destructive) {
                withMotion(.snappy(duration: 0.2)) { WorkspaceActions(context: context).delete(message) }
            }
        }
        .onAppear { isPinned = message.isPinned }
        .onChange(of: isPinned) { message.isPinned = isPinned }
    }
}
