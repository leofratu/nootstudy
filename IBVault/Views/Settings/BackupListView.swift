import SwiftUI

struct BackupListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backups = BackupService.listBackups()
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()
                if backups.isEmpty {
                    EmptyStateView(icon: "externaldrive", title: "No Backups", message: "Create your first backup in Settings")
                } else {
                    List {
                        ForEach(backups, id: \.name) { backup in
                            HStack {
                                Image(systemName: "doc.zipper").foregroundColor(IBColors.electricBlue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backup.name).font(IBTypography.captionBold).foregroundColor(IBColors.softWhite).lineLimit(1)
                                    Text(backup.date, style: .date).font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                                }
                                Spacer()
                                Text(backup.date, style: .time).font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    try? BackupService.deleteBackup(at: backup.url)
                                    backups = BackupService.listBackups()
                                    IBHaptics.warning()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        .listRowBackground(IBColors.cardBackground)
                    }
                    .scrollContentBackground(.hidden)
                }

                if !statusMessage.isEmpty {
                    VStack { Spacer(); Text(statusMessage).font(IBTypography.caption).foregroundColor(IBColors.success).padding().glassCard().padding() }
                }
            }
            .navigationTitle("Backups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
