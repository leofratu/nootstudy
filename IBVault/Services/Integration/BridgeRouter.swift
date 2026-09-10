import Foundation
import SwiftData

/// Router implementing EXACTLY the v1 API contract. All routes except /v1/health require Authorization Bearer.
/// Errors use {"error":{"code","message"}} with 400/401/404/405/500.
/// The router is a pure function `(BridgeRequest) -> BridgeResponse` for testability — provide a ModelContainer at init.
nonisolated struct BridgeRouter: Sendable {
    let container: ModelContainer

    // Pure function entry point for tests: synchronous.
    nonisolated func handle(_ request: BridgeRequest) -> BridgeResponse {
        // Check health auth exemption first
        let isHealth = request.path == "/v1/health" && request.method.uppercased() == "GET"
        if !isHealth {
            guard isAuthorized(request) else {
                return .error(code: "unauthorized", message: "Missing or invalid Authorization header.", status: 401)
            }
        }
        // Route
        let method = request.method.uppercased()
        let path = request.path

        switch (method, path) {
        case ("GET", "/v1/health"):
            return handleHealth()
        case ("GET", "/v1/snapshot"):
            return handleSnapshot(request)
        case ("GET", "/v1/cards"):
            return handleGetCards(request)
        case ("POST", "/v1/cards"):
            return handlePostCards(request)
        case ("POST", "/v1/reviews"):
            return handlePostReviews(request)
        case ("GET", "/v1/sessions"):
            return handleGetSessions(request)
        case ("POST", "/v1/sessions"):
            return handlePostSessions(request)
        case ("GET", "/v1/subjects"):
            return handleGetSubjects()
        case ("GET", "/v1/progress"):
            return handleGetProgress()
        case ("GET", "/v1/plans"):
            return handleGetPlans(request)
        case ("POST", "/v1/plans"):
            return handlePostPlans(request)
        case ("GET", "/v1/memories"):
            return handleGetMemories(request)
        case ("POST", "/v1/memories"):
            return handlePostMemories(request)
        case ("POST", "/v1/activity"):
            return handlePostActivity(request)
        case ("GET", "/v1/activity"):
            return handleGetActivity(request)
        case ("POST", "/v1/activity/merge"):
            return handlePostActivityMerge(request)
        case ("GET", "/v1/notebook/export"):
            return handleNotebookExport(request)
        case ("POST", "/v1/notebook/import"):
            return handleNotebookImport(request)
        case ("POST", "/v1/import/snapshot"):
            return handleImportSnapshot(request)
        default:
            if isKnownPathButWrongMethod(path: path, method: method) {
                return .error(code: "method_not_allowed", message: "Method not allowed.", status: 405)
            }
            // Check for unknown route under /v1
            if path.hasPrefix("/v1/") {
                return .error(code: "not_found", message: "Route not found.", status: 404)
            }
            return .error(code: "not_found", message: "Route not found.", status: 404)
        }
    }

    // Async variant that hops to MainActor for engine calls (used by LocalBridgeServer)
    func handleAsync(_ request: BridgeRequest) async -> BridgeResponse {
        // For now, delegate to sync handle; reviews need MainActor hop handled inside.
        // To allow MainActor engine calls, run the sync handle's review path on MainActor if needed.
        // Since handle is sync and reviews hop via DispatchQueue.main.sync internally, async is not needed.
        // But we provide it for future engine integration.
        handle(request)
    }

    // MARK: - Auth

    private func isAuthorized(_ request: BridgeRequest) -> Bool {
        guard let auth = request.headers["authorization"] ?? request.headers["Authorization"] else { return false }
        return BridgeAuthService.isValidBearer(auth)
    }

    // MARK: - Handlers

    private func handleHealth() -> BridgeResponse {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
        return .json(["ok": true, "app": "Noot Study", "version": version, "apiVersion": 1, "authRequired": true], status: 200)
    }

    private func handleSnapshot(_ request: BridgeRequest) -> BridgeResponse {
        let context = ModelContext(container)
        let sinceStr = request.queryItems["since"]
        let sinceDate: Date? = sinceStr.flatMap { ISO8601DateFormatter().date(from: $0) }

        // Helper to filter by created/updated
        func isAfterSince(_ date: Date) -> Bool {
            guard let sinceDate else { return true }
            return date >= sinceDate
        }

        let subjects = ((try? context.fetch(FetchDescriptor<Subject>())) ?? []).filter { _ in true }
        let subjectDTOs = subjects.map { subject in
            let mastery = subject.masteryProgress
            return BridgeDTOFactory.subjectDTO(from: subject, mastery: mastery)
        }
        let cards = ((try? context.fetch(FetchDescriptor<StudyCard>())) ?? []).filter { isAfterSince($0.createdDate) }
        let cardDTOs = cards.map(BridgeDTOFactory.cardDTO)
        let reviews = ((try? context.fetch(FetchDescriptor<ReviewSession>())) ?? []).filter { isAfterSince($0.timestamp) }
        let reviewDTOs = reviews.map(BridgeDTOFactory.reviewDTO)
        let sessions = ((try? context.fetch(FetchDescriptor<StudySession>())) ?? []).filter { isAfterSince($0.startDate) }
        let sessionDTOs = sessions.map(BridgeDTOFactory.sessionDTO)
        let grades = ((try? context.fetch(FetchDescriptor<Grade>())) ?? []).filter { isAfterSince($0.date) }
        let gradeDTOs = grades.map(BridgeDTOFactory.gradeDTO)
        let plans = ((try? context.fetch(FetchDescriptor<StudyPlan>())) ?? []).filter { isAfterSince($0.createdDate) }
        let planDTOs = plans.map(BridgeDTOFactory.planDTO)
        let activities = ((try? context.fetch(FetchDescriptor<ExternalActivity>())) ?? []).filter { isAfterSince($0.importedAt) }
        let activityDTOs = activities.map { act in
            ActivityDTO(
                id: act.id,
                externalID: act.externalID,
                source: act.source,
                kind: act.kindRaw,
                subjectName: act.subjectName,
                topicName: act.topicName,
                minutes: act.minutes,
                cardsReviewed: act.cardsReviewed,
                correctCount: act.correctCount,
                occurredAt: act.occurredAt,
                details: act.details,
                status: act.statusRaw,
                importedAt: act.importedAt,
                mergedStudySessionID: act.mergedStudySessionID
            )
        }

        let payload: [String: Any] = [
            "version": 1,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "datasets": [
                "subjects": subjectDTOs.map(dtoToDict),
                "cards": cardDTOs.map(dtoToDict),
                "reviewSessions": reviewDTOs.map(dtoToDict),
                "studySessions": sessionDTOs.map(dtoToDict),
                "grades": gradeDTOs.map(dtoToDict),
                "studyPlans": planDTOs.map(dtoToDict),
                "activity": activityDTOs.map(dtoToDict)
            ]
        ]
        return .json(payload, status: 200)
    }

    private func handleGetCards(_ request: BridgeRequest) -> BridgeResponse {
        let context = ModelContext(container)
        let subjectFilter = request.queryItems["subject"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryFilter = request.queryItems["query"]?.lowercased()
        let dueOnly = request.queryItems["dueOnly"]?.lowercased() == "true"
        let limit = min(max(Int(request.queryItems["limit"] ?? "50") ?? 50, 1), 500)
        let offset = max(Int(request.queryItems["offset"] ?? "0") ?? 0, 0)

        var cards = (try? context.fetch(FetchDescriptor<StudyCard>())) ?? []
        // Sort by createdDate for determinism
        cards.sort { $0.createdDate < $1.createdDate }
        if let subjectFilter, !subjectFilter.isEmpty {
            cards = cards.filter { $0.subject?.name == subjectFilter }
        }
        if let queryFilter, !queryFilter.isEmpty {
            cards = cards.filter { $0.front.lowercased().contains(queryFilter) || $0.back.lowercased().contains(queryFilter) }
        }
        if dueOnly {
            let now = Date()
            cards = cards.filter { $0.nextReviewDate <= now }
        }
        let total = cards.count
        let sliced = Array(cards.dropFirst(offset).prefix(limit))
        let dtos = sliced.map(BridgeDTOFactory.cardDTO)
        let payload: [String: Any] = [
            "cards": dtos.map(dtoToDict),
            "total": total
        ]
        return .json(payload, status: 200)
    }

    private func handlePostCards(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable { let cards: [IncomingCard] }
        struct IncomingCard: Decodable {
            let subjectName: String
            let topicName: String
            let subtopic: String?
            let front: String
            let back: String
            let hint: String?
            let difficulty: String?
            let cognitiveSkill: String?
            let cardStyle: String?
            let choices: [String]?
            let source: String?
        }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let context = ModelContext(container)
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let subjectsByName = Dictionary(uniqueKeysWithValues: subjects.map { ($0.name, $0) })
        let existingCards = (try? context.fetch(FetchDescriptor<StudyCard>())) ?? []
        var seenNormalized = Set(existingCards.map { normalizedKey($0.front) })

        var createdDTOs: [[String: Any]] = []
        var skipped: [[String: String]] = []

        for incoming in payload.cards {
            let trimmedSubject = incoming.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let subject = subjectsByName[trimmedSubject] else {
                skipped.append(["front": incoming.front, "reason": "subject not found: \(trimmedSubject)"])
                continue
            }
            let front = incoming.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = incoming.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else {
                skipped.append(["front": incoming.front, "reason": "front/back empty"])
                continue
            }
            let normalized = normalizedKey(front)
            if seenNormalized.contains(normalized) {
                skipped.append(["front": incoming.front, "reason": "duplicate front"])
                continue
            }
            // Validate cardStyle/choices like CardGeneratorService
            let rawStyle = incoming.cardStyle
            let style = parsedCardStyle(rawStyle) ?? .basic
            var finalStyle = style
            var finalChoices: [String] = []
            switch style {
            case .basic:
                finalChoices = []
            case .cloze:
                if !CardGeneratorService.isValidCloze(front: front, back: back) {
                    finalStyle = .basic
                }
            case .multipleChoice:
                if let validated = CardGeneratorService.validatedChoices(back: back, choices: incoming.choices) {
                    finalChoices = validated
                } else {
                    finalStyle = .basic
                }
            }
            let difficulty = incoming.difficulty.flatMap { CardDifficulty(rawValue: $0) } ?? .standard
            let skill = incoming.cognitiveSkill.flatMap { CardCognitiveSkill(rawValue: $0) } ?? .recall
            let card = StudyCard(
                topicName: incoming.topicName,
                subtopic: incoming.subtopic ?? "",
                front: front,
                back: back,
                subject: subject,
                isCustom: true,
                isAIGenerated: false,
                generationSource: incoming.source ?? "bridge",
                hint: incoming.hint,
                difficulty: difficulty,
                cognitiveSkill: skill,
                cardStyle: finalStyle,
                choices: finalChoices
            )
            context.insert(card)
            seenNormalized.insert(normalized)
            createdDTOs.append(dtoToDict(BridgeDTOFactory.cardDTO(from: card)))
        }
        if !createdDTOs.isEmpty {
            try? context.save()
        }
        let payloadOut: [String: Any] = ["created": createdDTOs, "skipped": skipped]
        return .json(payloadOut, status: 200)
    }

    private func handlePostReviews(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable { let reviews: [IncomingReview] }
        struct IncomingReview: Decodable {
            let cardID: UUID
            let quality: Int
            let timestamp: Date?
            let durationSeconds: Double?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let context = ModelContext(container)
        let allowedQualities: Set<Int> = [0, 2, 3, 5]
        var accepted: [[String: Any]] = []
        var rejected: [[String: Any]] = []

        for incoming in payload.reviews {
            guard allowedQualities.contains(incoming.quality) else {
                rejected.append(["cardID": incoming.cardID.uuidString, "reason": "invalid quality \(incoming.quality)"])
                continue
            }
            // Fetch card
            let cardID = incoming.cardID
            let descriptor = FetchDescriptor<StudyCard>(predicate: #Predicate { $0.id == cardID })
            guard let card = (try? context.fetch(descriptor))?.first else {
                rejected.append(["cardID": incoming.cardID.uuidString, "reason": "card not found"])
                continue
            }
            let quality: RecallQuality = switch incoming.quality {
            case 0: .again
            case 2: .hard
            case 3: .good
            case 5: .easy
            default: .good
            }
            let now = incoming.timestamp ?? Date()
            let duration = incoming.durationSeconds ?? 0
            // Apply through FSRSScheduler via nonisolated sync helper (no MainActor hop required for bridge scratch context)
            let applyResult: Result<Void, any Error> = Result { try FSRSScheduler.applyReviewSync(to: card, quality: quality, now: now) }
            switch applyResult {
            case .success:
                let session = ReviewSession(cardID: card.id, subjectName: card.subject?.name ?? "", topicName: card.topicName, qualityRating: incoming.quality, sessionDuration: duration)
                session.timestamp = now
                FSRSScheduler.configureSync(session, quality: quality)
                context.insert(session)
                accepted.append(["cardID": card.id.uuidString, "nextReviewDate": ISO8601DateFormatter().string(from: card.nextReviewDate)])
            case .failure(let error):
                rejected.append(["cardID": incoming.cardID.uuidString, "reason": error.localizedDescription])
            }
        }
        if !accepted.isEmpty {
            try? context.save()
            // Recompute progression on MainActor (best effort, non-blocking)
            if !accepted.isEmpty {
                let containerCopy = container
                Task { @MainActor in
                    let ctx = ModelContext(containerCopy)
                    _ = ProgressionService.recompute(context: ctx)
                }
            }
        }
        let out: [String: Any] = ["accepted": accepted, "rejected": rejected]
        return .json(out, status: 200)
    }

    private func handleGetSessions(_ request: BridgeRequest) -> BridgeResponse {
        let context = ModelContext(container)
        let limit = min(max(Int(request.queryItems["limit"] ?? "50") ?? 50, 1), 500)
        var sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        sessions.sort { $0.startDate > $1.startDate }
        sessions = Array(sessions.prefix(limit))
        let dtos = sessions.map(BridgeDTOFactory.sessionDTO)
        return .json(["sessions": dtos.map(dtoToDict)], status: 200)
    }

    private func handlePostSessions(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable { let sessions: [IncomingSession] }
        struct IncomingSession: Decodable {
            let subjectName: String
            let topicsCovered: String?
            let subtopicsCovered: String?
            let startDate: Date
            let endDate: Date
            let cardsReviewed: Int
            let correctCount: Int
            let notes: String?
            // Also support array forms
            let topicsCoveredArray: [String]?
            enum CodingKeys: String, CodingKey {
                case subjectName, topicsCovered, subtopicsCovered, startDate, endDate, cardsReviewed, correctCount, notes
                case topicsCoveredArray
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let context = ModelContext(container)
        var accepted: [[String: String]] = []
        for incoming in payload.sessions {
            let topics: String
            if let arr = incoming.topicsCoveredArray, !arr.isEmpty {
                topics = arr.joined(separator: ",")
            } else {
                topics = incoming.topicsCovered ?? ""
            }
            let subtopics = incoming.subtopicsCovered ?? ""
            let session = StudySession(
                subjectName: incoming.subjectName,
                topicsCovered: topics,
                subtopicsCovered: subtopics,
                startDate: incoming.startDate,
                endDate: incoming.endDate,
                cardsReviewed: incoming.cardsReviewed,
                correctCount: incoming.correctCount,
                xpEarned: max(incoming.cardsReviewed * 2, 0),
                notes: incoming.notes ?? ""
            )
            context.insert(session)
            accepted.append(["id": session.id.uuidString])
        }
        if !accepted.isEmpty { try? context.save() }
        return .json(["accepted": accepted], status: 200)
    }

    private func handleGetSubjects() -> BridgeResponse {
        let context = ModelContext(container)
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let dtos = subjects.map { BridgeDTOFactory.subjectDTO(from: $0, mastery: $0.masteryProgress) }
        return .json(["subjects": dtos.map(dtoToDict)], status: 200)
    }

    private func handleGetProgress() -> BridgeResponse {
        let context = ModelContext(container)
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let profile = profiles.first
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let reviews = (try? context.fetch(FetchDescriptor<ReviewSession>())) ?? []
        let totalXP = profile?.totalXP ?? 0
        let streak = profile?.currentStreak ?? 0
        let longest = profile?.longestStreak ?? 0
        // Compute mastery as global blended
        let snapshots = SnapshotBuilder.snapshots(for: subjects, reviews: reviews)
        let now = Date()
        let globalMastery: Double = {
            guard !snapshots.isEmpty else { return 0 }
            return snapshots.reduce(0) { $0 + MasteryCalculator.mastery(for: $1, now: now) } / Double(snapshots.count)
        }()
        let rank = profile?.achievedStep.rank.displayName ?? Rank.electron.displayName
        let tier = profile?.achievedStep.tier.rawValue ?? 3
        let achievements = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []
        let achDTOs = achievements.map { AchievementDTO(id: $0.id, title: $0.title, unlocked: $0.unlocked) }
        let payload: [String: Any] = [
            "xp": totalXP,
            "rank": rank,
            "tier": tier,
            "mastery": globalMastery,
            "streak": streak,
            "longestStreak": longest,
            "achievements": achDTOs.map(dtoToDict)
        ]
        return .json(payload, status: 200)
    }

    private func handleGetPlans(_ request: BridgeRequest) -> BridgeResponse {
        let context = ModelContext(container)
        var plans = (try? context.fetch(FetchDescriptor<StudyPlan>())) ?? []
        let fromStr = request.queryItems["from"]
        let toStr = request.queryItems["to"]
        let formatter = ISO8601DateFormatter()
        if let fromStr, let fromDate = formatter.date(from: fromStr) {
            plans = plans.filter { $0.scheduledDate >= fromDate }
        }
        if let toStr, let toDate = formatter.date(from: toStr) {
            plans = plans.filter { $0.scheduledDate <= toDate }
        }
        plans.sort { $0.scheduledDate < $1.scheduledDate }
        let dtos = plans.map(BridgeDTOFactory.planDTO)
        return .json(["plans": dtos.map(dtoToDict)], status: 200)
    }

    private func handlePostPlans(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable {
            let subjectName: String
            let topicNames: [String]
            let scheduledDate: Date
            let durationMinutes: Int
            let notes: String?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let context = ModelContext(container)
        let plan = StudyPlan(
            subjectName: payload.subjectName,
            topicName: payload.topicNames.joined(separator: ","),
            planMarkdown: "",
            scheduledDate: payload.scheduledDate,
            durationMinutes: payload.durationMinutes,
            notes: payload.notes ?? ""
        )
        context.insert(plan)
        try? context.save()
        return .json(["id": plan.id.uuidString], status: 200)
    }

    private func handleGetMemories(_ request: BridgeRequest) -> BridgeResponse {
        let context = ModelContext(container)
        var memories = (try? context.fetch(FetchDescriptor<ARIAMemory>())) ?? []
        if let query = request.queryItems["query"]?.lowercased(), !query.isEmpty {
            memories = memories.filter { $0.content.lowercased().contains(query) }
        }
        let limit = min(max(Int(request.queryItems["limit"] ?? "50") ?? 50, 1), 500)
        memories.sort { $0.timestamp > $1.timestamp }
        memories = Array(memories.prefix(limit))
        let dtos = memories.map(BridgeDTOFactory.memoryDTO)
        return .json(["memories": dtos.map(dtoToDict)], status: 200)
    }

    private func handlePostMemories(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable {
            let content: String
            let category: String?
            let subjectName: String?
        }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let trimmed = payload.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .error(code: "bad_request", message: "content empty", status: 400)
        }
        let context = ModelContext(container)
        let category = payload.category.flatMap { MemoryCategory(rawValue: $0) } ?? .userNotes
        let memory = ARIAMemory(category: category, content: trimmed, subjectName: payload.subjectName)
        context.insert(memory)
        try? context.save()
        return .json(["id": memory.id.uuidString], status: 200)
    }

    private func handlePostActivity(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable { let activities: [ExternalActivityImportDTO] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let context = ModelContext(container)
        let result = ExternalActivityService.importActivities(payload.activities, context: context)
        return .json(["accepted": result.accepted, "duplicates": result.duplicates], status: 200)
    }

    private func handleGetActivity(_ request: BridgeRequest) -> BridgeResponse {
        let context = ModelContext(container)
        let status = request.queryItems["status"]?.lowercased() ?? "pending"
        let activities: [ExternalActivity]
        if status == "all" {
            activities = ExternalActivityService.listAll(context: context)
        } else {
            activities = ExternalActivityService.listPending(context: context)
        }
        let dtos = activities.map { act in
            ActivityDTO(
                id: act.id,
                externalID: act.externalID,
                source: act.source,
                kind: act.kindRaw,
                subjectName: act.subjectName,
                topicName: act.topicName,
                minutes: act.minutes,
                cardsReviewed: act.cardsReviewed,
                correctCount: act.correctCount,
                occurredAt: act.occurredAt,
                details: act.details,
                status: act.statusRaw,
                importedAt: act.importedAt,
                mergedStudySessionID: act.mergedStudySessionID
            )
        }
        return .json(["activities": dtos.map(dtoToDict)], status: 200)
    }

    private func handlePostActivityMerge(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable { let ids: [UUID] }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let context = ModelContext(container)
        let results = ExternalActivityService.merge(ids: payload.ids, context: context)
        let out = results.map { ["id": $0.id.uuidString, "studySessionID": $0.studySessionID.uuidString] }
        return .json(["merged": out], status: 200)
    }

    private func handleNotebookExport(_ request: BridgeRequest) -> BridgeResponse {
        guard let subject = request.queryItems["subject"], !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error(code: "bad_request", message: "subject query required", status: 400)
        }
        let topic = request.queryItems["topic"]
        guard let pack = NotebookPackService.export(subjectName: subject, topicName: topic, container: container) else {
            return .error(code: "not_found", message: "subject not found", status: 404)
        }
        let payload: [String: Any] = [
            "subject": pack.subject,
            "markdown": pack.markdown,
            "cards": pack.cards.map(dtoToDict),
            "generatedAt": ISO8601DateFormatter().string(from: pack.generatedAt)
        ]
        return .json(payload, status: 200)
    }

    private func handleNotebookImport(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        struct Payload: Decodable {
            let title: String
            let markdown: String
            let saveDrafts: Bool?
        }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: body) else {
            return .error(code: "bad_request", message: "Malformed JSON.", status: 400)
        }
        let result = NotebookPackService.import(title: payload.title, markdown: payload.markdown, saveDrafts: payload.saveDrafts ?? false, container: container)
        let payloadOut: [String: Any] = [
            "memoryID": result.memoryID.uuidString,
            "draftCards": result.draftCards.map { ["front": $0.front, "back": $0.back, "cardStyle": $0.cardStyle ?? "basic", "topicName": $0.topicName ?? ""] }
        ]
        return .json(payloadOut, status: 200)
    }

    private func handleImportSnapshot(_ request: BridgeRequest) -> BridgeResponse {
        guard let body = request.body, !body.isEmpty else {
            return .error(code: "bad_request", message: "Missing body.", status: 400)
        }
        // Snapshot format: {"version":1,"datasets":{"subjects":[...],"cards":[...],...}}
        // Use lenient decoding: try to decode as generic JSON and merge by UUID deterministically.
        // Never destructive (no wipe).
        struct Snapshot: Decodable {
            let version: Int
            let datasets: Datasets?
            struct Datasets: Decodable {
                let subjects: [SubjectSnapshot]?
                let cards: [CardSnapshot]?
                let reviewSessions: [ReviewSnapshot]?
                let studySessions: [StudySessionSnapshot]?
                let grades: [GradeSnapshot]?
                let studyPlans: [PlanSnapshot]?
                let activity: [ActivitySnapshot]?
            }
            struct SubjectSnapshot: Decodable { let name: String; let level: String; let accentColorHex: String?; let examDate: Date? }
            struct CardSnapshot: Decodable { let id: UUID; let topicName: String; let subtopic: String?; let front: String; let back: String; let subjectName: String?; let hint: String?; let difficulty: String?; let cognitiveSkill: String?; let cardStyle: String?; let choices: [String]?; let proficiency: String?; let nextReviewDate: Date?; let createdDate: Date? }
            struct ReviewSnapshot: Decodable { let id: UUID; let cardID: UUID; let subjectName: String; let topicName: String; let quality: Int?; let qualityRating: Int?; let timestamp: Date?; let durationSeconds: Double?; let sessionDuration: Double? }
            struct StudySessionSnapshot: Decodable { let id: UUID; let subjectName: String; let topicsCovered: String?; let topicsCoveredArray: [String]?; let startDate: Date?; let endDate: Date?; let cardsReviewed: Int?; let correctCount: Int? }
            struct GradeSnapshot: Decodable { let id: UUID; let subjectName: String?; let component: String; let score: Int; let predictedGrade: Int?; let date: Date?; let assessmentTitle: String?; let teacherFeedback: String? }
            struct PlanSnapshot: Decodable { let id: UUID; let subjectName: String; let topicName: String?; let topicNames: [String]?; let scheduledDate: Date?; let durationMinutes: Int? }
            struct ActivitySnapshot: Decodable { let id: UUID?; let externalID: String; let source: String; let kind: String; let subjectName: String?; let topicName: String?; let minutes: Double?; let cardsReviewed: Int?; let correctCount: Int?; let occurredAt: Date? }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: body), snapshot.version == 1 else {
            return .error(code: "bad_request", message: "Invalid snapshot version or malformed JSON.", status: 400)
        }
        let context = ModelContext(container)
        var applied: [String: Int] = [:]
        // Merge subjects by name (idempotent)
        if let subjects = snapshot.datasets?.subjects {
            let existing = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
            let existingNames = Set(existing.map(\.name))
            var count = 0
            for s in subjects where !existingNames.contains(s.name) {
                let subject = Subject(name: s.name, level: s.level, accentColorHex: s.accentColorHex ?? "3B82F6", examDate: s.examDate)
                context.insert(subject)
                count += 1
            }
            if count > 0 { applied["subjects"] = count }
        }
        // Merge cards by UUID
        if let cards = snapshot.datasets?.cards {
            let existing = Set(((try? context.fetch(FetchDescriptor<StudyCard>())) ?? []).map(\.id))
            let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
            let byName = Dictionary(uniqueKeysWithValues: subjects.map { ($0.name, $0) })
            var count = 0
            for c in cards where !existing.contains(c.id) {
                let subject = c.subjectName.flatMap { byName[$0] }
                let card = StudyCard(
                    topicName: c.topicName,
                    subtopic: c.subtopic ?? "",
                    front: c.front,
                    back: c.back,
                    subject: subject,
                    isCustom: true,
                    isAIGenerated: false,
                    hint: c.hint,
                    difficulty: c.difficulty.flatMap { CardDifficulty(rawValue: $0) } ?? .standard,
                    cognitiveSkill: c.cognitiveSkill.flatMap { CardCognitiveSkill(rawValue: $0) } ?? .recall,
                    cardStyle: c.cardStyle.flatMap { CardStyle(rawValue: $0) } ?? .basic,
                    choices: c.choices ?? []
                )
                card.id = c.id
                if let d = c.nextReviewDate { card.nextReviewDate = d }
                if let d = c.createdDate { card.createdDate = d }
                if let p = c.proficiency { card.proficiencyRaw = p }
                context.insert(card)
                count += 1
            }
            if count > 0 { applied["cards"] = count }
        }
        // Merge review sessions
        if let reviews = snapshot.datasets?.reviewSessions {
            let existing = Set(((try? context.fetch(FetchDescriptor<ReviewSession>())) ?? []).map(\.id))
            var count = 0
            for r in reviews where !existing.contains(r.id) {
                let quality = r.quality ?? r.qualityRating ?? 3
                let session = ReviewSession(cardID: r.cardID, subjectName: r.subjectName, topicName: r.topicName, qualityRating: quality, sessionDuration: r.durationSeconds ?? r.sessionDuration ?? 0)
                session.id = r.id
                if let t = r.timestamp { session.timestamp = t }
                context.insert(session)
                count += 1
            }
            if count > 0 { applied["reviewSessions"] = count }
        }
        // Merge study sessions
        if let sessions = snapshot.datasets?.studySessions {
            let existing = Set(((try? context.fetch(FetchDescriptor<StudySession>())) ?? []).map(\.id))
            var count = 0
            for s in sessions where !existing.contains(s.id) {
                let topics: String
                if let arr = s.topicsCoveredArray { topics = arr.joined(separator: ",") } else { topics = s.topicsCovered ?? "" }
                let session = StudySession(
                    id: s.id,
                    subjectName: s.subjectName,
                    topicsCovered: topics,
                    startDate: s.startDate ?? Date(),
                    endDate: s.endDate ?? Date(),
                    cardsReviewed: s.cardsReviewed ?? 0,
                    correctCount: s.correctCount ?? 0,
                    xpEarned: 0
                )
                context.insert(session)
                count += 1
            }
            if count > 0 { applied["studySessions"] = count }
        }
        // Merge grades
        if let grades = snapshot.datasets?.grades {
            let existing = Set(((try? context.fetch(FetchDescriptor<Grade>())) ?? []).map(\.id))
            let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
            let byName = Dictionary(uniqueKeysWithValues: subjects.map { ($0.name, $0) })
            var count = 0
            for g in grades where !existing.contains(g.id) {
                let grade = Grade(component: g.component, score: g.score, predictedGrade: g.predictedGrade, teacherFeedback: g.teacherFeedback ?? "", assessmentTitle: g.assessmentTitle ?? "", subject: g.subjectName.flatMap { byName[$0] })
                grade.id = g.id
                if let d = g.date { grade.date = d }
                context.insert(grade)
                count += 1
            }
            if count > 0 { applied["grades"] = count }
        }
        // Merge plans
        if let plans = snapshot.datasets?.studyPlans {
            let existing = Set(((try? context.fetch(FetchDescriptor<StudyPlan>())) ?? []).map(\.id))
            var count = 0
            for p in plans where !existing.contains(p.id) {
                let topic = p.topicName ?? p.topicNames?.joined(separator: ",") ?? ""
                let plan = StudyPlan(subjectName: p.subjectName, topicName: topic, scheduledDate: p.scheduledDate ?? Date(), durationMinutes: p.durationMinutes ?? 30)
                plan.id = p.id
                context.insert(plan)
                count += 1
            }
            if count > 0 { applied["studyPlans"] = count }
        }
        // Merge activity
        if let acts = snapshot.datasets?.activity {
            let existing = Set(((try? context.fetch(FetchDescriptor<ExternalActivity>())) ?? []).map { "\($0.source)|\($0.externalID)" })
            var count = 0
            for a in acts {
                let key = "\(a.source)|\(a.externalID)"
                if existing.contains(key) { continue }
                let activity = ExternalActivity(
                    id: a.id ?? UUID(),
                    externalID: a.externalID,
                    source: a.source,
                    kindRaw: a.kind,
                    subjectName: a.subjectName,
                    topicName: a.topicName,
                    minutes: a.minutes ?? 0,
                    cardsReviewed: a.cardsReviewed ?? 0,
                    correctCount: a.correctCount ?? 0,
                    occurredAt: a.occurredAt ?? Date()
                )
                context.insert(activity)
                count += 1
            }
            if count > 0 { applied["activity"] = count }
        }
        if !applied.isEmpty { try? context.save() }
        return .json(["applied": applied], status: 200)
    }

    private func isKnownPathButWrongMethod(path: String, method: String) -> Bool {
        let known: [String: Set<String>] = [
            "/v1/health": ["GET"],
            "/v1/snapshot": ["GET"],
            "/v1/cards": ["GET", "POST"],
            "/v1/reviews": ["POST"],
            "/v1/sessions": ["GET", "POST"],
            "/v1/subjects": ["GET"],
            "/v1/progress": ["GET"],
            "/v1/plans": ["GET", "POST"],
            "/v1/memories": ["GET", "POST"],
            "/v1/activity": ["GET", "POST"],
            "/v1/activity/merge": ["POST"],
            "/v1/notebook/export": ["GET"],
            "/v1/notebook/import": ["POST"],
            "/v1/import/snapshot": ["POST"]
        ]
        guard let allowed = known[path] else { return false }
        return !allowed.contains(method)
    }

    // MARK: - Helpers

    private func dtoToDict<T: Encodable>(_ dto: T) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(dto),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private func normalizedKey(_ front: String) -> String {
        front.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func parsedCardStyle(_ raw: String?) -> CardStyle? {
        guard let raw else { return nil }
        let lower = raw.lowercased()
        if lower == "multiplechoice" || lower == "multiple_choice" || lower == "multiple-choice" { return .multipleChoice }
        return CardStyle.allCases.first { $0.rawValue.lowercased() == lower }
    }


}
