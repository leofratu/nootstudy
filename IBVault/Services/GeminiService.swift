import Foundation

struct GeminiConfig: Sendable {
    var apiBase: String = "https://generativelanguage.googleapis.com/v1beta"
    var defaultRequestTimeout: TimeInterval = 90
    var defaultResourceTimeout: TimeInterval = 180
    var defaultTemperature: Double = 0.7
    var defaultMaxTokens: Int = 4096
    var defaultTopP: Double = 0.95
    var maxRetries: Int = 3
    
    static let `default` = GeminiConfig()
}

struct GeminiMessage: Sendable {
    let role: String
    let text: String
}

struct GeminiModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let inputTokenLimit: Int
    let outputTokenLimit: Int
    let supportsStreaming: Bool
    
    var shortDescription: String {
        description.count > 80 ? String(description.prefix(77)) + "..." : description
    }
    
    var tokenInfo: String {
        let inK = inputTokenLimit / 1000
        let outK = outputTokenLimit / 1000
        let inStr = inK >= 1000 ? "\(inK/1000)M" : "\(inK)K"
        let outStr = outK >= 1000 ? "\(outK/1000)M" : "\(outK)K"
        return "\(inStr) in → \(outStr) out"
    }
}

enum GeminiError: Error, LocalizedError, Sendable {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case noAPIKey
    case maxRetriesExceeded
    case offline
    case rateLimited(retryAfter: Int?)
    case quotaExceeded
    case invalidModel
    case contentFiltered
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .apiError(let code, _):
            return apiErrorMessage(for: code)
        case .parseError:
            return "Failed to parse Gemini response"
        case .noAPIKey:
            return "No Gemini API key configured. Go to Settings to add your key."
        case .maxRetriesExceeded:
            return "Request timed out. Please try again."
        case .offline:
            return "No internet connection. Please check your network."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .quotaExceeded:
            return "API quota exceeded. Please check your Gemini API usage."
        case .invalidModel:
            return "Selected model is not available. Try a different model in Settings."
        case .contentFiltered:
            return "Request was blocked due to content policy. Try rephrasing your question."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .maxRetriesExceeded, .offline:
            return true
        case .apiError(let code, _):
            return code == 429 || code == 503
        default:
            return false
        }
    }
    
    private func apiErrorMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 400: return "Invalid request. Try rephrasing your question."
        case 403: return "API key doesn't have permission. Check your key in Settings."
        case 404: return "Model not found. Select a different model in Settings."
        case 429: return "Rate limit exceeded. Wait a moment before trying again."
        case 500: return "Gemini server error. Try again in a few seconds."
        case 503: return "Service temporarily unavailable. Please try again."
        default: return "API error (\(statusCode))"
        }
    }
}

enum GeminiService {
    static var selectedModel: String {
        UserDefaults.standard.string(forKey: "geminiModel") ?? "gemini-2.0-flash"
    }
    
    private static var temperature: Double {
        let temp = UserDefaults.standard.double(forKey: "ariaTemperature")
        return temp > 0 ? temp : 0.7
    }
    
    private static var maxTokens: Int {
        let tokens = UserDefaults.standard.integer(forKey: "ariaMaxTokens")
        return tokens > 0 ? tokens : 4096
    }
    
    static func listModels(apiKey: String, config: GeminiConfig = .default) async throws -> [GeminiModel] {
        let url = URL(string: "\(config.apiBase)/models?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeminiError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw GeminiError.parseError
        }
        
        return models.compactMap { dict -> GeminiModel? in
            guard let name = dict["name"] as? String,
                  let displayName = dict["displayName"] as? String else { return nil }
            
            let desc = dict["description"] as? String ?? ""
            let inputLimit = dict["inputTokenLimit"] as? Int ?? 0
            let outputLimit = dict["outputTokenLimit"] as? Int ?? 0
            let methods = dict["supportedGenerationMethods"] as? [String] ?? []
            
            guard methods.contains("generateContent") else { return nil }
            
            let modelId = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
            
            return GeminiModel(
                id: modelId,
                displayName: displayName,
                description: desc,
                inputTokenLimit: inputLimit,
                outputTokenLimit: outputLimit,
                supportsStreaming: methods.contains("streamGenerateContent")
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }
    
    static func generateContent(
        messages: [GeminiMessage],
        systemInstruction: String,
        apiKey: String,
        modelOverride: String? = nil,
        timeout: TimeInterval = 90,
        config: GeminiConfig = .default
    ) async throws -> String {
        let model = modelOverride ?? selectedModel
        let url = URL(string: "\(config.apiBase)/models/\(model):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        let body = buildRequestBody(
            messages: messages,
            systemInstruction: systemInstruction,
            temperature: temperature,
            maxTokens: maxTokens,
            topP: config.defaultTopP
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await retryRequest(
            request: request,
            maxRetries: config.maxRetries,
            timeout: timeout
        )
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw parseAPIError(statusCode: httpResponse.statusCode, body: errorBody)
        }
        
        return try parseResponse(data: data)
    }
    
    static func streamContent(
        messages: [GeminiMessage],
        systemInstruction: String,
        apiKey: String,
        config: GeminiConfig = .default
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(config.apiBase)/models/\(selectedModel):streamGenerateContent?alt=sse&key=\(apiKey)")!
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60
                    
                    let body = buildRequestBody(
                        messages: messages,
                        systemInstruction: systemInstruction,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        topP: config.defaultTopP
                    )
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw GeminiError.invalidResponse
                    }
                    
                    if httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw parseAPIError(statusCode: httpResponse.statusCode, body: errorBody)
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            if jsonStr == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let jsonData = jsonStr.data(using: .utf8),
                               let text = try? parseStreamChunk(data: jsonData),
                               !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch let error as GeminiError {
                    continuation.finish(throwing: error)
                } catch {
                    if (error as NSError).code == NSURLErrorTimedOut {
                        continuation.finish(throwing: GeminiError.maxRetriesExceeded)
                    } else if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        continuation.finish(throwing: GeminiError.offline)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
    
    private static func buildRequestBody(
        messages: [GeminiMessage],
        systemInstruction: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double
    ) -> [String: Any] {
        var body: [String: Any] = [:]
        
        if !systemInstruction.isEmpty {
            body["system_instruction"] = [
                "parts": [["text": systemInstruction]]
            ]
        }
        
        let contents = messages.map { msg in
            [
                "role": msg.role,
                "parts": [["text": msg.text]]
            ]
        }
        body["contents"] = contents
        
        body["generationConfig"] = [
            "temperature": temperature,
            "topP": topP,
            "maxOutputTokens": maxTokens
        ]
        
        return body
    }
    
    private static func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw GeminiError.parseError
        }
        return text
    }
    
    private static func parseStreamChunk(data: Data) throws -> String? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return nil
        }
        return text
    }
    
    private static func parseAPIError(statusCode: Int, body: String) -> GeminiError {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? body
            let status = error["status"] as? String ?? ""
            
            if status == "RESOURCE_EXHAUSTED" || statusCode == 429 {
                return .quotaExceeded
            }
            if status == "SAFETY" || message.lowercased().contains("blocked") {
                return .contentFiltered
            }
            if status == "MODEL_NOT_FOUND" {
                return .invalidModel
            }
            return .apiError(statusCode: statusCode, message: message)
        }
        
        switch statusCode {
        case 429:
            return .rateLimited(retryAfter: nil)
        default:
            return .apiError(statusCode: statusCode, message: body)
        }
    }
    
    private static func retryRequest(
        request: URLRequest,
        maxRetries: Int,
        timeout: TimeInterval
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        let session = configuredSession(timeout: timeout)
        
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
                        let delay = pow(2.0, Double(attempt)) + Double.random(in: 0...1)
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }
                
                return (data, response)
            } catch {
                lastError = error
                let nsError = error as NSError
                
                if nsError.code == NSURLErrorNotConnectedToInternet {
                    throw GeminiError.offline
                }
                
                if nsError.code == NSURLErrorTimedOut && attempt == maxRetries - 1 {
                    throw GeminiError.maxRetriesExceeded
                }
                
                let delay = pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? GeminiError.maxRetriesExceeded
    }
    
    private static func configuredSession(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }
}