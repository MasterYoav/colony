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
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.preferences.appearance.colorScheme)
                .task {
                    guard !CloudStore.isRunningForTests else { return }
                    StarterContent.seedIfNeeded(context: container.mainContext, preferences: app.preferences)
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Task") { app.sheet = .newTask(project: nil, list: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Project") { app.sheet = .newProject }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Channel") { app.sheet = .newChannel }
            }
        }
        #endif
    }
}
