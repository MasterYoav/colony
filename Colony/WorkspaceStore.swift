//
//  WorkspaceStore.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import Foundation
import SwiftUI

struct WorkspaceStore: Codable, Equatable {
    var selectedSection: ColonySection?
    var selectedChannelID: ColonyChannel.ID?
    var selectedTheme: ColonyTheme
    var messageText: String
    var channels: [ColonyChannel]
    var tasks: [ColonyTask]
    var contacts: [ColonyContact]
    var updates: [ColonyUpdate]
    var members: [WorkspaceMember]
    var pendingInvites: [PendingInvite]
    var authProviders: [AuthProvider]
    var securityPolicy: SecurityPolicy
    var appearancePreferences: AppearancePreferences
    var profilePreferences: ProfilePreferences

    init(
        selectedSection: ColonySection? = .home,
        selectedChannelID: ColonyChannel.ID? = nil,
        selectedTheme: ColonyTheme = .system,
        messageText: String = "",
        channels: [ColonyChannel],
        tasks: [ColonyTask],
        contacts: [ColonyContact],
        updates: [ColonyUpdate],
        members: [WorkspaceMember],
        pendingInvites: [PendingInvite],
        authProviders: [AuthProvider],
        securityPolicy: SecurityPolicy = .recommended,
        appearancePreferences: AppearancePreferences = .default,
        profilePreferences: ProfilePreferences = .default
    ) {
        self.selectedSection = selectedSection
        self.selectedChannelID = selectedChannelID ?? channels.first?.id
        self.selectedTheme = selectedTheme
        self.messageText = messageText
        self.channels = channels
        self.tasks = tasks
        self.contacts = contacts
        self.updates = updates
        self.members = members
        self.pendingInvites = pendingInvites
        self.authProviders = authProviders
        self.securityPolicy = securityPolicy
        self.appearancePreferences = appearancePreferences
        self.profilePreferences = profilePreferences
    }

    var activeChannel: ColonyChannel {
        guard let selectedChannelID,
              let channel = channels.first(where: { $0.id == selectedChannelID }) else {
            return channels[0]
        }

        return channel
    }

    var activeChannelCount: Int {
        channels.count
    }

    var openTaskCount: Int {
        tasks.filter { $0.status != .review }.count
    }

    var taskCategories: [String] {
        Array(Set(tasks.map(\.category))).sorted()
    }

    var crmRecordCount: Int {
        contacts.count
    }

    var ssoProviderCount: Int {
        authProviders.filter { provider in
            [.google, .microsoft, .oidc, .saml].contains(provider.kind)
        }.count
    }

    var enabledAuthProviderCount: Int {
        authProviders.filter { $0.status == .enabled }.count
    }

    mutating func sendMessage(to channelID: ColonyChannel.ID) {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty,
              let channelIndex = channels.firstIndex(where: { $0.id == channelID }) else {
            return
        }

        channels[channelIndex].messages.append(
            ColonyMessage(
                author: "Yoav",
                time: Self.shortTimeFormatter.string(from: Date()),
                body: trimmedMessage,
                authorColor: .blue
            )
        )
        messageText = ""
    }

    mutating func createUpdate(title: String, detail: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedDetail.isEmpty else {
            return
        }

        updates.insert(
            ColonyUpdate(
                title: trimmedTitle,
                detail: trimmedDetail,
                systemImage: "sparkles",
                color: selectedTheme.colorToken
            ),
            at: 0
        )
    }

    mutating func createChannel(name: String, description: String) {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !trimmedDescription.isEmpty else {
            return
        }

        let channel = ColonyChannel(
            name: normalizedName,
            description: trimmedDescription,
            unreadCount: 0,
            messages: [
                ColonyMessage(
                    author: "Colony",
                    time: Self.shortTimeFormatter.string(from: Date()),
                    body: "#\(normalizedName) was created.",
                    authorColor: selectedTheme.colorToken
                )
            ]
        )

        channels.append(channel)
        selectedSection = .messages
        selectedChannelID = channel.id
        addSystemUpdate(
            title: "Channel created",
            detail: "#\(normalizedName) is ready for team conversation.",
            systemImage: "number"
        )
    }

    mutating func createTask(title: String, owner: String, priority: String, status: TaskStatus) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedOwner.isEmpty else {
            return
        }

        tasks.append(
            ColonyTask(
                title: trimmedTitle,
                owner: trimmedOwner,
                priority: priority,
                status: status
            )
        )
        selectedSection = .work
        addSystemUpdate(
            title: "Task created",
            detail: "\(trimmedTitle) is assigned to \(trimmedOwner).",
            systemImage: "checkmark.circle"
        )
    }

    mutating func createContact(name: String, company: String, stage: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCompany.isEmpty, !trimmedStage.isEmpty else {
            return
        }

        contacts.append(
            ColonyContact(
                name: trimmedName,
                company: trimmedCompany,
                stage: trimmedStage,
                initials: Self.initials(for: trimmedName),
                color: selectedTheme.colorToken
            )
        )
        selectedSection = .crm
        addSystemUpdate(
            title: "Contact created",
            detail: "\(trimmedName) from \(trimmedCompany) was added to CRM.",
            systemImage: "person.crop.rectangle.stack"
        )
    }

    mutating func updateTaskStatus(taskID: ColonyTask.ID, status: TaskStatus) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[taskIndex].status != status else {
            return
        }

        tasks[taskIndex].status = status
        addSystemUpdate(
            title: "Task moved",
            detail: "\(tasks[taskIndex].title) moved to \(status.title).",
            systemImage: status.systemImage
        )
    }

    mutating func updateContactStage(contactID: ColonyContact.ID, stage: String) {
        guard let contactIndex = contacts.firstIndex(where: { $0.id == contactID }),
              contacts[contactIndex].stage != stage else {
            return
        }

        contacts[contactIndex].stage = stage
        addSystemUpdate(
            title: "CRM stage updated",
            detail: "\(contacts[contactIndex].name) moved to \(stage).",
            systemImage: "arrow.triangle.branch"
        )
    }

    mutating func prepareInvite(email: String, role: WorkspaceRole) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            return
        }

        pendingInvites.append(PendingInvite(email: trimmedEmail, role: role))
        addSystemUpdate(
            title: "Invite prepared",
            detail: "\(trimmedEmail) will join as \(role.title).",
            systemImage: "person.badge.plus"
        )
    }

    static func sample() -> WorkspaceStore {
        WorkspaceStore(
            channels: SampleData.channels,
            tasks: SampleData.tasks,
            contacts: SampleData.contacts,
            updates: SampleData.updates,
            members: SampleData.members,
            pendingInvites: SampleData.pendingInvites,
            authProviders: SampleData.authProviders
        )
    }

    static let contactStages = [
        "Discovery",
        "Pilot",
        "Proposal",
        "Security review",
        "Customer"
    ]

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private mutating func addSystemUpdate(title: String, detail: String, systemImage: String) {
        updates.insert(
            ColonyUpdate(
                title: title,
                detail: detail,
                systemImage: systemImage,
                color: selectedTheme.colorToken
            ),
            at: 0
        )
    }

    private static func initials(for name: String) -> String {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()

        return initials.isEmpty ? "?" : initials.uppercased()
    }
}

extension WorkspaceStore {
    private enum CodingKeys: String, CodingKey {
        case selectedSection
        case selectedChannelID
        case selectedTheme
        case messageText
        case channels
        case tasks
        case contacts
        case updates
        case members
        case pendingInvites
        case authProviders
        case securityPolicy
        case appearancePreferences
        case profilePreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        try self.init(
            selectedSection: container.decodeIfPresent(ColonySection.self, forKey: .selectedSection),
            selectedChannelID: container.decodeIfPresent(ColonyChannel.ID.self, forKey: .selectedChannelID),
            selectedTheme: container.decodeIfPresent(ColonyTheme.self, forKey: .selectedTheme) ?? .system,
            messageText: container.decodeIfPresent(String.self, forKey: .messageText) ?? "",
            channels: container.decode([ColonyChannel].self, forKey: .channels),
            tasks: container.decode([ColonyTask].self, forKey: .tasks),
            contacts: container.decode([ColonyContact].self, forKey: .contacts),
            updates: container.decode([ColonyUpdate].self, forKey: .updates),
            members: container.decode([WorkspaceMember].self, forKey: .members),
            pendingInvites: container.decode([PendingInvite].self, forKey: .pendingInvites),
            authProviders: container.decode([AuthProvider].self, forKey: .authProviders),
            securityPolicy: container.decodeIfPresent(SecurityPolicy.self, forKey: .securityPolicy) ?? .recommended,
            appearancePreferences: container.decodeIfPresent(AppearancePreferences.self, forKey: .appearancePreferences) ?? .default,
            profilePreferences: container.decodeIfPresent(ProfilePreferences.self, forKey: .profilePreferences) ?? .default
        )
    }
}
