//
//  SectionListView.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct SectionListView: View {
    @Binding var store: WorkspaceStore
    @State private var channelSearchText = ""

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

    var body: some View {
        List(selection: $store.selectedChannelID) {
            switch selectedSection {
            case .home:
                Section("Today") {
                    ForEach(store.updates) { update in
                        UpdateRow(update: update)
                    }
                }
            case .messages:
                Section {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right")
                        .font(.headline)

                    TextField("Search chats", text: $channelSearchText)
                        .textFieldStyle(.roundedBorder)
                }
                .listRowSeparator(.hidden)

                Section("Chats") {
                    ForEach(filteredChannels) { channel in
                        ChannelRow(channel: channel)
                            .tag(channel.id)
                    }

                    if filteredChannels.isEmpty {
                        Text("No chats found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .work:
                Section("Projects") {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task)
                    }
                }
            case .crm:
                Section("Relationships") {
                    ForEach(store.contacts) { contact in
                        ContactRow(contact: contact)
                    }
                }
            case .settings:
                Section("Admin") {
                    Label("Members", systemImage: "person.2")
                    Label("Authentication", systemImage: "lock.shield")
                    Label("Self-hosting", systemImage: "server.rack")
                    Label("Appearance", systemImage: "paintpalette")
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
}
