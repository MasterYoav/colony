//
//  Jev.swift
//  Colony
//
//  Jev (TypeSafe's "System One" model) gives fast, calibrated judgments instead of
//  text: how likely a yes/no statement is true, or which of a few options fits best.
//
//  Optional. With a Jev key in Settings › AI and "Let agents ask Jev" on, every agent
//  gets an `ask_jev` tool for judgment calls (is this urgent? which project fits? is
//  this customer at risk?), whichever model runs the agent. Each question appears in
//  the agent's chat as an action row with Jev's answer.
//
//  API: POST https://api.typesafe.ai/v1/systemone  { state, model, questions }
//

import Foundation
import FoundationModels

nonisolated enum Jev {
    static let url = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let keyURL = URL(string: "https://console.typesafe.ai/keys")!
    static let docsURL = URL(string: "https://docs.typesafe.ai/introduction")!
    static let model = "jev-latest"

    struct Answer: Equatable, Sendable {
        /// Yes/no questions: how likely the answer is yes (0–1).
        var yes: Double?
        /// Choice questions: the pick and each option's probability.
        var choice: String?
        var probabilities: [String: Double] = [:]
        var confidence: Double?
        var model: String?

        /// "87% likely yes" or "Ops (72%)".
        var summary: String {
            if let choice {
                let p = probabilities[choice] ?? confidence
                return p.map { "\(choice) (\(Int(($0 * 100).rounded()))%)" } ?? choice
            }
            if let yes {
                let percent = Int((yes * 100).rounded())
                return yes >= 0.5 ? "\(percent)% likely yes" : "\(100 - percent)% likely no"
            }
            return "no answer"
        }
    }

    enum JevError: LocalizedError {
        case http(Int, String)
        case unreachable(String)
        case noAnswer

        var errorDescription: String? {
            switch self {
            case let .http(status, message):
                switch status {
                case 401: "Jev didn't accept the API key. Check it in Settings › AI."
                case 402: "The Jev account is out of credits or needs a plan."
                case 422: "Jev couldn't read the question (\(message))."
                case 429: "Jev is rate limiting. Try again in a moment."
                default: "Jev returned an error (\(status)): \(message)"
                }
            case let .unreachable(detail): "Couldn't reach Jev: \(detail)"
            case .noAnswer: "Jev didn't return an answer."
            }
        }
    }

    // MARK: Request / response (pure, tested)

    /// A yes/no question, or a choice when `options` has two or more entries.
    static func body(state: String, question: String, options: [String]) -> [String: Any] {
        let options = cleanOptions(options)
        var spec: [String: Any] = ["instructions": question]
        if options.count >= 2 {
            spec["type"] = "choice"
            spec["criteria"] = Dictionary(options.map { ($0, $0) }, uniquingKeysWith: { a, _ in a })
        } else {
            spec["type"] = "noul"
        }
        return ["state": state, "model": model, "questions": ["q": spec]]
    }

    static func parse(_ json: [String: Any]) throws -> Answer {
        guard let answer = (json["answers"] as? [String: Any])?["q"] as? [String: Any] else { throw JevError.noAnswer }
        var result = Answer(model: json["model"] as? String)
        switch answer["type"] as? String {
        case "noul":
            result.yes = (answer["noul"] as? NSNumber)?.doubleValue
            guard result.yes != nil else { throw JevError.noAnswer }
        case "choice":
            result.choice = answer["choice"] as? String
            result.confidence = (answer["confidence"] as? NSNumber)?.doubleValue
            for (key, value) in answer["probabilities"] as? [String: Any] ?? [:] {
                if let number = value as? NSNumber { result.probabilities[key] = number.doubleValue }
            }
            guard result.choice != nil else { throw JevError.noAnswer }
        default:
            throw JevError.noAnswer
        }
        return result
    }

    /// "Launch, Sales,  Ops" -> ["Launch", "Sales", "Ops"]; also accepts new lines or "|".
    static func cleanOptions(_ options: [String]) -> [String] {
        var seen = Set<String>()
        return options
            .flatMap { $0.split(whereSeparator: { ",|\n".contains($0) }) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(12)
            .map { String($0.prefix(60)) }
    }

    // MARK: Network

    static func ask(key: String, state: String, question: String, options: [String] = []) async throws -> Answer {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body(state: String(state.prefix(8000)), question: question, options: options))
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw JevError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else { throw JevError.http(status, HTTP.errorMessage(json, data)) }
        return try parse(json ?? [:])
    }
}

// MARK: - Agent tool

/// `ask_jev`: added to every agent when Jev is on (not listed in AGENT.md).
nonisolated struct AskJevTool: Tool {
    static let toolName = "ask_jev"
    let bridge: AgentBridge
    let key: String
    let name = AskJevTool.toolName
    let description = "Ask Jev, a fast decision model, for a calibrated judgment before acting: a yes/no question (returns how likely yes), or with options, which one fits best. Use it for judgment calls like: is this urgent, is this customer at risk, which project does this belong to."

    @Generable
    struct Arguments {
        @Guide(description: "One clear yes/no question, or what to choose (e.g. Is this task urgent? / Which project fits this task?)")
        var question: String
        @Guide(description: "The facts to judge: the relevant task, message or customer details, copied from what you looked up")
        var context: String
        @Guide(description: "For a choice: the options, separated by commas. Leave empty for a yes/no question")
        var options: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        let question = ColonyText.trimmed(a.question)
        let options = Jev.cleanOptions([a.options ?? ""])
        do {
            let answer = try await Jev.ask(key: key, state: a.context, question: question, options: options)
            let summary = answer.summary
            _ = await bridge { $0.record("Asked Jev: \(question) — \(summary)", symbol: "scalemass.fill"); return "" }
            if answer.choice != nil {
                let all = answer.probabilities.sorted { $0.value > $1.value }.map { "\($0.key) \(Int(($0.value * 100).rounded()))%" }.joined(separator: ", ")
                return "Jev picked \(summary). All options: \(all)."
            }
            return "Jev: \(summary) (probability of yes: \(String(format: "%.2f", answer.yes ?? 0)))."
        } catch {
            _ = await bridge { $0.record("Couldn't ask Jev: \(error.localizedDescription)", symbol: "exclamationmark.triangle"); return "" }
            return "Jev isn't available right now (\(error.localizedDescription)). Use your own judgment."
        }
    }
}
