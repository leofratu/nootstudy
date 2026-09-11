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
}
