//
//  SettingsDetailView.swift
//  Colony
//
//  Created by Yoav Peretz on 18/06/2026.
//

import SwiftUI

struct SettingsOverview: View {
    @Binding var store: WorkspaceStore

    var body: some View {
        SettingsReadinessPanel(store: store)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
            SettingsCard(title: "Authentication", detail: "\(store.enabledAuthProviderCount) enabled providers, \(store.ssoProviderCount) SSO-capable providers configured.", systemImage: "lock.shield", color: .blue)
            SettingsCard(title: "Self-hosting", detail: "Docker Compose first, with PostgreSQL, Redis, object storage, and a reverse proxy.", systemImage: "server.rack", color: .green)
            SettingsCard(title: "Appearance", detail: "\(store.selectedTheme.title) accent, \(store.appearancePreferences.density.title.lowercased()) density, and user-controlled navigation preferences.", systemImage: "paintpalette", color: store.selectedTheme.accentColor)
            SettingsCard(title: "Members", detail: "\(store.members.count) active members and \(store.pendingInvites.count) pending invite.", systemImage: "person.2", color: .orange)
        }

        Picker("Settings", selection: $store.selectedSettingsTab) {
            ForEach(WorkspaceSettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
        }
        .pickerStyle(.segmented)

        switch store.selectedSettingsTab {
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

private struct SettingsReadinessPanel: View {
    let store: WorkspaceStore

    var body: some View {
        ContentGroup(title: "Workspace readiness") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                SettingsReadinessItem(
                    title: "Identity",
                    value: "\(store.enabledAuthProviderCount)/\(store.authProviders.count)",
                    detail: "providers enabled",
                    systemImage: "person.badge.key",
                    color: .blue
                )

                SettingsReadinessItem(
                    title: "Security",
                    value: securityScore,
                    detail: "policy strength",
                    systemImage: "checkmark.shield",
                    color: .green
                )

                SettingsReadinessItem(
                    title: "Members",
                    value: "\(store.members.count)",
                    detail: "\(store.pendingInvites.count) pending invite",
                    systemImage: "person.2",
                    color: .orange
                )

                SettingsReadinessItem(
                    title: "Hosting",
                    value: "Local",
                    detail: "compose target",
                    systemImage: "server.rack",
                    color: .purple
                )
            }
        }
    }

    private var securityScore: String {
        let enabledPolicies = [
            store.securityPolicy.requiresTwoFactor,
            store.securityPolicy.allowsPasskeys,
            store.securityPolicy.requiresSSOForBusinessUsers
        ].filter { $0 }.count

        return "\(enabledPolicies)/3"
    }
}

private struct SettingsReadinessItem: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
