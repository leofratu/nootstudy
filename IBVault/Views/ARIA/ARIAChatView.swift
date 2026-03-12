import SwiftUI
import SwiftData
import WebKit

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
                // Chat content
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            if messages.isEmpty && !ariaService.isLoading {
                                emptyState
                            }

                            ForEach(messages, id: \.id) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }

                            if ariaService.isLoading {
                                if streamingText.isEmpty {
                                    thinkingIndicator
                                } else {
                                    StreamingMessageRow(text: streamingText)
                                        .id("streaming")
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: streamingText) { _, _ in
                        withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                    }
                }

                Divider()

                // Input bar
                inputBar
            }
            .background(.background)
            .navigationTitle("ARIA")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showMemory = true } label: {
                        Label("Memory", systemImage: "brain")
                    }
                }
            }
            .sheet(isPresented: $showMemory) { ARIAMemoryView() }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(IBColors.electricBlue)
            }

            VStack(spacing: 6) {
                Text("Meet ARIA")
                    .font(.title2.bold())
                Text("Your AI study companion. Ask about topics, request study guides, or get help with revision strategies.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Prompt chips
            VStack(spacing: 8) {
                ForEach(ariaService.suggestedPrompts, id: \.self) { prompt in
                    PromptChip(text: prompt) { sendMessage(prompt) }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IBColors.electricBlue)
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("ARIA is thinking…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask ARIA…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit { sendMessage(inputText) }

                Button {
                    sendMessage(inputText)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ariaService.isLoading
                                ? Color.secondary.opacity(0.3) : IBColors.electricBlue
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ariaService.isLoading)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
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

// MARK: - Message Row
struct MessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isUser {
                // ARIA avatar
                ZStack {
                    Circle()
                        .fill(IBColors.electricBlue.opacity(0.1))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IBColors.electricBlue)
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "ARIA")
                    .font(.caption.bold())
                    .foregroundStyle(isUser ? .secondary : IBColors.electricBlue)

                FormattedMessageContent(text: message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isUser ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                    )
            }

            if isUser {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Streaming Message Row
struct StreamingMessageRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IBColors.electricBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ARIA")
                    .font(.caption.bold())
                    .foregroundStyle(IBColors.electricBlue)
                FormattedMessageContent(text: text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct FormattedMessageContent: View {
    let text: String

    private var sections: [FormattedMessageSection] {
        FormattedMessageFormatter.sections(from: text)
    }

    private var containsMath: Bool {
        MathMarkdownHTMLRenderer.containsMath(in: text)
    }

    var body: some View {
        Group {
            if containsMath {
                MathMarkdownContainer(markdown: text)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        sectionView(section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: FormattedMessageSection) -> some View {
        switch section {
        case .markdown(let markdown):
            if let attributed = FormattedMessageFormatter.attributedMarkdown(from: markdown) {
                Text(attributed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(markdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .mathBlock(let latex):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: latex)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

struct MathMarkdownContainer: View {
    let markdown: String
    @State private var contentHeight: CGFloat = 28

    var body: some View {
        MathMarkdownWebView(markdown: markdown, contentHeight: $contentHeight)
            .frame(height: max(contentHeight, 28))
    }
}

#if os(macOS)
struct MathMarkdownWebView: NSViewRepresentable {
    let markdown: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "heightUpdated")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.load(markdown: markdown, into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.load(markdown: markdown, into: nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding private var contentHeight: CGFloat
        private var lastHTML = ""

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func load(markdown: String, into webView: WKWebView) {
            let html = MathMarkdownHTMLRenderer.document(for: markdown)
            guard html != lastHTML else { return }
            lastHTML = html
            webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            reportHeight(for: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightUpdated" else { return }

            if let value = message.body as? Double {
                DispatchQueue.main.async {
                    self.contentHeight = ceil(value)
                }
            } else if let value = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.contentHeight = ceil(value)
                }
            }
        }

        private func reportHeight(for webView: WKWebView) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { result, _ in
                if let value = result as? Double {
                    DispatchQueue.main.async {
                        self.contentHeight = ceil(value)
                    }
                }
            }
        }
    }
}
#endif

enum FormattedMessageSection {
    case markdown(String)
    case mathBlock(String)
}

enum FormattedMessageFormatter {
    static func sections(from source: String) -> [FormattedMessageSection] {
        let normalized = normalizeMathDelimiters(in: source)
        var sections: [FormattedMessageSection] = []
        var buffer = ""
        var index = normalized.startIndex

        while index < normalized.endIndex {
            let remaining = normalized[index...]

            if remaining.hasPrefix("$$") {
                let contentStart = normalized.index(index, offsetBy: 2)

                if let closingRange = normalized[contentStart...].range(of: "$$") {
                    let mathContent = String(normalized[contentStart..<closingRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !buffer.isEmpty {
                        sections.append(.markdown(buffer))
                        buffer = ""
                    }

                    if !mathContent.isEmpty {
                        sections.append(.mathBlock(mathContent))
                    }

                    index = closingRange.upperBound
                    continue
                }
            }

            buffer.append(normalized[index])
            index = normalized.index(after: index)
        }

        if !buffer.isEmpty {
            sections.append(.markdown(buffer))
        }

        return sections.isEmpty ? [.markdown(source)] : sections
    }

    static func attributedMarkdown(from source: String) -> AttributedString? {
        let processed = convertInlineMathToMarkdownCode(in: source)
        return try? AttributedString(markdown: processed)
    }

    private static func normalizeMathDelimiters(in source: String) -> String {
        source
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
    }

    private static func convertInlineMathToMarkdownCode(in source: String) -> String {
        var result = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "$" {
                let next = source.index(after: index)

                if next < source.endIndex,
                   source[next] != "$",
                   let closing = source[next...].firstIndex(of: "$") {
                    let candidate = String(source[next..<closing])
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmed.isEmpty && !candidate.contains("\n") {
                        result += "`\(candidate)`"
                        index = source.index(after: closing)
                        continue
                    }
                }
            }

            result.append(source[index])
            index = source.index(after: index)
        }

        return result
    }
}

enum MathMarkdownHTMLRenderer {
    static func containsMath(in source: String) -> Bool {
        let normalized = source
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")

        return normalized.contains("$$") || normalized.contains("$")
    }

    static func document(for source: String) -> String {
        let normalized = normalizeDelimiters(in: source)
        var placeholders: [String: String] = [:]
        let withDisplay = replaceDisplayMath(in: normalized, placeholders: &placeholders)
        let withInline = replaceInlineMath(in: withDisplay, placeholders: &placeholders)
        let htmlBody = restorePlaceholders(in: renderTextHTML(from: withInline), placeholders: placeholders)

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
          <style>
            :root { color-scheme: light dark; }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              color: CanvasText;
              font: 14px -apple-system, BlinkMacSystemFont, sans-serif;
              line-height: 1.45;
              overflow: hidden;
            }
            p { margin: 0 0 0.55em 0; }
            p:last-child { margin-bottom: 0; }
            ul { margin: 0.2em 0 0.55em 1.2em; padding: 0; }
            li { margin: 0.12em 0; }
            strong { font-weight: 650; }
            code {
              font: 13px Menlo, Monaco, monospace;
              background: rgba(127, 127, 127, 0.12);
              border-radius: 4px;
              padding: 1px 4px;
            }
            .math-block {
              margin: 0.45em 0;
              overflow-x: auto;
              overflow-y: hidden;
            }
          </style>
          <script>
            window.MathJax = {
              tex: {
                inlineMath: [['\\(','\\)']],
                displayMath: [['\\[','\\]']]
              },
              options: { skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre'] },
              startup: {
                pageReady: () => {
                  return MathJax.startup.defaultPageReady().then(() => {
                    setTimeout(reportHeight, 50);
                  });
                }
              }
            };

            function reportHeight() {
              const height = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightUpdated) {
                window.webkit.messageHandlers.heightUpdated.postMessage(height);
              }
            }

            window.addEventListener('load', () => setTimeout(reportHeight, 50));
          </script>
          <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
        </head>
        <body>
          \(htmlBody)
        </body>
        </html>
        """
    }

    private static func normalizeDelimiters(in source: String) -> String {
        source
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
    }

    private static func replaceDisplayMath(in source: String, placeholders: inout [String: String]) -> String {
        var result = ""
        var index = source.startIndex
        var counter = 0

        while index < source.endIndex {
            let remaining = source[index...]
            if remaining.hasPrefix("$$") {
                let start = source.index(index, offsetBy: 2)
                if let endRange = source[start...].range(of: "$$") {
                    let content = String(source[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let token = "@@DISPLAY_\(counter)@@"
                    placeholders[token] = "<div class=\"math-block\">\\[\(escapeHTML(content))\\]</div>"
                    result += "\n\(token)\n"
                    counter += 1
                    index = endRange.upperBound
                    continue
                }
            }

            result.append(source[index])
            index = source.index(after: index)
        }

        return result
    }

    private static func replaceInlineMath(in source: String, placeholders: inout [String: String]) -> String {
        var result = ""
        var index = source.startIndex
        var counter = placeholders.count

        while index < source.endIndex {
            if source[index] == "$" {
                let start = source.index(after: index)
                if start < source.endIndex,
                   source[start] != "$",
                   let end = source[start...].firstIndex(of: "$") {
                    let content = String(source[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty && !content.contains("\n") {
                        let token = "@@INLINE_\(counter)@@"
                        placeholders[token] = "<span class=\"math-inline\">\\(\(escapeHTML(content))\\)</span>"
                        result += token
                        counter += 1
                        index = source.index(after: end)
                        continue
                    }
                }
            }

            result.append(source[index])
            index = source.index(after: index)
        }

        return result
    }

    private static func renderTextHTML(from source: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        var html = ""
        var listItems: [String] = []

        func flushList() {
            guard !listItems.isEmpty else { return }
            html += "<ul>" + listItems.map { "<li>\($0)</li>" }.joined() + "</ul>"
            listItems.removeAll()
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushList()
                continue
            }

            if trimmed.hasPrefix("@@DISPLAY_") {
                flushList()
                html += trimmed
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2))
                listItems.append(applyInlineMarkup(to: escapeHTML(content)))
            } else {
                flushList()
                html += "<p>\(applyInlineMarkup(to: escapeHTML(trimmed)))</p>"
            }
        }

        flushList()
        return html
    }

    private static func applyInlineMarkup(to escaped: String) -> String {
        var html = escaped

        html = html.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )

        return html
    }

    private static func restorePlaceholders(in source: String, placeholders: [String: String]) -> String {
        placeholders.reduce(source) { partial, entry in
            partial.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }

    private static func escapeHTML(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
