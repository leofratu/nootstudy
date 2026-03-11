import SwiftUI
import SwiftData

struct ARIAMemoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ARIAMemory.timestamp, order: .reverse) private var memories: [ARIAMemory]
    @State private var newNote = ""
    @State private var selectedCategory: MemoryCategory = .userNotes

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: IBSpacing.lg) {
                        addNoteSection
                        ForEach(MemoryCategory.allCases, id: \.self) { cat in
                            let items = memories.filter { $0.category == cat }
                            if !items.isEmpty { categorySection(cat, items: items) }
                        }
                    }.padding(IBSpacing.md).padding(.bottom, 40)
                }
            }
            .navigationTitle("ARIA's Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var addNoteSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                Text("Add a Note").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                Text("Help ARIA remember important things").font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                HStack {
                    TextField("e.g. My Biology exam is on May 12th", text: $newNote)
                        .font(IBTypography.body).foregroundColor(IBColors.softWhite)
                        .textFieldStyle(.plain)
                    Button {
                        guard !newNote.isEmpty else { return }
                        let mem = ARIAMemory(category: .userNotes, content: newNote)
                        context.insert(mem); try? context.save()
                        newNote = ""; IBHaptics.success()
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(IBColors.electricBlue)
                    }
                }
                .padding(IBSpacing.sm).background(RoundedRectangle(cornerRadius: 10).fill(IBColors.navy))
            }
        }
    }

    private func categorySection(_ category: MemoryCategory, items: [ARIAMemory]) -> some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            HStack {
                Image(systemName: category.icon).foregroundColor(IBColors.electricBlue)
                Text(category.rawValue).font(IBTypography.headline).foregroundColor(IBColors.softWhite)
            }
            ForEach(items, id: \.id) { item in
                GlassCard(cornerRadius: 10, padding: IBSpacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.content).font(IBTypography.caption).foregroundColor(IBColors.softWhite).lineLimit(3)
                            Text(item.timestamp, style: .relative).font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                        }
                        Spacer()
                        Button { context.delete(item); try? context.save() } label: {
                            Image(systemName: "trash").font(.caption).foregroundColor(IBColors.danger.opacity(0.7))
                        }
                    }
                }
            }
        }
    }
}
