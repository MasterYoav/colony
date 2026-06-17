//
//  WorkspaceDetailView.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI

struct WorkspaceDetailView: View {
    @Binding var store: WorkspaceStore
    @State private var creationSheet: WorkspaceCreationSheet?

    private var section: ColonySection {
        store.selectedSection ?? .home
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: store.appearancePreferences.density.contentSpacing) {
                HeroPanel(
                    section: section,
                    selectedTheme: store.selectedTheme,
                    primaryAction: {
                        creationSheet = WorkspaceCreationSheet(section: section)
                    }
                )

                switch section {
                case .home:
                    HomeOverview(store: store)
                case .messages:
                    ChannelDetail(store: $store, channel: store.activeChannel)
                case .work:
                    WorkOverview(store: $store)
                case .crm:
                    CRMOverview(store: $store)
                case .settings:
                    SettingsOverview(store: $store)
                }
            }
            .padding(.horizontal, store.appearancePreferences.density.contentPadding)
            .padding(.bottom, store.appearancePreferences.density.contentPadding)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(.background)
        .navigationTitle("")
#if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
#else
        .toolbar(.hidden, for: .navigationBar)
#endif
        .sheet(item: $creationSheet) { sheet in
            switch sheet {
            case .update:
                UpdateCreationView(store: $store)
            case .channel:
                ChannelCreationView(store: $store)
            case .task:
                TaskCreationView(store: $store)
            case .contact:
                ContactCreationView(store: $store)
            case .invite:
                InviteCreationView(store: $store)
            }
        }
    }
}

private enum WorkspaceCreationSheet: String, Identifiable {
    case update
    case channel
    case task
    case contact
    case invite

    init(section: ColonySection) {
        switch section {
        case .home:
            self = .update
        case .messages:
            self = .channel
        case .work:
            self = .task
        case .crm:
            self = .contact
        case .settings:
            self = .invite
        }
    }

    var id: String { rawValue }
}

private struct HeroPanel: View {
    let section: ColonySection
    let selectedTheme: ColonyTheme
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.eyebrow)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(selectedTheme.accentColor)

                    Text(section.headline)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: primaryAction) {
                    Label(section.primaryAction, systemImage: section.primaryActionImage)
                }
                .buttonStyle(.borderedProminent)
            }

            Text(section.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HomeOverview: View {
    let store: WorkspaceStore

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            MetricCard(title: "Active channels", value: "\(store.activeChannelCount)", systemImage: "bubble.left.and.bubble.right", color: store.selectedTheme.accentColor)
            MetricCard(title: "Open tasks", value: "\(store.openTaskCount)", systemImage: "checklist", color: .green)
            MetricCard(title: "CRM records", value: "\(store.crmRecordCount)", systemImage: "person.crop.rectangle.stack", color: .orange)
            MetricCard(title: "SSO providers", value: "\(store.ssoProviderCount)", systemImage: "lock.shield", color: .purple)
        }

        ContentGroup(title: "Recent activity") {
            ForEach(store.updates) { update in
                UpdateRow(update: update)
                if update.id != store.updates.last?.id {
                    Divider()
                }
            }
        }
    }
}

private struct ChannelDetail: View {
    @Binding var store: WorkspaceStore
    let channel: ColonyChannel

    var body: some View {
        ContentGroup(title: "# \(channel.name)") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(channel.messages) { message in
                    MessageRow(message: message)
                }

                HStack(spacing: 10) {
                    TextField("Message #\(channel.name)", text: $store.messageText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        store.sendMessage(to: channel.id)
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct WorkOverview: View {
    @Binding var store: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TaskBoardHeader()

            ForEach(store.taskCategories, id: \.self) { category in
                let tasks = store.tasks.filter { $0.category == category }

                TaskGroupTable(
                    title: category,
                    tasks: tasks,
                    accentColor: categoryAccentColor(for: category)
                ) { taskID, status in
                    store.updateTaskStatus(taskID: taskID, status: status)
                }
            }
        }
    }

    private func categoryAccentColor(for category: String) -> Color {
        switch category {
        case "SharePoint":
            return .blue
        case "AI Tools Integration & Research":
            return .purple
        case "Infrastructure":
            return .green
        default:
            return store.selectedTheme.accentColor
        }
    }
}

private struct TaskBoardHeader: View {
    var body: some View {
        ContentGroup(title: "Task groups") {
            HStack(spacing: 12) {
                Label("Grouped by initiative", systemImage: "rectangle.3.group")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Label("Owner, status, and dates stay visible", systemImage: "line.3.horizontal.decrease")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TaskGroupTable: View {
    let title: String
    let tasks: [ColonyTask]
    let accentColor: Color
    let updateStatus: (ColonyTask.ID, TaskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(accentColor)

            VStack(spacing: 0) {
                TaskTableHeader()

                ForEach(tasks) { task in
                    TaskTableRow(task: task, accentColor: accentColor) { status in
                        updateStatus(task.id, status)
                    }

                    if task.id != tasks.last?.id {
                        Divider()
                    }
                }

                Button {
                } label: {
                    Label("Add task", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 5)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.8), lineWidth: 1)
            }
        }
    }
}

private struct TaskTableHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Updates")
                .frame(width: 86)
            Text("Person")
                .frame(width: 88)
            Text("Status")
                .frame(width: 158)
            Text("Date")
                .frame(width: 120)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }
}

private struct TaskTableRow: View {
    let task: ColonyTask
    let accentColor: Color
    let updateStatus: (TaskStatus) -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .stroke(.secondary.opacity(0.65), lineWidth: 2)
                    .frame(width: 20, height: 20)

                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
            } label: {
                Image(systemName: "bubble.left.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 86)
            }
            .buttonStyle(.plain)

            OwnerBadge(owner: task.owner)
                .frame(width: 88)

            Picker("Status", selection: statusBinding) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.boardTitle).tag(status)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 146)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .background(task.status.boardColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.white)

            Text(task.dueDate)
                .font(.subheadline.weight(.semibold))
                .frame(width: 120)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { updateStatus($0) }
        )
    }
}

private struct OwnerBadge: View {
    let owner: String

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.blue.gradient, in: Circle())
    }

    private var initials: String {
        let initials = owner
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()

        return initials.isEmpty ? "?" : initials.uppercased()
    }
}

private extension TaskStatus {
    var boardTitle: String {
        switch self {
        case .planned: "Future"
        case .active: "Working on it"
        case .review: "Done"
        }
    }

    var boardColor: Color {
        switch self {
        case .planned: .gray.opacity(0.45)
        case .active: .orange
        case .review: .green
        }
    }
}

private struct CRMOverview: View {
    @Binding var store: WorkspaceStore

    var body: some View {
        ContentGroup(title: "Pipeline") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(store.contacts) { contact in
                    ContactPipelineRow(contact: contact) { newStage in
                        store.updateContactStage(contactID: contact.id, stage: newStage)
                    }
                    if contact.id != store.contacts.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct SettingsOverview: View {
    @Binding var store: WorkspaceStore
    @State private var selectedTab = SettingsTab.appearance

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
            SettingsCard(title: "Authentication", detail: "\(store.enabledAuthProviderCount) enabled providers, \(store.ssoProviderCount) SSO-capable providers configured.", systemImage: "lock.shield", color: .blue)
            SettingsCard(title: "Self-hosting", detail: "Docker Compose first, with PostgreSQL, Redis, object storage, and a reverse proxy.", systemImage: "server.rack", color: .green)
            SettingsCard(title: "Appearance", detail: "\(store.selectedTheme.title) accent, \(store.appearancePreferences.density.title.lowercased()) density, and user-controlled navigation preferences.", systemImage: "paintpalette", color: store.selectedTheme.accentColor)
            SettingsCard(title: "Members", detail: "\(store.members.count) active members and \(store.pendingInvites.count) pending invite.", systemImage: "person.2", color: .orange)
        }

        Picker("Settings", selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
        }
        .pickerStyle(.segmented)

        switch selectedTab {
        case .appearance:
            AppearanceSettingsTab(store: $store)
        case .authentication:
            AuthSettingsTab(store: $store)
        case .security:
            SecuritySettingsTab(store: $store)
        case .members:
            MembersSettingsTab(store: store)
        case .hosting:
            HostingSettingsTab()
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case authentication
    case security
    case members
    case hosting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .authentication: "Auth"
        case .security: "Security"
        case .members: "Members"
        case .hosting: "Hosting"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette"
        case .authentication: "lock.shield"
        case .security: "checkmark.shield"
        case .members: "person.2"
        case .hosting: "server.rack"
        }
    }
}

private struct AppearanceSettingsTab: View {
    @Binding var store: WorkspaceStore

    var body: some View {
        ContentGroup(title: "Appearance") {
            VStack(alignment: .leading, spacing: 16) {
                ThemeSwatchPicker(selectedTheme: $store.selectedTheme)

                Picker("Density", selection: $store.appearancePreferences.density) {
                    ForEach(AppearanceDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.appearancePreferences.density.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PolicyToggleRow(
                    title: "High-contrast accents",
                    detail: "Use stronger accent treatments for important controls and status marks.",
                    isEnabled: $store.appearancePreferences.usesHighContrastAccents
                )

                AppearancePreview(
                    theme: store.selectedTheme,
                    preferences: store.appearancePreferences
                )
            }
        }
    }
}

private struct AuthSettingsTab: View {
    @Binding var store: WorkspaceStore

    var body: some View {
        ContentGroup(title: "Auth providers") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach($store.authProviders) { $provider in
                    ProviderControlRow(provider: $provider)
                    if provider.id != store.authProviders.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct SecuritySettingsTab: View {
    @Binding var store: WorkspaceStore

    var body: some View {
        ContentGroup(title: "Security policy") {
            VStack(alignment: .leading, spacing: 12) {
                PolicyToggleRow(
                    title: "Require 2FA",
                    detail: "Ask every member to add a second factor before they can use the workspace.",
                    isEnabled: $store.securityPolicy.requiresTwoFactor
                )
                PolicyToggleRow(
                    title: "Allow passkeys",
                    detail: "Let users sign in with platform passkeys on supported devices.",
                    isEnabled: $store.securityPolicy.allowsPasskeys
                )
                PolicyToggleRow(
                    title: "Allow personal accounts",
                    detail: "Permit Google, GitHub, and email users outside a managed business domain.",
                    isEnabled: $store.securityPolicy.allowsPersonalAccounts
                )
                PolicyToggleRow(
                    title: "Require SSO for business users",
                    detail: "Force company-domain accounts through configured Google, Microsoft, OIDC, or SAML SSO.",
                    isEnabled: $store.securityPolicy.requiresSSOForBusinessUsers
                )
            }
        }
    }
}

private struct MembersSettingsTab: View {
    let store: WorkspaceStore

    var body: some View {
        ContentGroup(title: "Members") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.members) { member in
                    MemberRow(member: member)
                    if member.id != store.members.last?.id || !store.pendingInvites.isEmpty {
                        Divider()
                    }
                }

                ForEach(store.pendingInvites) { invite in
                    InviteRow(invite: invite)
                    if invite.id != store.pendingInvites.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct HostingSettingsTab: View {
    var body: some View {
        ContentGroup(title: "Self-hosting") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsChecklistRow(title: "Docker Compose", detail: "Local-first deployment for early teams.", systemImage: "shippingbox")
                Divider()
                SettingsChecklistRow(title: "PostgreSQL", detail: "Primary relational store for workspace data.", systemImage: "cylinder.split.1x2")
                Divider()
                SettingsChecklistRow(title: "Redis", detail: "Presence, jobs, notifications, and realtime fanout.", systemImage: "bolt.horizontal")
                Divider()
                SettingsChecklistRow(title: "Object storage", detail: "Files, attachments, avatars, and imports.", systemImage: "externaldrive")
            }
        }
    }
}
