import SwiftUI
import SwiftData

struct SavedTestPracticeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State var test: SavedStudyTest
    @State private var task: Task<Void, Never>?
    @State private var status: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(test.subject + " · " + test.title).font(IBTypography.title3)
                    FormattedMessageContent(text: test.question).textSelection(.enabled)
                    Divider()
                    Text("Your answer").font(IBTypography.headline)
                    TextEditor(text: $test.answer).font(IBTypography.body)
                        .frame(minHeight: 200).accessibilityLabel("Test answer")
                        .disabled(task != nil)
                    HStack {
                        Button("Save answer") { save() }.buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        if task != nil {
                            ProgressView().controlSize(.small)
                            Button("Cancel") { task?.cancel() }
                        } else {
                            Button("Mark my answer", action: mark).buttonStyle(PrimaryButtonStyle()).disabled(!test.request.isValid)
                        }
                    }
                    if let status { Text(status).font(IBTypography.caption).textSelection(.enabled) }
                    if !test.feedback.isEmpty {
                        DisclosureGroup("Saved feedback") { FormattedMessageContent(text: test.feedback).padding(.top, 12) }
                    }
                    if !test.markScheme.isEmpty {
                        DisclosureGroup("Mark scheme") { FormattedMessageContent(text: test.markScheme).padding(.top, 12) }
                    }
                }.padding(28)
            }.background(IBColors.canvas)
                .navigationTitle("Practice test")
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Save & close") { if save() { dismiss() } }.disabled(task != nil)
                } }
        }.frame(minWidth: 720, minHeight: 650)
            .onDisappear { task?.cancel() }
    }

    @discardableResult private func save() -> Bool {
        do { test = try StudyTestStore.save(test, context: context); status = "Saved"; return true }
        catch { status = "Couldn't save: \(error.localizedDescription)"; return false }
    }

    private func mark() {
        let request = test.request
        task = Task { @MainActor in
            defer { task = nil }
            do {
                let result = try await ExamMarkingService.mark(request)
                try Task.checkCancellation()
                test.feedback = result.transcript(hasScheme: request.hasScheme)
                save()
            } catch is CancellationError {} catch { status = error.localizedDescription }
        }
    }
}
