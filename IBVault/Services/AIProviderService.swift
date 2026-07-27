import Foundation

enum AIProviderError: Error, LocalizedError, Sendable {
    case missingCredential(provider: AIProviderKind)
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case codexNotInstalled
    case codexNotAuthenticated(String)
    case processFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingCredential(let provider):
            return "No \(provider.shortName) credential is configured. Open Settings > AI provider."
        case .invalidEndpoint:
            return "The configured AI endpoint is not a valid URL."
        case .invalidResponse:
            return "The AI provider returned an unreadable response."
        case .apiError(let statusCode, let message):
            return message.isEmpty ? "AI request failed (HTTP \(statusCode))." : message
        case .codexNotInstalled:
            return "Codex CLI was not found. Install Codex or set its executable path in Settings."
        case .codexNotAuthenticated(let detail):
            return detail.isEmpty ? "Codex CLI is not signed in. Run `codex login`." : detail
        case .processFailed(let message):
            return message
        case .emptyResponse:
            return "The AI provider completed without returning an answer."
        }
    }
}

struct AIProviderStatus: Sendable {
    let isReady: Bool
    let message: String
}

enum AIProviderService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func generateContent(
        messages: [GeminiMessage],
        systemInstruction: String,
        modelOverride: String? = nil,
        timeout: TimeInterval = 120
    ) async throws -> String {
        switch AIConfiguration.provider {
        case .gemini:
            guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
                throw AIProviderError.missingCredential(provider: .gemini)
            }
            return try await GeminiService.generateContent(
                messages: messages,
                systemInstruction: systemInstruction,
                apiKey: apiKey,
                modelOverride: modelOverride,
                timeout: timeout
            )
        case .junali:
            return try await generateJunali(
                messages: messages,
                systemInstruction: systemInstruction,
                model: modelOverride ?? AIConfiguration.model(for: .junali),
                timeout: timeout
            )
        case .codexCLI:
            return try await generateCodex(
                messages: messages,
                systemInstruction: systemInstruction,
                model: modelOverride ?? AIConfiguration.model(for: .codexCLI),
                timeout: timeout
            )
        }
    }

    static func streamContent(
        messages: [GeminiMessage],
        systemInstruction: String
    ) -> AsyncThrowingStream<String, Error> {
        if AIConfiguration.provider == .gemini,
           let apiKey = KeychainService.loadAPIKey(),
           !apiKey.isEmpty {
            return GeminiService.streamContent(
                messages: messages,
                systemInstruction: systemInstruction,
                apiKey: apiKey
            )
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generateContent(
                        messages: messages,
                        systemInstruction: systemInstruction
                    )
                    continuation.yield(response)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    static func status(for provider: AIProviderKind) async -> AIProviderStatus {
        switch provider {
        case .gemini:
            guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
                return AIProviderStatus(isReady: false, message: "Add a Gemini API key to use this provider.")
            }
            do {
                _ = try await GeminiService.generateContent(
                    messages: [GeminiMessage(role: "user", text: "Reply with READY.")],
                    systemInstruction: "This is a provider health check. Return only READY.",
                    apiKey: apiKey,
                    modelOverride: AIConfiguration.model(for: .gemini),
                    timeout: 30
                )
                return AIProviderStatus(isReady: true, message: "Gemini completed a live response check.")
            } catch {
                return AIProviderStatus(isReady: false, message: error.localizedDescription)
            }
        case .junali:
            guard KeychainService.hasJunaliAPIKey else {
                return AIProviderStatus(isReady: false, message: "Add a Junali API key to use this provider.")
            }
            do {
                _ = try await generateJunali(
                    messages: [GeminiMessage(role: "user", text: "Reply with READY.")],
                    systemInstruction: "This is a provider health check. Return only READY.",
                    model: AIConfiguration.model(for: .junali),
                    timeout: 30
                )
                return AIProviderStatus(isReady: true, message: "Junali completed a live response check.")
            } catch {
                return AIProviderStatus(isReady: false, message: error.localizedDescription)
            }
        case .codexCLI:
            do {
                let executable = try codexExecutableURL()
                let result = try await runProcess(
                    executableURL: executable,
                    arguments: ["login", "status"],
                    input: nil,
                    timeout: 15
                )
                let detail = [result.stdout, result.stderr]
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard result.exitCode == 0 else {
                    return AIProviderStatus(isReady: false, message: detail.isEmpty ? "Codex is not signed in." : detail)
                }
                _ = try await generateCodex(
                    messages: [GeminiMessage(role: "user", text: "Reply with READY.")],
                    systemInstruction: "This is a provider health check. Return only READY.",
                    model: AIConfiguration.model(for: .codexCLI),
                    timeout: 45
                )
                return AIProviderStatus(isReady: true, message: "Codex CLI completed a live response check using its saved login.")
            } catch {
                return AIProviderStatus(isReady: false, message: error.localizedDescription)
            }
        }
    }

    private static func generateJunali(
        messages: [GeminiMessage],
        systemInstruction: String,
        model: String,
        timeout: TimeInterval
    ) async throws -> String {
        guard let apiKey = KeychainService.loadJunaliAPIKey(), !apiKey.isEmpty else {
            throw AIProviderError.missingCredential(provider: .junali)
        }
        guard let baseURL = normalizedBaseURL(AIConfiguration.junaliBaseURL) else {
            throw AIProviderError.invalidEndpoint
        }

        do {
            return try await sendResponsesRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                messages: messages,
                systemInstruction: systemInstruction,
                timeout: timeout
            )
        } catch let error as AIProviderError {
            switch error {
            case .apiError(let statusCode, _) where statusCode == 400 || statusCode == 404 || statusCode == 405:
                return try await sendChatCompletionsRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    messages: messages,
                    systemInstruction: systemInstruction,
                    timeout: timeout
                )
            default:
                throw error
            }
        }
    }

    private static func sendResponsesRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [GeminiMessage],
        systemInstruction: String,
        timeout: TimeInterval
    ) async throws -> String {
        let input = messages.map { message -> [String: Any] in
            [
                "role": message.role == "model" ? "assistant" : message.role,
                "content": message.text
            ]
        }
        let body: [String: Any] = [
            "model": model,
            "instructions": systemInstruction,
            "input": input,
            "reasoning": ["effort": AIConfiguration.reasoningEffort.rawValue],
            "text": ["verbosity": AIConfiguration.verbosity.rawValue],
            "max_output_tokens": max(UserDefaults.standard.integer(forKey: "ariaMaxTokens"), 1024),
            "store": false
        ]

        let data = try await sendJSON(
            url: baseURL.appendingPathComponent("responses"),
            apiKey: apiKey,
            body: body,
            timeout: timeout
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }
        if let output = json["output"] as? [[String: Any]] {
            let text = output
                .compactMap { $0["content"] as? [[String: Any]] }
                .flatMap { $0 }
                .compactMap { $0["text"] as? String }
                .joined()
            if !text.isEmpty { return text }
        }
        throw AIProviderError.emptyResponse
    }

    private static func sendChatCompletionsRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [GeminiMessage],
        systemInstruction: String,
        timeout: TimeInterval
    ) async throws -> String {
        var payloadMessages: [[String: String]] = []
        if !systemInstruction.isEmpty {
            payloadMessages.append(["role": "system", "content": systemInstruction])
        }
        payloadMessages.append(contentsOf: messages.map {
            ["role": $0.role == "model" ? "assistant" : $0.role, "content": $0.text]
        })
        let body: [String: Any] = [
            "model": model,
            "messages": payloadMessages,
            "reasoning_effort": AIConfiguration.reasoningEffort.rawValue,
            "max_completion_tokens": max(UserDefaults.standard.integer(forKey: "ariaMaxTokens"), 1024)
        ]
        let data = try await sendJSON(
            url: baseURL
                .appendingPathComponent("chat")
                .appendingPathComponent("completions"),
            apiKey: apiKey,
            body: body,
            timeout: timeout
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw AIProviderError.emptyResponse
        }
        return content
    }

    private static func sendJSON(
        url: URL,
        apiKey: String,
        body: [String: Any],
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIProviderError.apiError(
                statusCode: httpResponse.statusCode,
                message: providerErrorMessage(from: data, fallbackStatus: httpResponse.statusCode)
            )
        }
        return data
    }

    private static func providerErrorMessage(from data: Data, fallbackStatus: Int) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "AI request failed (HTTP \(fallbackStatus))."
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return json["message"] as? String ?? "AI request failed (HTTP \(fallbackStatus))."
    }

    private static func generateCodex(
        messages: [GeminiMessage],
        systemInstruction: String,
        model: String,
        timeout: TimeInterval
    ) async throws -> String {
        let executable = try codexExecutableURL()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IBVault-Codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let finalMessageURL = temporaryDirectory.appendingPathComponent("final-response.md")

        let transcript = messages.map { message in
            let role = message.role == "model" ? "ASSISTANT" : message.role.uppercased()
            return "\(role):\n\(message.text)"
        }.joined(separator: "\n\n")
        let prompt = """
        Role: You are ARIA, a rigorous and encouraging International Baccalaureate study coach inside IBVault.

        Goal: Answer the learner's latest request accurately, at the requested IB subject level, using the supplied study context.

        Success criteria:
        - teach the concept, not merely state an answer
        - use clean Markdown and valid LaTeX delimiters: $...$ inline and $$...$$ for display equations
        - distinguish sourced facts from inference and never invent a citation
        - preserve the learner's requested output format
        - return only the final learner-facing response

        Constraints:
        - do not inspect local files or modify the machine
        - do not expose hidden reasoning or authentication details

        APP SYSTEM CONTEXT:
        \(systemInstruction)

        CONVERSATION:
        \(transcript)
        """

        let arguments = [
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--cd", temporaryDirectory.path,
            "--model", model,
            "--config", "model_reasoning_effort=\"\(AIConfiguration.reasoningEffort.codexValue)\"",
            "--config", "model_verbosity=\"\(AIConfiguration.verbosity.rawValue)\"",
            "--config", "web_search=\"cached\"",
            "--output-last-message", finalMessageURL.path,
            "-"
        ]
        let result = try await runProcess(
            executableURL: executable,
            arguments: arguments,
            input: prompt,
            timeout: timeout
        )
        guard result.exitCode == 0 else {
            let detail = result.stderr.lowercased()
            let authenticationFailure = ["login", "authentication", "unauthorized", "invalid_api_key", "incorrect api key"]
                .contains { detail.contains($0) }
            if authenticationFailure {
                throw AIProviderError.codexNotAuthenticated(
                    "Codex CLI credentials were rejected. Run `codex logout`, then `codex login`, and retry."
                )
            }
            throw AIProviderError.processFailed("Codex CLI exited with status \(result.exitCode).")
        }
        let response = (try? String(contentsOf: finalMessageURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !response.isEmpty else { throw AIProviderError.emptyResponse }
        return response
    }

    private static func codexExecutableURL() throws -> URL {
        let configured = AIConfiguration.codexCLIPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            configured,
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ].filter { !$0.isEmpty }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw AIProviderError.codexNotInstalled
    }

    private static func normalizedBaseURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private final class ProcessOutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ newData: Data) {
            guard !newData.isEmpty else { return }
            lock.lock()
            data.append(newData)
            lock.unlock()
        }

        func string() -> String {
            lock.lock()
            let snapshot = data
            lock.unlock()
            return String(data: snapshot, encoding: .utf8) ?? ""
        }
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        input: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            let stdoutBuffer = ProcessOutputBuffer()
            let stderrBuffer = ProcessOutputBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                stdoutBuffer.append(handle.availableData)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrBuffer.append(handle.availableData)
            }

            process.executableURL = executableURL
            process.arguments = arguments
            // The local provider intentionally uses the account already authenticated by
            // `codex login`. An inherited API key can override that login and make a
            // desktop launch behave differently from the CLI the learner has configured.
            var environment = ProcessInfo.processInfo.environment
            for key in ["OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID", "OPENAI_PROJECT_ID", "CODEX_API_KEY"] {
                environment.removeValue(forKey: key)
            }
            process.environment = environment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if input != nil { process.standardInput = stdinPipe }

            try process.run()

            if let input, let data = input.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try? stdinPipe.fileHandleForWriting.close()
            }

            let timeoutWork = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            process.waitUntilExit()
            timeoutWork.cancel()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: stdoutBuffer.string(),
                stderr: stderrBuffer.string()
            )
        }.value
    }
}
