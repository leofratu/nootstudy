import Foundation
import Testing
@testable import IBVault

@Suite("Gemini Service Tests")
struct GeminiServiceTests {
    @Test("Encoded request body preserves Gemini wire format")
    func encodedRequestBodyPreservesWireFormat() throws {
        let data = try GeminiService.encodedRequestBodyForTesting(
            messages: [
                GeminiMessage(role: "user", text: "Explain osmosis"),
                GeminiMessage(role: "model", text: "Osmosis is water movement.")
            ],
            systemInstruction: "You are an IB tutor.",
            temperature: 0.4,
            topP: 0.9
        )

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let systemInstruction = json?["system_instruction"] as? [String: Any]
        let systemParts = systemInstruction?["parts"] as? [[String: Any]]
        let contents = json?["contents"] as? [[String: Any]]
        let generationConfig = json?["generationConfig"] as? [String: Any]

        #expect(systemParts?.first?["text"] as? String == "You are an IB tutor.")
        #expect(contents?.count == 2)
        #expect(contents?.first?["role"] as? String == "user")
        #expect(generationConfig?["maxOutputTokens"] == nil)
        #expect(generationConfig?["temperature"] as? Double == 0.4)
        #expect(generationConfig?["topP"] as? Double == 0.9)
    }

    @Test("The API key travels in the x-goog-api-key header, never in the body")
    func apiKeyIsHeaderOnly() throws {
        let secret = "AIza-SECRET-KEY-do-not-leak"
        let request = try GeminiService.makeGenerateContentRequest(
            messages: [GeminiMessage(role: "user", text: "Explain photosynthesis")],
            systemInstruction: "You are an IB Biology tutor.",
            apiKey: secret,
            modelOverride: "gemini-2.0-flash",
            timeout: 30
        )

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == secret)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString.contains("gemini-2.0-flash") == true)

        let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(!bodyString.contains(secret))
        #expect(!bodyString.lowercased().contains("api-key"))
        #expect(bodyString.contains("Explain photosynthesis"))
    }

    @Test("Request building rejects a malformed base URL without force-unwrapping")
    func malformedBaseURLThrows() {
        var broken = GeminiConfig.default
        broken.apiBase = "not a url"
        #expect(throws: GeminiError.self) {
            _ = try GeminiService.makeGenerateContentRequest(
                messages: [GeminiMessage(role: "user", text: "hi")],
                systemInstruction: "",
                apiKey: "key",
                config: broken
            )
        }
    }
}
