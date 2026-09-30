//
//  ColonyApp.swift
//  Colony
//

import SwiftData
import SwiftUI

@main
struct ColonyApp: App {
    private let container: ModelContainer
    @State private var app: AppModel

    init() {
        let (container, mode) = CloudStore.makeContainer()
        self.container = container
        // Tests get throwaway preferences so they never touch the user's real iCloud/defaults.
        let preferences = CloudStore.isRunningForTests
            ? CloudPreferences(useICloud: false, defaults: UserDefaults(suiteName: "colony-test-host-\(UUID())") ?? .standard)
            : CloudPreferences()
        _app = State(initialValue: AppModel(preferences: preferences, iCloud: ICloudStatus(mode: mode)))
    }

    var body: some Scene {
        #if os(macOS)
        // A single main window. All UI state (dialogs, palette) lives in one AppModel,
        // so a second window would mirror it and fight over keyboard focus.
        Window("Colony", id: "main") {
            root
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            // Replaces "New Window" (⌘N) with Colony's own create commands.
            CommandGroup(replacing: .newItem) {
                Button("New Task") { app.present(.newTask(project: nil, list: nil)) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Project") { app.present(.newProject) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Channel") { app.present(.newChannel) }
            }
            CommandGroup(after: .sidebar) {
                Button("Command Center…") { app.toggleCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
                Button(app.preferences.isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar") {
                    app.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
        #else
        WindowGroup {
            root
        }
        .modelContainer(container)
        #endif
    }

    private var root: some View {
        RootView()
            .environment(app)
            .preferredColorScheme(app.preferences.appearance.colorScheme)
            // Default font for plain Text; must sit inside the typefaces environment.
            .appFont(.body)
            .environment(\.appTypefaces, AppTypefaces(
                ui: InstalledFonts.available(app.preferences.uiFontFamily),
                data: InstalledFonts.available(app.preferences.dataFontFamily)
            ))
            .task {
                guard !CloudStore.isRunningForTests else { return }
                StarterContent.seedIfNeeded(context: container.mainContext, preferences: app.preferences)
                app.nowPlaying.start()
            }
    }
}
