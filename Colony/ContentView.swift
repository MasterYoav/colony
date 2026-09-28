//
//  ContentView.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var store = WorkspacePersistence.load()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    private let sidebarMinimumWidth: CGFloat = 200
    private let sidebarIdealWidth: CGFloat = 200
    private let sidebarMaximumWidth: CGFloat = 200

    var body: some View {
        splitView
        .tint(store.selectedTheme.accentColor)
#if os(macOS)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .overlay(alignment: .topLeading) {
            TrafficLightGlassBackdrop()
                .opacity(showsTrafficLightGlass ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: columnVisibility)
                .padding(.leading, 10)
                .padding(.top, -40)
                .allowsHitTesting(false)
        }
#endif
#if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .onAppear {
            updateColumnVisibility(for: store.selectedSection)
        }
        .onChange(of: store.selectedSection) { _, selectedSection in
            updateColumnVisibility(for: selectedSection)
        }
        .onChange(of: store) { _, updatedStore in
            WorkspacePersistence.save(updatedStore)
        }
    }

    @ViewBuilder
    private var splitView: some View {
        if store.selectedSection == .work {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                WorkspaceDetailView(store: $store)
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } content: {
                SectionListView(store: $store, isSidebarCollapsed: isSidebarCollapsed)
            } detail: {
                WorkspaceDetailView(store: $store)
            }
        }
    }

    private var sidebar: some View {
        SidebarView(store: $store)
            .frame(minWidth: sidebarMinimumWidth)
            .navigationSplitViewColumnWidth(
                min: sidebarMinimumWidth,
                ideal: sidebarIdealWidth,
                max: sidebarMaximumWidth
            )
    }

    private func updateColumnVisibility(for section: ColonySection?) {
        columnVisibility = .all
    }

#if os(macOS)
    private var showsTrafficLightGlass: Bool {
        isSidebarCollapsed
    }
#endif

    private var isSidebarCollapsed: Bool {
        columnVisibility != .all
    }
}

#if os(macOS)
private struct TrafficLightGlassBackdrop: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(width: 80, height: 28)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
