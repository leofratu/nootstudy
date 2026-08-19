import AppKit
import CryptoKit
import Foundation
@preconcurrency import Network

struct CalendarSyncOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let accountName: String

    var displayName: String {
        accountName.isEmpty ? title : "\(title) - \(accountName)"
    }
}

enum CalendarSyncPreferences {
    static let isEnabledKey = "calendarSyncEnabled"
    static let calendarIdentifierKey = "calendarSyncCalendarIdentifier"
    static let eventIdentifiersKey = "googleCalendarSyncEventIdentifiers"
    static let lastSyncDateKey = "calendarSyncLastDate"
    static let lastErrorKey = "calendarSyncLastError"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var calendarIdentifier: String {
        UserDefaults.standard.string(forKey: calendarIdentifierKey) ?? ""
    }

    static var eventIdentifiers: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: eventIdentifiersKey) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: eventIdentifiersKey)
        }
    }

    static func recordSuccess(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastSyncDateKey)
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
    }

    static func recordFailure(_ error: any Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: lastErrorKey)
    }
}

nonisolated struct GoogleOAuthConfiguration: Codable, Equatable, Sendable {
    let clientID: String
    let clientSecret: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL

    init(clientID: String, clientSecret: String, authorizationEndpoint: URL, tokenEndpoint: URL) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    static func decodeGoogleDesktopFile(_ data: Data) throws -> GoogleOAuthConfiguration {
        struct Document: Decodable {
            struct Installed: Decodable {
                let clientID: String
                let clientSecret: String
                let authURI: URL
                let tokenURI: URL

                enum CodingKeys: String, CodingKey {
                    case clientID = "client_id"
                    case clientSecret = "client_secret"
                    case authURI = "auth_uri"
                    case tokenURI = "token_uri"
                }
            }

            let installed: Installed?
        }

        let document = try JSONDecoder().decode(Document.self, from: data)
        guard let installed = document.installed,
              installed.clientID.hasSuffix(".apps.googleusercontent.com"),
              installed.authURI.scheme == "https",
              installed.authURI.host == "accounts.google.com",
              installed.tokenURI.scheme == "https",
              installed.tokenURI.host == "oauth2.googleapis.com" else {
            throw CalendarSyncError.invalidConfiguration
        }
        return GoogleOAuthConfiguration(
            clientID: installed.clientID,
            clientSecret: installed.clientSecret,
            authorizationEndpoint: installed.authURI,
            tokenEndpoint: installed.tokenURI
        )
    }
}

nonisolated struct GoogleOAuthToken: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow < 120
    }
}

nonisolated enum CalendarSyncError: LocalizedError {
    case invalidConfiguration
    case configurationMissing
    case signInCancelled
    case authorizationFailed(String)
    case tokenMissing
    case calendarUnavailable
    case serverError(String)
    case callbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Choose the Desktop app OAuth JSON file downloaded from Google Cloud."
        case .configurationMissing:
            return "Google OAuth is not configured yet. Choose your Desktop app OAuth file first."
        case .signInCancelled:
            return "Google sign-in was cancelled."
        case .authorizationFailed(let detail):
            return detail.isEmpty ? "Google did not authorize calendar access." : "Google sign-in failed: \(detail)"
        case .tokenMissing:
            return "Your Google connection expired. Connect Google Calendar again."
        case .calendarUnavailable:
            return "The selected Google calendar is no longer available or cannot be edited."
        case .serverError(let detail):
            return detail.isEmpty ? "Google Calendar could not complete the request." : detail
        case .callbackFailed:
            return "Noot could not receive the Google sign-in response. Try connecting again."
        }
    }
}

extension Notification.Name {
    static let calendarSyncRequested = Notification.Name("CalendarSyncRequested")
}

@MainActor
final class CalendarSyncService {
    static let shared = CalendarSyncService()

    private static let calendarAPI = URL(string: "https://www.googleapis.com/calendar/v3")!
    private static let scopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    ]

    private let session: URLSession

    var isConfigured: Bool { KeychainService.loadGoogleOAuthConfiguration() != nil }
    var isConnected: Bool { KeychainService.loadGoogleOAuthToken() != nil }

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func importConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let configuration = try GoogleOAuthConfiguration.decodeGoogleDesktopFile(data)
        guard KeychainService.saveGoogleOAuthConfiguration(configuration) else {
            throw CalendarSyncError.serverError("Noot could not securely save the Google configuration.")
        }
    }

    func connect() async throws {
        guard let configuration = KeychainService.loadGoogleOAuthConfiguration() else {
            throw CalendarSyncError.configurationMissing
        }

        let callbackServer = try OAuthLoopbackServer()
        let redirectURI = try await callbackServer.start()
        defer { callbackServer.stop() }

        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafeString(byteCount: 32)
        let authorizationURL = try authorizationURL(
            configuration: configuration,
            redirectURI: redirectURI,
            state: state,
            challenge: challenge
        )

        guard NSWorkspace.shared.open(authorizationURL) else {
            throw CalendarSyncError.authorizationFailed("The sign-in page could not be opened.")
        }

        let callbackURL = try await callbackServer.waitForCallback(timeout: 180)
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw CalendarSyncError.callbackFailed
        }
        let parameters: [String: String] = Dictionary(uniqueKeysWithValues: components.queryItems?.compactMap {
            guard let value = $0.value else { return nil }
            return ($0.name, value)
        } ?? [])

        if let error = parameters["error"] {
            if error == "access_denied" { throw CalendarSyncError.signInCancelled }
            throw CalendarSyncError.authorizationFailed(parameters["error_description"] ?? error)
        }
        guard parameters["state"] == state, let code = parameters["code"] else {
            throw CalendarSyncError.callbackFailed
        }

        let token = try await exchangeCode(
            code,
            verifier: verifier,
            redirectURI: redirectURI,
            configuration: configuration
        )
        guard KeychainService.saveGoogleOAuthToken(token) else {
            throw CalendarSyncError.serverError("Noot could not securely save the Google connection.")
        }
    }

    func disconnect() {
        _ = KeychainService.deleteGoogleOAuthToken()
        CalendarSyncPreferences.eventIdentifiers = [:]
        UserDefaults.standard.set(false, forKey: CalendarSyncPreferences.isEnabledKey)
    }

    func writableCalendars() async throws -> [CalendarSyncOption] {
        let request = URLRequest(url: Self.calendarAPI.appending(path: "users/me/calendarList"))
        let response: CalendarListResponse = try await authenticatedJSON(request)
        return response.items
            .filter { $0.accessRole == "owner" || $0.accessRole == "writer" }
            .map {
                CalendarSyncOption(
                    id: $0.id,
                    title: $0.summary,
                    accountName: $0.primary == true ? "Primary" : "Google Calendar"
                )
            }
            .sorted {
                if $0.accountName == $1.accountName { return $0.title < $1.title }
                return $0.accountName < $1.accountName
            }
    }

    func sync(plans: [StudyPlan]) async throws {
        guard CalendarSyncPreferences.isEnabled else { return }
        let calendarID = CalendarSyncPreferences.calendarIdentifier
        guard !calendarID.isEmpty else { throw CalendarSyncError.calendarUnavailable }

        var mappings = CalendarSyncPreferences.eventIdentifiers
        let currentPlanIDs = Set(plans.map { $0.id.uuidString })

        for stalePlanID in mappings.keys.filter({ !currentPlanIDs.contains($0) }) {
            if let eventID = mappings[stalePlanID] {
                try await deleteEvent(eventID, calendarID: calendarID)
            }
            mappings.removeValue(forKey: stalePlanID)
            CalendarSyncPreferences.eventIdentifiers = mappings
        }

        for plan in plans {
            let planID = plan.id.uuidString
            let body = eventBody(for: plan)
            if let eventID = mappings[planID] {
                do {
                    try await updateEvent(eventID, calendarID: calendarID, body: body)
                    continue
                } catch GoogleHTTPError.notFound {
                    mappings.removeValue(forKey: planID)
                }
            }
            mappings[planID] = try await createEvent(calendarID: calendarID, body: body)
            CalendarSyncPreferences.eventIdentifiers = mappings
        }

        CalendarSyncPreferences.eventIdentifiers = mappings
        CalendarSyncPreferences.recordSuccess()
    }

    private func authorizationURL(
        configuration: GoogleOAuthConfiguration,
        redirectURI: URL,
        state: String,
        challenge: String
    ) throws -> URL {
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else { throw CalendarSyncError.invalidConfiguration }
        return url
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: URL,
        configuration: GoogleOAuthConfiguration
    ) async throws -> GoogleOAuthToken {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded([
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI.absoluteString
        ])
        let response: TokenResponse = try await plainJSON(request)
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw CalendarSyncError.authorizationFailed("Google did not return offline access. Reconnect and approve access.")
        }
        return GoogleOAuthToken(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    private func refreshedToken(
        _ token: GoogleOAuthToken,
        configuration: GoogleOAuthConfiguration
    ) async throws -> GoogleOAuthToken {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded([
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken
        ])
        let response: TokenResponse = try await plainJSON(request)
        return GoogleOAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    private func validToken(forceRefresh: Bool = false) async throws -> GoogleOAuthToken {
        guard let configuration = KeychainService.loadGoogleOAuthConfiguration() else {
            throw CalendarSyncError.configurationMissing
        }
        guard let stored = KeychainService.loadGoogleOAuthToken() else {
            throw CalendarSyncError.tokenMissing
        }
        guard forceRefresh || stored.needsRefresh else { return stored }
        let refreshed = try await refreshedToken(stored, configuration: configuration)
        guard KeychainService.saveGoogleOAuthToken(refreshed) else {
            throw CalendarSyncError.serverError("Noot could not securely update the Google connection.")
        }
        return refreshed
    }

    private func authenticatedData(_ original: URLRequest) async throws -> Data {
        var token = try await validToken()
        for attempt in 0...1 {
            var request = original
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CalendarSyncError.serverError("Google Calendar returned an invalid response.")
            }
            if http.statusCode == 401, attempt == 0 {
                token = try await validToken(forceRefresh: true)
                continue
            }
            if http.statusCode == 404 { throw GoogleHTTPError.notFound }
            guard (200..<300).contains(http.statusCode) else {
                throw CalendarSyncError.serverError(Self.googleError(from: data, statusCode: http.statusCode))
            }
            return data
        }
        throw CalendarSyncError.tokenMissing
    }

    private func authenticatedJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await authenticatedData(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func plainJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CalendarSyncError.serverError(Self.googleError(from: data, statusCode: statusCode))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func createEvent(calendarID: String, body: GoogleCalendarEvent) async throws -> String {
        var request = URLRequest(url: eventsURL(calendarID: calendarID))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.googleCalendar.encode(body)
        let response: EventIDResponse = try await authenticatedJSON(request)
        return response.id
    }

    private func updateEvent(_ eventID: String, calendarID: String, body: GoogleCalendarEvent) async throws {
        var request = URLRequest(url: eventsURL(calendarID: calendarID).appending(path: eventID))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.googleCalendar.encode(body)
        _ = try await authenticatedData(request)
    }

    private func deleteEvent(_ eventID: String, calendarID: String) async throws {
        var request = URLRequest(url: eventsURL(calendarID: calendarID).appending(path: eventID))
        request.httpMethod = "DELETE"
        do {
            _ = try await authenticatedData(request)
        } catch GoogleHTTPError.notFound {
            return
        }
    }

    private func eventsURL(calendarID: String) -> URL {
        Self.calendarAPI
            .appending(path: "calendars")
            .appending(path: calendarID)
            .appending(path: "events")
    }

    private func eventBody(for plan: StudyPlan) -> GoogleCalendarEvent {
        var lines: [String] = []
        if !plan.selectedTopicNames.isEmpty {
            lines.append("Topics: \(plan.selectedTopicNames.joined(separator: ", "))")
        }
        if !plan.selectedSubtopicNames.isEmpty {
            lines.append("Subtopics: \(plan.selectedSubtopicNames.joined(separator: ", "))")
        }
        lines.append("Status: \(plan.isCompleted ? "Completed" : "Planned")")
        lines.append("Created by Noot Study")

        return GoogleCalendarEvent(
            summary: plan.isFollowUpReview
                ? "Noot Review: \(plan.subjectName)"
                : "Noot Study: \(plan.subjectName)",
            description: lines.joined(separator: "\n"),
            start: .init(dateTime: plan.scheduledDate),
            end: .init(dateTime: max(plan.scheduledEndDate, plan.scheduledDate.addingTimeInterval(60))),
            transparency: "opaque",
            extendedProperties: .init(private: [
                "nootStudySource": "NootStudy",
                "nootStudyPlanID": plan.id.uuidString
            ])
        )
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncoded(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let string = values.sorted(by: { $0.key < $1.key }).map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(string.utf8)
    }

    private static func googleError(from data: Data, statusCode: Int) -> String {
        struct ErrorEnvelope: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return envelope.error.message
        }
        return "Google Calendar request failed (\(statusCode))."
    }
}

nonisolated private enum GoogleHTTPError: Error {
    case notFound
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct CalendarListResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let summary: String
        let accessRole: String
        let primary: Bool?
    }
    let items: [Item]
}

private struct EventIDResponse: Decodable {
    let id: String
}

private struct GoogleCalendarEvent: Encodable {
    struct DateValue: Encodable { let dateTime: Date }
    struct ExtendedProperties: Encodable { let `private`: [String: String] }

    let summary: String
    let description: String
    let start: DateValue
    let end: DateValue
    let transparency: String
    let extendedProperties: ExtendedProperties
}

private extension JSONEncoder {
    static var googleCalendar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

nonisolated private final class OAuthLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.nootstudy.oauth-loopback")
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<URL, any Error>?
    private var callbackContinuation: CheckedContinuation<URL, any Error>?
    private var callbackResult: Result<URL, any Error>?
    private var timeoutTask: Task<Void, Never>?

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { startContinuation = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener.port else {
                        self.finishStart(.failure(CalendarSyncError.callbackFailed))
                        return
                    }
                    self.finishStart(.success(URL(string: "http://127.0.0.1:\(port.rawValue)/oauth2callback")!))
                case .failed(let error):
                    self.finishStart(.failure(error))
                    self.finishCallback(.failure(error))
                case .cancelled:
                    self.finishStart(.failure(CalendarSyncError.callbackFailed))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(connection)
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let result = lock.withLock { () -> Result<URL, any Error>? in
                if let callbackResult { return callbackResult }
                callbackContinuation = continuation
                return nil
            }
            if let result { continuation.resume(with: result); return }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finishCallback(.failure(CalendarSyncError.callbackFailed))
            }
        }
    }

    func stop() {
        timeoutTask?.cancel()
        listener.cancel()
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.finishCallback(.failure(error))
                connection.cancel()
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n", maxSplits: 1).first,
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let callbackURL = URL(string: "http://127.0.0.1\(target)") else {
                self.sendResponse(connection, success: false)
                self.finishCallback(.failure(CalendarSyncError.callbackFailed))
                return
            }
            self.sendResponse(connection, success: true)
            self.finishCallback(.success(callbackURL))
        }
    }

    private func sendResponse(_ connection: NWConnection, success: Bool) {
        let message = success
            ? "Google Calendar is connected. You can close this window and return to Noot Study."
            : "Noot Study could not complete the connection. Return to the app and try again."
        let body = "<!doctype html><meta charset=\"utf-8\"><title>Noot Study</title><style>body{font:16px -apple-system;margin:64px;max-width:560px;color:#18202a}h1{font-size:28px}</style><h1>\(success ? "Connected" : "Connection failed")</h1><p>\(message)</p>"
        let response = "HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finishStart(_ result: Result<URL, any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, any Error>? in
            defer { startContinuation = nil }
            return startContinuation
        }
        continuation?.resume(with: result)
    }

    private func finishCallback(_ result: Result<URL, any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, any Error>? in
            guard callbackResult == nil else { return nil }
            callbackResult = result
            defer { callbackContinuation = nil }
            return callbackContinuation
        }
        timeoutTask?.cancel()
        continuation?.resume(with: result)
    }
}
