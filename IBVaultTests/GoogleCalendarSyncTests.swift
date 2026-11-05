import Foundation
import Testing
@testable import IBVault

@Suite("Google Calendar sync", .serialized)
@MainActor
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

    @Test("Revoked OAuth refresh tokens expose a reconnect action instead of a generic 400")
    func revokedRefreshToken() {
        // Google's documented OAuth token-error response uses a string error,
        // unlike the nested error object returned by the Calendar REST API.
        let data = Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)
        let error = CalendarSyncService.responseError(from: data, statusCode: 400)
        guard case .tokenMissing = error else {
            Issue.record("Expected a reconnect error, got \(error)")
            return
        }
        #expect(error.localizedDescription.contains("Connect Google Calendar again"))
    }

    @Test("Calendar REST errors retain Google's actionable message")
    func calendarErrorMessage() {
        // Response example from developers.google.com/workspace/calendar/api/guides/errors.
        let data = Data(#"{"error":{"errors":[{"domain":"global","reason":"notFound","message":"Not Found"}],"code":404,"message":"Not Found"}}"#.utf8)
        #expect(CalendarSyncService.responseError(from: data, statusCode: 404).localizedDescription == "Not Found")
    }

    @Test("Switching calendars does not reuse or discard another calendar's event IDs")
    func calendarScopedMappings() throws {
        let suite = "CalendarSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("first", forKey: CalendarSyncPreferences.calendarIdentifierKey)
        defaults.set(["plan": "old-event"], forKey: CalendarSyncPreferences.eventIdentifiersKey)
        #expect(CalendarSyncPreferences.eventIdentifiers(for: "first", defaults: defaults) == ["plan": "old-event"])
        defaults.set("second", forKey: CalendarSyncPreferences.calendarIdentifierKey)
        #expect(CalendarSyncPreferences.eventIdentifiers(for: "second", defaults: defaults).isEmpty)
        CalendarSyncPreferences.setEventIdentifiers(["plan": "new-event"], for: "second", defaults: defaults)
        #expect(CalendarSyncPreferences.eventIdentifiers(for: "first", defaults: defaults) == ["plan": "old-event"])
        #expect(CalendarSyncPreferences.eventIdentifiers(for: "second", defaults: defaults) == ["plan": "new-event"])
    }

    @Test("Disconnect preserves event mappings for a future reconnect")
    func disconnectPreservesMappings() throws {
        let suite = "CalendarSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        CalendarSyncPreferences.setEventIdentifiers(["plan": "event"], for: "calendar", defaults: defaults)
        defaults.set(true, forKey: CalendarSyncPreferences.isEnabledKey)

        CalendarSyncService(defaults: defaults).disconnect()

        #expect(!defaults.bool(forKey: CalendarSyncPreferences.isEnabledKey))
        #expect(CalendarSyncPreferences.eventIdentifiers(for: "calendar", defaults: defaults) == ["plan": "event"])
    }

    @Test("Concurrent expired-token requests refresh once and return to reconnect")
    func expiredConnectionRecovery() async throws {
        let configuration = GoogleOAuthConfiguration(clientID: "test.apps.googleusercontent.com", clientSecret: "test",
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        #expect(KeychainService.saveGoogleOAuthConfiguration(configuration))
        #expect(KeychainService.saveGoogleOAuthToken(.init(accessToken: "expired", refreshToken: "revoked", expiresAt: .distantPast)))
        defer { _ = KeychainService.deleteGoogleOAuthToken() }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RevokedTokenProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        RevokedTokenProtocol.reset()
        let service = CalendarSyncService(session: session)

        func attempt() async -> Bool {
            do { _ = try await service.writableCalendars(); return false }
            catch CalendarSyncError.tokenMissing { return true }
            catch { Issue.record("Unexpected error: \(error)"); return false }
        }
        async let first = attempt()
        async let second = attempt()
        let results = await (first, second)

        #expect(results.0 && results.1)
        #expect(RevokedTokenProtocol.requestCount == 1)
        #expect(service.isConfigured)
        #expect(!service.isConnected)
    }

    @Test("One event Google rejects does not stop the sessions after it")
    func rejectedEventDoesNotStopSync() async throws {
        let suite = "CalendarSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: CalendarSyncPreferences.isEnabledKey)
        defaults.set("calendar", forKey: CalendarSyncPreferences.calendarIdentifierKey)
        let configuration = GoogleOAuthConfiguration(clientID: "test.apps.googleusercontent.com", clientSecret: "test",
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        #expect(KeychainService.saveGoogleOAuthConfiguration(configuration))
        #expect(KeychainService.saveGoogleOAuthToken(.init(accessToken: "valid", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3_600))))
        defer { _ = KeychainService.deleteGoogleOAuthToken() }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RejectingCalendarProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let service = CalendarSyncService(session: session, defaults: defaults)

        let rejected = StudyPlan(subjectName: "Rejected", topicName: "Topic", scheduledDate: .now)
        let accepted = StudyPlan(subjectName: "Accepted", topicName: "Topic", scheduledDate: .now)

        do {
            try await service.sync(plans: [rejected, accepted])
            Issue.record("A partial sync must report the failure")
        } catch {
            #expect(error.localizedDescription.contains("1 of 2"))
        }
        let mappings = CalendarSyncPreferences.eventIdentifiers(for: "calendar", defaults: defaults)
        #expect(mappings[accepted.id.uuidString] == "created")
        #expect(mappings[rejected.id.uuidString] == nil)
    }

    @Test("Only failures the learner must fix raise the attention flag")
    func attentionFlag() throws {
        let suite = "CalendarSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = CalendarSyncPreferences.needsAttentionKey

        CalendarSyncPreferences.recordFailure(CalendarSyncError.serverError("Busy"), defaults: defaults)
        CalendarSyncPreferences.recordFailure(URLError(.notConnectedToInternet), defaults: defaults)
        #expect(!defaults.bool(forKey: key))

        CalendarSyncPreferences.recordFailure(CalendarSyncError.tokenMissing, defaults: defaults)
        #expect(defaults.bool(forKey: key))

        CalendarSyncPreferences.recordSuccess(defaults: defaults)
        #expect(!defaults.bool(forKey: key))
        #expect(defaults.string(forKey: CalendarSyncPreferences.lastErrorKey) == nil)
    }
}

nonisolated private final class RejectingCalendarProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var status = 200
        var body = #"{"items":[]}"#
        if request.httpMethod == "POST" {
            // URLProtocol receives uploads as a stream, so read it back.
            var data = Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4_096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(buffer, count: count)
                }
            }
            if String(data: data, encoding: .utf8)?.contains("Rejected") == true {
                status = 400
                body = #"{"error":{"code":400,"message":"Bad event"}}"#
            } else {
                body = #"{"id":"created"}"#
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

nonisolated private final class RevokedTokenProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    static var requestCount: Int { lock.withLock { count } }
    static func reset() { lock.withLock { count = 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        // The documented Google OAuth error payload, not a fabricated success DTO.
        let data = Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
