//
//  AISettingsPage.swift
//  Colony
//
//  Settings › AI: what runs the agents, the user's AI accounts and Jev.
//
//  Keys are typed into secure fields and saved to the Keychain (synced by iCloud
//  Keychain). The page never shows a saved key again — only that one is saved.
//

import SwiftUI

struct AISettingsPage: View {
    @Environment(AppModel.self) private var app
    @State private var expanded: AIProvider?

    var body: some View {
        @Bindable var prefs = app.preferences
        PageHeader(section: .ai, text: "Choose what powers your agents. Apple Intelligence runs privately on this device. You can also connect your own AI account. Keys are kept in your iCloud Keychain.")

        SettingsGroup(header: "Agents run on", footer: "Each agent can use a different one: open the agent, then ⋯ › Runs On.") {
            ForEach(AIProvider.allCases) { provider in
                ProviderRow(
                    provider: provider,
                    isDefault: prefs.ai.provider == provider,
                    status: status(of: provider),
                    choose: { prefs.ai.provider = provider; if provider.isCloud, !isReady(provider) { expanded = provider } }
                )
            }
        }

        SettingsGroup(header: "Your AI accounts", footer: "Colony talks to these services directly with your key. Usage is billed to your account by the provider.") {
            ForEach(AIProvider.allCases.filter(\.isCloud)) { provider in
                AccountSection(provider: provider, isExpanded: Binding(
                    get: { expanded == provider },
                    set: { expanded = $0 ? provider : nil }
                ))
            }
        }

        JevSection()

        SettingsGroup(header: "What gets shared") {
            VStack(alignment: .leading, spacing: 8) {
                SharingLine(symbol: "apple.intelligence", text: "**Apple Intelligence**: everything stays on this device.")
                SharingLine(symbol: "icloud.and.arrow.up", text: "**Cloud models**: an agent's chat and the workspace data its tools read (tasks, customers, messages) are sent to that provider, under your account and its privacy terms.")
                SharingLine(symbol: "scalemass", text: "**Jev**: only the question and the facts an agent asks about.")
            }
            .padding(12)
        }
    }

    private func isReady(_ provider: AIProvider) -> Bool { app.agents.canUse(provider) }

    private func status(of provider: AIProvider) -> ProviderStatus {
        if !provider.isCloud {
            return app.agents.availability == .available ? .ready : .unavailable(app.agents.availability.title)
        }
        return isReady(provider) ? .ready : .notSetUp
    }
}

// MARK: - Providers

enum ProviderStatus: Equatable {
    case ready, notSetUp, unavailable(String)

    var title: String {
        switch self {
        case .ready: "Ready"
        case .notSetUp: "Not set up"
        case .unavailable: "Unavailable"
        }
    }

    var color: Color {
        switch self {
        case .ready: ColonyColor.green.color
        case .notSetUp: Theme.tertiaryText
        case .unavailable: ColonyColor.orange.color
        }
    }
}

private struct ProviderRow: View {
    let provider: AIProvider
    let isDefault: Bool
    let status: ProviderStatus
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 12) {
                ProviderIcon(provider: provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title).appFont(.system(size: 13.5)).foregroundStyle(Theme.text)
                    Text(subtitle).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 6, height: 6)
                    Text(status.title).appFont(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                }
                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                    .appFont(.system(size: 16))
                    .foregroundStyle(isDefault ? Color.accentColor : Theme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.title), \(status.title)\(isDefault ? ", selected" : "")")
        .accessibilityAddTraits(isDefault ? .isSelected : [])
    }

    private var subtitle: String {
        if case let .unavailable(reason) = status { return reason }
        return provider.subtitle
    }
}

struct ProviderIcon: View {
    let provider: AIProvider
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: provider.symbol)
            .appFont(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }

    private var color: Color {
        switch provider {
        case .device: Color(red: 0.55, green: 0.36, blue: 0.96)
        case .openai: Color(white: 0.2)
        case .anthropic: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .custom: Color(white: 0.5)
        }
    }
}

// MARK: - Account

private struct AccountSection: View {
    @Environment(AppModel.self) private var app
    let provider: AIProvider
    @Binding var isExpanded: Bool
    @State private var draftKey = ""

    var body: some View {
        @Bindable var prefs = app.preferences
        VStack(alignment: .leading, spacing: 0) {
            Button { withMotion(.snappy(duration: 0.2)) { isExpanded.toggle() } } label: {
                HStack(spacing: 12) {
                    ProviderIcon(provider: provider, size: 22)
                    Text(provider.title).appFont(.system(size: 13.5)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(summary).appFont(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.right")
                        .appFont(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(provider.title) account, \(summary)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if provider == .custom {
                        Field(title: "Server address", footer: "The OpenAI-style API base, e.g. https://openrouter.ai/api/v1 or http://localhost:11434/v1") {
                            TextField("https://…/v1", text: $prefs.ai.customURL)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                        }
                    }
                    keyField
                    modelField
                    checkRow
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    private var summary: String {
        let hasKey = app.ai.hasKey(provider)
        if provider == .custom { return app.agents.canUse(.custom) ? app.preferences.ai.model(for: .custom) : "Not set up" }
        return hasKey ? app.preferences.ai.model(for: provider) : "No key"
    }

    // Key

    @ViewBuilder
    private var keyField: some View {
        let saved = app.ai.hasKey(provider)
        Field(title: provider == .custom ? "API key (optional)" : "API key", footer: saved ? "Saved in your iCloud Keychain. Paste a new key to replace it." : nil) {
            HStack(spacing: 8) {
                SecureField(saved ? "••••••••••••  saved" : provider.keyPlaceholder, text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveKey)
                    .accessibilityLabel("\(provider.title) API key")
                Button("Save", action: saveKey)
                    .buttonStyle(.dialogPrimary)
                    .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if saved {
                    Button("Remove", role: .destructive) {
                        app.ai.removeKey(for: provider)
                        app.show("Removed the \(provider.title) key")
                    }
                    .buttonStyle(.dialogSecondary)
                }
            }
            if !saved, let url = provider.keyURL {
                Link(destination: url) {
                    Label("Get a key from \(provider.shortTitle)", systemImage: "arrow.up.right")
                        .appFont(.system(size: 12))
                }
            }
        }
    }

    private func saveKey() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        app.ai.save(key, for: provider)
        draftKey = ""
        app.show("Saved the \(provider.title) key")
        Task { await app.ai.checkConnection(provider, settings: app.preferences.ai) }
    }

    // Model

    @ViewBuilder
    private var modelField: some View {
        @Bindable var prefs = app.preferences
        let models = app.ai.availableModels[provider] ?? []
        Field(title: "Model", footer: models.isEmpty ? "Check the connection to choose from your account's models." : nil) {
            HStack(spacing: 8) {
                TextField(provider.defaultModel.isEmpty ? "Model name" : provider.defaultModel, text: Binding(
                    get: { prefs.ai.models[provider.rawValue] ?? "" },
                    set: { prefs.ai.models[provider.rawValue] = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("\(provider.title) model")
                if !models.isEmpty {
                    Menu {
                        ForEach(models.prefix(60), id: \.self) { model in
                            Button(model) { prefs.ai.models[provider.rawValue] = model }
                        }
                    } label: {
                        Text("Choose")
                    }
                    .fixedSize()
                    .accessibilityLabel("Choose a \(provider.title) model")
                }
            }
        }
    }

    // Check

    private var checkRow: some View {
        HStack(spacing: 10) {
            Button("Check connection") {
                Task { await app.ai.checkConnection(provider, settings: app.preferences.ai) }
            }
            .buttonStyle(.dialogSecondary)
            .disabled(app.ai.check(for: provider) == .checking)
            CheckStatus(check: app.ai.check(for: provider))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Jev

private struct JevSection: View {
    @Environment(AppModel.self) private var app
    @State private var draftKey = ""

    var body: some View {
        @Bindable var prefs = app.preferences
        let saved = app.ai.hasJevKey
        SettingsGroup(header: "Jev", footer: "Jev is a decision model by TypeSafe. It doesn't write text; it answers \"how likely is this?\" and \"which one fits?\" with calibrated odds. Agents ask it before judgment calls, and each answer appears in the chat. Works with any of the models above.") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "scalemass.fill")
                    .appFont(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color(red: 0.13, green: 0.62, blue: 0.55).gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let agents ask Jev").appFont(.system(size: 13.5)).foregroundStyle(Theme.text)
                    Text(saved ? "Agents get an ask_jev tool for yes/no and pick-one decisions." : "Add your Jev API key below to turn this on.")
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Toggle("Let agents ask Jev", isOn: $prefs.ai.jevEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!saved)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            VStack(alignment: .leading, spacing: 12) {
                Field(title: "Jev API key", footer: saved ? "Saved in your iCloud Keychain. Paste a new key to replace it." : nil) {
                    HStack(spacing: 8) {
                        SecureField(saved ? "••••••••••••  saved" : "Your TypeSafe API key", text: $draftKey)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                            .accessibilityLabel("Jev API key")
                        Button("Save", action: save)
                            .buttonStyle(.dialogPrimary)
                            .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        if saved {
                            Button("Remove", role: .destructive) {
                                app.ai.removeJevKey()
                                prefs.ai.jevEnabled = false
                                app.show("Removed the Jev key")
                            }
                            .buttonStyle(.dialogSecondary)
                        }
                    }
                    HStack(spacing: 14) {
                        if !saved {
                            Link(destination: Jev.keyURL) { Label("Get a key", systemImage: "arrow.up.right").appFont(.system(size: 12)) }
                        }
                        Link(destination: Jev.docsURL) { Label("What is Jev?", systemImage: "arrow.up.right").appFont(.system(size: 12)) }
                    }
                }
                HStack(spacing: 10) {
                    Button("Check connection") { Task { await app.ai.checkJev() } }
                        .buttonStyle(.dialogSecondary)
                        .disabled(!saved || app.ai.jevCheck == .checking)
                    CheckStatus(check: app.ai.jevCheck)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
        }
    }

    private func save() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        app.ai.saveJevKey(key)
        draftKey = ""
        app.preferences.ai.jevEnabled = true
        app.show("Saved the Jev key")
        Task { await app.ai.checkJev() }
    }
}

// MARK: - Pieces

private struct Field<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            content
            if let footer {
                Text(footer)
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CheckStatus: View {
    let check: AIAccounts.Check

    var body: some View {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").appFont(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
        case let .connected(text):
            Label(text, systemImage: "checkmark.circle.fill")
                .appFont(.system(size: 12))
                .foregroundStyle(ColonyColor.green.color)
        case let .failed(text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .appFont(.system(size: 12))
                .foregroundStyle(ColonyColor.orange.color)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SharingLine: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .appFont(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 18)
            Text(text)
                .appFont(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
