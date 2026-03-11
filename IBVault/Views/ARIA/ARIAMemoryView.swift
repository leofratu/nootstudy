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
            List {
                addNoteSection

                ForEach(MemoryCategory.allCases, id: \.self) { cat in
                    let items = memories.filter { $0.category == cat }
                    if !items.isEmpty {
                        categorySection(cat, items: items)
                    }
                }
            }
            .listStyle(.inset)
            .controlSize(.small)
            .navigationTitle("ARIA's Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var addNoteSection: some View {
        Section("Add a Note") {
            Picker("Category", selection: $selectedCategory) {
                ForEach(MemoryCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }

            TextField("e.g. My Biology exam is on May 12th", text: $newNote)

            Button("Save Note") {
                guard !newNote.isEmpty else { return }
                let mem = ARIAMemory(category: selectedCategory, content: newNote)
                context.insert(mem)
                try? context.save()
                newNote = ""
                IBHaptics.success()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func categorySection(_ category: MemoryCategory, items: [ARIAMemory]) -> some View {
        Section(category.rawValue) {
            ForEach(items, id: \.id) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.content)
                        Text(item.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button(role: .destructive) {
                        context.delete(item)
                        try? context.save()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
}
