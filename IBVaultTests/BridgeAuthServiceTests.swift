import Testing
import Foundation
@testable import IBVault

@Suite("BridgeAuthService Tests")
struct BridgeAuthServiceTests {

    @Test("Constant-time comparison is correct")
    func constantTimeEqual() {
        #expect(BridgeAuthService.constantTimeEqual("abc", "abc"))
        #expect(!BridgeAuthService.constantTimeEqual("abc", "abd"))
        #expect(!BridgeAuthService.constantTimeEqual("abc", "ab"))
        #expect(!BridgeAuthService.constantTimeEqual("", "a"))
        #expect(BridgeAuthService.constantTimeEqual("", ""))
    }

    @Test("Regenerate token changes value and is valid bearer")
    func regenerateChangesToken() {
        let first = BridgeAuthService.token()
        let second = BridgeAuthService.regenerateToken()
        #expect(first != second)
        #expect(BridgeAuthService.isValidBearer("Bearer \(second)"))
        #expect(!BridgeAuthService.isValidBearer("Bearer \(first)"))
        #expect(!BridgeAuthService.isValidBearer("Bearer invalid"))
        #expect(!BridgeAuthService.isValidBearer(nil))
        #expect(!BridgeAuthService.isValidBearer("Basic \(second)"))
    }

    @Test("IsValidBearer trims and checks prefix")
    func bearerPrefix() {
        let token = BridgeAuthService.token()
        #expect(BridgeAuthService.isValidBearer("Bearer \(token)"))
        #expect(BridgeAuthService.isValidBearer("Bearer  \(token)  "))
        #expect(!BridgeAuthService.isValidBearer("bearer \(token)"))
    }
}
