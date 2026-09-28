//
//  WorkspaceDetailView.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct WorkspaceDetailView: View {
    @Binding var store: WorkspaceStore
    @State private var creationSheet: WorkspaceCreationSheet?

    private var section: ColonySection {
        store.selectedSection ?? .home
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: store.appearancePreferences.density.contentSpacing) {
                switch section {
                case .home:
                    HomeOverview(store: store) { sheet in
                        creationSheet = sheet
                    }
                case .messages:
                    ChannelDetail(store: $store, channel: store.activeChannel)
                case .work:
                    WorkOverview(store: $store) { category in
                        creationSheet = .task(category)
                    }
                case .crm:
                    CRMOverview(store: $store)
                case .settings:
                    SettingsOverview(store: $store)
                }
            }
            .padding(.horizontal, store.appearancePreferences.density.contentPadding)
            .padding(.top, detailTopPadding)
            .padding(.bottom, store.appearancePreferences.density.contentPadding)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(.background)
        .navigationTitle("")
#if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
#else
        .toolbar(.hidden, for: .navigationBar)
#endif
        .sheet(item: $creationSheet) { sheet in
            switch sheet {
            case .update:
                UpdateCreationView(store: $store)
            case .channel:
                ChannelCreationView(store: $store)
            case .task(let category):
                TaskCreationView(store: $store, initialCategory: category)
            case .contact:
                ContactCreationView(store: $store)
            case .invite:
                InviteCreationView(store: $store)
            }
        }
    }

    private var detailTopPadding: CGFloat {
#if os(macOS)
        store.appearancePreferences.density.contentPadding + 28
#else
        store.appearancePreferences.density.contentPadding
#endif
    }
}

enum WorkspaceCreationSheet: Identifiable {
    case update
    case channel
    case task(String?)
    case contact
    case invite

    init(section: ColonySection) {
        switch section {
        case .home:
            self = .update
        case .messages:
            self = .channel
        case .work:
            self = .task(nil)
        case .crm:
            self = .contact
        case .settings:
            self = .invite
        }
    }

    var id: String {
        switch self {
        case .update:
            return "update"
        case .channel:
            return "channel"
        case .task(let category):
            return "task-\(category ?? "default")"
        case .contact:
            return "contact"
        case .invite:
            return "invite"
        }
    }
}
