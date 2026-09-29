import SwiftUI
import SwiftData

struct ExamMarkerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @State private var subjectID: UUID?
    @State private var question = ""
    @State private var answer = ""
    @State private var scheme = ""
    @State private var maximumMarks = 6
    @State private var task: Task<Void, Never>?
    @State private var result: ExamMarkingResult?
    @State private var submitted: ExamMarkingRequest?
    @State private var error: String?
    @State private var saved = false
    @State private var showHistory = false
    @State private var scope: Set<CardTopicSelection> = []
    @State private var savedTestID = UUID()
    @State private var testSaved = false

    private var subject: Subject? { subjects.first { $0.id == subjectID } }
    private var request: ExamMarkingRequest {
        ExamMarkingRequest(subject: subject?.name ?? "", level: subject?.level ?? "", question: question,
                           answer: answer, markScheme: scheme, maximumMarks: maximumMarks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    StudioPageHeader(eyebrow: "Practice / Feedback", title: "Exam marker",
                                     subtitle: "Find the marks you're missing.", symbol: "checkmark.bubble", tint: IBColors.coral) {
                        Button { showHistory = true } label: {
                            Label("Saved feedback", systemImage: "clock.arrow.circlepath")
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                    if let result, let submitted {
                        feedback(result, submitted: submitted)
                    } else {
                        input
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(IBTypography.body).foregroundStyle(IBColors.coral).textSelection(.enabled)
                        NavigationLink("Open AI settings") { SettingsView() }
                    }
                }
                .frame(maxWidth: 1000, alignment: .leading)
                .padding(32).frame(maxWidth: .infinity)
            }
            .background(IBColors.canvas)
            .navigationTitle("Exam marker")
            .sheet(isPresented: $showHistory) { ExamMarkingHistoryView() }
        }
        .onAppear { if subjectID == nil { subjectID = subjects.first?.id } }
        .onChange(of: subjectID) { _, _ in scope = []; testSaved = false }
        .onDisappear { task?.cancel() }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                Picker("Subject", selection: $subjectID) {
                    Text("Choose a subject").tag(Optional<UUID>.none)
                    ForEach(subjects) { Text("\($0.name) · \($0.level)").tag(Optional($0.id)) }
                }.frame(maxWidth: 380)
                Spacer()
                Stepper("Out of \(maximumMarks) marks", value: $maximumMarks, in: 1...100)
                    .font(IBTypography.headline).fixedSize()
            }
            .disabled(task != nil)
            writingField("01", title: "The question", prompt: "Paste the exam question, including any data or context.", text: $question, height: 120)
            if let subject {
                DisclosureGroup("Unit & topics · \(scope.count) selected") {
                    ScrollView { TopicSelectionView(subject: subject, selection: $scope).padding(.top, 12) }
                        .frame(maxHeight: 300)
                }.disabled(task != nil)
            }
            writingField("02", title: "Your answer", prompt: "Write or paste your answer here.", text: $answer, height: 220)
            DisclosureGroup {
                writingField("03", title: "Mark scheme", prompt: "Paste the marking points or assessment rubric.", text: $scheme, height: 160)
                    .padding(.top, 16)
            } label: {
                HStack {
                    Text("Add a mark scheme").font(IBTypography.headline)
                    Text("Optional").font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                }
            }
            .disabled(task != nil)
            HStack(spacing: 20) {
                Button(testSaved ? "Update saved test" : "Save test to Library") { saveTest() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subject == nil || task != nil)
                Text(request.hasScheme ? "AI feedback against your supplied scheme." : "Without a scheme, the score is a practice estimate.")
                    .font(IBTypography.body).foregroundStyle(IBColors.inkSecondary)
                Spacer()
                if task != nil {
                    ProgressView().controlSize(.small)
                    Text("Marking your answer…").font(IBTypography.body)
                    Button("Cancel") { task?.cancel() }.buttonStyle(SecondaryButtonStyle())
                } else {
                    Button(action: mark) { Label("Mark my answer", systemImage: "checkmark.bubble") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!request.isValid)
                }
            }
        }
        .padding(28).surfaceCard()
    }

    private func writingField(_ number: String, title: String, prompt: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(number).font(IBTypography.mono).foregroundStyle(IBColors.coral)
                Text(title).font(IBTypography.title3)
                Spacer()
                if !text.wrappedValue.isEmpty {
                    Text("\(text.wrappedValue.split(whereSeparator: \.isWhitespace).count) words")
                        .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(size: 14)).lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .accessibilityLabel(title)
                    .disabled(task != nil)
                if text.wrappedValue.isEmpty {
                    Text(prompt).font(.system(size: 14)).foregroundStyle(IBColors.inkTertiary)
                        .padding(.horizontal, 15).padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: height)
            .background(IBColors.canvas, in: RoundedRectangle(cornerRadius: IBRadius.md))
            .overlay(RoundedRectangle(cornerRadius: IBRadius.md).stroke(IBColors.borderStrong, lineWidth: 1))
        }
    }

    private func feedback(_ result: ExamMarkingResult, submitted: ExamMarkingRequest) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.scoreLabel).font(.custom("Georgia", size: 52))
                    Text(submitted.hasScheme ? "AI-marked · Supplied scheme" : "Practice estimate · No scheme")
                        .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Text("\(submitted.subject) · \(submitted.level)").font(IBTypography.headline)
                    Button(saved ? "Saved to feedback history" : "Save feedback") { save(result, request: submitted) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(saved)
                    Button("Edit & try again") {
                        self.result = nil; self.submitted = nil; saved = false; error = nil
                    }.buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(28).background(IBColors.highlight, in: RoundedRectangle(cornerRadius: IBRadius.card))
            Text(result.summary).font(IBTypography.body).lineSpacing(5).textSelection(.enabled)
            Text("Where the marks went").font(IBTypography.title3)
            VStack(spacing: 0) {
                ForEach(Array(result.criteria.enumerated()), id: \.offset) { index, criterion in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(criterion.name).font(IBTypography.headline)
                            Spacer()
                            Text("\(ExamMarkingResult.marks(criterion.awarded)) / \(ExamMarkingResult.marks(criterion.available))")
                                .font(IBTypography.mono)
                                .foregroundStyle(criterion.awarded == criterion.available ? IBColors.success : IBColors.coral)
                        }
                        Text(criterion.evidence).font(IBTypography.body).foregroundStyle(IBColors.inkSecondary)
                        Text(criterion.feedback).font(IBTypography.body)
                    }.padding(24).textSelection(.enabled)
                    if index < result.criteria.count - 1 { Divider() }
                }
            }.surfaceCard()
            DisclosureGroup("A stronger answer") {
                FormattedMessageContent(text: result.improvedAnswer)
                    .textSelection(.enabled).padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.font(IBTypography.headline).padding(24).surfaceCard()
            VStack(alignment: .leading, spacing: 16) {
                Text("Practise next").font(IBTypography.title3)
                ForEach(Array(result.nextSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", index + 1)).font(IBTypography.mono).foregroundStyle(IBColors.accent)
                        Text(step).font(IBTypography.body)
                    }
                }
            }.padding(24).surfaceCard()
        }
        .foregroundStyle(IBColors.ink)
    }

    private func mark() {
        let payload = request
        guard payload.isValid, task == nil else { return }
        error = nil
        task = Task { @MainActor in
            defer { task = nil }
            do {
                let marked = try await ExamMarkingService.mark(payload)
                try Task.checkCancellation()
                submitted = payload; result = marked; saved = false
            } catch is CancellationError {
                // Keep the draft available for retry.
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save(_ result: ExamMarkingResult, request: ExamMarkingRequest) {
        // Reuse the backed-up conversation store so feedback survives upgrades
        // and is available to ARIA without becoming a school assessment.
        let session = ARIAChatSession(title: "Exam · \(request.subject) · \(result.scoreLabel)",
                                      lastMessagePreview: result.summary)
        let prompt = ChatMessage(role: .user, content: request.transcript, sessionID: session.id)
        let reply = ChatMessage(role: .model, content: result.transcript(hasScheme: request.hasScheme), sessionID: session.id)
        context.insert(session); context.insert(prompt); context.insert(reply)
        do { try context.save(); saved = true; error = nil }
        catch {
            context.delete(prompt); context.delete(reply); context.delete(session)
            self.error = "Couldn't save feedback: \(error.localizedDescription)"
        }
        if saved { saveTest(feedback: result.transcript(hasScheme: request.hasScheme)) }
    }

    private func saveTest(feedback: String = "") {
        guard let subject else { return }
        let test = SavedStudyTest(id: savedTestID, subject: subject.name, level: subject.level,
            topics: Set(scope.map(\.topic)).sorted(), subtopics: Set(scope.map(\.subtopic)).filter { !$0.isEmpty }.sorted(),
            question: question, answer: answer, markScheme: scheme, feedback: feedback, maximumMarks: maximumMarks)
        do { _ = try StudyTestStore.save(test, context: context); testSaved = true; error = nil }
        catch { self.error = "Couldn't save test: \(error.localizedDescription)" }
    }
}

struct ExamMarkingHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ARIAChatSession> { $0.title.starts(with: "Exam · ") },
           sort: \ARIAChatSession.updatedAt, order: .reverse) private var sessions: [ARIAChatSession]

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                NavigationLink { ExamFeedbackTranscriptView(session: session) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.title).font(IBTypography.headline)
                        Text(session.lastMessagePreview).font(IBTypography.body).foregroundStyle(IBColors.inkSecondary).lineLimit(2)
                        Text(session.updatedAt, style: .date).font(IBTypography.caption)
                    }.padding(.vertical, 8)
                }
            }
            .overlay { if sessions.isEmpty { ContentUnavailableView("No saved feedback", systemImage: "checkmark.bubble", description: Text("Mark an answer, then save the feedback here.")) } }
            .scrollContentBackground(.hidden).background(IBColors.canvas)
            .navigationTitle("Saved feedback")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.frame(minWidth: 700, minHeight: 600)
    }
}

private struct ExamFeedbackTranscriptView: View {
    let session: ARIAChatSession
    @Query private var messages: [ChatMessage]
    init(session: ARIAChatSession) {
        self.session = session
        let id = session.id
        _messages = Query(filter: #Predicate<ChatMessage> { $0.sessionID == id }, sort: \ChatMessage.timestamp)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(messages) { message in
                    FormattedMessageContent(text: message.content).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(24).surfaceCard()
                }
            }.padding(24)
        }.background(IBColors.canvas).navigationTitle(session.title)
    }
}
