//
//  MenuBarPanel.swift
//  Colony
//
//  Mac only: the optional menu-bar item that keeps Colony running after its window
//  closes (Settings › Notifications › Keep running in the menu bar), and Open at Login.
//  While it's there, snoozes, completions from alerts and changes synced from other
//  devices update notifications and Calendar straight away.
//

#if os(macOS)
import ServiceManagement
import SwiftData
import SwiftUI

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]

    private var due: [TaskItem] {
        tasks.filter { !$0.isDone && SmartList.today.includes($0) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        let today = due
        Section(today.isEmpty ? "Nothing due today" : "Due today") {
            ForEach(today.prefix(12)) { task in
                Button {
                    WorkspaceActions(context: context).setStatus(.done, for: task)
                    app.syncReminder(for: task)
                    try? context.save()
                } label: {
                    Text(label(task))
                }
                .help("Mark as completed")
            }
        }
        Divider()
        Button("New Task…") { open(then: { app.present(.newTask(project: nil, list: nil)) }) }
        Button("Open Colony") { open(then: { app.go(.tasks) }) }
            .keyboardShortcut("o")
        Divider()
        Button("Quit Colony") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func label(_ task: TaskItem) -> String {
        var text = "○  " + task.title
        if let due = task.dueDate, task.dueHasTime { text += "  ·  " + DueText.time(due) }
        if task.isOverdue { text += "  ·  overdue" }
        return text
    }

    private func open(then action: @escaping () -> Void) {
        openWindow(id: "main")
        NSApp.activate()
        action()
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Shown as the switch snapping back; System Settings › Login Items has the details.
        }
    }
}
#endif
