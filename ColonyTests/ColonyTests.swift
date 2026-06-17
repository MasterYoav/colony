//
//  ColonyTests.swift
//  ColonyTests
//
//  Created by Yoav Peretz on 17/06/2026.
//

import Testing
import Foundation
@testable import Colony

@MainActor
struct ColonyTests {

    @Test func sampleWorkspaceStartsWithExpectedMetrics() {
        let store = WorkspaceStore.sample()

        #expect(store.activeChannelCount == 3)
        #expect(store.openTaskCount == 4)
        #expect(store.crmRecordCount == 4)
        #expect(store.ssoProviderCount == 3)
        #expect(store.members.count == 3)
        #expect(store.pendingInvites.count == 1)
        #expect(store.enabledAuthProviderCount == 3)
    }

    @Test func sendMessageAppendsToSelectedChannelAndClearsDraft() throws {
        var store = WorkspaceStore.sample()
        let channelID = try #require(store.selectedChannelID)
        let initialMessageCount = store.activeChannel.messages.count

        store.messageText = "Let's keep chat connected to CRM and tasks."
        store.sendMessage(to: channelID)

        #expect(store.activeChannel.messages.count == initialMessageCount + 1)
        #expect(store.activeChannel.messages.last?.body == "Let's keep chat connected to CRM and tasks.")
        #expect(store.messageText.isEmpty)
    }

    @Test func createChannelAddsChannelSelectsItAndRecordsActivity() {
        var store = WorkspaceStore.sample()
        let initialChannelCount = store.channels.count
        let initialUpdateCount = store.updates.count

        store.createChannel(name: "Customer Success", description: "Renewals and customer health")

        #expect(store.channels.count == initialChannelCount + 1)
        #expect(store.activeChannel.name == "customer-success")
        #expect(store.selectedSection == .messages)
        #expect(store.updates.count == initialUpdateCount + 1)
        #expect(store.updates.first?.title == "Channel created")
    }

    @Test func createTaskAddsTaskAndRecordsActivity() {
        var store = WorkspaceStore.sample()
        let initialTaskCount = store.tasks.count

        store.createTask(title: "Design passkey setup", owner: "Maya", priority: "High", status: .active)

        #expect(store.tasks.count == initialTaskCount + 1)
        #expect(store.tasks.last?.title == "Design passkey setup")
        #expect(store.tasks.last?.status == .active)
        #expect(store.selectedSection == .work)
        #expect(store.updates.first?.title == "Task created")
    }

    @Test func createContactAddsContactWithInitialsAndRecordsActivity() {
        var store = WorkspaceStore.sample()
        let initialContactCount = store.contacts.count

        store.createContact(name: "Lior Stein", company: "Northwind", stage: "Pilot")

        #expect(store.contacts.count == initialContactCount + 1)
        #expect(store.contacts.last?.initials == "LS")
        #expect(store.selectedSection == .crm)
        #expect(store.updates.first?.title == "Contact created")
    }

    @Test func updateTaskStatusMovesTaskAndRecordsActivity() throws {
        var store = WorkspaceStore.sample()
        let taskID = try #require(store.tasks.first?.id)

        store.updateTaskStatus(taskID: taskID, status: .review)

        #expect(store.tasks.first?.status == .review)
        #expect(store.updates.first?.title == "Task moved")
    }

    @Test func updateContactStageMovesContactAndRecordsActivity() throws {
        var store = WorkspaceStore.sample()
        let contactID = try #require(store.contacts.first?.id)

        store.updateContactStage(contactID: contactID, stage: "Customer")

        #expect(store.contacts.first?.stage == "Customer")
        #expect(store.updates.first?.title == "CRM stage updated")
    }

    @Test func prepareInviteAddsPendingInviteAndRecordsActivity() {
        var store = WorkspaceStore.sample()
        let initialInviteCount = store.pendingInvites.count

        store.prepareInvite(email: "ops@example.com", role: .admin)

        #expect(store.pendingInvites.count == initialInviteCount + 1)
        #expect(store.pendingInvites.last?.email == "ops@example.com")
        #expect(store.pendingInvites.last?.role == .admin)
        #expect(store.updates.first?.title == "Invite prepared")
    }

    @Test func securityPolicyAndProviderStatusCanBeConfiguredAndEncoded() throws {
        var store = WorkspaceStore.sample()
        store.securityPolicy.requiresTwoFactor = false
        store.securityPolicy.requiresSSOForBusinessUsers = true
        store.appearancePreferences.density = .compact
        store.appearancePreferences.usesHighContrastAccents = true

        let microsoftIndex = try #require(store.authProviders.firstIndex { $0.kind == .microsoft })
        store.authProviders[microsoftIndex].status = .enabled

        let data = try JSONEncoder().encode(store)
        let decodedStore = try JSONDecoder().decode(WorkspaceStore.self, from: data)

        #expect(decodedStore.securityPolicy.requiresTwoFactor == false)
        #expect(decodedStore.securityPolicy.requiresSSOForBusinessUsers)
        #expect(decodedStore.authProviders[microsoftIndex].status == .enabled)
        #expect(decodedStore.appearancePreferences.density == .compact)
        #expect(decodedStore.appearancePreferences.usesHighContrastAccents)
    }

    @Test func appearancePreferencesDefaultWhenDecodingOlderWorkspaceJSON() throws {
        let store = WorkspaceStore.sample()
        let data = try JSONEncoder().encode(store)
        var payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "appearancePreferences")

        let olderData = try JSONSerialization.data(withJSONObject: payload)
        let decodedStore = try JSONDecoder().decode(WorkspaceStore.self, from: olderData)

        #expect(decodedStore.appearancePreferences == .default)
        #expect(decodedStore.profilePreferences == .default)
        #expect(decodedStore.channels.count == store.channels.count)
    }

    @Test func workspaceStoreRoundTripsThroughJSON() throws {
        var store = WorkspaceStore.sample()
        store.createChannel(name: "Design Systems", description: "Tokens, components, and UI polish")
        store.createTask(title: "Persist workspace state", owner: "Yoav", priority: "High", status: .active)

        let data = try JSONEncoder().encode(store)
        let decodedStore = try JSONDecoder().decode(WorkspaceStore.self, from: data)

        #expect(decodedStore == store)
        #expect(decodedStore.activeChannel.name == "design-systems")
    }
}
