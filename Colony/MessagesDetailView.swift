//
//  MessagesDetailView.swift
//  Colony
//
//  Created by Yoav Peretz on 18/06/2026.
//

import SwiftUI

struct ChannelDetail: View {
    @Binding var store: WorkspaceStore
    let channel: ColonyChannel
    @State private var messageSearchText = ""

    private var filteredMessages: [ColonyMessage] {
        let query = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return channel.messages
        }

        return channel.messages.filter { message in
            message.author.localizedCaseInsensitiveContains(query) ||
            message.body.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChatHeader(
                channel: channel,
                searchText: $messageSearchText,
                accentColor: store.selectedTheme.accentColor
            )

            Divider()

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    ChatDateDivider(label: "Today")

                    if filteredMessages.isEmpty {
                        EmptyChatSearchState(query: messageSearchText)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(filteredMessages) { message in
                            ChatMessageRow(
                                message: message,
                                isSearchMatch: !messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    ChatComposer(
                        text: $store.messageText,
                        channelName: channel.name,
                        accentColor: store.selectedTheme.accentColor
                    ) {
                        store.sendMessage(to: channel.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                ChannelInfoPanel(
                    channel: channel,
                    matchingMessages: filteredMessages,
                    searchText: messageSearchText,
                    members: store.members,
                    accentColor: store.selectedTheme.accentColor
                )
                .frame(width: 248)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }
}

private struct ChatHeader: View {
    let channel: ColonyChannel
    @Binding var searchText: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "number")
                            .foregroundStyle(accentColor)

                        Text(channel.name)
                            .font(.title2.weight(.semibold))
                    }

                    Text(channel.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Label("12 online", systemImage: "person.2")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())

                    Button {
                    } label: {
                        Image(systemName: "phone")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)

                    Button {
                    } label: {
                        Image(systemName: "video")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)

                    Button {
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search messages in #\(channel.name)", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
        }
        .padding(18)
    }
}

private struct ChannelInfoPanel: View {
    let channel: ColonyChannel
    let matchingMessages: [ColonyMessage]
    let searchText: String
    let members: [WorkspaceMember]
    let accentColor: Color

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("About #\(channel.name)")
                    .font(.headline)

                Text(channel.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ChannelInfoStat(label: "Messages", value: "\(channel.messages.count)", systemImage: "bubble.left.and.bubble.right", color: accentColor)
                ChannelInfoStat(label: "Unread", value: "\(channel.unreadCount)", systemImage: "circle.fill", color: .orange)
                ChannelInfoStat(label: "Members", value: "\(members.count)", systemImage: "person.2", color: .green)
                if isSearching {
                    ChannelInfoStat(label: "Matches", value: "\(matchingMessages.count)", systemImage: "magnifyingglass", color: .purple)
                }
            }

            if isSearching {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Search results")
                        .font(.subheadline.weight(.semibold))

                    if matchingMessages.isEmpty {
                        Text("No messages match this search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matchingMessages.prefix(3)) { message in
                            ChannelSearchResultRow(message: message)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("People")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button {
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(accentColor)
                }

                ForEach(members.prefix(4)) { member in
                    ChannelMemberRow(member: member)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button {
                } label: {
                    Label("Pinned items", systemImage: "pin")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)

                Button {
                } label: {
                    Label("Channel settings", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.opacity(0.25))
    }
}

private struct ChannelInfoStat: View {
    let label: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct ChannelMemberRow: View {
    let member: WorkspaceMember

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(member.color.color.gradient)
                .frame(width: 30, height: 30)
                .overlay {
                    Text(member.initials)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(member.role.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

private struct ChatDateDivider: View {
    let label: String

    var body: some View {
        HStack {
            Rectangle()
                .fill(.separator.opacity(0.55))
                .frame(height: 1)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())

            Rectangle()
                .fill(.separator.opacity(0.55))
                .frame(height: 1)
        }
    }
}

private struct ChatMessageRow: View {
    let message: ColonyMessage
    let isSearchMatch: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(message.authorColor.color.gradient)
                .frame(width: 38, height: 38)
                .overlay {
                    Text(String(message.author.prefix(1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(message.author)
                        .font(.subheadline.weight(.semibold))

                    Text(message.time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ReactionPill(label: "👍", count: 3)
                    ReactionPill(label: "👀", count: 2)
                    Button {
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isSearchMatch ? 10 : 0)
        .background(isSearchMatch ? Color.yellow.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ChannelSearchResultRow: View {
    let message: ColonyMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(message.authorColor.color.gradient)
                .frame(width: 24, height: 24)
                .overlay {
                    Text(String(message.author.prefix(1)))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(message.author)
                        .font(.caption.weight(.semibold))

                    Text(message.time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct EmptyChatSearchState: View {
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No messages found")
                .font(.headline)

            Text(query)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ReactionPill: View {
    let label: String
    let count: Int

    var body: some View {
        Text("\(label) \(count)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct ChatComposer: View {
    @Binding var text: String
    let channelName: String
    let accentColor: Color
    let send: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Message #\(channelName)", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .padding(14)

            Divider()

            HStack(spacing: 8) {
                Button {
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)

                Button {
                } label: {
                    Image(systemName: "face.smiling")
                }
                .buttonStyle(.borderless)

                Button {
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: send) {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(composerBorderColor, lineWidth: 1)
        }
    }

    private var composerBorderColor: Color {
        canSend ? accentColor.opacity(0.7) : Color.secondary.opacity(0.25)
    }
}
