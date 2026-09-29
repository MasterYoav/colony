//
//  SettingsViews.swift
//  Colony
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.preferences

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Settings", subtitle: "Preferences roam with your iCloud account")

                Card {
                    Text("Profile").appFont(.headline).foregroundStyle(Theme.text)
                    FormField("Your name", text: $prefs.displayName, leading: Image(systemName: "person"), limit: 40, textContentType: .name, style: fieldStyle)
                    FormField("Workspace name", text: $prefs.workspaceName, leading: Image(systemName: "square.stack.3d.up"), limit: 32, style: fieldStyle)
                }

                Card {
                    Text("Appearance").appFont(.headline).foregroundStyle(Theme.text)
                    GlassSegments(options: AppearancePreference.allCases, selection: $prefs.appearance, label: { $0.title }, systemImage: { $0.symbol })
                        .frame(maxWidth: 360)
                    SidebarDivider().padding(.vertical, 2)
                    FontPickerRow(
                        title: "Interface font",
                        detail: "Sidebar, headers, buttons and labels",
                        sample: "Home  Updates  Settings",
                        family: $prefs.uiFontFamily
                    )
                    FontPickerRow(
                        title: "Data font",
                        detail: "Tasks, messages, contacts and numbers",
                        sample: "Ship the onboarding flow · 42",
                        family: $prefs.dataFontFamily
                    )
                    if !prefs.uiFontFamily.isEmpty || !prefs.dataFontFamily.isEmpty {
                        Button("Reset to system fonts", systemImage: "arrow.counterclockwise") {
                            prefs.uiFontFamily = ""
                            prefs.dataFontFamily = ""
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                }

                Card {
                    HStack {
                        Text("iCloud").appFont(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await app.iCloud.refresh() } }
                            .buttonStyle(QuietButtonStyle())
                    }
                    HStack(spacing: 12) {
                        Image(systemName: app.iCloud.displayState.symbol)
                            .appFont(.system(size: 22))
                            .foregroundStyle(app.iCloud.displayState.isHealthy ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.iCloud.displayState.title).appFont(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                            Text(iCloudDetail).appFont(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Text("Projects, tasks, messages and contacts are stored in your private iCloud database (\(CloudStore.containerIdentifier)). Only you can read them; Colony has no server.")
                        .appFont(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Card {
                    Text("About").appFont(.headline).foregroundStyle(Theme.text)
                    Text("Colony collects no data about you. Nothing leaves your devices except to your own iCloud.")
                        .appFont(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    HStack(spacing: 8) {
                        Link(destination: ColonyLinks.privacy) {
                            Label("Privacy policy", systemImage: "hand.raised")
                        }
                        Link(destination: ColonyLinks.accessibility) {
                            Label("Accessibility", systemImage: "accessibility")
                        }
                        Link(destination: ColonyLinks.support) {
                            Label("Support", systemImage: "questionmark.circle")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    Text("Version \(ColonyLinks.version)")
                        .appFont(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Settings")
    }

    private var fieldStyle: FormField.Style {
        FormField.Style(field: Theme.field, label: Theme.text, secondaryLabel: Theme.secondaryText, focusRing: Theme.strongStroke, height: 50, cornerRadius: 12)
    }

    private var iCloudDetail: String {
        switch app.iCloud.displayState {
        case .available: "Changes sync automatically to every device signed in with your Apple Account."
        case .noAccount: "Sign in to iCloud in System Settings to sync. Data is kept locally until then."
        case .restricted: "iCloud is restricted by Screen Time or device management."
        case .temporarilyUnavailable: "iCloud will resume syncing automatically."
        case .localOnly(let reason): reason
        case .error(let message): message
        case .checking: "Contacting iCloud…"
        }
    }
}

// MARK: - Apple services

struct AppleServicesView: View {
    @Environment(AppModel.self) private var app
    @Query private var tasks: [TaskItem]

    var body: some View {
        @Bindable var prefs = app.preferences

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Apple services", subtitle: "Colony connects to Apple's built-in apps. No third-party accounts.")

                serviceCard(
                    symbol: "icloud.fill", color: .blue, title: "iCloud",
                    detail: "Stores every record in your private CloudKit database and syncs preferences with iCloud key-value storage.",
                    status: app.iCloud.displayState.title, healthy: app.iCloud.displayState.isHealthy
                ) { EmptyView() }

                serviceCard(
                    symbol: "checklist", color: .orange, title: "Reminders",
                    detail: "Mirror tasks into Apple Reminders so due dates alert you on iPhone, Apple Watch and Mac.",
                    status: remindersStatus, healthy: app.reminders.canWrite
                ) {
                    if app.reminders.canWrite {
                        Toggle("Mirror tasks to Reminders", isOn: $prefs.mirrorsToReminders)
                            .onChange(of: prefs.mirrorsToReminders) { _, on in
                                guard on else { return }
                                let open = tasks.filter { !$0.isDone }
                                open.forEach { app.reminders.mirror($0) }
                                app.show("Mirrored \(open.count) tasks to Reminders")
                            }
                        if let error = app.reminders.lastError {
                            Text(error).appFont(.caption).foregroundStyle(.red)
                        }
                    } else {
                        Button("Connect Reminders") { app.present(.connectReminders) }.buttonStyle(QuietButtonStyle())
                    }
                }

                serviceCard(
                    symbol: "person.crop.circle.fill", color: .gray, title: "Contacts",
                    detail: "Import people from Apple Contacts into the CRM. Colony only reads; it never edits your address book.",
                    status: contactsStatus, healthy: app.contacts.canRead
                ) {
                    if app.contacts.canRead {
                        Button("Import people…") { app.present(.importContacts) }.buttonStyle(QuietButtonStyle())
                    } else {
                        Button("Connect Contacts") { app.present(.connectContacts) }.buttonStyle(QuietButtonStyle())
                    }
                }

                serviceCard(
                    symbol: "square.and.arrow.up", color: .teal, title: "Share, Mail & FaceTime",
                    detail: "Share transcripts with the system share sheet, and call or email contacts through Phone, FaceTime and Mail.",
                    status: "Built in", healthy: true
                ) { EmptyView() }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Apple services")
    }

    private var remindersStatus: String {
        app.reminders.canWrite && app.preferences.mirrorsToReminders ? "Mirroring" : app.reminders.statusTitle
    }

    private var contactsStatus: String { app.contacts.statusTitle }

    private func serviceCard<Controls: View>(symbol: String, color: ColonyColor, title: String, detail: String, status: String, healthy: Bool, @ViewBuilder controls: () -> Controls) -> some View {
        let controls = controls()
        return Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .appFont(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(color.color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).appFont(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Label(status, systemImage: healthy ? "checkmark.circle.fill" : "circle.dashed")
                            .appFont(.caption)
                            .foregroundStyle(healthy ? Color.green : Theme.secondaryText)
                    }
                    Text(detail).appFont(.subheadline).foregroundStyle(Theme.secondaryText)
                    controls.padding(.top, 6)
                }
            }
        }
    }
}
