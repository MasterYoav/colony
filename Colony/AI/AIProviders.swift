//
//  AIProviders.swift
//  Colony
//
//  Which model runs the agents, and the user's own AI accounts.
//
//  - Apple Intelligence (on device) is the default and needs no account.
//  - Optionally the user connects their own OpenAI, Anthropic, Google Gemini or any
//    OpenAI-compatible server (OpenRouter, Ollama, LM Studio…) with an API key.
//  - Optionally Jev (TypeSafe) gives agents fast, calibrated yes/no and pick-one
//    judgments.
//
//  API keys live in the Keychain, synced by iCloud Keychain — never in SwiftData or
//  key-value storage. Which provider and model to use is a normal preference
//  (`AISettings`, synced through iCloud key-value storage).
//

import Foundation
import Observation
import Security

// MARK: - Providers

nonisolated enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case device, openai, anthropic, gemini, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: "Apple Intelligence"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .gemini: "Google Gemini"
        case .custom: "Other (OpenAI-compatible)"
        }
    }

    /// Short name for menus and badges.
    var shortTitle: String {
        switch self {
        case .device: "This device"
        case .openai: "OpenAI"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        case .custom: "Custom server"
        }
    }

    var subtitle: String {
        switch self {
        case .device: "On device. Private, free, no account."
        case .openai: "GPT models with your OpenAI API key."
        case .anthropic: "Claude models with your Anthropic API key."
        case .gemini: "Gemini models with your Google AI Studio key."
        case .custom: "OpenRouter, Ollama, LM Studio or any OpenAI-style server."
        }
    }

    var symbol: String {
        switch self {
        case .device: "apple.intelligence"
        case .openai: "circle.hexagongrid"
        case .anthropic: "asterisk"
        case .gemini: "sparkle"
        case .custom: "server.rack"
        }
    }

    var isCloud: Bool { self != .device }

    /// Used until the user picks one from the provider's own list.
    var defaultModel: String {
        switch self {
        case .device: ""
        case .openai: "gpt-5-mini"
        case .anthropic: "claude-sonnet-4-5"
        case .gemini: "gemini-2.5-flash"
        case .custom: ""
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .device: ""
        case .openai: "sk-…"
        case .anthropic: "sk-ant-…"
        case .gemini: "AIza…"
        case .custom: "Optional for local servers"
        }
    }

    /// Where to create a key.
    var keyURL: URL? {
        switch self {
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .device, .custom: nil
        }
    }

    /// A custom server may run locally without a key.
    var requiresKey: Bool { self != .device && self != .custom }

    var keychainAccount: String { "ai.\(rawValue)" }
}

/// Everything a request needs; resolved on the main actor, then sent off it.
nonisolated struct AIConfig: Sendable, Equatable {
    var provider: AIProvider
    var model: String
    var key: String
    /// Custom servers: e.g. https://openrouter.ai/api/v1 or http://localhost:11434/v1
    var baseURL: String = ""
}

// MARK: - Settings (synced, not secret)

nonisolated struct AISettings: Codable, Equatable, Sendable {
    /// The model agents use unless an agent picks its own.
    var provider: AIProvider = .device
    /// Chosen model per provider (raw value -> model id).
    var models: [String: String] = [:]
    var customURL: String = ""
    /// Give agents the ask_jev tool (needs a Jev key).
    var jevEnabled: Bool = false

    init() {}

    /// Tolerant: settings written by an older or newer Colony still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? c.decodeIfPresent(AIProvider.self, forKey: .provider)) ?? .device
        models = (try? c.decodeIfPresent([String: String].self, forKey: .models)) ?? [:]
        customURL = (try? c.decodeIfPresent(String.self, forKey: .customURL)) ?? ""
        jevEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .jevEnabled)) ?? false
    }

    func model(for provider: AIProvider) -> String {
        let chosen = models[provider.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return chosen.isEmpty ? provider.defaultModel : chosen
    }
}

// MARK: - Keychain

/// Generic passwords, synced with iCloud Keychain when the app is signed for it.
nonisolated enum Keychain {
    static let service = "yoavperetz.Colony.ai"

    private static func base(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    static func read(_ account: String) -> String? {
        var query = base(account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, for account: String) -> Bool {
        delete(account)
        let data = Data(value.utf8)
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrLabel as String] = "Colony · \(account)"
        if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return true }
        // Builds without iCloud Keychain (unsigned, simulator): keep it on this device.
        item[kSecAttrSynchronizable as String] = false
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        var query = base(account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Accounts

/// The user's saved keys and the result of the last connection check.
@MainActor
@Observable
final class AIAccounts {
    enum Check: Equatable {
        case idle
        case checking
        case connected(String)
        case failed(String)
    }

    static let jevAccount = "jev"

    /// Which accounts have a key (Keychain reads are cheap but not free; cached).
    private(set) var savedKeys: Set<String> = []
    /// Models offered by each provider, loaded by "Check connection".
    private(set) var availableModels: [AIProvider: [String]] = [:]
    private(set) var checks: [String: Check] = [:]

    init() { refresh() }

    func refresh() {
        let accounts = AIProvider.allCases.filter(\.isCloud).map(\.keychainAccount) + [Self.jevAccount]
        savedKeys = Set(accounts.filter { Keychain.read($0) != nil })
    }

    func hasKey(_ provider: AIProvider) -> Bool { savedKeys.contains(provider.keychainAccount) }
    var hasJevKey: Bool { savedKeys.contains(Self.jevAccount) }

    func save(_ key: String, for provider: AIProvider) {
        store(key, account: provider.keychainAccount)
        checks[provider.rawValue] = .idle
    }

    func removeKey(for provider: AIProvider) {
        Keychain.delete(provider.keychainAccount)
        availableModels[provider] = nil
        checks[provider.rawValue] = .idle
        refresh()
    }

    func saveJevKey(_ key: String) {
        store(key, account: Self.jevAccount)
        checks[Self.jevAccount] = .idle
    }

    func removeJevKey() {
        Keychain.delete(Self.jevAccount)
        checks[Self.jevAccount] = .idle
        refresh()
    }

    func check(for provider: AIProvider) -> Check { checks[provider.rawValue] ?? .idle }
    var jevCheck: Check { checks[Self.jevAccount] ?? .idle }

    /// A ready-to-use configuration, or nil if the provider isn't set up.
    func config(for provider: AIProvider, settings: AISettings) -> AIConfig? {
        guard provider.isCloud else { return nil }
        let key = Keychain.read(provider.keychainAccount) ?? ""
        if provider.requiresKey, key.isEmpty { return nil }
        let model = settings.model(for: provider)
        guard !model.isEmpty else { return nil }
        if provider == .custom, URL(string: settings.customURL)?.host == nil { return nil }
        return AIConfig(provider: provider, model: model, key: key, baseURL: settings.customURL)
    }

    /// Whether this provider can run agents right now (keys and model set).
    func isReady(_ provider: AIProvider, settings: AISettings) -> Bool {
        config(for: provider, settings: settings) != nil
    }

    var jevKey: String? { Keychain.read(Self.jevAccount).flatMap { $0.isEmpty ? nil : $0 } }

    // MARK: Connection checks

    /// Lists the provider's models: proves the key works without spending tokens.
    func checkConnection(_ provider: AIProvider, settings: AISettings) async {
        let key = Keychain.read(provider.keychainAccount) ?? ""
        guard !provider.requiresKey || !key.isEmpty else {
            checks[provider.rawValue] = .failed("Add an API key first.")
            return
        }
        checks[provider.rawValue] = .checking
        let config = AIConfig(provider: provider, model: settings.model(for: provider), key: key, baseURL: settings.customURL)
        do {
            let models = try await CloudModel.listModels(config)
            availableModels[provider] = models
            checks[provider.rawValue] = .connected(models.isEmpty ? "Connected" : "Connected · \(models.count) models")
        } catch {
            checks[provider.rawValue] = .failed(error.localizedDescription)
        }
    }

    func checkJev() async {
        guard let key = jevKey else {
            checks[Self.jevAccount] = .failed("Add your Jev API key first.")
            return
        }
        checks[Self.jevAccount] = .checking
        do {
            let answer = try await Jev.ask(key: key, state: "Colony is checking that its connection to Jev works.", question: "Is this a connection test?")
            checks[Self.jevAccount] = .connected("Connected · \(answer.model ?? "Jev")")
        } catch {
            checks[Self.jevAccount] = .failed(error.localizedDescription)
        }
    }

    private func store(_ key: String, account: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { Keychain.delete(account) } else { Keychain.save(key, for: account) }
        refresh()
    }
}
