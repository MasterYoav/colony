//
//  Sheets.swift
//  Colony
//
//  Creation sheets, task detail, contacts import and the ⌘K command palette.
//

import SwiftData
import SwiftUI

private let sheetFieldStyle = FormField.Style(field: Theme.field, label: Theme.text, secondaryLabel: Theme.secondaryText, focusRing: Theme.strongStroke, height: 52, cornerRadius: 12)

/// Shared chrome: title, content, and a Swift Pieces `CommitButton` as the primary action.
struct SheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    let canCommit: Bool
    let commit: () -> Bool
    @ViewBuilder var content: () -> Content
    @State private var phase: CommitButton.Phase = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14, content: content)
            }
            CommitButton(actionTitle, phase: $phase, successTitle: "Saved", style: .init(height: 46)) {
                phase = .loading
                if commit() {
                    phase = .success
                    Task {
                        try? await Task.sleep(for: .milliseconds(650))
                        dismiss()
                    }
                } else {
                    phase = .error("Check the fields")
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .background(Theme.canvas)
        .onChange(of: canCommit, initial: true) { _, ok in
            if phase == .idle || phase == .disabled { phase = ok ? .idle : .disabled }
        }
    }
}

// MARK: - New project

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var summary = ""
    @State private var color: ColonyColor = .blue
    @State private var symbol = "folder.fill"
    @State private var lists: [String] = ["March", "April"]
    @State private var newList = ""

    private let symbols = ["folder.fill", "calendar", "doc.text.fill", "square.grid.2x2.fill", "chart.bar.fill", "creditcard.fill", "star.fill", "bolt.fill", "paintbrush.fill", "hammer.fill", "globe", "heart.fill"]

    var body: some View {
        SheetScaffold(title: "New project", actionTitle: "Create project", canCommit: !ColonyText.trimmed(name).isEmpty, commit: create) {
            FormField("Project name", text: $name, leading: Image(systemName: "folder"), limit: 40, style: sheetFieldStyle)
            FormField("Description", text: $summary, limit: 140, axis: .vertical, style: sheetFieldStyle)

            Text("Icon & color").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 12), alignment: .leading, spacing: 8) {
                ForEach(symbols, id: \.self) { s in
                    Button { symbol = s } label: {
                        ProjectGlyph(symbol: s, color: symbol == s ? color.color : Theme.tertiaryText, size: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s)
                }
                ForEach(ColonyColor.allCases) { c in
                    Button { color = c } label: {
                        Circle().fill(c.color).frame(width: 22, height: 22)
                            .overlay { if c == color { Circle().strokeBorder(Theme.text, lineWidth: 2).frame(width: 28, height: 28) } }
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.title)
                }
            }

            Text("Lists").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            FilterRail(options: lists, selection: .constant(Set(lists)), allowsMultiple: true)
            HStack {
                TextField("Add a list (e.g. Sprint 1)", text: $newList)
                    .textFieldStyle(.plain)
                    .onSubmit(addList)
                Button("Add", action: addList).buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !lists.isEmpty {
                Button("Clear lists") { lists = [] }.buttonStyle(.plain).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func addList() {
        let value = ColonyText.trimmed(newList)
        guard !value.isEmpty, !lists.contains(value) else { return }
        lists.append(value)
        newList = ""
    }

    private func create() -> Bool {
        guard let project = WorkspaceActions(context: context).createProject(name: name, symbol: symbol, color: color, summary: summary, lists: lists) else { return false }
        app.preferences.expandedProjectIDs.insert(project.uuid.uuidString)
        app.go(.project(project.uuid))
        return true
    }
}

// MARK: - New task

struct NewTaskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    let projectID: UUID?
    let listID: UUID?

    @State private var title = ""
    @State private var notes = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
    @State private var selectedProject: UUID?
    @State private var selectedList: UUID?

    var body: some View {
        SheetScaffold(title: "New task", actionTitle: "Create task", canCommit: !ColonyText.trimmed(title).isEmpty, commit: create) {
            FormField("What needs to be done?", text: $title, leading: Image(systemName: "checklist"), limit: 120, style: sheetFieldStyle)
            FormField("Notes", text: $notes, axis: .vertical, style: sheetFieldStyle)

            Text("Priority").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            GlassSegments(options: TaskPriority.allCases, selection: $priority, height: 34, label: { $0.title })

            Picker("Project", selection: $selectedProject) {
                Text("None").tag(UUID?.none)
                ForEach(projects) { Text($0.name).tag(Optional($0.uuid)) }
            }
            if let project = projects.first(where: { $0.uuid == selectedProject }), !project.sortedLists.isEmpty {
                Picker("List", selection: $selectedList) {
                    Text("None").tag(UUID?.none)
                    ForEach(project.sortedLists) { Text($0.name).tag(Optional($0.uuid)) }
                }
            }

            Toggle("Due date", isOn: $hasDue.animation())
            if hasDue {
                DatePicker("Due", selection: $due)
            }
            if app.preferences.mirrorsToReminders {
                Label("Will also appear in Apple Reminders", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onAppear {
            selectedProject = projectID ?? context.list(listID ?? UUID())?.project?.uuid
            selectedList = listID
        }
    }

    private func create() -> Bool {
        let project = selectedProject.flatMap(context.project)
        let list = selectedList.flatMap(context.list)
        guard let task = WorkspaceActions(context: context).createTask(title: title, notes: notes, priority: priority, dueDate: hasDue ? due : nil, project: project, list: list?.project?.uuid == project?.uuid ? list : nil) else { return false }
        app.syncReminder(for: task)
        return true
    }
}

// MARK: - New channel

struct NewChannelSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var topic = ""

    var body: some View {
        SheetScaffold(title: "New channel", actionTitle: "Create channel", canCommit: !ColonyText.channelSlug(name).isEmpty, commit: create) {
            FormField("Channel name", text: $name, prompt: "e.g. design-reviews", help: name.isEmpty ? nil : "#\(ColonyText.channelSlug(name))", leading: Image(systemName: "number"), limit: 40, style: sheetFieldStyle)
            FormField("Topic", text: $topic, limit: 120, style: sheetFieldStyle)
        }
    }

    private func create() -> Bool {
        guard let channel = WorkspaceActions(context: context).createChannel(name: name, topic: topic) else { return false }
        app.go(.messages(channel: channel.uuid))
        return true
    }
}

// MARK: - New contact

struct NewContactSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var company = ""
    @State private var jobTitle = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var stage: DealStage = .lead

    var body: some View {
        SheetScaffold(title: "New contact", actionTitle: "Add contact", canCommit: !ColonyText.trimmed(name).isEmpty, commit: create) {
            FormField("Full name", text: $name, leading: Image(systemName: "person"), textContentType: .name, style: sheetFieldStyle)
            FormField("Company", text: $company, leading: Image(systemName: "building.2"), textContentType: .organizationName, style: sheetFieldStyle)
            FormField("Job title", text: $jobTitle, leading: Image(systemName: "briefcase"), textContentType: .jobTitle, style: sheetFieldStyle)
            FormField("Email", text: $email, leading: Image(systemName: "envelope"), validate: { $0.isEmpty || $0.contains("@") ? nil : "Enter a valid email" }, textContentType: .emailAddress, keyboardType: .emailAddress, style: sheetFieldStyle)
            FormField("Phone", text: $phone, leading: Image(systemName: "phone"), textContentType: .telephoneNumber, keyboardType: .phonePad, style: sheetFieldStyle)
            Picker("Stage", selection: $stage) {
                ForEach(DealStage.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private func create() -> Bool {
        guard email.isEmpty || email.contains("@") else { return false }
        guard WorkspaceActions(context: context).createContact(name: name, company: company, jobTitle: jobTitle, email: email, phone: phone, stage: stage) != nil else { return false }
        app.go(.contacts)
        return true
    }
}

// MARK: - Import from Apple Contacts

struct ImportContactsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [Contact]
    @State private var candidates: [AppleContactCandidate] = []
    @State private var selection: Set<String> = []
    @State private var search = ""
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Import from Contacts").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
            }

            if !app.contacts.canRead {
                PermissionSheet(
                    systemImage: "person.crop.circle",
                    title: "Allow Contacts access",
                    message: "Colony reads your address book so you can choose who to add. Nothing is changed.",
                    benefits: [.init(symbol: "person.2", text: "Names, companies and photos"), .init(symbol: "lock", text: "Imported people sync via your iCloud")],
                    allowTitle: "Allow access",
                    request: { await app.contacts.requestAccess() },
                    onGranted: { Task { await load() } }
                )
            } else {
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else if candidates.isEmpty {
                    EmptyStateView(symbol: "person.crop.circle.badge.questionmark", title: "No contacts found", message: "Your address book is empty or access is limited.")
                } else {
                    List(filtered, selection: $selection) { person in
                        HStack(spacing: 10) {
                            AvatarView(name: person.name, color: ColonyColor.indigo.color, imageData: person.imageData, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name).font(.subheadline)
                                if !person.company.isEmpty { Text(person.company).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if importedIDs.contains(person.id) {
                                Text("Added").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(person.id)
                    }
                    #if os(iOS)
                    .environment(\.editMode, .constant(.active))
                    #endif
                    .frame(minHeight: 260)
                }

                Button {
                    importSelected()
                } label: {
                    Text(selection.isEmpty ? "Select people to import" : "Import \(selection.count) \(selection.count == 1 ? "person" : "people")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selection.isEmpty)
            }
        }
        .padding(24)
        .background(Theme.canvas)
        .task { await load() }
    }

    private var importedIDs: Set<String> { Set(existing.compactMap(\.appleContactIdentifier)) }

    private var filtered: [AppleContactCandidate] {
        let q = ColonyText.trimmed(search)
        guard !q.isEmpty else { return candidates }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.company.localizedCaseInsensitiveContains(q) }
    }

    private func load() async {
        guard app.contacts.canRead else { isLoading = false; return }
        isLoading = true
        candidates = await app.contacts.fetchAll()
        isLoading = false
    }

    private func importSelected() {
        let actions = WorkspaceActions(context: context)
        var count = 0
        for person in candidates where selection.contains(person.id) && !importedIDs.contains(person.id) {
            if actions.createContact(name: person.name, company: person.company, jobTitle: person.jobTitle, email: person.email, phone: person.phone, appleIdentifier: person.id, imageData: person.imageData) != nil {
                count += 1
            }
        }
        app.show("Imported \(count) \(count == 1 ? "person" : "people")", detail: "From Apple Contacts")
        app.go(.contacts)
        dismiss()
    }
}

// MARK: - Task detail

struct TaskDetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    @State private var confirmingDelete = false

    var body: some View {
        if let task = context.task(taskID) {
            TaskDetailForm(task: task, confirmingDelete: $confirmingDelete)
                .confirmSheet(isPresented: $confirmingDelete, inline: true, systemImage: "trash", title: "Delete task?", message: "It will be removed from all your devices.", confirmTitle: "Delete", isDestructive: true) {
                    app.reminders.removeMirror(for: task)
                    WorkspaceActions(context: context).delete(task)
                    dismiss()
                }
        } else {
            EmptyStateView(symbol: "questionmark.circle", title: "Task not found", message: "It may have been deleted on another device.", actionTitle: "Close") { dismiss() }
        }
    }
}

private struct TaskDetailForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: TaskItem
    @Binding var confirmingDelete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if let project = task.project {
                    ProjectGlyph(symbol: project.symbol, color: project.color.color, size: 18)
                    Text(task.list.map { "\(project.name) › \($0.name)" } ?? project.name)
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                Button("Done") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.defaultAction)
            }

            TextField("Title", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))

            Text("Status").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            GlassSegments(options: TaskStatus.allCases, selection: Binding(get: { task.status }, set: { WorkspaceActions(context: context).setStatus($0, for: task); app.syncReminder(for: task) }), height: 34, label: { $0.title })

            Text("Priority").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            GlassSegments(options: TaskPriority.allCases, selection: $task.priority, height: 34, label: { $0.title })

            Toggle("Due date", isOn: Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? (task.dueDate ?? .now.addingTimeInterval(86_400)) : nil }))
            if let due = task.dueDate {
                DatePicker("Due", selection: Binding(get: { due }, set: { task.dueDate = $0 }))
            }

            TextField("Notes", text: $task.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...12)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }

            if task.reminderIdentifier != nil {
                Label("Mirrored in Apple Reminders", systemImage: "checklist").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Theme.canvas)
        .onDisappear { app.syncReminder(for: task) }
    }
}

// MARK: - Command palette

struct CommandPalette: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query private var channels: [Channel]
    @Query private var contacts: [Contact]
    @State private var query = ""
    @FocusState private var focused: Bool

    struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").foregroundStyle(Theme.secondaryText)
                TextField("Type a command or search…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { results.first?.run() }
            }
            .padding(16)
            .overlay(alignment: .bottom) { SidebarDivider() }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { item in
                        Button {
                            item.run()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).frame(width: 18).foregroundStyle(Theme.icon)
                                Text(item.title).foregroundStyle(Theme.text)
                                Spacer()
                                Text(item.subtitle).font(.caption).foregroundStyle(Theme.tertiaryText)
                            }
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .background(Theme.canvas)
        .onAppear { focused = true }
        #if os(macOS)
        .frame(width: 560, height: 420)
        #endif
    }

    private func go(_ destination: Destination) -> () -> Void {
        { app.go(destination); dismiss() }
    }

    private func open(_ sheet: ActiveSheet) -> () -> Void {
        { dismiss(); Task { try? await Task.sleep(for: .milliseconds(250)); app.sheet = sheet } }
    }

    private var allItems: [Item] {
        var items: [Item] = [
            Item(id: "a-task", symbol: "plus", title: "New task", subtitle: "Action", run: open(.newTask(project: nil, list: nil))),
            Item(id: "a-project", symbol: "folder.badge.plus", title: "New project", subtitle: "Action", run: open(.newProject)),
            Item(id: "a-channel", symbol: "number", title: "New channel", subtitle: "Action", run: open(.newChannel)),
            Item(id: "a-contact", symbol: "person.crop.circle.badge.plus", title: "New contact", subtitle: "Action", run: open(.newContact)),
            Item(id: "a-import", symbol: "person.crop.rectangle.stack", title: "Import from Apple Contacts", subtitle: "Action", run: open(.importContacts)),
            Item(id: "n-home", symbol: "house", title: "Home", subtitle: "Go to", run: go(.home)),
            Item(id: "n-updates", symbol: "bell", title: "Updates", subtitle: "Go to", run: go(.updates)),
            Item(id: "n-inbox", symbol: "tray", title: "Inbox", subtitle: "Go to", run: go(.messages(channel: nil))),
            Item(id: "n-mine", symbol: "list.clipboard", title: "My tasks", subtitle: "Go to", run: go(.myTasks)),
            Item(id: "n-pipeline", symbol: "square.grid.2x2", title: "Pipeline", subtitle: "Go to", run: go(.pipeline)),
            Item(id: "n-reports", symbol: "chart.pie", title: "Reports", subtitle: "Go to", run: go(.reports)),
            Item(id: "n-apple", symbol: "puzzlepiece.extension", title: "Apple services", subtitle: "Go to", run: go(.appleServices)),
            Item(id: "n-settings", symbol: "slider.horizontal.3", title: "Settings", subtitle: "Go to", run: go(.settings))
        ]
        items += projects.map { p in Item(id: "p-\(p.uuid)", symbol: p.symbol, title: p.name, subtitle: "Project", run: go(.project(p.uuid))) }
        items += channels.map { c in Item(id: "c-\(c.uuid)", symbol: "number", title: c.name, subtitle: "Channel", run: go(.messages(channel: c.uuid))) }
        items += contacts.map { c in Item(id: "k-\(c.uuid)", symbol: "person", title: c.name, subtitle: c.company.isEmpty ? "Contact" : c.company, run: go(.contacts)) }
        items += tasks.map { t in Item(id: "t-\(t.uuid)", symbol: t.status.symbol, title: t.title, subtitle: t.project?.name ?? "Task", run: open(.task(t.uuid))) }
        return items
    }

    private var results: [Item] {
        let q = ColonyText.trimmed(query)
        guard !q.isEmpty else { return Array(allItems.prefix(13)) }
        return allItems.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q) }.prefix(40).map { $0 }
    }
}
