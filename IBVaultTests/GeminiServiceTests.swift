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
}
