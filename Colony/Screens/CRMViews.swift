//
//  CRMViews.swift
//  Colony
//
//  Contacts and pipeline. People can be imported straight from Apple Contacts;
//  calls and email hand off to the system Phone/FaceTime/Mail apps.
//

import SwiftData
import SwiftUI

struct ContactsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @State private var search = ""
    @State private var selectedID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Contacts", subtitle: "\(contacts.count) people") {
                    Menu {
                        Button("New contact", systemImage: "person.crop.circle.badge.plus") { app.sheet = .newContact }
                        Button("Import from Contacts", systemImage: "person.crop.rectangle.stack") { app.sheet = .importContacts }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                    TextField("Search people or companies", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke) }

                if contacts.isEmpty {
                    EmptyStateView(symbol: "person.2", title: "No contacts yet", message: "Import people from Apple Contacts or add them by hand.", actionTitle: "Import from Contacts") {
                        app.sheet = .importContacts
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { contact in
                            Button { selectedID = contact.uuid } label: {
                                HStack(spacing: 12) {
                                    AvatarView(name: contact.name, color: contact.color.color, imageData: contact.imageData, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(contact.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                                        Text([contact.jobTitle, contact.company].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    StageChip(stage: contact.stage)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedID == contact.uuid ? Theme.selection : .clear)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)

            if let contact = contacts.first(where: { $0.uuid == selectedID }) {
                Rectangle().fill(Theme.stroke).frame(width: 1)
                ContactInspector(contact: contact)
                    .frame(width: 320)
                    .background(Theme.sidebar)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: selectedID)
        .navigationTitle("Contacts")
    }

    private var filtered: [Contact] {
        let q = ColonyText.trimmed(search)
        guard !q.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.company.localizedCaseInsensitiveContains(q) }
    }
}

struct StageChip: View {
    let stage: DealStage

    var body: some View {
        Text(stage.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(stage.color.color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(stage.color.color.opacity(0.14), in: Capsule())
    }
}

struct ContactInspector: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Bindable var contact: Contact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 10) {
                    AvatarView(name: contact.name, color: contact.color.color, imageData: contact.imageData, size: 64)
                    Text(contact.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                    if !contact.company.isEmpty {
                        Text(contact.company).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    if contact.appleContactIdentifier != nil {
                        Label("Linked to Apple Contacts", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    action("envelope", "Mail", url: contact.email.isEmpty ? nil : URL(string: "mailto:\(contact.email)"))
                    action("phone", "Call", url: contact.phone.isEmpty ? nil : URL(string: "tel:\(contact.phone.filter { !$0.isWhitespace })"))
                    action("video", "FaceTime", url: facetimeURL)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Stage").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    Picker("Stage", selection: Binding(get: { contact.stage }, set: { WorkspaceActions(context: context).setStage($0, for: contact) })) {
                        ForEach(DealStage.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 10) {
                    field("Title", $contact.jobTitle)
                    field("Company", $contact.company)
                    field("Email", $contact.email)
                    field("Phone", $contact.phone)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    TextField("Add notes", text: $contact.notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...10)
                        .padding(10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke) }
                }
            }
            .padding(20)
        }
    }

    private var facetimeURL: URL? {
        let handle = contact.phone.isEmpty ? contact.email : contact.phone.filter { !$0.isWhitespace }
        return handle.isEmpty ? nil : URL(string: "facetime:\(handle)")
    }

    private func action(_ symbol: String, _ title: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(url == nil ? Theme.tertiaryText : Theme.text)
            .glassSurface(.rect(cornerRadius: 12), interactive: url != nil)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText).frame(width: 64, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.plain).font(.subheadline)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { SidebarDivider() }
    }
}

// MARK: - Pipeline

struct PipelineView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Contact.name) private var contacts: [Contact]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Pipeline", subtitle: "Drag people between stages") {
                Button("New contact", systemImage: "plus") { app.sheet = .newContact }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(DealStage.allCases) { stage in
                        column(stage)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Pipeline")
    }

    private func column(_ stage: DealStage) -> some View {
        let people = contacts.filter { $0.stage == stage }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(stage.color.color).frame(width: 8, height: 8)
                Text(stage.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("\(people.count)").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(people) { contact in
                        HStack(spacing: 10) {
                            AvatarView(name: contact.name, color: contact.color.color, imageData: contact.imageData, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                                Text(contact.company).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
                        .draggable(contact.uuid.uuidString)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke) }
        .dropDestination(for: String.self) { ids, _ in
            let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
            for contact in contacts where uuids.contains(contact.uuid) {
                withAnimation(.snappy) { WorkspaceActions(context: context).setStage(stage, for: contact) }
            }
            return true
        }
    }
}

// MARK: - Reports

struct ReportsView: View {
    @Query private var tasks: [TaskItem]
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query private var contacts: [Contact]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Reports", subtitle: "Computed on-device from your iCloud data")
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Text("Tasks by status").font(.headline).foregroundStyle(Theme.text)
                        RingBreakdown(slices: TaskStatus.allCases.map { status in
                            .init(label: status.title, value: Double(tasks.filter { $0.status == status }.count))
                        }, thickness: 26)
                    }
                    Card {
                        Text("Pipeline by stage").font(.headline).foregroundStyle(Theme.text)
                        RingBreakdown(slices: DealStage.allCases.map { stage in
                            .init(label: stage.title, value: Double(contacts.filter { $0.stage == stage }.count), color: stage.color.color)
                        }, thickness: 26)
                    }
                }
                Card {
                    Text("Open work per project").font(.headline).foregroundStyle(Theme.text)
                    RingBreakdown(slices: projects.map { project in
                        .init(label: project.name, value: Double(project.openTaskCount), color: project.color.color)
                    }, thickness: 26)
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("Reports")
    }
}
