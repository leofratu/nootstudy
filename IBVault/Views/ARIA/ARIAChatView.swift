import Foundation
import SwiftData
import SwiftUI
import WebKit

struct ARIAChatView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    @State private var ariaService = ARIAService()
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var showMemory = false
    @State private var errorMessage: String?
    @State private var pendingScrollTarget: AnyHashable?

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
                    .onChange(of: messages.last?.id) { _, newValue in
                        guard let newValue else { return }
                        pendingScrollTarget = AnyHashable(newValue)
                    }
                    .onChange(of: streamingText.count) { _, newValue in
                        guard ariaService.isLoading, newValue > 0 else { return }
                        pendingScrollTarget = AnyHashable("streaming")
                    }
                    .task(id: pendingScrollTarget) {
                        guard let pendingScrollTarget else { return }
                        await Task.yield()
                        withAnimation {
                            proxy.scrollTo(pendingScrollTarget, anchor: .bottom)
                        }
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
            onToken: { partial in streamingText = partial },
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

                FormattedMessageContent(text: message.content, preferRichRendering: !isUser)
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
                FormattedMessageContent(text: text, preferRichRendering: true)
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
    var preferRichRendering = false

    private var sections: [FormattedMessageSection] {
        FormattedMessageFormatter.sections(from: text)
    }

    private var canUseRichRenderer: Bool {
        preferRichRendering && Bundle.main.url(forResource: "MathJax", withExtension: nil) != nil
    }

    var body: some View {
        Group {
            if canUseRichRenderer {
                ARIALocalRichMessageContainer(text: text)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        sectionView(section)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionView(_ section: FormattedMessageSection) -> some View {
        switch section {
        case .markdown(let markdown):
            if let attributed = FormattedMessageFormatter.attributedMarkdown(from: markdown) {
                Text(attributed)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(markdown)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .mathBlock(let latex):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: MathExpressionFormatter.displayString(from: latex))
                    .font(.system(size: 16, weight: .medium, design: .serif))
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

        case .flashcard(let front, let back):
            FlashcardMessageView(front: front, back: back)
        }
    }
}

private struct ARIALocalRichMessageContainer: View {
    let text: String
    @State private var height: CGFloat = 24

    private var baseURL: URL? {
        Bundle.main.url(forResource: "MathJax", withExtension: nil)
    }

    var body: some View {
        if let baseURL {
            ARIALocalRichMessageWebView(
                html: ARIARichMessageHTMLRenderer.document(for: text),
                baseURL: baseURL,
                height: $height
            )
            .frame(height: max(height, 24))
        } else {
            Text(FormattedMessageFormatter.attributedMarkdown(from: text) ?? AttributedString(text))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ARIALocalRichMessageWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "renderHeight")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.isInspectable = false
        webView.enclosingScrollView?.drawsBackground = false
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderHeight")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var lastHTML = ""

        init(height: Binding<CGFloat>) {
            self._height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { value, _ in
                guard let number = value as? NSNumber else { return }
                DispatchQueue.main.async {
                    self.height = max(CGFloat(number.doubleValue), 24)
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "renderHeight" else { return }
            if let value = message.body as? NSNumber {
                DispatchQueue.main.async {
                    self.height = max(CGFloat(value.doubleValue), 24)
                }
            }
        }
    }
}

private enum ARIARichMessageHTMLRenderer {
    static func document(for source: String) -> String {
        let body = FormattedMessageFormatter.sections(from: source)
            .map(renderSection(_:))
            .joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: light dark;
              --text: rgba(28, 28, 30, 0.96);
              --muted: rgba(60, 60, 67, 0.72);
              --line: rgba(60, 60, 67, 0.12);
              --surface: rgba(127, 127, 127, 0.06);
              --surface-strong: rgba(127, 127, 127, 0.1);
              --blue: #2f80ed;
              --green: #27ae60;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --text: rgba(255, 255, 255, 0.94);
                --muted: rgba(235, 235, 245, 0.68);
                --line: rgba(255, 255, 255, 0.12);
                --surface: rgba(255, 255, 255, 0.05);
                --surface-strong: rgba(255, 255, 255, 0.08);
              }
            }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
            }
            body {
              color: var(--text);
              font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              -webkit-font-smoothing: antialiased;
              word-wrap: break-word;
              overflow-wrap: anywhere;
            }
            .content > *:first-child { margin-top: 0; }
            .content > *:last-child { margin-bottom: 0; }
            p, ul, ol, .flashcard, .math-block {
              margin: 0 0 12px 0;
            }
            h3 {
              margin: 18px 0 8px;
              font-size: 13px;
              line-height: 1.3;
              letter-spacing: 0.08em;
              text-transform: uppercase;
              color: var(--muted);
            }
            ul, ol {
              padding-left: 20px;
            }
            li + li {
              margin-top: 6px;
            }
            strong {
              font-weight: 700;
            }
            code {
              font: 13px/1.4 SFMono-Regular, Menlo, monospace;
              background: var(--surface);
              border-radius: 6px;
              padding: 2px 5px;
            }
            .flashcard {
              border: 1px solid var(--line);
              border-radius: 14px;
              background: var(--surface);
              padding: 12px;
            }
            .flashcard-side + .flashcard-side {
              margin-top: 10px;
            }
            .flashcard-label {
              display: flex;
              align-items: center;
              gap: 8px;
              margin-bottom: 6px;
              font-size: 12px;
              font-weight: 700;
              letter-spacing: 0.08em;
              text-transform: uppercase;
            }
            .flashcard-label.front { color: var(--blue); }
            .flashcard-label.back { color: var(--green); }
            .flashcard-body {
              background: var(--surface-strong);
              border-radius: 10px;
              padding: 10px 12px;
            }
            .math-block {
              overflow-x: auto;
              border: 1px solid var(--line);
              border-radius: 12px;
              background: var(--surface);
              padding: 12px;
            }
            .math-block mjx-container {
              margin: 0 !important;
            }
          </style>
          <script>
            window.MathJax = {
              tex: {
                inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                packages: {'[+]': ['ams', 'mathtools', 'physics', 'mhchem', 'bussproofs']},
                processEscapes: true
              },
              svg: { fontCache: 'none' },
              startup: { typeset: false }
            };

            function sendHeight() {
              const height = Math.max(
                document.documentElement.scrollHeight,
                document.body.scrollHeight
              );
              if (window.webkit?.messageHandlers?.renderHeight) {
                window.webkit.messageHandlers.renderHeight.postMessage(height);
              }
            }

            async function renderARIA() {
              try {
                if (window.MathJax?.startup?.promise) {
                  await window.MathJax.startup.promise;
                }
                if (window.MathJax?.typesetPromise) {
                  await window.MathJax.typesetPromise();
                }
              } catch (error) {
                console.error(error);
              }
              requestAnimationFrame(() => setTimeout(sendHeight, 0));
            }

            window.addEventListener('load', renderARIA);
            window.addEventListener('resize', sendHeight);
          </script>
          <script defer src="tex-svg.js"></script>
        </head>
        <body>
          <div class="content">\(body)</div>
        </body>
        </html>
        """
    }

    private static func renderSection(_ section: FormattedMessageSection) -> String {
        switch section {
        case .markdown(let markdown):
            return renderMarkdownBlocks(markdown)
        case .mathBlock(let latex):
            return "<div class=\"math-block\">$$\(escapeHTML(latex))$$</div>"
        case .flashcard(let front, let back):
            return """
            <section class="flashcard">
              <div class="flashcard-side">
                <div class="flashcard-label front">Front</div>
                <div class="flashcard-body">\(renderInline(front))</div>
              </div>
              <div class="flashcard-side">
                <div class="flashcard-label back">Back</div>
                <div class="flashcard-body">\(renderInline(back))</div>
              </div>
            </section>
            """
        }
    }

    private static func renderMarkdownBlocks(_ source: String) -> String {
        source
            .components(separatedBy: "\n\n")
            .map { block in
                let lines = block
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard !lines.isEmpty else { return "" }

                if lines.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("* ") }) {
                    let items = lines.map {
                        "<li>\(renderInline(String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)))</li>"
                    }.joined()
                    return "<ul>\(items)</ul>"
                }

                if lines.allSatisfy(isOrderedListItem(_:)) {
                    let items = lines.map { line in
                        let content = line.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                        return "<li>\(renderInline(content))</li>"
                    }.joined()
                    return "<ol>\(items)</ol>"
                }

                if let first = lines.first, first.hasPrefix("### ") {
                    let heading = "<h3>\(renderInline(String(first.dropFirst(4))))</h3>"
                    let remainder = Array(lines.dropFirst())
                    if remainder.isEmpty {
                        return heading
                    }
                    return heading + "<p>\(renderInline(remainder.joined(separator: " ")))</p>"
                }

                return "<p>\(renderInline(lines.joined(separator: " ")))</p>"
            }
            .joined(separator: "\n")
    }

    private static func renderInline(_ source: String) -> String {
        let placeholders = preserveMath(in: source)
        var rendered = escapeHTML(placeholders.text)
        rendered = replaceRegex(pattern: #"`([^`\n]+)`"#, template: "<code>$1</code>", in: rendered)
        rendered = replaceRegex(pattern: #"\*\*([^\*\n]+)\*\*"#, template: "<strong>$1</strong>", in: rendered)
        rendered = replaceRegex(pattern: #"(?<!\*)\*([^\*\n]+)\*(?!\*)"#, template: "<em>$1</em>", in: rendered)

        for (placeholder, math) in placeholders.tokens {
            rendered = rendered.replacingOccurrences(of: placeholder, with: math)
        }

        return rendered
    }

    private static func preserveMath(in source: String) -> (text: String, tokens: [String: String]) {
        var result = ""
        var tokens: [String: String] = [:]
        var index = source.startIndex
        var counter = 0

        while index < source.endIndex {
            if source[index] == "$" {
                let next = source.index(after: index)
                if next < source.endIndex, source[next] != "$",
                   let closing = source[next...].firstIndex(of: "$") {
                    let raw = String(source[index...closing])
                    let placeholder = "__ARIA_MATH_\(counter)__"
                    tokens[placeholder] = escapeHTML(raw)
                    result += placeholder
                    counter += 1
                    index = source.index(after: closing)
                    continue
                }
            }

            result.append(source[index])
            index = source.index(after: index)
        }

        return (result, tokens)
    }

    private static func replaceRegex(pattern: String, template: String, in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    private static func escapeHTML(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }
}

enum FormattedMessageSection {
    case markdown(String)
    case mathBlock(String)
    case flashcard(front: String, back: String)
}

private struct FlashcardMessageView: View {
    let front: String
    let back: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            flashcardSide(
                label: "Front",
                icon: "questionmark.circle.fill",
                tint: IBColors.electricBlue,
                text: front
            )

            flashcardSide(
                label: "Back",
                icon: "checkmark.seal.fill",
                tint: IBColors.success,
                text: back
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func flashcardSide(label: String, icon: String, tint: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                Spacer()
            }

            Text(FormattedMessageFormatter.attributedMarkdown(from: text) ?? AttributedString(text))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(0.08))
                )
        }
    }
}

enum FormattedMessageFormatter {
    static func sections(from source: String) -> [FormattedMessageSection] {
        let normalized = normalizeResponseText(source)
        var sections: [FormattedMessageSection] = []
        var markdownLines: [String] = []
        var frontLines: [String] = []
        var backLines: [String] = []

        enum ParseMode {
            case markdown
            case flashcardFront
            case flashcardBack
        }

        var mode: ParseMode = .markdown

        func appendMarkdownBuffer() {
            let markdown = markdownLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else {
                markdownLines.removeAll()
                return
            }
            appendMathAwareSections(from: markdown, into: &sections)
            markdownLines.removeAll()
        }

        func appendFlashcardBuffer() {
            let front = frontLines.joined(separator: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let back = backLines.joined(separator: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !front.isEmpty && !back.isEmpty {
                sections.append(.flashcard(front: front, back: back))
            } else {
                let fallback = ([front, back].filter { !$0.isEmpty }).joined(separator: "\n")
                if !fallback.isEmpty {
                    appendMathAwareSections(from: fallback, into: &sections)
                }
            }

            frontLines.removeAll()
            backLines.removeAll()
        }

        for line in normalized.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            switch mode {
            case .markdown:
                if trimmed.hasPrefix("FRONT:") {
                    appendMarkdownBuffer()
                    frontLines = [String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)]
                    mode = .flashcardFront
                } else {
                    markdownLines.append(line)
                }

            case .flashcardFront:
                if trimmed.hasPrefix("BACK:") {
                    backLines = [String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)]
                    mode = .flashcardBack
                } else if trimmed.hasPrefix("FRONT:") {
                    appendFlashcardBuffer()
                    frontLines = [String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)]
                    mode = .flashcardFront
                } else if trimmed.hasPrefix("### ") {
                    appendFlashcardBuffer()
                    markdownLines.append(line)
                    mode = .markdown
                } else if !trimmed.isEmpty {
                    frontLines.append(trimmed)
                }

            case .flashcardBack:
                if trimmed.hasPrefix("FRONT:") {
                    appendFlashcardBuffer()
                    frontLines = [String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)]
                    mode = .flashcardFront
                } else if trimmed.hasPrefix("### ") {
                    appendFlashcardBuffer()
                    markdownLines.append(line)
                    mode = .markdown
                } else if !trimmed.isEmpty {
                    backLines.append(trimmed)
                }
            }
        }

        switch mode {
        case .markdown:
            appendMarkdownBuffer()
        case .flashcardFront, .flashcardBack:
            appendFlashcardBuffer()
        }

        return sections.isEmpty ? [.markdown(normalized)] : sections
    }

    static func attributedMarkdown(from source: String) -> AttributedString? {
        let processed = convertInlineMathToReadableText(in: source)
        return try? AttributedString(markdown: processed)
    }

    private static func normalizeResponseText(_ source: String) -> String {
        var result = source.replacingOccurrences(of: "\r\n", with: "\n")
        result = normalizeMathDelimiters(in: result)
        result = replaceRegex(pattern: #"[-—]{3,}\s*(FRONT:|BACK:)"#, template: "\n\n$1", in: result)
        result = replaceRegex(pattern: #"(?<=[.!?])(?=[A-Z])"#, template: " ", in: result)
        result = replaceRegex(pattern: #"(?<=[^\n])\s*(FRONT:)"#, template: "\n\n$1", in: result)
        result = replaceRegex(pattern: #"(?<=[^\n])\s*(BACK:)"#, template: "\n$1", in: result)
        result = replaceRegex(
            pattern: #"(?i)why it(?:’|')s critical for [^:]+:\s*"#,
            template: "\n\n### Why It Matters\n",
            in: result
        )
        result = replaceRegex(
            pattern: #"(?i)how did you go\?\s*"#,
            template: "\n\n### Check-in\nHow did you go?\n",
            in: result
        )
        result = replaceRegex(pattern: #"\n{3,}"#, template: "\n\n", in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeMathDelimiters(in source: String) -> String {
        source
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
    }

    private static func appendMathAwareSections(from source: String, into sections: inout [FormattedMessageSection]) {
        var buffer = ""
        var index = source.startIndex

        while index < source.endIndex {
            let remaining = source[index...]

            if remaining.hasPrefix("$$") {
                let contentStart = source.index(index, offsetBy: 2)

                if let closingRange = source[contentStart...].range(of: "$$") {
                    let mathContent = String(source[contentStart..<closingRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    let markdown = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !markdown.isEmpty {
                        sections.append(.markdown(markdown))
                    }
                    buffer = ""

                    if !mathContent.isEmpty {
                        sections.append(.mathBlock(mathContent))
                    }

                    index = closingRange.upperBound
                    continue
                }
            }

            buffer.append(source[index])
            index = source.index(after: index)
        }

        let markdown = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !markdown.isEmpty {
            sections.append(.markdown(markdown))
        }
    }

    private static func convertInlineMathToReadableText(in source: String) -> String {
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
                        result += MathExpressionFormatter.inlineString(from: candidate)
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

    private static func replaceRegex(pattern: String, template: String, in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }
}

enum MathExpressionFormatter {
    private static let commandMap: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ϵ",
        "\\theta": "θ", "\\lambda": "λ", "\\mu": "μ", "\\pi": "π", "\\sigma": "σ",
        "\\phi": "φ", "\\omega": "ω", "\\Delta": "Δ", "\\Gamma": "Γ", "\\Lambda": "Λ",
        "\\Pi": "Π", "\\Sigma": "Σ", "\\Omega": "Ω", "\\times": "×", "\\cdot": "·",
        "\\pm": "±", "\\neq": "≠", "\\leq": "≤", "\\geq": "≥", "\\approx": "≈",
        "\\infty": "∞", "\\to": "→", "\\rightarrow": "→", "\\left": "", "\\right": "",
        "\\sum": "Σ", "\\prod": "∏", "\\int": "∫", "\\cdots": "⋯", "\\ldots": "…",
        "\\sin": "sin", "\\cos": "cos", "\\tan": "tan", "\\sec": "sec", "\\csc": "csc",
        "\\cot": "cot", "\\log": "log", "\\ln": "ln",
        "\\lim": "lim"
    ]

    private static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"
    ]

    private static let subscripts: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ",
        "u": "ᵤ", "v": "ᵥ", "x": "ₓ"
    ]

    static func inlineString(from source: String) -> String {
        prettified(source)
    }

    static func displayString(from source: String) -> String {
        prettified(source)
    }

    private static func prettified(_ source: String) -> String {
        var result = source.trimmingCharacters(in: .whitespacesAndNewlines)

        result = replaceBinaryCommand("\\frac", in: result) { lhs, rhs in
            formatFraction(lhs: lhs, rhs: rhs)
        }
        result = replaceBinaryCommand("\\dfrac", in: result) { lhs, rhs in
            formatFraction(lhs: lhs, rhs: rhs)
        }
        result = replaceBinaryCommand("\\tfrac", in: result) { lhs, rhs in
            formatFraction(lhs: lhs, rhs: rhs)
        }
        result = replaceUnaryCommand("\\sqrt", in: result) { value in
            "√(\(value))"
        }
        result = replaceUnaryCommand("\\text", in: result) { $0 }
        result = replaceUnaryCommand("\\mathrm", in: result) { $0 }
        result = replaceUnaryCommand("\\operatorname", in: result) { $0 }

        for (command, symbol) in commandMap {
            result = result.replacingOccurrences(of: command, with: symbol)
        }

        result = result
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\\", with: "")

        result = applyScript(marker: "^", mapping: superscripts, to: result)
        result = applyScript(marker: "_", mapping: subscripts, to: result)

        return result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceUnaryCommand(_ command: String, in source: String, transform: (String) -> String) -> String {
        replaceRegex(pattern: "\\\\\(command.dropFirst())\\{([^{}]+)\\}", in: source) { match in
            let rawValue = match.numberOfRanges > 1 ? nsRange(match.range(at: 1), in: source).flatMap { Range($0, in: source) }.map { String(source[$0]) } : nil
            return transform(prettified(rawValue ?? ""))
        }
    }

    private static func replaceBinaryCommand(_ command: String, in source: String, transform: (String, String) -> String) -> String {
        replaceRegex(pattern: "\\\\\(command.dropFirst())\\{([^{}]+)\\}\\{([^{}]+)\\}", in: source) { match in
            let lhs = match.numberOfRanges > 1 ? nsRange(match.range(at: 1), in: source).flatMap { Range($0, in: source) }.map { String(source[$0]) } ?? "" : ""
            let rhs = match.numberOfRanges > 2 ? nsRange(match.range(at: 2), in: source).flatMap { Range($0, in: source) }.map { String(source[$0]) } ?? "" : ""
            return transform(prettified(lhs), prettified(rhs))
        }
    }

    private static func replaceRegex(pattern: String, in source: String, replacement: (NSTextCheckingResult) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard !matches.isEmpty else { return source }

        var result = source
        for match in matches.reversed() {
            let replacementText = replacement(match)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacementText)
            }
        }
        return result == source ? source : replaceRegex(pattern: pattern, in: result, replacement: replacement)
    }

    private static func applyScript(marker: Character, mapping: [Character: String], to source: String) -> String {
        var result = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == marker {
                let next = source.index(after: index)
                guard next < source.endIndex else {
                    index = next
                    continue
                }

                if source[next] == "{" {
                    if let closing = source[next...].firstIndex(of: "}") {
                        let content = source[source.index(after: next)..<closing]
                        let rendered = content.compactMap { mapping[$0] ?? String($0) }.joined()
                        result += rendered
                        index = source.index(after: closing)
                        continue
                    }
                } else {
                    let rendered = mapping[source[next]] ?? String(source[next])
                    result += rendered
                    index = source.index(after: next)
                    continue
                }
            }

            result.append(source[index])
            index = source.index(after: index)
        }

        return result
    }

    private static func nsRange(_ range: NSRange, in source: String) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }

    private static func formatFraction(lhs: String, rhs: String) -> String {
        let numerator = needsGrouping(lhs) ? "(\(lhs))" : lhs
        let denominator = needsGrouping(rhs) ? "(\(rhs))" : rhs
        return "\(numerator)/\(denominator)"
    }

    private static func needsGrouping(_ expression: String) -> Bool {
        expression.contains(where: { "+-= ".contains($0) })
    }
}
