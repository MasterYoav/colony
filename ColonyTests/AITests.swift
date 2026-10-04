//
//  AITests.swift
//  ColonyTests
//
//  Cloud model wire formats, the tool-calling loop (against a stubbed network),
//  Jev requests/answers and AI settings. No real network calls.
//

import Foundation
import FoundationModels
import Testing
@testable import Colony

/// A stand-in agent tool.
private struct EchoTool: Tool {
    let name = "list_tasks"
    let description = "Lists tasks"

    @Generable
    struct Arguments {
        @Guide(description: "Which tasks")
        var filter: String?
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        "tasks(filter: \(arguments.filter ?? "none"), limit: \(arguments.limit ?? 0))"
    }
}

private func body(_ request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

private let config = AIConfig(provider: .openai, model: "gpt-test", key: "sk-test")

@MainActor
struct AIFormatTests {
    @Test func toolSchemaDropsAppleOnlyKeys() throws {
        let spec = ToolSpec(EchoTool())
        let schema = spec.schema
        #expect(spec.name == "list_tasks")
        #expect(schema["type"] as? String == "object")
        #expect(schema["x-order"] == nil)
        #expect(schema["title"] == nil)
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["filter", "limit"])
        #expect((properties["filter"] as? [String: Any])?["description"] as? String == "Which tasks")
    }

    @Test func toolInvokerDecodesJSONArguments() async {
        let tools: [any Tool] = [EchoTool()]
        #expect(await ToolInvoker.call(tools, ToolCall(id: "1", name: "list_tasks", arguments: #"{"filter":"today","limit":3}"#)) == "tasks(filter: today, limit: 3)")
        #expect(await ToolInvoker.call(tools, ToolCall(id: "2", name: "list_tasks", arguments: "")) == "tasks(filter: none, limit: 0)")
        #expect(await ToolInvoker.call(tools, ToolCall(id: "3", name: "nope", arguments: "{}")).contains("no tool called nope"))
        #expect(await ToolInvoker.call(tools, ToolCall(id: "4", name: "list_tasks", arguments: "not json")).contains("invalid"))
    }

    @Test func openAIRoundTrip() throws {
        var format = OpenAIFormat(system: "Be brief.", history: [ChatLine(role: .user, text: "hi"), ChatLine(role: .assistant, text: "hello")], prompt: "What's due?")
        let request = try format.request(config, tools: [ToolSpec(EchoTool())])
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let sent = body(request)
        #expect((sent["messages"] as? [[String: Any]])?.map { $0["role"] as? String } == ["system", "user", "assistant", "user"])
        let tool = (sent["tools"] as? [[String: Any]])?.first?["function"] as? [String: Any]
        #expect(tool?["name"] as? String == "list_tasks")

        let step = try format.read(["choices": [["message": ["role": "assistant", "content": NSNull(), "tool_calls": [
            ["id": "call_1", "type": "function", "function": ["name": "list_tasks", "arguments": #"{"filter":"today"}"#]],
        ]]]]])
        #expect(step.calls == [ToolCall(id: "call_1", name: "list_tasks", arguments: #"{"filter":"today"}"#)])
        format.addResults([(step.calls[0], "2 tasks")])
        #expect(format.messages.last?["role"] as? String == "tool")
        #expect(format.messages.last?["tool_call_id"] as? String == "call_1")

        let final = try format.read(["choices": [["message": ["role": "assistant", "content": "Two tasks."]]]])
        #expect(final == ModelStep(text: "Two tasks.", calls: []))
    }

    @Test func customServerUsesItsAddressAndOptionalKey() throws {
        let local = AIConfig(provider: .custom, model: "llama3", key: "", baseURL: "http://localhost:11434/v1/")
        let request = try OpenAIFormat(system: "", history: [], prompt: "hi").request(local, tools: [])
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body(request)["tools"] == nil)
    }

    @Test func anthropicAlternatesAndReadsToolUse() throws {
        let claude = AIConfig(provider: .anthropic, model: "claude-test", key: "sk-ant")
        var format = AnthropicFormat(system: "Be brief.", history: [
            ChatLine(role: .assistant, text: "Hi, I'm Neo."),
            ChatLine(role: .user, text: "Plan my day"),
            ChatLine(role: .user, text: "and tomorrow"),
        ], prompt: "Thanks")
        // Leading assistant dropped; consecutive user lines merged.
        #expect(format.messages.count == 1)
        #expect(format.messages[0]["content"] as? String == "Plan my day\n\nand tomorrow\n\nThanks")
        let request = try format.request(claude, tools: [ToolSpec(EchoTool())])
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(body(request)["system"] as? String == "Be brief.")
        #expect(((body(request)["tools"] as? [[String: Any]])?.first?["input_schema"] as? [String: Any])?["type"] as? String == "object")

        let step = try format.read(["content": [
            ["type": "text", "text": "Let me look."],
            ["type": "tool_use", "id": "toolu_1", "name": "list_tasks", "input": ["filter": "today"]],
        ], "stop_reason": "tool_use"])
        #expect(step.text == "Let me look.")
        #expect(step.calls.first?.id == "toolu_1")
        #expect(step.calls.first?.arguments == #"{"filter":"today"}"#)
        format.addResults([(step.calls[0], "2 tasks")])
        let result = (format.messages.last?["content"] as? [[String: Any]])?.first
        #expect(result?["type"] as? String == "tool_result")
        #expect(result?["tool_use_id"] as? String == "toolu_1")
    }

    @Test func geminiReadsFunctionCallsAndSkipsThoughts() throws {
        let gemini = AIConfig(provider: .gemini, model: "models/gemini-test", key: "AIza")
        var format = GeminiFormat(system: "Be brief.", history: [ChatLine(role: .assistant, text: "Hi")], prompt: "What's due?")
        #expect(format.contents.map { $0["role"] as? String } == ["model", "user"])
        let request = try format.request(gemini, tools: [ToolSpec(EchoTool())])
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza")
        let declaration = (((body(request)["tools"] as? [[String: Any]])?.first?["functionDeclarations"]) as? [[String: Any]])?.first
        let parameters = declaration?["parameters"] as? [String: Any]
        #expect(parameters?["type"] as? String == "object")
        #expect(parameters?["additionalProperties"] == nil)

        let step = try format.read(["candidates": [["content": ["role": "model", "parts": [
            ["text": "thinking…", "thought": true],
            ["functionCall": ["name": "list_tasks", "args": ["filter": "today"]], "thoughtSignature": "abc"],
        ]]]]])
        #expect(step.text.isEmpty)
        #expect(step.calls == [ToolCall(id: "list_tasks", name: "list_tasks", arguments: #"{"filter":"today"}"#)])
        // The model's parts go back unchanged (thought signature included).
        #expect(((format.contents.last?["parts"] as? [[String: Any]])?.last?["thoughtSignature"]) as? String == "abc")
        format.addResults([(step.calls[0], "2 tasks")])
        let response = ((format.contents.last?["parts"] as? [[String: Any]])?.first?["functionResponse"]) as? [String: Any]
        #expect(response?["name"] as? String == "list_tasks")
        #expect((response?["response"] as? [String: Any])?["result"] as? String == "2 tasks")
    }

    @Test func modelListsKeepChatModels() {
        let openai = CloudModel.models(in: ["data": [["id": "gpt-5"], ["id": "gpt-4o-audio-preview"], ["id": "text-embedding-3-large"], ["id": "o4-mini"], ["id": "dall-e-3"]]], provider: .openai)
        #expect(openai == ["o4-mini", "gpt-5"])
        let gemini = CloudModel.models(in: ["models": [
            ["name": "models/gemini-2.5-flash", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/text-embedding-004", "supportedGenerationMethods": ["embedContent"]],
            ["name": "models/gemini-2.5-pro", "supportedGenerationMethods": ["generateContent", "countTokens"]],
        ]], provider: .gemini)
        #expect(gemini == ["gemini-2.5-pro", "gemini-2.5-flash"])
        #expect(CloudModel.models(in: ["data": [["id": "claude-x"]]], provider: .anthropic) == ["claude-x"])
    }

    @Test func friendlyErrors() {
        #expect(CloudModelError.http(provider: "OpenAI", status: 401, message: "bad").localizedDescription.contains("didn't accept the API key"))
        #expect(CloudModelError.http(provider: "Claude", status: 404, message: "model: x").localizedDescription.contains("doesn't know this model"))
        #expect(HTTP.errorMessage(["error": ["message": "Invalid key"]], Data()) == "Invalid key")
    }
}

// MARK: - Loop against a stubbed network

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [[String: Any]] = []
    nonisolated(unsafe) static var requests: [[String: Any]] = []

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.colony.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            Self.requests.append((try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
        let json = Self.responses.isEmpty ? [:] : Self.responses.removeFirst()
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct AILoopTests {
    @Test func toolCallThenAnswer() async throws {
        URLProtocol.registerClass(StubProtocol.self)
        defer { URLProtocol.unregisterClass(StubProtocol.self) }
        StubProtocol.requests = []
        StubProtocol.responses = [
            ["choices": [["message": ["role": "assistant", "content": NSNull(), "tool_calls": [
                ["id": "c1", "type": "function", "function": ["name": "list_tasks", "arguments": #"{"filter":"overdue"}"#]],
            ]]]]],
            ["choices": [["message": ["role": "assistant", "content": "You have nothing overdue."]]]],
        ]
        let stub = AIConfig(provider: .custom, model: "stub", key: "", baseURL: "https://stub.colony.test/v1")
        let reply = try await CloudModel.respond(stub, system: "s", history: [], prompt: "Anything overdue?", tools: [EchoTool()])
        #expect(reply == "You have nothing overdue.")
        #expect(StubProtocol.requests.count == 2)
        let second = StubProtocol.requests.last?["messages"] as? [[String: Any]]
        #expect(second?.last?["role"] as? String == "tool")
        #expect(second?.last?["content"] as? String == "tasks(filter: overdue, limit: 0)")
    }
}

// MARK: - Jev

struct JevTests {
    @Test func yesNoAndChoiceRequests() {
        let yesNo = Jev.body(state: "Task: renew domain", question: "Is this urgent?", options: [])
        let q = (yesNo["questions"] as? [String: Any])?["q"] as? [String: Any]
        #expect(q?["type"] as? String == "noul")
        #expect(q?["instructions"] as? String == "Is this urgent?")
        #expect(yesNo["model"] as? String == "jev-latest")

        let choice = Jev.body(state: "x", question: "Which project?", options: ["Launch, Sales", " Ops", "launch"])
        let c = (choice["questions"] as? [String: Any])?["q"] as? [String: Any]
        #expect(c?["type"] as? String == "choice")
        #expect(Set(((c?["criteria"] as? [String: String]) ?? [:]).keys) == ["Launch", "Sales", "Ops"])

        // One option isn't a choice.
        let single = (Jev.body(state: "x", question: "q", options: ["Only"])["questions"] as? [String: Any])?["q"] as? [String: Any]
        #expect(single?["type"] as? String == "noul")
    }

    @Test func parsesAnswers() throws {
        let yes = try Jev.parse(["model": "jev-1.13.0", "answers": ["q": ["type": "noul", "noul": 0.96]]])
        #expect(yes.yes == 0.96)
        #expect(yes.model == "jev-1.13.0")
        #expect(yes.summary == "96% likely yes")
        let no = try Jev.parse(["answers": ["q": ["type": "noul", "noul": 0.03]]])
        #expect(no.summary == "97% likely no")
        let pick = try Jev.parse(["answers": ["q": ["type": "choice", "choice": "Ops", "confidence": 0.9, "probabilities": ["Ops": 0.72, "Launch": 0.28]]]])
        #expect(pick.choice == "Ops")
        #expect(pick.summary == "Ops (72%)")
        #expect(throws: (any Error).self) { try Jev.parse(["answers": [:]]) }
    }

    @Test func friendlyErrors() {
        #expect(Jev.JevError.http(401, "").localizedDescription.contains("didn't accept the API key"))
        #expect(Jev.JevError.http(402, "").localizedDescription.contains("credits"))
    }
}

// MARK: - Settings

struct AISettingsTests {
    @Test func modelFallsBackToTheProviderDefault() {
        var settings = AISettings()
        #expect(settings.provider == .device)
        #expect(settings.model(for: .anthropic) == AIProvider.anthropic.defaultModel)
        settings.models["anthropic"] = "  claude-custom "
        #expect(settings.model(for: .anthropic) == "claude-custom")
    }

    @Test func decodesPartialAndUnknownSettings() throws {
        let partial = try JSONDecoder().decode(AISettings.self, from: Data(#"{"provider":"gemini","future":1}"#.utf8))
        #expect(partial.provider == .gemini)
        #expect(partial.jevEnabled == false)
        let unknown = try JSONDecoder().decode(AISettings.self, from: Data(#"{"provider":"someday-ai"}"#.utf8))
        #expect(unknown.provider == .device)
        var full = AISettings()
        full.provider = .custom
        full.customURL = "http://localhost:11434/v1"
        full.jevEnabled = true
        #expect(try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(full)) == full)
    }

    @Test func onlyTheDeviceNeedsNoAccount() {
        #expect(AIProvider.device.isCloud == false)
        #expect(AIProvider.custom.requiresKey == false)
        #expect(AIProvider.allCases.filter(\.requiresKey) == [.openai, .anthropic, .gemini])
    }
}
