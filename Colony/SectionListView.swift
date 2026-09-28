//
//  SectionListView.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct SectionListView: View {
    @Binding var store: WorkspaceStore
    let isSidebarCollapsed: Bool
    @State private var channelSearchText = ""
    @State private var contactSearchText = ""

    private var selectedSection: ColonySection {
        store.selectedSection ?? .home
    }

    private var filteredChannels: [ColonyChannel] {
        let searchText = channelSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else {
            return store.channels
        }

        return store.channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(searchText) ||
            channel.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var favoriteChannels: [ColonyChannel] {
        filteredChannels.filter { $0.kind == .channel && ["founders", "product"].contains($0.name) }
    }

    private var teamChannels: [ColonyChannel] {
        filteredChannels.filter { $0.kind == .channel && !["founders", "product"].contains($0.name) }
    }

    private var directMessages: [ColonyChannel] {
        filteredChannels.filter { $0.kind == .directMessage }
    }

    private var filteredContacts: [ColonyContact] {
        let searchText = contactSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else {
            return store.contacts
        }

        return store.contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(searchText) ||
            contact.company.localizedCaseInsensitiveContains(searchText) ||
            contact.stage.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: $store.selectedChannelID) {
            Section {
                Color.clear
                    .frame(height: topInset)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            switch selectedSection {
            case .home:
                Section("Today") {
                    ForEach(store.updates) { update in
                        UpdateRow(update: update)
                    }
                }
            case .messages:
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search chats", text: $channelSearchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .listRowSeparator(.hidden)

                if !favoriteChannels.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteChannels) { channel in
                            ChannelRow(
                                channel: channel,
                                isSelected: store.selectedChannelID == channel.id,
                                accentColor: store.selectedTheme.accentColor
                            )
                            .tag(channel.id)
                        }
                    }
                }

                Section("Channels") {
                    ForEach(teamChannels) { channel in
                        ChannelRow(
                            channel: channel,
                            isSelected: store.selectedChannelID == channel.id,
                            accentColor: store.selectedTheme.accentColor
                        )
                        .tag(channel.id)
                    }

                    if filteredChannels.isEmpty {
                        Text("No chats found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !directMessages.isEmpty {
                    Section("People") {
                        ForEach(directMessages) { channel in
                            ChannelRow(
                                channel: channel,
                                isSelected: store.selectedChannelID == channel.id,
                                accentColor: store.selectedTheme.accentColor
                            )
                            .tag(channel.id)
                        }
                    }
                }
            case .work:
                EmptyView()
            case .crm:
                SearchHeader(
                    title: "CRM",
                    systemImage: "person.crop.rectangle.stack",
                    placeholder: "Search accounts",
                    text: $contactSearchText
                )

                ForEach(WorkspaceStore.contactStages, id: \.self) { stage in
                    let stageContacts = filteredContacts.filter { $0.stage == stage }

                    if !stageContacts.isEmpty {
                        Section(stage) {
                            ForEach(stageContacts) { contact in
                                ContactNavigatorRow(
                                    contact: contact,
                                    isSelected: store.selectedContact?.id == contact.id,
                                    accentColor: store.selectedTheme.accentColor
                                ) {
                                    store.selectedContactID = contact.id
                                }
                            }
                        }
                    }
                }

                if filteredContacts.isEmpty {
                    Section {
                        EmptyNavigatorRow(title: "No accounts found", systemImage: "tray")
                    }
                }
            case .settings:
                Section("Admin") {
                    ForEach(WorkspaceSettingsTab.allCases) { tab in
                        SettingsNavigatorRow(
                            tab: tab,
                            isSelected: store.selectedSettingsTab == tab,
                            accentColor: store.selectedTheme.accentColor
                        ) {
                            store.selectedSettingsTab = tab
                        }
                    }
                }
            }
        }
        .navigationTitle("")
#if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
#else
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    private var topInset: CGFloat {
        isSidebarCollapsed ? 20 : 0
    }
}

private struct SearchHeader: View {
    let title: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .listRowSeparator(.hidden)
    }
}

private struct TaskNavigatorRow: View {
    let task: ColonyTask
    let isSelected: Bool
    let accentColor: Color
    let select: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.status.systemImage)
                .foregroundStyle(task.status.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("\(task.owner) · \(task.dueDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(task.priority)
                .font(.caption.weight(.semibold))
                .foregroundStyle(task.priority == "High" ? .orange : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(isSelected ? accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: select)
    }
}

private struct ContactNavigatorRow: View {
    let contact: ColonyContact
    let isSelected: Bool
    let accentColor: Color
    let select: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(contact.color.color.gradient)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(contact.initials)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(contact.company)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? accentColor : Color.secondary.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(isSelected ? accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: select)
    }
}

private struct SettingsNavigatorRow: View {
    let tab: WorkspaceSettingsTab
    let isSelected: Bool
    let accentColor: Color
    let select: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.systemImage)
                .foregroundStyle(isSelected ? accentColor : .secondary)
                .frame(width: 22)

            Text(tab.sidebarTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(isSelected ? accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: select)
    }
}

private struct EmptyNavigatorRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }
}
