import SwiftUI
import SwiftData

struct ARIAChatView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    @State private var ariaService = ARIAService()
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var showMemory = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Status") {
                        LabeledContent("Assistant", value: "ARIA")
                        LabeledContent("State", value: ariaService.isLoading ? "Thinking…" : "Ready")

                        if let err = errorMessage {
                            Text(err)
                                .foregroundStyle(.red)
                        }
                    }

                    if messages.isEmpty && !ariaService.isLoading {
                        Section("Suggested Prompts") {
                            ForEach(ariaService.suggestedPrompts, id: \.self) { prompt in
                                Button(prompt) { sendMessage(prompt) }
                            }
                        }
                    }

                    Section("Conversation") {
                        if messages.isEmpty && streamingText.isEmpty && !ariaService.isLoading {
                            Text("Start a conversation with ARIA.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(messages, id: \.id) { message in
                            MessageRow(message: message)
                        }

                        if ariaService.isLoading {
                            if streamingText.isEmpty {
                                HStack {
                                    ProgressView()
                                    Text("ARIA is responding…")
                                }
                            } else {
                                StreamingMessageRow(text: streamingText)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .controlSize(.small)

                Divider()

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask ARIA...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button("Send") {
                        sendMessage(inputText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ariaService.isLoading)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .navigationTitle("ARIA")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Notes") { showMemory = true }
                }
            }
            .sheet(isPresented: $showMemory) { ARIAMemoryView() }
        }
    }

    private func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let msg = text; inputText = ""; streamingText = ""; errorMessage = nil; IBHaptics.light()
        ariaService.sendMessage(msg, context: context,
            onToken: { token in streamingText += token },
            onComplete: { _ in streamingText = "" },
            onError: { error in errorMessage = error.localizedDescription; streamingText = "" }
        )
    }
}

struct MessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isUser ? "You" : "ARIA")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.content)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

struct StreamingMessageRow: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ARIA")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
        }
        .padding(.vertical, 2)
    }
}
