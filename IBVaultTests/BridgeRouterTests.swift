import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("BridgeRouter Tests", .serialized)
struct BridgeRouterTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for:
            Subject.self,
            StudyCard.self,
            ReviewSession.self,
            Grade.self,
            StudySession.self,
            StudyPlan.self,
            ARIAMemory.self,
            ExternalActivity.self,
            UserProfile.self,
            Achievement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeRequest(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data? = nil) -> BridgeRequest {
        BridgeRequest(method: method, path: path, queryItems: query, headers: headers, body: body)
    }

    private func authHeaders() -> [String: String] {
        let token = BridgeAuthService.token()
        return ["authorization": "Bearer \(token)"]
    }

    @Test("Health does not require auth and returns ok")
    func healthNoAuth() throws {
        let container = try makeContainer()
        let router = BridgeRouter(container: container)
        let req = makeRequest(method: "GET", path: "/v1/health")
        let resp = router.handle(req)
        #expect(resp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        #expect(json?["ok"] as? Bool == true)
        #expect(json?["apiVersion"] as? Int == 1)
    }

    @Test("Unauthorized without token returns 401")
    func unauthorizedReturns401() throws {
        let container = try makeContainer()
        let router = BridgeRouter(container: container)
        let req = makeRequest(method: "GET", path: "/v1/cards")
        let resp = router.handle(req)
        #expect(resp.statusCode == 401)
        let json = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        #expect(error?["code"] as? String == "unauthorized")
    }

    @Test("Authorized health still works with token")
    func healthWithAuth() throws {
        let container = try makeContainer()
        let router = BridgeRouter(container: container)
        let req = makeRequest(method: "GET", path: "/v1/health", headers: authHeaders())
        let resp = router.handle(req)
        #expect(resp.statusCode == 200)
    }

    @Test("Cards query with auth returns cards and total")
    func cardsQuery() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        ctx.insert(subject)
        let card = StudyCard(topicName: "Cells", front: "Q1", back: "A1", subject: subject)
        ctx.insert(card)
        try ctx.save()

        let router = BridgeRouter(container: container)
        let req = makeRequest(method: "GET", path: "/v1/cards", query: ["limit": "10"], headers: authHeaders())
        let resp = router.handle(req)
        #expect(resp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        #expect(json?["total"] as? Int == 1)
        let cards = json?["cards"] as? [[String: Any]]
        #expect(cards?.count == 1)
    }

    @Test("Post cards validates subject and dedup")
    func postCardsValidation() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        ctx.insert(subject)
        try ctx.save()

        let router = BridgeRouter(container: container)
        let payload: [String: Any] = ["cards": [
            ["subjectName": "Economics", "topicName": "Demand", "front": "What is demand?", "back": "Willingness to buy"],
            ["subjectName": "Missing", "topicName": "X", "front": "Q", "back": "A"],
            ["subjectName": "Economics", "topicName": "Demand", "front": "What is demand?", "back": "Duplicate"]
        ]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = makeRequest(method: "POST", path: "/v1/cards", headers: authHeaders(), body: body)
        let resp = router.handle(req)
        #expect(resp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        let created = json?["created"] as? [[String: Any]]
        let skipped = json?["skipped"] as? [[String: Any]]
        #expect(created?.count == 1)
        #expect(skipped?.count == 2)
        let reasons = skipped?.compactMap { $0["reason"] as? String } ?? []
        #expect(reasons.contains { $0.contains("subject not found") })
        #expect(reasons.contains { $0.contains("duplicate") })
    }

    @Test("Post reviews applies via FSRS")
    func postReviewsApply() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        ctx.insert(subject)
        let card = StudyCard(topicName: "Cells", front: "Q", back: "A", subject: subject)
        ctx.insert(card)
        try ctx.save()
        let cardID = card.id
        let originalDue = card.nextReviewDate

        let router = BridgeRouter(container: container)
        let payload: [String: Any] = ["reviews": [["cardID": cardID.uuidString, "quality": 3]]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = makeRequest(method: "POST", path: "/v1/reviews", headers: authHeaders(), body: body)
        let resp = router.handle(req)
        #expect(resp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        let accepted = json?["accepted"] as? [[String: Any]]
        #expect(accepted?.count == 1)
        // Verify card due date changed via fresh context
        let ctx2 = ModelContext(container)
        let fetched = try ctx2.fetch(FetchDescriptor<StudyCard>(predicate: #Predicate { $0.id == cardID }))
        #expect(fetched.first?.nextReviewDate != originalDue)
        #expect(fetched.first?.totalReviewCount == 1)
    }

    @Test("Post reviews rejects invalid quality")
    func postReviewsRejectInvalidQuality() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        ctx.insert(subject)
        let card = StudyCard(topicName: "Cells", front: "Q", back: "A", subject: subject)
        ctx.insert(card)
        try ctx.save()

        let router = BridgeRouter(container: container)
        let payload: [String: Any] = ["reviews": [["cardID": card.id.uuidString, "quality": 1]]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = makeRequest(method: "POST", path: "/v1/reviews", headers: authHeaders(), body: body)
        let resp = router.handle(req)
        let json = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        let rejected = json?["rejected"] as? [[String: Any]]
        #expect(rejected?.count == 1)
    }

    @Test("Malformed JSON returns 400")
    func malformedJSON400() throws {
        let container = try makeContainer()
        let router = BridgeRouter(container: container)
        let body = Data("not json".utf8)
        let req = makeRequest(method: "POST", path: "/v1/cards", headers: authHeaders(), body: body)
        let resp = router.handle(req)
        #expect(resp.statusCode == 400)
    }

    @Test("Unknown route returns 404")
    func unknownRoute404() throws {
        let container = try makeContainer()
        let router = BridgeRouter(container: container)
        let req = makeRequest(method: "GET", path: "/v1/unknown", headers: authHeaders())
        let resp = router.handle(req)
        #expect(resp.statusCode == 404)
    }

    @Test("Snapshot returns datasets")
    func snapshotReturnsDatasets() throws {
        let container = try makeContainer()
        let router = BridgeRouter(container: container)
        let req = makeRequest(method: "GET", path: "/v1/snapshot", headers: authHeaders())
        let resp = router.handle(req)
        #expect(resp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        #expect(json?["version"] as? Int == 1)
        let datasets = json?["datasets"] as? [String: Any]
        #expect(datasets != nil)
    }

    @Test("Import snapshot is idempotent and not destructive")
    func importSnapshotIdempotent() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        ctx.insert(subject)
        try ctx.save()

        let router = BridgeRouter(container: container)
        let snapshot: [String: Any] = [
            "version": 1,
            "datasets": [
                "subjects": [["name": "Chemistry", "level": "SL"]],
                "cards": []
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: snapshot)
        let req = makeRequest(method: "POST", path: "/v1/import/snapshot", headers: authHeaders(), body: body)
        let resp1 = router.handle(req)
        #expect(resp1.statusCode == 200)
        let resp2 = router.handle(req)
        #expect(resp2.statusCode == 200)
        // Verify both Biology and Chemistry exist (not wiped)
        let ctx2 = ModelContext(container)
        let subjects = try ctx2.fetch(FetchDescriptor<Subject>())
        #expect(subjects.map(\.name).contains("Biology"))
        #expect(subjects.map(\.name).contains("Chemistry"))
    }

    @Test("A retried review upload is acknowledged but not applied or paid twice")
    func duplicateReviewUpload() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let profile = UserProfile()
        ctx.insert(profile)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        ctx.insert(subject)
        let card = StudyCard(topicName: "Cells", front: "Q", back: "A", subject: subject)
        ctx.insert(card)
        try ctx.save()

        let router = BridgeRouter(container: container)
        let review: [String: Any] = ["cardID": card.id.uuidString, "quality": 3, "timestamp": "2026-01-02T10:00:00Z"]
        let body = try JSONSerialization.data(withJSONObject: ["reviews": [review, review]])
        func upload() throws -> [[String: Any]] {
            let response = router.handle(makeRequest(method: "POST", path: "/v1/reviews", headers: authHeaders(), body: body))
            #expect(response.statusCode == 200)
            let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
            return json?["accepted"] as? [[String: Any]] ?? []
        }
        #expect(try upload().count == 2)
        let paid = try ModelContext(container).fetch(FetchDescriptor<UserProfile>()).first?.totalXP ?? 0
        #expect(paid > 0)

        let retried = try upload()
        #expect(retried.allSatisfy { $0["duplicate"] as? Bool == true })

        let check = ModelContext(container)
        #expect(try check.fetch(FetchDescriptor<ReviewSession>()).count == 1)
        #expect(try check.fetch(FetchDescriptor<StudyCard>()).first?.totalReviewCount == 1)
        #expect(try check.fetch(FetchDescriptor<UserProfile>()).first?.totalXP == paid)
    }

    @Test("A retried session upload returns the first copy")
    func duplicateSessionUpload() throws {
        let container = try makeContainer()
        let router = BridgeRouter(container: container)
        let session: [String: Any] = ["subjectName": "Biology", "startDate": "2026-01-02T10:00:00Z", "endDate": "2026-01-02T10:30:00Z",
                                      "cardsReviewed": 3, "correctCount": 2]
        let body = try JSONSerialization.data(withJSONObject: ["sessions": [session]])
        func upload() throws -> String? {
            let response = router.handle(makeRequest(method: "POST", path: "/v1/sessions", headers: authHeaders(), body: body))
            let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
            return (json?["accepted"] as? [[String: String]])?.first?["id"]
        }
        let first = try upload()
        #expect(first != nil)
        #expect(try upload() == first)
        #expect(try ModelContext(container).fetch(FetchDescriptor<StudySession>()).count == 1)
    }

    @Test("Bridge reviews respect an enforced daily limit, except backdated imports")
    func bridgeDailyLimit() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let profile = UserProfile()
        profile.dailyGoal = 1
        ctx.insert(profile)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        ctx.insert(subject)
        let first = StudyCard(topicName: "Cells", front: "First", back: "A", subject: subject)
        let second = StudyCard(topicName: "Cells", front: "Second", back: "A", subject: subject)
        ctx.insert(first)
        ctx.insert(second)
        try ctx.save()

        let router = BridgeRouter(container: container)
        let reviews: [[String: Any]] = [
            ["cardID": first.id.uuidString, "quality": 3],
            ["cardID": second.id.uuidString, "quality": 3],
            ["cardID": second.id.uuidString, "quality": 3, "timestamp": "2026-01-02T10:00:00Z"]
        ]
        let body = try JSONSerialization.data(withJSONObject: ["reviews": reviews])
        let response = ReviewDailyLimitPolicy.$enforcementOverride.withValue(true) {
            router.handle(makeRequest(method: "POST", path: "/v1/reviews", headers: authHeaders(), body: body))
        }
        let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        #expect((json?["accepted"] as? [[String: Any]])?.count == 2)
        let rejected = json?["rejected"] as? [[String: Any]]
        #expect(rejected?.count == 1)
        #expect(rejected?.first?["reason"] as? String == "daily limit reached")
    }

    @Test("Stopping the bridge during startup closes the listener and stays stopped")
    @MainActor
    func stopDuringStartup() async throws {
        let wasEnabled = BridgeAuthService.isEnabled
        let savedPort = UserDefaults.standard.object(forKey: "BridgeActualPort")
        defer {
            BridgeAuthService.isEnabled = wasEnabled
            UserDefaults.standard.set(savedPort, forKey: "BridgeActualPort")
        }
        BridgeAuthService.isEnabled = true
        let controller = IntegrationBridgeController(container: try makeContainer())

        controller.start()
        controller.stop()
        // Long enough for the abandoned start to bind and be closed.
        try await Task.sleep(for: .milliseconds(400))
        guard case .stopped = controller.state else {
            Issue.record("Expected stopped, got \(controller.state)")
            return
        }

        // A later start is not blocked by the abandoned one.
        controller.start()
        for _ in 0..<40 {
            if case .running = controller.state { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard case .running = controller.state else {
            Issue.record("Expected running, got \(controller.state)")
            return
        }
        controller.stop()
    }
}
