//
//  Sheets.swift
//  Colony
//
//  Every dialog in the app: create project/task/channel/contact, task detail,
//  Apple Contacts import, permission prompts and confirmations. All of them are
//  built from `DialogFrame` (DesignSystem/Dialog.swift) so they share one look.
//

import SwiftData
import SwiftUI

/// Swift Pieces `GlassSegments`, tuned to the dialog palette.
private let segmentStyle = GlassSegmentsStyle(
    track: Theme.field,
    ink: Theme.secondaryText,
    selectedInk: Theme.text,
    indicatorSurface: Theme.selection,
    font: .system(size: 12.5, weight: .medium)
)

/// Primary + Cancel footer shared by the create dialogs.
private struct CreateFooter: View {
    let title: String
    let canCommit: Bool
    let commit: () -> Void
    @Environment(\.dialogDismiss) private var dismiss

    var body: some View {
        KeyHint(keys: ["⌘", "⏎"], label: title.lowercased())
        Spacer()
        Button("Cancel") { dismiss() }
            .buttonStyle(.dialogGhost)
        Button(title, action: commit)
            .buttonStyle(.dialogPrimary)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canCommit)
    }
}

// MARK: - New project

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    @State private var name = ""
    @State private var summary = ""
    @State private var color: ColonyColor = .blue
    @State private var symbol = "folder.fill"
    @State private var lists: [String] = []

    static let symbols = ["folder.fill", "calendar", "doc.text.fill", "square.grid.2x2.fill", "chart.bar.fill", "creditcard.fill", "star.fill", "bolt.fill", "paintbrush.fill", "hammer.fill", "globe", "heart.fill", "flag.fill", "cart.fill", "megaphone.fill", "book.fill"]

    private var canCommit: Bool { !ColonyText.trimmed(name).isEmpty }

    var body: some View {
        DialogFrame(symbol: "folder.badge.plus", title: "New project", description: "Projects group tasks into lists and sync to all your devices through iCloud.") {
            HStack(alignment: .bottom, spacing: 12) {
                ProjectGlyph(symbol: symbol, color: color.color, size: 34)
                    .animation(.snappy(duration: 0.2), value: symbol)
                    .animation(.snappy(duration: 0.2), value: color)
                    .accessibilityHidden(true)
                DialogField(label: "Name") {
                    DialogTextField(placeholder: "e.g. Website relaunch", text: $name, limit: 40, autofocus: true, onSubmit: create)
                } accessory: {
                    Text("\(name.count)/40").appFont(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiaryText)
                }
            }

            DialogField(label: "Description", hint: "Optional. Shown under the project title.") {
                DialogTextEditor(placeholder: "What is this project about?", text: $summary, lines: 2...4)
            }

            DialogField(label: "Icon") {
                SymbolGrid(symbols: Self.symbols, selection: $symbol, tint: color.color)
            }

            DialogField(label: "Color") {
                ColorSwatches(selection: $color)
            }

            DialogField(label: "Lists", hint: "Press Return to add a list, like a sprint, a month or a phase.") {
                ChipInput(items: $lists, placeholder: "Sprint 1, March, Discovery…")
            }
        } footer: {
            CreateFooter(title: "Create project", canCommit: canCommit, commit: create)
        }
    }

    private func create() {
        guard canCommit, let project = WorkspaceActions(context: context).createProject(name: name, symbol: symbol, color: color, summary: summary, lists: lists) else { return }
        app.preferences.expandedProjectIDs.insert(project.uuid.uuidString)
        app.go(.project(project.uuid))
        app.show("Project created", detail: project.name)
        dismiss()
    }
}

/// Grid of SF Symbols in bordered tiles; the selected tile fills with the project colour.
struct SymbolGrid: View {
    let symbols: [String]
    @Binding var selection: String
    let tint: Color

    var body: some View {
        // Fixed column count so the 16 symbols always form two even rows.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(symbols, id: \.self) { item in
                let selected = item == selection
                Button { selection = item } label: {
                    Image(systemName: item)
                        .appFont(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? .white : Theme.icon)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selected ? tint : Theme.field, in: .rect(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? .clear : Theme.strongStroke)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.15), value: selection)
    }
}

struct ColorSwatches: View {
    @Binding var selection: ColonyColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ColonyColor.allCases) { item in
                let selected = item == selection
                Button { selection = item } label: {
                    Circle()
                        .fill(item.color)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark").appFont(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay { Circle().strokeBorder(selected ? item.color : .clear, lineWidth: 1.5) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.15), value: selection)
    }
}

// MARK: - New task

struct NewTaskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
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

    private var canCommit: Bool { !ColonyText.trimmed(title).isEmpty }

    var body: some View {
        DialogFrame(symbol: "checklist", title: "New task", description: destinationDescription) {
            DialogField(label: "Title") {
                DialogTextField(placeholder: "What needs to be done?", text: $title, limit: 120, autofocus: true, onSubmit: create)
            }
            DialogField(label: "Notes") {
                DialogTextEditor(placeholder: "Add details, links or acceptance criteria", text: $notes)
            }

            HStack(alignment: .top, spacing: 12) {
                DialogField(label: "Project") {
                    DialogSelect(selection: $selectedProject, options: [(UUID?.none, "No project", "tray")] + projects.map { (Optional($0.uuid), $0.name, $0.symbol) })
                }
                DialogField(label: "List") {
                    DialogSelect(selection: $selectedList, options: [(UUID?.none, "No list", nil)] + availableLists.map { (Optional($0.uuid), $0.name, nil) })
                        .disabled(availableLists.isEmpty)
                }
            }

            DialogField(label: "Priority") {
                GlassSegments(options: TaskPriority.allCases, selection: $priority, height: 32, style: segmentStyle, label: { $0.title })
            }

            VStack(alignment: .leading, spacing: 10) {
                DialogToggleRow(title: "Due date", description: app.preferences.mirrorsToReminders ? "Also creates an alert in Apple Reminders" : nil, isOn: $hasDue)
                if hasDue {
                    DatePicker("Due", selection: $due)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } footer: {
            CreateFooter(title: "Create task", canCommit: canCommit, commit: create)
        }
        .onAppear {
            selectedProject = projectID ?? context.list(listID ?? UUID())?.project?.uuid
            selectedList = listID
        }
        .onChange(of: selectedProject) { _, _ in
            if !availableLists.contains(where: { $0.uuid == selectedList }) { selectedList = nil }
        }
    }

    private var availableLists: [ProjectList] {
        projects.first { $0.uuid == selectedProject }?.sortedLists ?? []
    }

    private var destinationDescription: String {
        guard let project = projects.first(where: { $0.uuid == selectedProject }) else { return "Adds to My tasks." }
        if let list = availableLists.first(where: { $0.uuid == selectedList }) { return "Adds to \(project.name) › \(list.name)." }
        return "Adds to \(project.name)."
    }

    private func create() {
        guard canCommit else { return }
        let project = selectedProject.flatMap(context.project)
        let list = selectedList.flatMap(context.list)
        guard let task = WorkspaceActions(context: context).createTask(title: title, notes: notes, priority: priority, dueDate: hasDue ? due : nil, project: project, list: list?.project?.uuid == project?.uuid ? list : nil) else { return }
        app.syncReminder(for: task)
        app.show("Task created", detail: task.title)
        dismiss()
    }
}

// MARK: - New channel

struct NewChannelSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    @State private var name = ""
    @State private var topic = ""

    private var slug: String { ColonyText.channelSlug(name) }

    var body: some View {
        DialogFrame(symbol: "number", title: "New channel", description: "A place for notes and conversations about one topic.") {
            DialogField(label: "Name", hint: slug.isEmpty ? "Lowercase, no spaces." : "Will appear as #\(slug)") {
                DialogTextField(placeholder: "design-reviews", text: $name, symbol: "number", limit: 40, autofocus: true, onSubmit: create)
            }
            DialogField(label: "Topic") {
                DialogTextField(placeholder: "What's this channel for?", text: $topic, limit: 120, onSubmit: create)
            }
        } footer: {
            CreateFooter(title: "Create channel", canCommit: !slug.isEmpty, commit: create)
        }
    }

    private func create() {
        guard !slug.isEmpty, let channel = WorkspaceActions(context: context).createChannel(name: name, topic: topic) else { return }
        app.go(.messages(channel: channel.uuid))
        dismiss()
    }
}

// MARK: - New contact

struct NewContactSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    @State private var name = ""
    @State private var company = ""
    @State private var jobTitle = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var stage: DealStage = .lead

    private var emailInvalid: Bool { !email.isEmpty && !email.contains("@") }
    private var canCommit: Bool { !ColonyText.trimmed(name).isEmpty && !emailInvalid }

    var body: some View {
        DialogFrame(symbol: "person.crop.circle.badge.plus", title: "New contact", description: "Add a person to your CRM. You can also import from Apple Contacts.") {
            DialogField(label: "Full name") {
                DialogTextField(placeholder: "Jane Appleseed", text: $name, symbol: "person", autofocus: true, onSubmit: create)
            }
            HStack(alignment: .top, spacing: 12) {
                DialogField(label: "Company") {
                    DialogTextField(placeholder: "Acme Inc.", text: $company, symbol: "building.2")
                }
                DialogField(label: "Job title") {
                    DialogTextField(placeholder: "Head of Design", text: $jobTitle, symbol: "briefcase")
                }
            }
            HStack(alignment: .top, spacing: 12) {
                DialogField(label: "Email", hint: emailInvalid ? "Enter a valid email address." : nil) {
                    DialogTextField(placeholder: "jane@acme.com", text: $email, symbol: "envelope", isInvalid: emailInvalid)
                }
                DialogField(label: "Phone") {
                    DialogTextField(placeholder: "+1 555 0100", text: $phone, symbol: "phone")
                }
            }
            DialogField(label: "Pipeline stage") {
                DialogSelect(selection: $stage, options: DealStage.allCases.map { ($0, $0.title, "circle.fill") })
            }
        } footer: {
            Button("Import from Contacts…") { app.present(.importContacts) }
                .buttonStyle(.dialogGhost)
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(.dialogGhost)
            Button("Add contact", action: create)
                .buttonStyle(.dialogPrimary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit)
        }
    }

    private func create() {
        guard canCommit, WorkspaceActions(context: context).createContact(name: name, company: company, jobTitle: jobTitle, email: email, phone: phone, stage: stage) != nil else { return }
        app.go(.contacts)
        dismiss()
    }
}

// MARK: - Import from Apple Contacts

struct ImportContactsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    @Query private var existing: [Contact]
    @State private var candidates: [AppleContactCandidate] = []
    @State private var selection: Set<String> = []
    @State private var search = ""
    @State private var isLoading = true

    var body: some View {
        if !app.contacts.canRead {
            PermissionDialog(kind: .contacts)
        } else {
            DialogFrame(symbol: "person.crop.rectangle.stack", title: "Import from Contacts", description: "Choose people from your address book. Nothing in Contacts is changed.") {
                DialogTextField(placeholder: "Search people or companies", text: $search, symbol: "magnifyingglass", autofocus: true)

                Group {
                    if isLoading {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 240)
                    } else if candidates.isEmpty {
                        EmptyStateView(symbol: "person.crop.circle.badge.questionmark", title: "No contacts found", message: "Your address book is empty or access is limited.")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filtered) { person in row(person) }
                            }
                            .padding(4)
                        }
                        .frame(height: 280)
                        .background(Theme.field, in: .rect(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.strongStroke) }
                    }
                }
            } footer: {
                Button(allSelected ? "Deselect all" : "Select all") {
                    selection = allSelected ? [] : Set(filtered.filter { !importedIDs.contains($0.id) }.map(\.id))
                }
                .buttonStyle(.dialogGhost)
                .disabled(filtered.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.dialogGhost)
                Button(selection.isEmpty ? "Import" : "Import \(selection.count)", action: importSelected)
                    .buttonStyle(.dialogPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(selection.isEmpty)
            }
            .task { await load() }
        }
    }

    private func row(_ person: AppleContactCandidate) -> some View {
        let imported = importedIDs.contains(person.id)
        let selected = selection.contains(person.id)
        return Button {
            guard !imported else { return }
            if selected { selection.remove(person.id) } else { selection.insert(person.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: imported || selected ? "checkmark.square.fill" : "square")
                    .appFont(.system(size: 14))
                    .foregroundStyle(imported ? Theme.tertiaryText : (selected ? Theme.text : Theme.secondaryText))
                AvatarView(name: person.name, color: ColonyColor.indigo.color, imageData: person.imageData, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name).appFont(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    if !person.company.isEmpty {
                        Text(person.company).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                if imported {
                    Text("Added").appFont(.system(size: 11, weight: .medium)).foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(selected ? Theme.selection : .clear, in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(imported)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var importedIDs: Set<String> { Set(existing.compactMap(\.appleContactIdentifier)) }

    private var allSelected: Bool {
        let selectable = filtered.filter { !importedIDs.contains($0.id) }
        return !selectable.isEmpty && selectable.allSatisfy { selection.contains($0.id) }
    }

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

// MARK: - Permission prompts

/// Explains why Colony wants access to an Apple service before the system prompt appears.
struct PermissionDialog: View {
    enum Kind { case contacts, reminders }
    let kind: Kind
    @Environment(AppModel.self) private var app
    @Environment(\.dialogDismiss) private var dismiss
    @State private var isRequesting = false
    @State private var wasDenied = false

    var body: some View {
        DialogFrame(symbol: symbol, tint: tint, title: title, description: message) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                    HStack(spacing: 12) {
                        Image(systemName: benefit.symbol)
                            .appFont(.system(size: 13))
                            .foregroundStyle(Theme.icon)
                            .frame(width: 20)
                        Text(benefit.text)
                            .appFont(.system(size: 13))
                            .foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Theme.stroke).frame(height: 1) }
                    }
                }
            }
            .background(Theme.surface, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke) }

            if wasDenied {
                Label("Access is off. Turn it on in System Settings › Privacy & Security.", systemImage: "exclamationmark.triangle.fill")
                    .appFont(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        } footer: {
            Spacer()
            Button("Not now") { dismiss() }.buttonStyle(.dialogGhost)
            Button {
                Task { await request() }
            } label: {
                HStack(spacing: 6) {
                    if isRequesting { ProgressView().controlSize(.mini) }
                    Text("Allow access")
                }
            }
            .buttonStyle(.dialogPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(isRequesting)
        }
    }

    private func request() async {
        isRequesting = true
        let granted: Bool
        switch kind {
        case .contacts: granted = await app.contacts.requestAccess()
        case .reminders: granted = await app.reminders.requestAccess()
        }
        isRequesting = false
        guard granted else { wasDenied = true; return }
        switch kind {
        case .contacts:
            app.present(.importContacts)
        case .reminders:
            app.preferences.mirrorsToReminders = true
            app.show("Reminders connected", detail: "Tasks with due dates will alert you")
            dismiss()
        }
    }

    private var symbol: String { kind == .contacts ? "person.crop.circle" : "checklist" }
    private var tint: Color { kind == .contacts ? ColonyColor.indigo.color : ColonyColor.orange.color }
    private var title: String { kind == .contacts ? "Connect Contacts" : "Connect Reminders" }
    private var message: String {
        kind == .contacts
            ? "Pick people from your address book to add them to Colony's CRM."
            : "Colony can create a reminder for each task so you're notified when it's due."
    }
    private var benefits: [(symbol: String, text: String)] {
        kind == .contacts
            ? [("person.2", "Import names, companies and photos"), ("hand.raised", "Read-only: nothing in Contacts is changed"), ("lock", "Imported people live in your iCloud")]
            : [("bell.badge", "Due-date alerts on every Apple device"), ("applewatch", "Check tasks off from Apple Watch"), ("lock", "Stays in your iCloud account")]
    }
}

// MARK: - Task detail

struct TaskDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    let taskID: UUID

    var body: some View {
        if let task = context.task(taskID) {
            TaskDetailForm(task: task)
        } else {
            DialogFrame(symbol: "questionmark.circle", title: "Task not found", description: "It may have been deleted on another device.") {
                EmptyView()
            } footer: {
                Button("Close") { dismiss() }.buttonStyle(.dialogPrimary).keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct TaskDetailForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    @Bindable var task: TaskItem

    var body: some View {
        DialogFrame(symbol: task.status.symbol, tint: task.project?.color.color ?? Theme.text, title: "Task", description: breadcrumb) {
            DialogField(label: "Title") {
                DialogTextField(placeholder: "Task title", text: $task.title, limit: 120)
            }

            DialogField(label: "Status") {
                GlassSegments(options: TaskStatus.allCases, selection: Binding(get: { task.status }, set: { WorkspaceActions(context: context).setStatus($0, for: task); app.syncReminder(for: task) }), height: 32, style: segmentStyle, label: { $0.title })
            }
            DialogField(label: "Priority") {
                GlassSegments(options: TaskPriority.allCases, selection: $task.priority, height: 32, style: segmentStyle, label: { $0.title })
            }

            VStack(alignment: .leading, spacing: 10) {
                DialogToggleRow(
                    title: "Due date",
                    description: task.reminderIdentifier != nil ? "Mirrored in Apple Reminders" : nil,
                    isOn: Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? (task.dueDate ?? .now.addingTimeInterval(86_400)) : nil })
                )
                if let due = task.dueDate {
                    DatePicker("Due", selection: Binding(get: { due }, set: { task.dueDate = $0 }))
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }

            DialogField(label: "Notes") {
                DialogTextEditor(placeholder: "Add details", text: $task.notes, lines: 4...10)
            }
        } footer: {
            Button("Delete", systemImage: "trash") { app.present(.deleteTask(task.uuid)) }
                .buttonStyle(.dialogGhost)
                .foregroundStyle(.red)
            Spacer()
            Text("Changes save automatically")
                .appFont(.system(size: 11.5))
                .foregroundStyle(Theme.tertiaryText)
            Button("Done") { dismiss() }
                .buttonStyle(.dialogPrimary)
                .keyboardShortcut(.defaultAction)
        }
        .onDisappear { app.syncReminder(for: task) }
    }

    private var breadcrumb: String {
        guard let project = task.project else { return "My tasks" }
        return task.list.map { "\(project.name) › \($0.name)" } ?? project.name
    }
}

// MARK: - Confirmations

struct DeleteProjectDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let projectID: UUID

    var body: some View {
        let project = context.project(projectID)
        ConfirmDialog(
            symbol: "trash",
            title: "Delete \(project?.name ?? "project")?",
            message: "Its lists are removed from every device signed in to your iCloud account. Tasks stay in My tasks.",
            confirmTitle: "Delete project"
        ) {
            guard let project else { return }
            if case .project(let id) = app.destination, id == project.uuid { app.go(.projects) }
            if case .list(let id, _) = app.destination, id == project.uuid { app.go(.projects) }
            WorkspaceActions(context: context).delete(project)
        }
    }
}

struct DeleteTaskDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let taskID: UUID

    var body: some View {
        let task = context.task(taskID)
        ConfirmDialog(
            symbol: "trash",
            title: "Delete this task?",
            message: "\u{201C}\(task?.title ?? "Task")\u{201D} will be removed from all your devices.",
            confirmTitle: "Delete task"
        ) {
            guard let task else { return }
            app.reminders.removeMirror(for: task)
            WorkspaceActions(context: context).delete(task)
        }
    }
}
