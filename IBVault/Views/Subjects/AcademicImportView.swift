import AppKit
import SwiftData
import SwiftUI

struct AcademicImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \AcademicImport.importedAt, order: .reverse) private var imports: [AcademicImport]
    @State private var preview: AcademicImportPreview?
    @State private var folderPath = ""
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importResult: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let preview {
                        previewCard(preview)
                    } else {
                        emptyPreview
                    }
                    if !imports.isEmpty {
                        importHistory
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(IBColors.danger)
                            .padding(14)
                            .glassCard()
                    }
                    if let importResult {
                        Label(importResult, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(IBColors.success)
                            .padding(14)
                            .glassCard()
                    }
                }
                .padding(24)
            }
            .background(IBColors.canvas)
            .navigationTitle("Academic Records")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 660, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(IBColors.inkTertiary.opacity(0.13))
                        .frame(width: 46, height: 46)
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(IBColors.inkTertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calibrate progress from school evidence")
                        .font(.title3.bold())
                    Text("Import a folder containing the ManageBac workbook and school reports. Source files stay in place; only normalized records are saved.")
                        .font(.callout)
                        .foregroundStyle(IBColors.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(IBColors.accent)
                .disabled(isLoading || isImporting)
            }

            HStack(spacing: 10) {
                TextField("School-record folder path", text: $folderPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                Button("Preview path") {
                    previewTypedFolder()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || isImporting || folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .glassCard()
    }

    private var emptyPreview: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView().controlSize(.small)
                Text("Reading school records…")
                    .font(.callout.weight(.semibold))
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(IBColors.inkTertiary)
                Text("Choose a school-record folder to preview its import.")
                    .font(.callout)
                    .foregroundStyle(IBColors.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .glassCard()
    }

    private func previewCard(_ preview: AcademicImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.sourceFolderName)
                        .font(.headline)
                    Text(preview.sourceFiles.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(IBColors.inkSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if isLoading || isImporting { ProgressView().controlSize(.small) }
            }

            HStack(spacing: 12) {
                importMetric("Assessments", value: "\(preview.assessments.count)", tint: IBColors.accent)
                importMetric("Curriculum units", value: "\(preview.curriculumUnits.count)", tint: IBColors.inkTertiary)
                importMetric("Report snapshots", value: "\(preview.reportSnapshots.count)", tint: IBColors.inkTertiary)
                importMetric("Warnings", value: "\(preview.warnings.count)", tint: preview.warnings.isEmpty ? IBColors.success : IBColors.inkTertiary)
            }

            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import notes")
                        .font(.caption.bold())
                        .foregroundStyle(IBColors.inkSecondary)
                    ForEach(preview.warnings.prefix(4), id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(IBColors.inkSecondary)
                    }
                }
                .padding(12)
                .background(IBColors.canvas)
            }

            HStack {
                Text("Unassessed and pending work is retained for coverage, but never counted as numeric evidence.")
                    .font(.caption)
                    .foregroundStyle(IBColors.inkSecondary)
                Spacer()
                Button {
                    commit(preview)
                } label: {
                    Label("Import Records", systemImage: "arrow.down.doc.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(IBColors.inkTertiary)
                .disabled(isImporting || preview.assessments.isEmpty)
            }
        }
        .padding(18)
        .glassCard()
    }

    private var importHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Previous imports")
                .font(.headline)
            ForEach(imports.prefix(4), id: \.id) { record in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(IBColors.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.sourceFolderName)
                            .font(.callout.weight(.medium))
                        Text("\(record.assessmentCount) assessments · \(record.curriculumUnitCount) units · \(record.reportCount) report snapshots")
                            .font(.caption)
                            .foregroundStyle(IBColors.inkSecondary)
                    }
                    Spacer()
                    Text(record.importedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(IBColors.inkTertiary)
                }
                .padding(.vertical, 5)
            }
        }
        .padding(18)
        .glassCard()
    }

    private func importMetric(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(IBTypography.stat)
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(IBColors.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(IBColors.canvas)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Preview Records"
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        previewFolder(url)
    }

    private func previewTypedFolder() {
        let trimmedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        let url = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = "Choose a folder that exists on this Mac."
            return
        }
        previewFolder(url)
    }

    private func previewFolder(_ url: URL) {
        isLoading = true
        errorMessage = nil
        importResult = nil
        Task {
            do {
                preview = try await Task.detached(priority: .userInitiated) {
                    try AcademicRecordImporter.preview(folder: url)
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func commit(_ preview: AcademicImportPreview) {
        isImporting = true
        errorMessage = nil
        do {
            let record = try AcademicRecordImporter.commit(preview, context: context)
            importResult = "Imported \(record.assessmentCount) assessments. Review proposed mappings in each subject before they influence mastery."
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}

struct AcademicMappingReviewView: View {
    let subject: Subject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var assessments: [AcademicAssessment]
    @Query private var mappings: [AcademicAssessmentMapping]
    @State private var isProposing = false
    @State private var errorMessage: String?

    private var subjectAssessments: [AcademicAssessment] {
        assessments.filter { $0.subjectName == subject.name }
    }
    private var subjectMappings: [AcademicAssessmentMapping] {
        mappings.filter { $0.subjectName == subject.name }.sorted { $0.confidence > $1.confidence }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if subjectMappings.isEmpty {
                    ContentUnavailableView("No proposed mappings", systemImage: "arrow.triangle.branch", description: Text("Ask ARIA to match imported assessments to the official curriculum, then approve the useful proposals."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(subjectMappings, id: \.id) { mapping in
                        mappingRow(mapping)
                    }
                    .listStyle(.inset)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(IBColors.danger)
                        .padding(12)
                }
            }
            .background(IBColors.canvas)
            .navigationTitle("Assessment Mappings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(subjectAssessments.count) imported assessments")
                    .font(.headline)
                Text("Only approved mappings contribute to evidence and blended mastery.")
                    .font(.caption)
                    .foregroundStyle(IBColors.inkSecondary)
            }
            Spacer()
            Button {
                propose(localOnly: true)
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .help("Propose deterministic title matches")
            .buttonStyle(.bordered)
            .disabled(isProposing)
            Button {
                propose(localOnly: false)
            } label: {
                Label("Ask ARIA", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(IBColors.accent)
            .disabled(isProposing || subjectAssessments.isEmpty)
        }
        .padding(16)
        .glassCard()
        .padding(16)
    }

    private func mappingRow(_ mapping: AcademicAssessmentMapping) -> some View {
        let assessment = subjectAssessments.first(where: { $0.id == mapping.assessmentID })
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: mapping.status == .approved ? "checkmark.seal.fill" : "questionmark.diamond.fill")
                .foregroundStyle(mapping.status == .approved ? IBColors.success : IBColors.inkTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(assessment?.title ?? "Imported assessment")
                    .font(.callout.weight(.semibold))
                Text("\(mapping.unitName) > \(mapping.topicName) > \(mapping.subtopicName)")
                    .font(.caption)
                    .foregroundStyle(IBColors.inkSecondary)
                if !mapping.rationale.isEmpty {
                    Text(mapping.rationale)
                        .font(.caption2)
                        .foregroundStyle(IBColors.inkTertiary)
                }
            }
            Spacer(minLength: 8)
            Text("\(Int(mapping.confidence * 100))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(IBColors.accent)
            Menu {
                Button("Approve") { update(mapping, to: .approved) }
                Button("Reject", role: .destructive) { update(mapping, to: .rejected) }
                Button("Set Proposed") { update(mapping, to: .proposed) }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("Update mapping status")
        }
        .padding(.vertical, 5)
    }

    private func propose(localOnly: Bool) {
        isProposing = true
        errorMessage = nil
        Task {
            do {
                if localOnly {
                    _ = try AcademicMappingService.proposeLocalMappings(
                        for: subjectAssessments,
                        subject: subject,
                        existingMappings: subjectMappings,
                        context: context
                    )
                } else {
                    _ = try await AcademicMappingService.proposeWithARIA(
                        for: subjectAssessments,
                        subject: subject,
                        existingMappings: subjectMappings,
                        context: context
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isProposing = false
        }
    }

    private func update(_ mapping: AcademicAssessmentMapping, to status: AcademicMappingStatus) {
        mapping.status = status
        do { try context.save() }
        catch { errorMessage = error.localizedDescription }
    }
}
