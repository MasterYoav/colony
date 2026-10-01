//
//  WorkspaceViews.swift
//  Colony
//
//  New workspace, Workspace settings (rename, colour) and Delete workspace dialogs, and
//  switching between workspaces.
//

import SwiftData
import SwiftUI

extension AppModel {
    /// Opens another workspace: its data, its sidebar, its home.
    func switchWorkspace(to id: String) {
        guard id != preferences.currentWorkspaceID else { return }
        sheet = nil
        withMotion(.snappy(duration: 0.25)) {
            preferences.currentWorkspaceID = id
            go(.home)
        }
    }
}

/// Square with the workspace's colour and initial: the switcher, its menu and dialogs.
struct WorkspaceBadge: View {
    let workspace: WorkspaceInfo
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(workspace.isOriginal ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(workspace.color.color.gradient))
            .frame(width: size, height: size)
            .overlay {
                if !workspace.isOriginal {
                    Text(workspace.name.prefix(1).uppercased())
                        .appFont(.system(size: size * 0.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - New workspace

struct NewWorkspaceDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dialogDismiss) private var dismiss
    @State private var name = ""
    @State private var color: ColonyColor = .green
    @State private var preset: WorkspacePreset = .everything

    private var canCommit: Bool { !ColonyText.trimmed(name).isEmpty }

    var body: some View {
        DialogFrame(
            symbol: "plus.square.on.square",
            title: "New workspace",
            description: "A blank space with its own projects, tasks, customers, channels, agents and automations. Everything syncs with iCloud."
        ) {
            DialogField(label: "Name") {
                DialogTextField(placeholder: "Personal, Side project, Acme…", text: $name, symbol: "square.grid.2x2", limit: 32, autofocus: true, onSubmit: create)
            }
            DialogField(label: "Colour") {
                ColorSwatches(selection: $color)
            }
            DialogField(label: "What's it for?", hint: "Sets which tools the sidebar shows. Change it any time in Settings › Sidebar.") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(WorkspacePreset.allCases) { item in
                        PresetCard(preset: item, isSelected: preset == item) { preset = item }
                    }
                }
            }
        } footer: {
            KeyHint(keys: ["⌘", "⏎"], label: "create workspace")
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.dialogGhost)
            Button("Create workspace", action: create)
                .buttonStyle(.dialogPrimary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit)
        }
    }

    private func create() {
        let name = ColonyText.trimmed(name)
        guard !name.isEmpty else { return }
        let workspace = WorkspaceInfo(id: UUID().uuidString, name: name, colorRaw: color.rawValue, createdAt: .now)
        app.preferences.extraWorkspaces.append(workspace)
        app.preferences.sidebarSetups[workspace.id] = preset.setup
        dismiss()
        app.switchWorkspace(to: workspace.id)
        app.show("Created \(name)", detail: "A fresh workspace. Switch back any time from its name in the sidebar.")
    }
}

/// One choice in "What's it for?": icon, title, one line.
struct PresetCard: View {
    let preset: WorkspacePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: preset.symbol)
                    .appFont(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(preset.color.color.gradient, in: .rect(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title).appFont(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(preset.detail).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.10) : Theme.surface, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Theme.stroke, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.title): \(preset.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Delete workspace

struct DeleteWorkspaceDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let workspaceID: String

    var body: some View {
        let workspace = app.preferences.workspaces.first { $0.id == workspaceID }
        ConfirmDialog(
            symbol: "trash",
            title: "Delete \(workspace?.name ?? "this workspace")?",
            message: "Its projects, tasks, customers, channels, agents and automations are deleted from all your devices. This can't be undone.",
            confirmTitle: "Delete workspace"
        ) {
            guard let workspace, !workspace.isOriginal else { return }
            app.switchWorkspace(to: WorkspaceInfo.originalID)
            WorkspaceActions(context: context).deleteWorkspaceData(workspace.id)
            try? context.save()
            app.preferences.extraWorkspaces.removeAll { $0.id == workspace.id }
            app.preferences.sidebarSetups[workspace.id] = nil
        }
    }
}

extension WorkspaceActions {
    /// Removes everything in a workspace (children cascade with their parents).
    func deleteWorkspaceData(_ id: String) {
        guard id != WorkspaceInfo.originalID else { return }
        func purge<T: PersistentModel & WorkspaceScoped>(_ type: T.Type) {
            for item in context.inWorkspace(type, id) { context.delete(item) }
        }
        purge(TaskItem.self)
        purge(Project.self)
        purge(Channel.self)
        purge(Contact.self)
        purge(ActivityEvent.self)
        purge(Agent.self)
        purge(Automation.self)
    }
}

// MARK: - New list

/// A list inside a project ("Sprint 1", "Groceries"). From the + on Tasks.
struct NewListDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    private var projects: [Project] { projectsEverywhere.inWorkspace().filter { $0.archivedAt == nil } }
    let projectID: UUID?

    @State private var name = ""
    @State private var selectedProject: UUID?
    @State private var newProjectName = ""

    /// No projects yet: the list gets a new project of its own.
    private var needsProject: Bool { projects.isEmpty }
    private var canCommit: Bool {
        !ColonyText.trimmed(name).isEmpty && (needsProject ? !ColonyText.trimmed(newProjectName).isEmpty : selectedProject != nil)
    }

    var body: some View {
        DialogFrame(symbol: "list.bullet.rectangle", title: "New list", description: "A list groups tasks inside a project, like “This week” or “Groceries”.") {
            DialogField(label: "Name") {
                DialogTextField(placeholder: "This week", text: $name, symbol: "list.bullet", limit: 40, autofocus: true, onSubmit: create)
            }
            if needsProject {
                DialogField(label: "Project", hint: "Lists live in a project. This creates your first one.") {
                    DialogTextField(placeholder: "Home, Launch, Clients…", text: $newProjectName, symbol: "folder", limit: 40, onSubmit: create)
                }
            } else {
                DialogField(label: "In project") {
                    DialogSelect(selection: $selectedProject, options: projects.map { (Optional($0.uuid), $0.name, $0.symbol) })
                }
            }
        } footer: {
            KeyHint(keys: ["⌘", "⏎"], label: "create list")
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.dialogGhost)
            Button("Create list", action: create)
                .buttonStyle(.dialogPrimary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit)
        }
        .onAppear {
            selectedProject = projectID.flatMap { id in projects.first { $0.uuid == id }?.uuid } ?? projects.first?.uuid
        }
    }

    private func create() {
        guard canCommit else { return }
        let actions = WorkspaceActions(context: context)
        let project: Project?
        if needsProject {
            project = actions.createProject(name: newProjectName, symbol: "folder.fill", color: .blue)
        } else {
            project = selectedProject.flatMap { id in projects.first { $0.uuid == id } }
        }
        guard let project, let list = actions.createList(named: name, in: project) else { return }
        try? context.save()
        if !app.isExpanded(project) { app.toggleExpanded(project) }
        dismiss()
        app.go(.list(project: project.uuid, list: list.uuid))
    }
}
