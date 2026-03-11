import SwiftUI

struct BackupListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backups = BackupService.listBackups()
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            List {
                if backups.isEmpty {
                    ContentUnavailableView("No Backups", systemImage: "externaldrive", description: Text("Create your first backup in Settings."))
                } else {
                    ForEach(backups, id: \.name) { backup in
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                try? BackupService.deleteBackup(at: backup.url)
                                backups = BackupService.listBackups()
                                statusMessage = "Backup deleted"
                                IBHaptics.warning()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Backups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
