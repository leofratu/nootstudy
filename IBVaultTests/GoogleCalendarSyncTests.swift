import Foundation
import Testing
@testable import IBVault

@Suite("Google Calendar sync")
struct GoogleCalendarSyncTests {
    @Test("Parses a Google Desktop OAuth configuration")
    func parsesDesktopConfiguration() throws {
        let data = Data(#"""
        {
          "installed": {
            "client_id": "desktop-client.apps.googleusercontent.com",
            "client_secret": "client-secret",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost"]
          }
        }
        """#.utf8)

        let configuration = try GoogleOAuthConfiguration.decodeGoogleDesktopFile(data)

        #expect(configuration.clientID == "desktop-client.apps.googleusercontent.com")
        #expect(configuration.clientSecret == "client-secret")
        #expect(configuration.authorizationEndpoint.host == "accounts.google.com")
        #expect(configuration.tokenEndpoint.host == "oauth2.googleapis.com")
    }

    @Test("Rejects a web OAuth configuration")
    func rejectsWebConfiguration() {
        let data = Data(#"""
        {
          "web": {
            "client_id": "web-client.apps.googleusercontent.com",
            "client_secret": "client-secret",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token"
          }
        }
        """#.utf8)

        #expect(throws: CalendarSyncError.self) {
            try GoogleOAuthConfiguration.decodeGoogleDesktopFile(data)
        }
    }

    @Test("Rejects non-Google token endpoints")
    func rejectsUntrustedTokenEndpoint() {
        let data = Data(#"""
        {
          "installed": {
            "client_id": "desktop-client.apps.googleusercontent.com",
            "client_secret": "client-secret",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://example.com/collect"
          }
        }
        """#.utf8)

        #expect(throws: CalendarSyncError.self) {
            try GoogleOAuthConfiguration.decodeGoogleDesktopFile(data)
        }
    }

    @Test("Refreshes shortly before token expiry")
    func tokenRefreshWindow() {
        let expiring = GoogleOAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(60)
        )
        let valid = GoogleOAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(600)
        )

        #expect(expiring.needsRefresh)
        #expect(!valid.needsRefresh)
    }
}
