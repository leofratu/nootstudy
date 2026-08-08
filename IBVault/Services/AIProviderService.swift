import Foundation

/// Shared admission control for every provider path. Multiple ARIA surfaces can
/// otherwise start requests at once, competing for CPU, network connections,
/// and the user's provider quota. Two active requests keeps the UI responsive
/// while still allowing a chat response and one background task to coexist.
private actor AIRequestGate {
    static let shared = AIRequestGate(maxConcurrent: 2, maxWaiting: 8)

    private let maxConcurrent: Int
    private let maxWaiting: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int, maxWaiting: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.maxWaiting = max(1, maxWaiting)
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if active < maxConcurrent {
            active += 1
            return
        }
        guard waiters.count < maxWaiting else {
            throw AIProviderError.busy
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        try Task.checkCancellation()
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            active = max(0, active - 1)
        }
    }
}

enum AIProviderError: Error, LocalizedError, Sendable {
    case missingCredential(provider: AIProviderKind)
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case codexNotInstalled
    case codexNotAuthenticated(String)
    case processFailed(String)
    case emptyResponse
    case busy

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
        case .busy:
            return "ARIA is already handling several requests. Let the current response finish, then try again."
        }
    }
}

struct AIProviderStatus: Sendable {
    let isReady: Bool
    let message: String
}

struct CodexEventUpdate: Equatable, Sendable {
    let status: String?
    let message: String?
    let error: String?
}

nonisolated enum AIProviderService {
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
        return try await withRequestPermit {
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
    }

    static func streamContent(
        messages: [GeminiMessage],
        systemInstruction: String,
        onStatus: @escaping @Sendable (String) -> Void = { _ in }
    ) -> AsyncThrowingStream<String, any Error> {
        switch AIConfiguration.provider {
        case .gemini:
            guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
                return failedStream(AIProviderError.missingCredential(provider: .gemini))
            }
            onStatus("Generating with Gemini")
            return gatedStream {
                GeminiService.streamContent(
                    messages: messages,
                    systemInstruction: systemInstruction,
                    apiKey: apiKey
                )
            }
        case .junali:
            return gatedResponseStream {
                onStatus("Contacting Junali")
                return try await generateJunali(
                    messages: messages,
                    systemInstruction: systemInstruction,
                    model: AIConfiguration.model(for: .junali),
                    timeout: 120
                )
            }
        case .codexCLI:
            return gatedStream {
                streamCodex(
                    messages: messages,
                    systemInstruction: systemInstruction,
                    model: AIConfiguration.model(for: .codexCLI),
                    timeout: 180,
                    onStatus: onStatus
                )
            }
        }
    }

    private static func withRequestPermit<T>(_ operation: () async throws -> T) async throws -> T {
        try await AIRequestGate.shared.acquire()
        do {
            let result = try await operation()
            await AIRequestGate.shared.release()
            return result
        } catch {
            await AIRequestGate.shared.release()
            throw error
        }
    }

    private static func gatedStream(
        _ operation: @escaping @Sendable () -> AsyncThrowingStream<String, any Error>
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try await AIRequestGate.shared.acquire()
                do {
                    for try await chunk in operation() {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    await AIRequestGate.shared.release()
                    continuation.finish()
                } catch {
                    await AIRequestGate.shared.release()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func gatedResponseStream(
        _ operation: @escaping @Sendable () async throws -> String
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try await AIRequestGate.shared.acquire()
                do {
                    continuation.yield(try await operation())
                    await AIRequestGate.shared.release()
                    continuation.finish()
                } catch {
                    await AIRequestGate.shared.release()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func failedStream(_ error: any Error) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    static func status(for provider: AIProviderKind) async -> AIProviderStatus {
        switch provider {
        case .gemini:
            guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
                return AIProviderStatus(isReady: false, message: "Add a Gemini API key to use this provider.")
            }
            do {
                _ = try await withRequestPermit {
                    try await GeminiService.generateContent(
                        messages: [GeminiMessage(role: "user", text: "Reply with READY.")],
                        systemInstruction: "This is a provider health check. Return only READY.",
                        apiKey: apiKey,
                        modelOverride: AIConfiguration.model(for: .gemini),
                        timeout: 30
                    )
                }
                return AIProviderStatus(isReady: true, message: "Gemini completed a live response check.")
            } catch {
                return AIProviderStatus(isReady: false, message: error.localizedDescription)
            }
        case .junali:
            guard KeychainService.hasJunaliAPIKey else {
                return AIProviderStatus(isReady: false, message: "Add a Junali API key to use this provider.")
            }
            do {
                _ = try await withRequestPermit {
                    try await generateJunali(
                        messages: [GeminiMessage(role: "user", text: "Reply with READY.")],
                        systemInstruction: "This is a provider health check. Return only READY.",
                        model: AIConfiguration.model(for: .junali),
                        timeout: 30
                    )
                }
                return AIProviderStatus(isReady: true, message: "Junali completed a live response check.")
            } catch {
                return AIProviderStatus(isReady: false, message: error.localizedDescription)
            }
        case .codexCLI:
            do {
                let executable = try codexExecutableURL()
                _ = try await codexLoginStatus(executableURL: executable)
                _ = try await withRequestPermit {
                    try await generateCodex(
                        messages: [GeminiMessage(role: "user", text: "Reply with READY.")],
                        systemInstruction: "This is a provider health check. Return only READY.",
                        model: AIConfiguration.model(for: .codexCLI),
                        timeout: 45
                    )
                }
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
            "reasoning": ["effort": AIConfiguration.reasoningEffortValue(for: .junali)],
            "text": ["verbosity": AIConfiguration.verbosity.rawValue],
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
            "reasoning_effort": AIConfiguration.reasoningEffortValue(for: .junali)
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
        let decodedMessage: String?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                decodedMessage = message
            } else {
                decodedMessage = json["message"] as? String
            }
        } else {
            decodedMessage = nil
        }
        let message = decodedMessage ?? String(data: data, encoding: .utf8) ?? "AI request failed (HTTP \(fallbackStatus))."
        // Error bodies can be large and may echo request payloads; truncate and
        // flatten so they are safe to surface and persist in chat history.
        let flattened = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > 300 else { return flattened }
        return String(flattened.prefix(297)) + "…"
    }

    private static func generateCodex(
        messages: [GeminiMessage],
        systemInstruction: String,
        model: String,
        timeout: TimeInterval
    ) async throws -> String {
        var response = ""
        let stream = streamCodex(
            messages: messages,
            systemInstruction: systemInstruction,
            model: model,
            timeout: timeout
        )
        for try await chunk in stream {
            if response.isEmpty {
                response = chunk
            } else {
                response += "\n\n\(chunk)"
            }
        }
        response = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else { throw AIProviderError.emptyResponse }
        return response
    }

    private static func streamCodex(
        messages: [GeminiMessage],
        systemInstruction: String,
        model: String,
        timeout: TimeInterval,
        onStatus: @escaping @Sendable (String) -> Void = { _ in }
    ) -> AsyncThrowingStream<String, any Error> {
        let processController = ProcessController()
        let webSearchMode = AIConfiguration.webSearchMode
        let reasoningEffort = AIConfiguration.reasoningEffortValue(for: .codexCLI)
        let verbosity = AIConfiguration.verbosity.rawValue

        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let temporaryDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("IBVault-Codex-\(UUID().uuidString)", isDirectory: true)

                do {
                    let executable = try codexExecutableURL()
                    onStatus("Checking Local Codex sign-in")
                    try await codexLoginStatus(executableURL: executable)
                    try Task.checkCancellation()
                    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

                    let finalMessageURL = temporaryDirectory.appendingPathComponent("final-response.md")
                    let process = Process()
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    let stdinPipe = Pipe()
                    let lineBuffer = JSONLineBuffer()
                    let stderrBuffer = ProcessOutputBuffer()
                    let responseState = CodexResponseState()

                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        for line in lineBuffer.append(data) {
                            handleCodexEvent(
                                line,
                                state: responseState,
                                continuation: continuation,
                                onStatus: onStatus
                            )
                        }
                    }
                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        stderrBuffer.append(handle.availableData)
                    }

                    configureCodexProcess(
                        process,
                        executableURL: executable,
                        arguments: codexArguments(
                            temporaryDirectory: temporaryDirectory,
                            finalMessageURL: finalMessageURL,
                            model: model,
                            reasoningEffort: reasoningEffort,
                            verbosity: verbosity,
                            webSearchMode: webSearchMode
                        )
                    )
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    process.standardInput = stdinPipe

                    onStatus("Starting Local Codex")
                    try processController.run(process)

                    if let data = codexPrompt(
                        messages: messages,
                        systemInstruction: systemInstruction,
                        webSearchMode: webSearchMode
                    ).data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                    try? stdinPipe.fileHandleForWriting.close()

                    let timeoutWork = DispatchWorkItem {
                        processController.terminate(timedOut: true)
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + timeout,
                        execute: timeoutWork
                    )
                    process.waitUntilExit()
                    timeoutWork.cancel()

                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    for line in lineBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile()) + lineBuffer.flush() {
                        handleCodexEvent(
                            line,
                            state: responseState,
                            continuation: continuation,
                            onStatus: onStatus
                        )
                    }
                    stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    guard process.terminationStatus == 0 else {
                        throw codexProcessError(
                            exitCode: process.terminationStatus,
                            stderr: stderrBuffer.string(),
                            eventDetail: responseState.errorDetail,
                            timedOut: processController.didTimeOut
                        )
                    }

                    if !responseState.didYieldMessage {
                        let fallback = (try? String(contentsOf: finalMessageURL, encoding: .utf8))?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !fallback.isEmpty else { throw AIProviderError.emptyResponse }
                        continuation.yield(fallback)
                    }
                    onStatus("Response complete")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                processController.terminate()
                task.cancel()
            }
        }
    }

    static func codexArguments(
        temporaryDirectory: URL,
        finalMessageURL: URL,
        model: String,
        reasoningEffort: String,
        verbosity: String,
        webSearchMode: AIWebSearchMode
    ) -> [String] {
        [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--cd", temporaryDirectory.path,
            "--model", model,
            "--config", "model_reasoning_effort=\"\(reasoningEffort)\"",
            "--config", "model_verbosity=\"\(verbosity)\"",
            "--config", "web_search=\"\(webSearchMode.rawValue)\"",
            "--json",
            "--output-last-message", finalMessageURL.path,
            "-"
        ]
    }

    static func codexLoginShellArguments(
        executableURL: URL,
        arguments: [String]
    ) -> [String] {
        ["-lc", "exec \"$@\"", "ibvault-codex", executableURL.path] + arguments
    }

    private static func configureCodexProcess(
        _ process: Process,
        executableURL: URL,
        arguments: [String]
    ) {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = codexLoginShellArguments(
            executableURL: executableURL,
            arguments: arguments
        )
    }

    private static func codexPrompt(
        messages: [GeminiMessage],
        systemInstruction: String,
        webSearchMode: AIWebSearchMode
    ) -> String {
        let transcript = messages.map { message in
            let role = message.role == "model" ? "ASSISTANT" : message.role.uppercased()
            return "\(role):\n\(message.text)"
        }.joined(separator: "\n\n")
        let sourcePolicy: String
        switch webSearchMode {
        case .disabled:
            sourcePolicy = "Web search is disabled. Be explicit when the supplied context is insufficient for a reliable answer."
        case .cached, .live:
            sourcePolicy = "Use web search only when the learner asks for sources or the answer depends on external, current, or source-sensitive facts. Cite only pages actually retrieved, with direct links, and stop once enough evidence supports the answer."
        }

        return """
        Role: You are ARIA, a rigorous and encouraging International Baccalaureate study coach inside IBVault.

        Goal: Answer the learner's latest request accurately, at the requested IB subject level, using the supplied study context.

        Success criteria:
        - teach the concept, not merely state an answer
        - adapt depth and command terms to the learner's SL or HL course
        - use clean Markdown and valid LaTeX delimiters: $...$ inline and $$...$$ for display equations
        - distinguish sourced facts from inference and never invent a citation
        - preserve the learner's requested output format
        - return only the final learner-facing response

        Tool and source rules:
        - \(sourcePolicy)
        - use tools only when they materially improve correctness
        - validate the final answer against the learner's request before stopping

        Constraints:
        - do not inspect local files or modify the machine
        - do not expose hidden reasoning or authentication details

        APP SYSTEM CONTEXT:
        \(systemInstruction)

        CONVERSATION:
        \(transcript)
        """
    }

    private static func handleCodexEvent(
        _ line: String,
        state: CodexResponseState,
        continuation: AsyncThrowingStream<String, any Error>.Continuation,
        onStatus: @escaping @Sendable (String) -> Void
    ) {
        guard let update = parseCodexEvent(line) else { return }
        if let status = update.status { onStatus(status) }
        if let error = update.error { state.appendError(error) }
        if let message = update.message {
            state.markMessageYielded()
            continuation.yield(message)
        }
    }

    static func parseCodexEvent(_ line: String) -> CodexEventUpdate? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            return nil
        }

        switch type {
        case "thread.started":
            return CodexEventUpdate(status: "Local Codex session started", message: nil, error: nil)
        case "turn.started":
            return CodexEventUpdate(status: "Analyzing your study context", message: nil, error: nil)
        case "turn.completed":
            return CodexEventUpdate(status: "Finalizing the answer", message: nil, error: nil)
        case "turn.failed", "error":
            return CodexEventUpdate(status: nil, message: nil, error: eventMessage(from: event))
        case "item.started", "item.updated", "item.completed":
            guard let item = event["item"] as? [String: Any],
                  let itemType = item["type"] as? String else {
                return nil
            }
            let status: String?
            switch itemType {
            case "reasoning": status = "Working through the problem"
            case "web_search": status = "Researching supporting sources"
            case "command_execution": status = "Using a local study tool"
            case "mcp_tool_call": status = "Using a connected tool"
            case "plan": status = "Planning the response"
            default: status = nil
            }
            let message: String?
            if itemType == "agent_message", type == "item.completed" {
                let text = (item["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                message = text.isEmpty ? nil : text
            } else {
                message = nil
            }
            guard status != nil || message != nil else { return nil }
            return CodexEventUpdate(status: status, message: message, error: nil)
        default:
            return nil
        }
    }

    private static func eventMessage(from event: [String: Any]) -> String {
        if let message = event["message"] as? String { return message }
        if let error = event["error"] as? [String: Any] {
            return error["message"] as? String ?? ""
        }
        return ""
    }

    private static func codexProcessError(
        exitCode: Int32,
        stderr: String,
        eventDetail: String,
        timedOut: Bool
    ) -> AIProviderError {
        if timedOut {
            return .processFailed("Local Codex timed out before completing the answer.")
        }
        let lowercasedEventDetail = eventDetail.lowercased()
        let lowercasedStderr = stderr.lowercased()
        let authenticationFailure = [
            "unauthorized",
            "invalid_api_key",
            "incorrect api key",
            "api key was rejected",
            "status 401"
        ].contains { lowercasedEventDetail.contains($0) }
            || ["not logged in", "run codex login", "please login"].contains {
                lowercasedStderr.contains($0)
            }
        if authenticationFailure {
            return .codexNotAuthenticated(
                "Codex CLI credentials were rejected. Sign in again, then retry this message."
            )
        }
        let bestDetail = eventDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            : eventDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let conciseDetail = String(bestDetail.prefix(500))
        return .processFailed(
            conciseDetail.isEmpty
                ? "Codex CLI exited with status \(exitCode)."
                : "Codex CLI failed: \(conciseDetail)"
        )
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

    private static func codexLoginStatus(executableURL: URL) async throws {
        let result = try await runProcess(
            executableURL: executableURL,
            arguments: ["login", "status"],
            input: nil,
            timeout: 12,
            useLoginShell: true
        )
        let detail = [result.stdout, result.stderr]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            throw AIProviderError.codexNotAuthenticated(
                detail.isEmpty
                    ? "Codex CLI is not signed in. Run codex login, then retry."
                    : detail
            )
        }
    }

    static func codexLoginCommand() throws -> String {
        let executablePath = try codexExecutableURL().path
        let quotedPath = "'" + executablePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Semicolon, not &&: `codex logout` exits non-zero when the CLI is
        // already signed out — precisely the state after rejected credentials —
        // and `&&` would then skip the login the user actually needs.
        return "\(quotedPath) logout; \(quotedPath) login"
    }

    /// Normalizes a provider base URL. Cleartext HTTP is rejected except for
    /// loopback hosts, where a locally-running provider (e.g. a local model
    /// server) is legitimate and never leaves the machine.
    private static func normalizedBaseURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        if scheme == "http" {
            let host = url.host?.lowercased() ?? ""
            let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
            guard isLoopback else { return nil }
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

    final class JSONLineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ newData: Data) -> [String] {
            guard !newData.isEmpty else { return [] }
            lock.lock()
            data.append(newData)
            let lines = extractCompleteLines()
            lock.unlock()
            return lines
        }

        func flush() -> [String] {
            lock.lock()
            defer {
                data.removeAll(keepingCapacity: false)
                lock.unlock()
            }
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else {
                return []
            }
            return [line]
        }

        private func extractCompleteLines() -> [String] {
            var lines: [String] = []
            // Advance a cursor instead of slicing the prefix off `data` per line;
            // removeSubrange(..<newlineIndex) is O(n) for every line, which turns
            // large transcript chunks into O(n²) work. The prefix is dropped once
            // after the scan.
            var searchStart = data.startIndex
            while let newlineIndex = data[searchStart...].firstIndex(of: 0x0A) {
                let lineData = data[searchStart..<newlineIndex]
                if let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    lines.append(line)
                }
                searchStart = data.index(after: newlineIndex)
            }
            if searchStart > data.startIndex {
                data.removeSubrange(..<searchStart)
            }
            return lines
        }
    }

    private final class CodexResponseState: @unchecked Sendable {
        private let lock = NSLock()
        private var yieldedMessage = false
        private var errors: [String] = []

        var didYieldMessage: Bool {
            lock.lock()
            defer { lock.unlock() }
            return yieldedMessage
        }

        var errorDetail: String {
            lock.lock()
            defer { lock.unlock() }
            return errors.joined(separator: " ")
        }

        func markMessageYielded() {
            lock.lock()
            yieldedMessage = true
            lock.unlock()
        }

        func appendError(_ message: String) {
            guard !message.isEmpty else { return }
            lock.lock()
            errors.append(message)
            lock.unlock()
        }
    }

    private final class ProcessController: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var timedOut = false
        private var terminationRequested = false

        var didTimeOut: Bool {
            lock.lock()
            defer { lock.unlock() }
            return timedOut
        }

        func run(_ process: Process) throws {
            lock.lock()
            guard !terminationRequested else {
                lock.unlock()
                throw CancellationError()
            }
            self.process = process
            do {
                try process.run()
                lock.unlock()
            } catch {
                self.process = nil
                lock.unlock()
                throw error
            }
        }

        func terminate(timedOut: Bool = false) {
            lock.lock()
            terminationRequested = true
            if timedOut { self.timedOut = true }
            let process = self.process
            lock.unlock()
            if process?.isRunning == true { process?.terminate() }
        }
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        input: String?,
        timeout: TimeInterval,
        useLoginShell: Bool = false
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

            if useLoginShell {
                configureCodexProcess(
                    process,
                    executableURL: executableURL,
                    arguments: arguments
                )
            } else {
                process.executableURL = executableURL
                process.arguments = arguments
            }
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
