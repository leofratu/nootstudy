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
            ZStack {
                IBColors.navy.ignoresSafeArea()
                VStack(spacing: 0) {
                    chatHeader
                    Divider().background(IBColors.cardBorder)
                    messagesScroll
                    if !ariaService.isLoading && messages.isEmpty { suggestedPrompts }
                    inputBar
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showMemory) { ARIAMemoryView() }
        }
    }

    private var chatHeader: some View {
        HStack(spacing: IBSpacing.md) {
            PulseOrb(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("ARIA").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                Text(ariaService.isLoading ? "Thinking..." : "Online")
                    .font(IBTypography.caption).foregroundColor(ariaService.isLoading ? IBColors.warning : IBColors.success)
            }
            Spacer()
            Button { showMemory = true } label: {
                Image(systemName: "brain").font(.title3).foregroundColor(IBColors.electricBlue)
            }
        }.padding(IBSpacing.md)
    }

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: IBSpacing.md) {
                    ForEach(messages, id: \.id) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if ariaService.isLoading {
                        if streamingText.isEmpty {
                            HStack { ThinkingDots(); Spacer() }.padding(.horizontal, IBSpacing.md).id("thinking")
                        } else {
                            streamingBubble.id("streaming")
                        }
                    }
                    if let err = errorMessage {
                        Text(err).font(IBTypography.caption).foregroundColor(IBColors.danger).padding()
                    }
                }.padding(.vertical, IBSpacing.md)
            }
            .onChange(of: messages.count) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            .onChange(of: streamingText) { proxy.scrollTo("streaming", anchor: .bottom) }
        }
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: IBSpacing.sm) {
            PulseOrb(size: 24)
            Text(streamingText).font(IBTypography.body).foregroundColor(IBColors.softWhite)
                .padding(IBSpacing.md).glassCard(cornerRadius: 16)
            Spacer(minLength: 40)
        }.padding(.horizontal, IBSpacing.md)
    }

    private var suggestedPrompts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: IBSpacing.sm) {
                ForEach(ariaService.suggestedPrompts, id: \.self) { prompt in
                    PromptChip(text: prompt) { sendMessage(prompt) }
                }
            }.padding(.horizontal, IBSpacing.md).padding(.vertical, IBSpacing.sm)
        }
    }

    private var inputBar: some View {
        HStack(spacing: IBSpacing.sm) {
            TextField("Ask ARIA...", text: $inputText, axis: .vertical)
                .font(IBTypography.body).foregroundColor(IBColors.softWhite)
                .padding(.horizontal, IBSpacing.md).padding(.vertical, IBSpacing.sm)
                .background(RoundedRectangle(cornerRadius: 20).fill(IBColors.cardBackground).overlay(RoundedRectangle(cornerRadius: 20).stroke(IBColors.cardBorder)))
                .lineLimit(1...4)
            Button { sendMessage(inputText) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    .foregroundColor(inputText.isEmpty || ariaService.isLoading ? IBColors.mutedGray : IBColors.electricBlue)
            }.disabled(inputText.isEmpty || ariaService.isLoading)
        }.padding(IBSpacing.md).background(IBColors.deepNavy)
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

struct MessageBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: IBSpacing.sm) {
            if isUser { Spacer(minLength: 40) }
            else { PulseOrb(size: 24) }
            Text(message.content).font(IBTypography.body)
                .foregroundColor(isUser ? .white : IBColors.softWhite)
                .padding(IBSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isUser ? IBColors.electricBlue : IBColors.cardBackground.opacity(0.8))
                        .overlay(isUser ? nil : RoundedRectangle(cornerRadius: 16).stroke(IBColors.cardBorder, lineWidth: 1))
                )
            if !isUser { Spacer(minLength: 40) }
        }.padding(.horizontal, IBSpacing.md)
    }
}
