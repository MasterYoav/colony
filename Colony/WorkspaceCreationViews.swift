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
    @State private var status = TaskStatus.planned

    private let priorities = ["Low", "Medium", "High"]

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        CreationForm(title: "New Task", actionTitle: "Create", canSubmit: canCreate) {
            store.createTask(title: title, owner: owner, priority: priority, status: status)
            dismiss()
        } content: {
            TextField("Task title", text: $title)
            TextField("Owner", text: $owner)

            Picker("Priority", selection: $priority) {
                ForEach(priorities, id: \.self) { priority in
                    Text(priority).tag(priority)
                }
            }

            Picker("Status", selection: $status) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
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
        NavigationStack {
            Form {
                Section {
                    content()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle, action: submit)
                        .disabled(!canSubmit)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    @Environment(\.dismiss) private var dismiss
}
