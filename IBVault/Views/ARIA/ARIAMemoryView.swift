import SwiftUI
import SwiftData

struct ARIAMemoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ARIAMemory.timestamp, order: .reverse) private var memories: [ARIAMemory]
    @State private var newNote = ""
    @State private var selectedCategory: MemoryCategory = .userNotes
    @State private var persistenceError: String?

    private var memoriesByCategory: [MemoryCategory: [ARIAMemory]] {
        Dictionary(grouping: memories, by: \.category)
    }

    var body: some View {
        NavigationStack {
            List {
                addNoteSection

                ForEach(MemoryCategory.allCases, id: \.self) { category in
                    let items = memoriesByCategory[category] ?? []
                    if !items.isEmpty {
                        categorySection(category, items: items)
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
            .alert("Memory Update Failed", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "The memory change could not be saved.")
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
                let memory = ARIAMemory(category: selectedCategory, content: newNote)
                context.insert(memory)
                do {
                    try context.save()
                    newNote = ""
                    IBHaptics.success()
                } catch {
                    context.rollback()
                    persistenceError = error.localizedDescription
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(newNote.isEmpty)
        }
    }

    private func categorySection(_ category: MemoryCategory, items: [ARIAMemory]) -> some View {
        Section {
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
                        do {
                            try context.save()
                        } catch {
                            context.rollback()
                            persistenceError = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Label(category.rawValue, systemImage: category.icon)
        }
    }
}
