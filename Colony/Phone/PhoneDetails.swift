//
//  PhoneDetails.swift
//  Colony
//
//  Detail screens on iPhone built like Contacts and Reminders' Details: a header,
//  then inset grouped rows that edit in place, and a red Delete row at the bottom.
//

#if os(iOS)
import SwiftData
import SwiftUI

// MARK: - Customer

struct PhoneContactDetail: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Bindable var contact: Contact

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    CustomerAvatar(contact: contact, size: 96)
                    Text(contact.name.isEmpty ? "No name" : contact.name)
                        .appFont(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    if !contact.company.isEmpty || !contact.jobTitle.isEmpty {
                        Text([contact.jobTitle, contact.company].filter { !$0.isEmpty }.joined(separator: " · "))
                            .appFont(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        action("Message", "message.fill", url: phoneURL("sms:"))
                        action("Call", "phone.fill", url: phoneURL("tel:"))
                        action("FaceTime", "video.fill", url: phoneURL("facetime:"))
                        action("Mail", "envelope.fill", url: contact.email.isEmpty ? nil : URL(string: "mailto:\(contact.email)"))
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Deal") {
                Picker("Stage", selection: Binding(get: { contact.stage }, set: { WorkspaceActions(context: context).setStage($0, for: contact) })) {
                    ForEach(DealStage.allCases) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                LabeledContent("Value") {
                    TextField("None", value: Binding(get: { contact.dealValue == 0 ? nil : contact.dealValue }, set: { WorkspaceActions(context: context).setDealValue($0 ?? 0, for: contact) }),
                              format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Favourite", isOn: $contact.isFavorite)
            }

            Section("Details") {
                field("Name", $contact.name, content: .name)
                field("Company", $contact.company, content: .organizationName)
                field("Job title", $contact.jobTitle, content: .jobTitle)
            }

            Section("Contact") {
                field("Email", $contact.email, content: .emailAddress, keyboard: .emailAddress)
                field("Phone", $contact.phone, content: .telephoneNumber, keyboard: .phonePad)
            }

            Section("Notes") {
                TextField("Add notes", text: $contact.notes, axis: .vertical)
                    .lineLimit(3...10)
            }

            Section {
                Button("Delete Customer", role: .destructive) { app.present(.deleteContact(contact.uuid)) }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { try? context.save() }
    }

    private func field(_ title: String, _ text: Binding<String>, content: UITextContentType, keyboard: UIKeyboardType = .default) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .textContentType(content)
                .keyboardType(keyboard)
                .autocorrectionDisabled(keyboard != .default)
                .textInputAutocapitalization(keyboard == .default ? .words : .never)
                .multilineTextAlignment(.trailing)
        }
    }

    private func phoneURL(_ scheme: String) -> URL? {
        let digits = contact.phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: scheme + digits)
    }

    /// Contacts' row of glass action buttons. Greyed when there's no number/address.
    private func action(_ title: String, _ symbol: String, url: URL?) -> some View {
        Button { if let url { openURL(url) } } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .appFont(.system(size: 18, weight: .semibold))
                    .frame(height: 22)
                Text(title).appFont(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(url == nil ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(url == nil)
        .accessibilityHint(url == nil ? "Add a \(title == "Mail" ? "email address" : "phone number") first" : "")
    }
}

// MARK: - Task

/// Reminders' Details sheet: title and notes, date and time switches that reveal
/// pickers, status, priority, list, flag, and Delete.
struct PhoneTaskDetail: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dialogDismiss) private var dismiss
    @Query(sort: \Project.sortIndex) private var projectsEverywhere: [Project]
    let taskID: UUID

    var body: some View {
        NavigationStack {
            if let task = context.task(taskID) {
                form(task)
            } else {
                ContentUnavailableView("Task not found", systemImage: "questionmark.circle", description: Text("It was deleted on another device."))
            }
        }
    }

    private func form(_ task: TaskItem) -> some View {
        @Bindable var task = task
        let actions = WorkspaceActions(context: context)
        let projects = projectsEverywhere.inWorkspace().filter { $0.archivedAt == nil }
        let hasDate = Binding(get: { task.dueDate != nil }, set: { on in
            if on {
                let base = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
                actions.setDue(base, hasTime: false, for: task)
            } else {
                actions.setDue(nil, hasTime: false, for: task)
            }
        })
        let hasTime = Binding(get: { task.dueDate != nil && task.dueHasTime }, set: { on in
            actions.setDue(task.dueDate ?? .now, hasTime: on, for: task)
        })
        let date = Binding(get: { task.dueDate ?? .now }, set: { actions.setDue($0, hasTime: task.dueHasTime, for: task) })

        return Form {
            Section {
                TextField("Title", text: $task.title, axis: .vertical)
                    .appFont(.system(size: 20, weight: .semibold))
                TextField("Notes", text: $task.notes, axis: .vertical)
                    .lineLimit(2...8)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: hasDate) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Date")
                            if let due = task.dueDate {
                                Text(DueText.day(due)).appFont(.system(size: 14)).foregroundStyle(Color.accentColor)
                            }
                        }
                    } icon: { CircleIcon(symbol: "calendar", color: ColonyColor.red.color, size: 30) }
                }
                if task.dueDate != nil {
                    DatePicker("Date", selection: date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                HStack {
                    Toggle(isOn: hasTime) {
                        Label { Text("Time") } icon: { CircleIcon(symbol: "clock.fill", color: ColonyColor.blue.color, size: 30) }
                    }
                    .fixedSize()
                    Spacer()
                    if task.dueDate != nil && task.dueHasTime {
                        DatePicker("Time", selection: date, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                .disabled(task.dueDate == nil)
            }

            Section {
                Toggle(isOn: Binding(get: { task.isFlagged }, set: { _ in actions.toggleFlag(task) })) {
                    Label { Text("Flag") } icon: { CircleIcon(symbol: "flag.fill", color: ColonyColor.orange.color, size: 30) }
                }
                Picker(selection: Binding(get: { task.priority }, set: { task.priority = $0 })) {
                    ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label { Text("Priority") } icon: { CircleIcon(symbol: "exclamationmark", color: ColonyColor.red.color, size: 30) }
                }
                Picker(selection: Binding(get: { task.status }, set: { actions.setStatus($0, for: task) })) {
                    ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label { Text("Status") } icon: { CircleIcon(symbol: "circle.dashed", color: ColonyColor.green.color, size: 30) }
                }
            }

            Section {
                Picker(selection: Binding(get: { task.project?.uuid }, set: { id in
                    actions.move(task, to: id.flatMap { id in projects.first { $0.uuid == id } })
                })) {
                    Text("None").tag(UUID?.none)
                    ForEach(projects) { Text($0.name).tag(Optional($0.uuid)) }
                } label: {
                    Label { Text("Project") } icon: { CircleIcon(symbol: task.project?.symbol ?? "tray.fill", color: task.project?.color.color ?? Color(white: 0.5), size: 30) }
                }
                if let project = task.project, !project.sortedLists.isEmpty {
                    Picker(selection: Binding(get: { task.list?.uuid }, set: { id in
                        actions.move(task, to: project, list: id.flatMap { id in project.sortedLists.first { $0.uuid == id } })
                    })) {
                        Text("None").tag(UUID?.none)
                        ForEach(project.sortedLists) { Text($0.name).tag(Optional($0.uuid)) }
                    } label: {
                        Label { Text("List") } icon: { CircleIcon(symbol: "list.bullet", color: project.color.color, size: 30) }
                    }
                }
            }

            Section {
                Button("Delete Task", role: .destructive) {
                    dismiss()
                    actions.delete(task)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    if ColonyText.trimmed(task.title).isEmpty { task.title = "Untitled" }
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}
#endif
