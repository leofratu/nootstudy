import SwiftUI
import SwiftData

struct ExternalActivityView: View {
    @Environment(\.modelContext) private var context
    @Query private var subjects: [Subject]
    @Query(sort: \ExternalActivity.occurredAt, order: .reverse) private var allActivities: [ExternalActivity]

    @State private var selectedIDs: Set<UUID> = []
    @State private var showAddForm = false

    // Add form state
    @State private var formSubjectName: String = "__unassigned__"
    @State private var formTopicName: String = ""
    @State private var formKind: String = "study"
    @State private var formMinutes: Double = 30
    @State private var formCardsReviewed: Int = 0
    @State private var formCorrectCount: Int = 0
    @State private var formOccurredAt: Date = Date()
    @State private var formDetails: String = ""
    @State private var formError: String?

    private var pending: [ExternalActivity] {
        allActivities.filter { $0.statusRaw == "pending" }
    }

    private var merged: [ExternalActivity] {
        allActivities.filter { $0.statusRaw == "merged" }
    }

    private var kindOptions: [String] { ["review", "study", "notes"] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StudioPageHeader(
                    eyebrow: "Integrations",
                    title: "External work",
                    subtitle: "Add work you did elsewhere — tutoring, Anki, reading — back into your study history.",
                    symbol: "tray.and.arrow.down.fill",
                    tint: IBColors.coral
                ) {
                    Button {
                        withAnimation { showAddForm.toggle() }
                    } label: {
                        Label(showAddForm ? "Close form" : "Add work", systemImage: showAddForm ? "xmark.circle.fill" : "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(IBColors.coral)
                }

                if showAddForm {
                    addWorkForm
                        .glassCard()
                        .padding(.vertical, 4)
                }

                pendingSection
                mergedSection
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(IBColors.canvas)
        .navigationTitle("External Work")
        .onAppear {
            if formSubjectName == "__unassigned__" && subjects.isEmpty {
                formSubjectName = "__unassigned__"
            }
        }
    }

    // MARK: - Add Work Form

    private var addWorkForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioSectionHeader("Add work", subtitle: "Manual entry becomes a pending activity", symbol: "plus.app.fill", tint: IBColors.coral) {
                EmptyView()
            }

            // Subject picker
            HStack(spacing: 12) {
                Text("Subject")
                    .font(.callout.weight(.medium))
                    .frame(width: 110, alignment: .leading)
                Picker("Subject", selection: $formSubjectName) {
                    Text("Unassigned").tag("__unassigned__")
                    ForEach(subjects.sorted { $0.name < $1.name }, id: \.name) { s in
                        Text(s.name).tag(s.name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Topic")
                    .font(.callout.weight(.medium))
                    .frame(width: 110, alignment: .leading)
                TextField("e.g. Photosynthesis", text: $formTopicName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Kind")
                    .font(.callout.weight(.medium))
                    .frame(width: 110, alignment: .leading)
                Picker("Kind", selection: $formKind) {
                    ForEach(kindOptions, id: \.self) { k in
                        Text(k.capitalized).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Minutes")
                    .font(.callout.weight(.medium))
                    .frame(width: 110, alignment: .leading)
                Stepper("\(Int(formMinutes)) min", value: $formMinutes, in: 5...480, step: 5)
                    .frame(maxWidth: 200)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Cards reviewed")
                    .font(.callout.weight(.medium))
                    .frame(width: 110, alignment: .leading)
                Stepper("\(formCardsReviewed)", value: $formCardsReviewed, in: 0...500, step: 1)
                    .frame(maxWidth: 200)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Correct")
                    .font(.callout.weight(.medium))
                    .frame(width: 110, alignment: .leading)
                Stepper("\(formCorrectCount)", value: $formCorrectCount, in: 0...500, step: 1)
                    .frame(maxWidth: 200)
                if formCorrectCount > formCardsReviewed {
                    Text("Cannot exceed reviewed")
                        .font(.caption)
                        .foregroundStyle(IBColors.danger)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Text("When")
                    .font(.callout.weight(.medium))
                    .frame(width: 110, alignment: .leading)
                DatePicker("", selection: $formOccurredAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Details")
                    .font(.callout.weight(.medium))
                TextField("Optional notes (e.g. tutor session, pages read)", text: $formDetails, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }

            if let formError {
                Text(formError)
                    .font(.caption)
                    .foregroundStyle(IBColors.danger)
            }

            HStack(spacing: 10) {
                Button {
                    addManualActivity()
                } label: {
                    Label("Save pending work", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(IBColors.coral)

                Button("Clear") { clearForm() }
                    .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(18)
    }

    private func clearForm() {
        formTopicName = ""
        formKind = "study"
        formMinutes = 30
        formCardsReviewed = 0
        formCorrectCount = 0
        formOccurredAt = Date()
        formDetails = ""
        formError = nil
        formSubjectName = "__unassigned__"
    }

    private func addManualActivity() {
        if formCorrectCount > formCardsReviewed {
            formError = "Correct count cannot exceed cards reviewed."
            return
        }
        let subjectName: String? = formSubjectName == "__unassigned__" ? nil : formSubjectName
        let topicName: String? = formTopicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : formTopicName.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = ExternalActivity(
            externalID: UUID().uuidString,
            source: "manual",
            kindRaw: formKind,
            subjectName: subjectName,
            topicName: topicName,
            minutes: formMinutes,
            cardsReviewed: formCardsReviewed,
            correctCount: formCorrectCount,
            occurredAt: formOccurredAt,
            details: formDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : formDetails,
            importedAt: Date(),
            statusRaw: "pending"
        )
        context.insert(activity)
        do {
            try context.save()
            IBHaptics.success()
            clearForm()
            withAnimation { showAddForm = false }
        } catch {
            formError = error.localizedDescription
            context.rollback()
        }
    }

    // MARK: - Pending

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(
                "Pending",
                subtitle: pending.isEmpty ? "Nothing waiting to be merged" : "\(pending.count) awaiting merge",
                symbol: "clock.badge.exclamationmark",
                tint: pending.isEmpty ? IBColors.success : IBColors.coral
            ) {
                HStack(spacing: 8) {
                    if !pending.isEmpty {
                        Button("Select All") { selectedIDs = Set(pending.map(\.id)) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Clear") { selectedIDs.removeAll() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if !selectedIDs.isEmpty {
                        Button("Merge Selected") { merge(ids: Array(selectedIDs)) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(IBColors.electricBlue)
                            .accessibilityLabel("Merge Selected")
                    }
                    if !pending.isEmpty {
                        Button("Merge All") { merge(ids: pending.map(\.id)) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Merge All")
                    }
                }
            }

            if pending.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    EmptyStateView(
                        icon: "tray",
                        title: "No pending work",
                        message: "Work you did elsewhere — tutoring, Anki, or reading — can be added here. Codex and ChatGPT can also push activity through the bridge at POST /v1/activity and it will appear here for you to merge."
                    )
                    .frame(maxWidth: .infinity)
                    Button("Add work") { withAnimation { showAddForm = true } }
                        .buttonStyle(.borderedProminent)
                        .tint(IBColors.coral)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(pending, id: \.id) { activity in
                        activityRow(activity, selectable: true)
                        if activity.id != pending.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
                .glassCard(cornerRadius: IBRadius.md)
            }
        }
    }

    // MARK: - Merged

    private var mergedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(
                "Merged",
                subtitle: merged.isEmpty ? "Merged work becomes a study session" : "\(merged.count) merged",
                symbol: "checkmark.circle.fill",
                tint: IBColors.teal
            ) {
                EmptyView()
            }

            if merged.isEmpty {
                Text("Merged entries are stored as study sessions and count toward streaks and analytics.")
                    .font(.callout)
                    .foregroundStyle(IBColors.secondaryText)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(merged, id: \.id) { activity in
                        activityRow(activity, selectable: false)
                        if activity.id != merged.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
                .glassCard(cornerRadius: IBRadius.md)
            }
        }
    }

    private func activityRow(_ activity: ExternalActivity, selectable: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if selectable {
                Button {
                    if selectedIDs.contains(activity.id) {
                        selectedIDs.remove(activity.id)
                    } else {
                        selectedIDs.insert(activity.id)
                    }
                } label: {
                    Image(systemName: selectedIDs.contains(activity.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIDs.contains(activity.id) ? IBColors.electricBlue : IBColors.secondaryText)
                        .font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedIDs.contains(activity.id) ? "Deselect" : "Select")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(IBColors.success)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    StudioPill(title: activity.kindRaw.uppercased(), tint: kindTint(activity.kindRaw))
                    if let subject = activity.subjectName, !subject.isEmpty {
                        Text(subject)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IBColors.ink)
                            .lineLimit(1)
                    } else {
                        Text("Unassigned")
                            .font(.caption)
                            .foregroundStyle(IBColors.secondaryText)
                    }
                    if let topic = activity.topicName, !topic.isEmpty {
                        Text("· \(topic)")
                            .font(.caption)
                            .foregroundStyle(IBColors.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }

                HStack(spacing: 10) {
                    Label("\(Int(activity.minutes)) min", systemImage: "clock")
                    Label("\(activity.cardsReviewed) cards", systemImage: "rectangle.stack.fill")
                    Label("\(activity.correctCount) correct", systemImage: "checkmark.circle")
                    Text(activity.occurredAt, style: .date)
                        .foregroundStyle(IBColors.secondaryText)
                }
                .font(.caption)
                .foregroundStyle(IBColors.secondaryText)
                .lineLimit(1)

                if let details = activity.details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(activity.source)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(IBColors.tertiaryText)
                    Text(activity.externalID)
                        .font(.caption2)
                        .foregroundStyle(IBColors.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if activity.statusRaw == "merged", let sid = activity.mergedStudySessionID {
                        StudioPill(title: "→ \(sid.uuidString.prefix(8))", tint: IBColors.success)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                if activity.statusRaw == "pending" {
                    Button("Merge") { merge(ids: [activity.id]) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(IBColors.electricBlue)
                        .accessibilityLabel("Merge")
                    Button("Delete", role: .destructive) {
                        delete(activity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Delete")
                } else {
                    Button("Delete", role: .destructive) {
                        delete(activity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Delete")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func kindTint(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "review": return IBColors.electricBlue
        case "study": return IBColors.teal
        case "notes": return IBColors.gold
        default: return IBColors.secondaryText
        }
    }

    private func merge(ids: [UUID]) {
        let results = ExternalActivityService.merge(ids: ids, context: context)
        if !results.isEmpty {
            IBHaptics.success()
            selectedIDs.subtract(results.map(\.id))
        }
    }

    private func delete(_ activity: ExternalActivity) {
        ExternalActivityService.delete(id: activity.id, context: context)
        selectedIDs.remove(activity.id)
        IBHaptics.warning()
    }
}
