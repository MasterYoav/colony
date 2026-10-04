//
//  CloudModel.swift
//  Colony
//
//  Runs an agent turn on the user's own cloud model (OpenAI, Anthropic, Gemini or an
//  OpenAI-compatible server), with the same tools the on-device model uses.
//
//  The tools are the Foundation Models `Tool`s from AgentTools.swift: their
//  `parameters` schema encodes to JSON Schema, and a model's JSON arguments decode
//  back through `GeneratedContent(json:)`. So every tool — and every action row in the
//  chat — works the same whichever model runs the agent.
//
//  Each provider's wire format is a small value type (`ChatFormat`) with pure
//  request/parse functions, so it can be unit-tested without the network.
//

import Foundation
import FoundationModels

// MARK: - Errors

nonisolated enum CloudModelError: LocalizedError, Equatable {
    case badURL
    case http(provider: String, status: Int, message: String)
    case badResponse(String)
    case tooManySteps
    case offline(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            "The server address isn't a valid URL. Check it in Settings › AI."
        case let .http(provider, status, message):
            switch status {
            case 401, 403: "\(provider) didn't accept the API key. Check it in Settings › AI."
            case 404: "\(provider) doesn't know this model. Pick another one in Settings › AI. (\(message))"
            case 429: "\(provider) is rate limiting or the account is out of credits. Try again later. (\(message))"
            case 500...599: "\(provider) is having trouble right now (\(status)). Try again in a moment."
            default: "\(provider) returned an error (\(status)): \(message)"
            }
        case let .badResponse(detail):
            "The model's reply couldn't be read (\(detail))."
        case .tooManySteps:
            "The agent used too many tools in one go and was stopped."
        case let .offline(detail):
            "Couldn't reach the AI service: \(detail)"
        }
    }
}

// MARK: - Tools as JSON

nonisolated struct ToolSpec: Sendable {
    let name: String
    let description: String
    /// JSON Schema of the arguments, as JSON text.
    let schemaJSON: String

    init(_ tool: any Tool) {
        name = tool.name
        description = tool.description
        let data = (try? JSONEncoder().encode(tool.parameters)) ?? Data("{\"type\":\"object\",\"properties\":{}}".utf8)
        schemaJSON = String(decoding: data, as: UTF8.self)
    }

    init(name: String, description: String, schemaJSON: String) {
        self.name = name
        self.description = description
        self.schemaJSON = schemaJSON
    }

    /// The schema as a dictionary, without Apple-specific keys other APIs reject.
    var schema: [String: Any] {
        let raw = (try? JSONSerialization.jsonObject(with: Data(schemaJSON.utf8))) as? [String: Any] ?? [:]
        var clean = Self.strip(raw) as? [String: Any] ?? [:]
        clean["type"] = "object"
        if clean["properties"] == nil { clean["properties"] = [String: Any]() }
        return clean
    }

    /// Gemini's `parameters` takes an OpenAPI-style subset: no additionalProperties.
    var geminiSchema: [String: Any] {
        Self.strip(schema, also: ["additionalProperties"]) as? [String: Any] ?? schema
    }

    private static func strip(_ value: Any, also extra: Set<String> = []) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, inner) in dict where key != "x-order" && key != "title" && !extra.contains(key) {
                out[key] = strip(inner, also: extra)
            }
            return out
        }
        if let array = value as? [Any] { return array.map { strip($0, also: extra) } }
        return value
    }
}

nonisolated struct ToolCall: Sendable, Equatable {
    var id: String
    var name: String
    /// Arguments as JSON text.
    var arguments: String
}

nonisolated enum ToolInvoker {
    /// Runs a tool with JSON arguments; errors go back to the model as text so it can
    /// correct itself.
    static func call(_ tools: [any Tool], _ call: ToolCall) async -> String {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return "There is no tool called \(call.name)."
        }
        do {
            return try await invoke(tool, json: call.arguments.isEmpty ? "{}" : call.arguments)
        } catch {
            return "The arguments for \(call.name) were invalid: \(error.localizedDescription)"
        }
    }

    private static func invoke<T: Tool>(_ tool: T, json: String) async throws -> String {
        let arguments = try T.Arguments(GeneratedContent(json: json))
        let output = try await tool.call(arguments: arguments)
        return (output as? String) ?? String(describing: output)
    }
}

// MARK: - Wire formats

/// One earlier message in the chat.
nonisolated struct ChatLine: Sendable, Equatable {
    enum Role: Sendable { case user, assistant }
    var role: Role
    var text: String
}

/// What a single model response asked for.
nonisolated struct ModelStep: Equatable {
    var text: String
    var calls: [ToolCall]
}

nonisolated protocol ChatFormat {
    init(system: String, history: [ChatLine], prompt: String)
    func request(_ config: AIConfig, tools: [ToolSpec]) throws -> URLRequest
    /// Reads a response and remembers the assistant's message for the next request.
    mutating func read(_ json: [String: Any]) throws -> ModelStep
    mutating func addResults(_ results: [(ToolCall, String)])
}

nonisolated enum HTTP {
    static func jsonRequest(_ url: URL, headers: [String: String], body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func send(_ request: URLRequest, provider: String) async throws -> [String: Any] {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CloudModelError.offline(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            throw CloudModelError.http(provider: provider, status: status, message: errorMessage(json, data))
        }
        guard let json else { throw CloudModelError.badResponse("not JSON") }
        return json
    }

    static func errorMessage(_ json: [String: Any]?, _ data: Data) -> String {
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = json?["message"] as? String { return message }
        if let detail = json?["detail"] as? String { return detail }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }

    static func jsonText(_ value: Any?) -> String {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// OpenAI Chat Completions (also OpenRouter, Ollama, LM Studio, vLLM…).
nonisolated struct OpenAIFormat: ChatFormat {
    private(set) var messages: [[String: Any]]

    init(system: String, history: [ChatLine], prompt: String) {
        messages = [["role": "system", "content": system]]
        messages += history.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        messages.append(["role": "user", "content": prompt])
    }

    static func baseURL(_ config: AIConfig) -> String {
        config.provider == .custom ? config.baseURL : "https://api.openai.com/v1"
    }

    func request(_ config: AIConfig, tools: [ToolSpec]) throws -> URLRequest {
        let base = Self.baseURL(config).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/chat/completions") else { throw CloudModelError.badURL }
        var body: [String: Any] = ["model": config.model, "messages": messages]
        if !tools.isEmpty {
            body["tools"] = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.schema]] }
        }
        return try HTTP.jsonRequest(url, headers: config.key.isEmpty ? [:] : ["Authorization": "Bearer \(config.key)"], body: body)
    }

    mutating func read(_ json: [String: Any]) throws -> ModelStep {
        guard let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else {
            throw CloudModelError.badResponse("no choices")
        }
        let text = message["content"] as? String ?? ""
        let rawCalls = message["tool_calls"] as? [[String: Any]] ?? []
        let calls = rawCalls.compactMap { call -> ToolCall? in
            guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
            return ToolCall(id: call["id"] as? String ?? UUID().uuidString, name: name, arguments: function["arguments"] as? String ?? "{}")
        }
        var assistant: [String: Any] = ["role": "assistant", "content": text.isEmpty ? NSNull() : text]
        if !rawCalls.isEmpty { assistant["tool_calls"] = rawCalls }
        messages.append(assistant)
        return ModelStep(text: text, calls: calls)
    }

    mutating func addResults(_ results: [(ToolCall, String)]) {
        for (call, result) in results {
            messages.append(["role": "tool", "tool_call_id": call.id, "content": result])
        }
    }
}

/// Anthropic Messages API.
nonisolated struct AnthropicFormat: ChatFormat {
    let system: String
    private(set) var messages: [[String: Any]] = []

    init(system: String, history: [ChatLine], prompt: String) {
        self.system = system
        // Must start with the user and alternate; merge neighbours with the same role.
        var lines = Array(history.drop { $0.role == .assistant })
        lines.append(ChatLine(role: .user, text: prompt))
        for line in lines {
            let role = line.role == .user ? "user" : "assistant"
            if let last = messages.last, last["role"] as? String == role, let text = last["content"] as? String {
                messages[messages.count - 1]["content"] = text + "\n\n" + line.text
            } else {
                messages.append(["role": role, "content": line.text])
            }
        }
    }

    func request(_ config: AIConfig, tools: [ToolSpec]) throws -> URLRequest {
        var body: [String: Any] = ["model": config.model, "max_tokens": 2048, "system": system, "messages": messages]
        if !tools.isEmpty {
            body["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] }
        }
        return try HTTP.jsonRequest(
            URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: ["x-api-key": config.key, "anthropic-version": "2023-06-01"],
            body: body
        )
    }

    mutating func read(_ json: [String: Any]) throws -> ModelStep {
        guard let content = json["content"] as? [[String: Any]] else { throw CloudModelError.badResponse("no content") }
        var text: [String] = []
        var calls: [ToolCall] = []
        for block in content {
            switch block["type"] as? String {
            case "text": text.append(block["text"] as? String ?? "")
            case "tool_use":
                calls.append(ToolCall(id: block["id"] as? String ?? "", name: block["name"] as? String ?? "", arguments: HTTP.jsonText(block["input"])))
            default: break
            }
        }
        messages.append(["role": "assistant", "content": content])
        return ModelStep(text: text.joined(separator: "\n"), calls: calls)
    }

    mutating func addResults(_ results: [(ToolCall, String)]) {
        messages.append(["role": "user", "content": results.map { call, result in
            ["type": "tool_result", "tool_use_id": call.id, "content": result] as [String: Any]
        }])
    }
}

/// Google Gemini generateContent.
nonisolated struct GeminiFormat: ChatFormat {
    let system: String
    private(set) var contents: [[String: Any]] = []

    init(system: String, history: [ChatLine], prompt: String) {
        self.system = system
        var lines = history
        lines.append(ChatLine(role: .user, text: prompt))
        for line in lines {
            let role = line.role == .user ? "user" : "model"
            if let last = contents.last, last["role"] as? String == role,
               var parts = last["parts"] as? [[String: Any]] {
                parts.append(["text": line.text])
                contents[contents.count - 1]["parts"] = parts
            } else {
                contents.append(["role": role, "parts": [["text": line.text]]])
            }
        }
    }

    func request(_ config: AIConfig, tools: [ToolSpec]) throws -> URLRequest {
        let model = config.model.hasPrefix("models/") ? String(config.model.dropFirst(7)) : config.model
        guard let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded):generateContent") else {
            throw CloudModelError.badURL
        }
        var body: [String: Any] = ["systemInstruction": ["parts": [["text": system]]], "contents": contents]
        if !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools.map { ["name": $0.name, "description": $0.description, "parameters": $0.geminiSchema] }]]
        }
        return try HTTP.jsonRequest(url, headers: ["x-goog-api-key": config.key], body: body)
    }

    mutating func read(_ json: [String: Any]) throws -> ModelStep {
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else {
            let reason = (json["promptFeedback"] as? [String: Any])?["blockReason"] as? String
            throw CloudModelError.badResponse(reason.map { "blocked: \($0)" } ?? "no candidates")
        }
        let content = candidate["content"] as? [String: Any] ?? ["role": "model", "parts": []]
        let parts = content["parts"] as? [[String: Any]] ?? []
        var text: [String] = []
        var calls: [ToolCall] = []
        for part in parts {
            if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String {
                calls.append(ToolCall(id: call["id"] as? String ?? name, name: name, arguments: HTTP.jsonText(call["args"] ?? [String: Any]())))
            } else if let value = part["text"] as? String, part["thought"] as? Bool != true {
                text.append(value)
            }
        }
        // Sent back unchanged: Gemini needs its own parts (and thought signatures).
        contents.append(["role": "model", "parts": parts])
        return ModelStep(text: text.joined(), calls: calls)
    }

    mutating func addResults(_ results: [(ToolCall, String)]) {
        contents.append(["role": "user", "parts": results.map { call, result in
            var response: [String: Any] = ["name": call.name, "response": ["result": result]]
            if call.id != call.name { response["id"] = call.id }
            return ["functionResponse": response] as [String: Any]
        }])
    }
}

// MARK: - Running a turn

nonisolated enum CloudModel {
    /// How many rounds of tool calls one turn may take.
    static let maxSteps = 10

    /// One agent turn: the model may call tools several times, then answers.
    static func respond(_ config: AIConfig, system: String, history: [ChatLine], prompt: String, tools: [any Tool]) async throws -> String {
        switch config.provider {
        case .openai, .custom: try await run(OpenAIFormat.self, config, system, history, prompt, tools)
        case .anthropic: try await run(AnthropicFormat.self, config, system, history, prompt, tools)
        case .gemini: try await run(GeminiFormat.self, config, system, history, prompt, tools)
        case .device: throw CloudModelError.badResponse("not a cloud provider")
        }
    }

    private static func run<F: ChatFormat>(_: F.Type, _ config: AIConfig, _ system: String, _ history: [ChatLine], _ prompt: String, _ tools: [any Tool]) async throws -> String {
        var format = F(system: system, history: history, prompt: prompt)
        let specs = tools.map(ToolSpec.init)
        for _ in 0..<maxSteps {
            try Task.checkCancellation()
            let json = try await HTTP.send(try format.request(config, tools: specs), provider: config.provider.shortTitle)
            let step = try format.read(json)
            guard !step.calls.isEmpty else { return step.text }
            var results: [(ToolCall, String)] = []
            for call in step.calls {
                try Task.checkCancellation()
                results.append((call, await ToolInvoker.call(tools, call)))
            }
            format.addResults(results)
        }
        throw CloudModelError.tooManySteps
    }

    // MARK: Models list

    /// The provider's chat models, newest-looking first. Also proves the key works.
    static func listModels(_ config: AIConfig) async throws -> [String] {
        let request: URLRequest
        switch config.provider {
        case .openai, .custom:
            let base = OpenAIFormat.baseURL(config).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard let url = URL(string: base + "/models"), url.host != nil else { throw CloudModelError.badURL }
            request = get(url, headers: config.key.isEmpty ? [:] : ["Authorization": "Bearer \(config.key)"])
        case .anthropic:
            request = get(URL(string: "https://api.anthropic.com/v1/models?limit=100")!, headers: ["x-api-key": config.key, "anthropic-version": "2023-06-01"])
        case .gemini:
            request = get(URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!, headers: ["x-goog-api-key": config.key])
        case .device:
            return []
        }
        return models(in: try await HTTP.send(request, provider: config.provider.shortTitle), provider: config.provider)
    }

    static func models(in json: [String: Any], provider: AIProvider) -> [String] {
        switch provider {
        case .gemini:
            let models = json["models"] as? [[String: Any]] ?? []
            return models.compactMap { model -> String? in
                guard let name = model["name"] as? String,
                      (model["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { return nil }
                let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                return id.hasPrefix("gemini") && !id.contains("embedding") && !id.contains("image") && !id.contains("tts") ? id : nil
            }
            .sorted(by: >)
        default:
            let ids = (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            guard provider == .openai else { return ids }
            let skip = ["audio", "realtime", "tts", "transcribe", "image", "embedding", "moderation", "search", "dall-e", "whisper", "davinci", "babbage", "codex"]
            return ids
                .filter { id in (id.hasPrefix("gpt-") || id.hasPrefix("o")) && !skip.contains { id.contains($0) } }
                .sorted(by: >)
        }
    }

    private static func get(_ url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}
