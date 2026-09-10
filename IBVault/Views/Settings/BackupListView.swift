import SwiftUI

private struct BackupListItem: Identifiable, Sendable {
    let id: String
    let name: String
    let date: Date
    let url: URL
}

struct BackupListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [BackupListItem] = []
    @State private var isLoading = true
    @State private var statusMessage = ""
    @State private var pendingDeletion: BackupListItem?

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading backups…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if backups.isEmpty {
                    ContentUnavailableView("No Backups", systemImage: "externaldrive", description: Text("Create your first backup in Settings."))
                } else {
                    ForEach(backups) { backup in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.name)
                                    .lineLimit(1)
                                Text(backup.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(backup.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = backup
                            } label: {
                                Label("Delete Backup", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = backup
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(statusMessage.hasPrefix("✗") ? IBColors.danger : IBColors.success)
                    }
                }
            }
            .navigationTitle("Backups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await reload() }
            .confirmationDialog(
                "Delete this backup?",
                isPresented: deleteDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Backup", role: .destructive) {
                    if let backup = pendingDeletion {
                        deleteBackup(backup)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the backup files from your Documents folder.")
            }
        }
    }

    @MainActor
    private func reload() async {
        let items = await Task.detached(priority: .utility) {
            BackupService.listBackups().map {
                BackupListItem(id: $0.name, name: $0.name, date: $0.date, url: $0.url)
            }
        }.value
        backups = items
        isLoading = false
    }

    private func deleteBackup(_ backup: BackupListItem) {
        do {
            try BackupService.deleteBackup(at: backup.url)
            statusMessage = "Backup deleted"
            IBHaptics.warning()
        } catch {
            statusMessage = "✗ Delete failed: \(error.localizedDescription)"
        }
        Task { await reload() }
    }
}
