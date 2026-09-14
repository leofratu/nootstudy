import SwiftUI
import SwiftData

struct CardStudioView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.name) private var subjects: [Subject]
    var initialSubject: Subject? = nil
    var initialSelection: Set<CardTopicSelection> = []
    @State private var subjectID: UUID?
    @State private var selection: Set<CardTopicSelection> = []
    @State private var formats: Set<CardStyle> = [.basic]
    @State private var options = CardGenerationOptions.default
    @State private var drafts: [CardDraft] = []
    @State private var issues: [String] = []
    @State private var status: String?
    @State private var progress = 0.0
    @State private var task: Task<Void, Never>?
    @State private var savedMessage: String?
    @State private var showLibrary = false

    private var subject: Subject? { subjects.first { $0.id == subjectID } }
    private var jobs: [CardBatchJob]? {
        try? CardBatchService.plan(scopes: Array(selection), styles: Array(formats), count: options.count)
    }
    private var selectionMinimum: Int { selection.count * formats.count }

    var body: some View {
        GeometryReader { geometry in
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    StudioPageHeader(eyebrow: "Practice / Create", title: "Card studio",
                                     subtitle: "A little recall. A lot of progress.", symbol: "rectangle.stack.badge.plus", tint: IBColors.accent) {
                        Button { showLibrary = true } label: {
                            Label("Your cards", systemImage: "rectangle.stack")
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                    if subjects.isEmpty && initialSubject == nil {
                        ContentUnavailableView("Add a subject first", systemImage: "books.vertical",
                                               description: Text("Your subjects and curriculum appear here after onboarding."))
                    } else {
                        if let savedMessage {
                            Label(savedMessage, systemImage: "checkmark.circle.fill")
                                .font(IBTypography.body).foregroundStyle(IBColors.success)
                        }
                        if drafts.isEmpty {
                            setup(width: geometry.size.width - 64)
                        } else {
                            preview
                        }
                        if !issues.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(drafts.isEmpty ? "Couldn't complete this batch" : "Some cards need another attempt", systemImage: "exclamationmark.triangle")
                                    .font(IBTypography.headline)
                                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                                    Text(issue).font(IBTypography.body).textSelection(.enabled)
                                }
                                NavigationLink("Open AI settings") { SettingsView() }
                                    .font(IBTypography.body)
                            }
                            .foregroundStyle(IBColors.inkSecondary)
                            .padding(20).surfaceCard()
                        }
                    }
                }
                .frame(maxWidth: 1200, alignment: .leading)
                .padding(32).frame(maxWidth: .infinity)
            }
            .background(IBColors.canvas)
            .navigationTitle("Card studio")
            .sheet(isPresented: $showLibrary) {
                NavigationStack { CardLibraryView() }
            }
        }
        }
        .onAppear {
            if subjectID == nil {
                subjectID = (initialSubject ?? subjects.first)?.id
                selection = initialSelection
            }
        }
        .onDisappear { task?.cancel() }
        .tint(IBColors.accent)
    }

    private func setup(width: CGFloat) -> some View {
        let narrow = width < 720
        let layout = narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 28))
        return VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Text("01").font(IBTypography.mono).foregroundStyle(IBColors.accent)
                Text("Choose your material").font(IBTypography.title3)
                Spacer()
                Picker("Subject", selection: $subjectID) {
                    Text("Choose a subject").tag(Optional<UUID>.none)
                    ForEach(subjects) { subject in
                        Text("\(subject.name) · \(subject.level)").tag(Optional(subject.id))
                    }
                }
                .frame(maxWidth: 280)
                .onChange(of: subjectID) { previous, _ in
                    if previous != nil { selection.removeAll(); savedMessage = nil; issues = [] }
                }
            }
                layout {
                    if let subject {
                        ScrollView {
                            TopicSelectionView(subject: subject, selection: $selection)
                                .id(subject.id).padding(20)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: narrow ? 360 : 720)
                        .surfaceCard()
                    }
                    configuration
                        .frame(width: narrow ? nil : 330)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
        }
        .disabled(task != nil)
        .overlay(alignment: .bottom) {
            if let status, task != nil {
                VStack(spacing: 12) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(status).font(IBTypography.body)
                        Spacer()
                        Button("Cancel") { task?.cancel() }.buttonStyle(SecondaryButtonStyle())
                    }
                    ProgressView(value: progress).tint(IBColors.accent)
                }
                .padding(20).surfaceCard(prominent: true)
                .disabled(false)
            }
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Text("02").font(IBTypography.mono).foregroundStyle(IBColors.accent)
                Text("Make it yours").font(IBTypography.title3)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Card formats").font(IBTypography.headline)
                ForEach(CardStyle.allCases) { style in
                    Button {
                        if formats.contains(style) { formats.remove(style) } else { formats.insert(style) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: style.symbol).font(.system(size: 19))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(style.label).font(IBTypography.headline)
                                Text(style.shortDescription).font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                            }
                            Spacer()
                            Image(systemName: formats.contains(style) ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(formats.contains(style) ? IBColors.accent : IBColors.ink)
                        .padding(12)
                        .background(formats.contains(style) ? IBColors.highlight : IBColors.surface, in: RoundedRectangle(cornerRadius: IBRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: IBRadius.md).stroke(formats.contains(style) ? IBColors.accent : IBColors.borderStrong, lineWidth: 1))
                    }.buttonStyle(.plain)
                    .accessibilityValue(formats.contains(style) ? "Selected" : "Not selected")
                }
            }
            CardStudioOptionsView(options: $options, compact: true, showsStyle: false)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("\(options.count) cards · \(selection.count) selected")
                    .font(IBTypography.headline)
                if selectionMinimum > options.count || selectionMinimum > 50 {
                    Text(selectionMinimum > 50 ? "Choose fewer topics or formats to fit a 50-card batch." : "Increase the count to at least \(selectionMinimum) to include every topic and format.")
                        .font(IBTypography.caption).foregroundStyle(IBColors.coral)
                }
                Button(action: generate) {
                    Label("Generate & preview", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(jobs == nil)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your new set").font(IBTypography.title3)
                    Text("\(drafts.count) cards · \(subject?.name ?? "") · Not saved yet")
                        .font(IBTypography.body).foregroundStyle(IBColors.inkSecondary)
                }
                Spacer()
                Button("Discard batch") { drafts = []; issues = [] }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save \(drafts.count) cards", action: save)
                    .buttonStyle(PrimaryButtonStyle()).disabled(!drafts.allSatisfy(\.isValid))
            }
            LazyVStack(spacing: 16) {
                ForEach($drafts) { $draft in
                    CardDraftEditor(draft: $draft) { drafts.removeAll { $0.id == draft.id } }
                }
            }
        }
    }

    private func generate() {
        guard let subject, let jobs, task == nil else { return }
        savedMessage = nil
        issues = []
        progress = 0
        status = "Preparing your set…"
        let settings = options
        task = Task { @MainActor in
            defer { task = nil; status = nil }
            do {
                let result = try await CardBatchService.generate(subject: subject, jobs: jobs, options: settings, context: context) { current, total, label in
                    progress = Double(current) / Double(max(total, 1))
                    status = "Generating \(current + 1) of \(total) · \(label)"
                }
                try Task.checkCancellation()
                drafts = result.drafts
                issues = result.issues
            } catch is CancellationError {
                status = nil
            } catch { issues = [error.localizedDescription] }
        }
    }

    private func save() {
        guard let subject else { return }
        do {
            let count = try CardBatchService.save(drafts, subject: subject, context: context)
            savedMessage = "\(count) cards saved to \(subject.name). Open Your cards to practise."
            drafts = []
            issues = []
        } catch { issues = [error.localizedDescription] }
    }
}

struct CardDraftEditor: View {
    @Binding var draft: CardDraft
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(draft.style.label, systemImage: draft.style.symbol).font(IBTypography.captionBold)
                Text("· \(draft.topic)").font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                Spacer()
                Button(action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).accessibilityLabel("Remove card from batch")
            }
            TextField("Question", text: $draft.front, axis: .vertical)
                .font(.custom("Georgia", size: 19)).textFieldStyle(.plain)
                .accessibilityLabel("Card question")
            Divider()
            TextField("Answer", text: $draft.back, axis: .vertical)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Correct answer")
            if draft.style == .multipleChoice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer choices").font(IBTypography.captionBold)
                    ForEach(draft.choices.indices, id: \.self) { index in
                        HStack {
                            Text(String(UnicodeScalar(65 + index)!)).font(IBTypography.mono)
                            TextField("Option \(index + 1)", text: $draft.choices[index])
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            if !draft.isValid {
                Label(draft.style == .multipleChoice ? "The answer must match exactly one unique choice." : "Check the question, answer and any cloze blank.",
                      systemImage: "exclamationmark.circle")
                    .font(IBTypography.caption).foregroundStyle(IBColors.coral)
            }
        }
        .padding(24).surfaceCard()
    }
}
