//
//  ContentView.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var store = WorkspacePersistence.load()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: $store)
        } content: {
            SectionListView(store: $store)
        } detail: {
            WorkspaceDetailView(store: $store)
        }
        .tint(store.selectedTheme.accentColor)
#if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .onChange(of: store) { _, updatedStore in
            WorkspacePersistence.save(updatedStore)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
