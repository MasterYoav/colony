//
//  WorkspaceCreationViews.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct UpdateCreationView: View {
    @Binding var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CreationForm(title: "New Update", actionTitle: "Post", canSubmit: canCreate) {
            store.createUpdate(title: title, detail: detail)
            dismiss()
        } content: {
            TextField("Title", text: $title)
            TextField("What changed?", text: $detail, axis: .vertical)
                .lineLimit(3...6)
        }
    }
}

struct ChannelCreationView: View {
    @Binding var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CreationForm(title: "New Channel", actionTitle: "Create", canSubmit: canCreate) {
            store.createChannel(name: name, description: description)
            dismiss()
        } content: {
            TextField("Channel name", text: $name)
            TextField("Purpose", text: $description, axis: .vertical)
                .lineLimit(2...4)
        }
    }
}

struct TaskCreationView: View {
    @Binding var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var owner = ""
    @State private var priority = "Medium"
    @State private var category: String
    @State private var dueDate = "Sep 20, 2025"
    @State private var status = TaskStatus.planned

    private let priorities = ["Low", "Medium", "High"]

    init(store: Binding<WorkspaceStore>, initialCategory: String? = nil) {
        _store = store
        _category = State(initialValue: initialCategory ?? "Infrastructure")
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CreationForm(title: "New Task", actionTitle: "Create", canSubmit: canCreate) {
            store.createTask(
                title: title,
                owner: owner,
                priority: priority,
                category: category,
                dueDate: dueDate,
                status: status
            )
            dismiss()
        } content: {
            TextField("Task title", text: $title)
            TextField("Owner", text: $owner)

            Picker("Group", selection: $category) {
                ForEach(taskCategories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }

            TextField("Due date", text: $dueDate)

            Picker("Urgency", selection: $priority) {
                ForEach(priorities, id: \.self) { priority in
                    Text(urgencyTitle(for: priority)).tag(priority)
                }
            }

            Picker("Status", selection: $status) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
        }
        .onAppear {
            if !taskCategories.contains(category) {
                category = taskCategories[0]
            }
        }
    }

    private var taskCategories: [String] {
        let existingCategories = store.taskCategories

        return existingCategories.isEmpty ? ["General"] : existingCategories
    }

    private func urgencyTitle(for priority: String) -> String {
        switch priority {
        case "High":
            return "Urgent"
        case "Medium":
            return "Mid"
        default:
            return "Low"
        }
    }
}

struct ContactCreationView: View {
    @Binding var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var company = ""
    @State private var stage = WorkspaceStore.contactStages[0]

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CreationForm(title: "New Contact", actionTitle: "Create", canSubmit: canCreate) {
            store.createContact(name: name, company: company, stage: stage)
            dismiss()
        } content: {
            TextField("Name", text: $name)
            TextField("Company", text: $company)

            Picker("Stage", selection: $stage) {
                ForEach(WorkspaceStore.contactStages, id: \.self) { stage in
                    Text(stage).tag(stage)
                }
            }
        }
    }
}

struct InviteCreationView: View {
    @Binding var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = WorkspaceRole.member

    private var canCreate: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CreationForm(title: "Invite Member", actionTitle: "Prepare", canSubmit: canCreate) {
            store.prepareInvite(email: email, role: role)
            dismiss()
        } content: {
            TextField("Email", text: $email)

            Picker("Role", selection: $role) {
                ForEach(WorkspaceRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
        }
    }
}

private struct CreationForm<Content: View>: View {
    let title: String
    let actionTitle: String
    let canSubmit: Bool
    let submit: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(22)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Group {
                    content()
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Divider()

            HStack(spacing: 10) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(actionTitle, action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(minWidth: 460, minHeight: 340)
        .background(.regularMaterial)
    }

    @Environment(\.dismiss) private var dismiss

    private var systemImage: String {
        switch title {
        case "New Update":
            return "doc.text"
        case "New Channel":
            return "number"
        case "New Task":
            return "checkmark.circle"
        case "New Contact":
            return "person.badge.plus"
        case "Invite Member":
            return "person.2.badge.plus"
        default:
            return "plus"
        }
    }

    private var detail: String {
        switch title {
        case "New Update":
            return "Post a workspace update that appears in Home and recent activity."
        case "New Channel":
            return "Create a focused place for team conversation."
        case "New Task":
            return "Add work to the grouped task board with owner, date, and status."
        case "New Contact":
            return "Add an account or relationship to the CRM pipeline."
        case "Invite Member":
            return "Prepare an invite with the right workspace role."
        default:
            return "Create a new workspace item."
        }
    }

    private var accentColor: Color {
        switch title {
        case "New Task":
            return .green
        case "New Contact":
            return .orange
        case "Invite Member":
            return .purple
        default:
            return .blue
        }
    }
}
