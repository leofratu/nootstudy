import Foundation
import SwiftUI

// MARK: - Section Model

nonisolated enum FormattedMessageSection: Equatable, Sendable {
    case heading(level: Int, text: String)
    case markdown(String)
    case listItem(marker: String, text: String)
    case quote(String)
    case divider
    case mathBlock(String)
    case codeBlock(code: String, language: String)
    case diagram(ARIADiagramSpec)
    case flashcard(front: String, back: String)
}

// MARK: - Formatter

nonisolated enum FormattedMessageFormatter: Sendable {

    // MARK: Precompiled regexes

    nonisolated static let frontBackDashRegex = try! NSRegularExpression(pattern: #"[-—]{3,}\s*(FRONT:|BACK:)"#)
    nonisolated static let headingMissingSpaceRegex = try! NSRegularExpression(pattern: #"(?m)^(#{1,6})([^ #\n])"#)
    nonisolated static let headingPrefixNewlineRegex = try! NSRegularExpression(pattern: #"(?m)(?<!\n)(#{1,6}\s)"#)
    nonisolated static let emptyHeadingRegex = try! NSRegularExpression(pattern: #"(?m)^\s*#{1,6}\s*$"#)
    nonisolated static let emptyBulletRegex = try! NSRegularExpression(pattern: #"(?m)^\s*(?:[-*•]|\d+[.)])\s*$"#)
    nonisolated static let frontInlineRegex = try! NSRegularExpression(pattern: #"(?<=[^\n])\s*(FRONT:)"#)
    nonisolated static let backInlineRegex = try! NSRegularExpression(pattern: #"(?<=[^\n])\s*(BACK:)"#)
    nonisolated static let consecutiveHeadingRegex = try! NSRegularExpression(pattern: #"(?m)^(#{1,6}\s+.+)\n(#{1,6}\s+.+)$"#)
    nonisolated static let tripleNewlineRegex = try! NSRegularExpression(pattern: #"\n{3,}"#)
    nonisolated static let bulletPrefixRegex = try! NSRegularExpression(pattern: #"^[\-\*\•]\s*"#)
    nonisolated static let numberedPrefixRegex = try! NSRegularExpression(pattern: #"^\d+[\.\)]\s*"#)
    nonisolated static let cardPrefixRegex = try! NSRegularExpression(pattern: #"(?i)^card\s*\d+\s*[:\-\.\)]\s*"#)

    // MARK: Public API

    nonisolated static func sections(from source: String) -> [FormattedMessageSection] {
        let normalized = normalizeResponseText(source)
        var sections: [FormattedMessageSection] = []
        var markdownLines: [String] = []
        var frontLines: [String] = []
        var backLines: [String] = []
        var codeBlockLines: [String] = []
        var codeBlockLanguage = ""

        enum ParseMode {
            case markdown
            case flashcardFront
            case flashcardBack
            case codeBlock
        }

        var mode: ParseMode = .markdown

        func appendMarkdownBuffer() {
            let markdown = markdownLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else {
                markdownLines.removeAll()
                return
            }
            appendStructuredMarkdownSections(from: markdown, into: &sections)
            markdownLines.removeAll()
        }

        func appendFlashcardBuffer() {
            let front = frontLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let back = backLines.joined(separator: "\n")
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

        func appendCodeBlockBuffer() {
            let code = codeBlockLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty {
                if let diagram = diagramSpec(from: code, language: codeBlockLanguage) {
                    sections.append(.diagram(diagram))
                } else {
                    sections.append(.codeBlock(code: code, language: codeBlockLanguage))
                }
            }
            codeBlockLines.removeAll()
            codeBlockLanguage = ""
        }

        let lines = normalized.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("```") {
                if mode == .codeBlock {
                    appendCodeBlockBuffer()
                    mode = .markdown
                } else {
                    appendMarkdownBuffer()
                    codeBlockLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeBlockLines.removeAll()
                    mode = .codeBlock
                }
                i += 1
                continue
            }

            switch mode {
            case .codeBlock:
                codeBlockLines.append(line)
            case .markdown:
                if let frontPayload = flashcardPayload(in: trimmed, marker: "FRONT") {
                    appendMarkdownBuffer()
                    frontLines = [frontPayload]
                    mode = .flashcardFront
                } else {
                    markdownLines.append(line)
                }
            case .flashcardFront:
                if let backPayload = flashcardPayload(in: trimmed, marker: "BACK") {
                    backLines = [backPayload]
                    mode = .flashcardBack
                } else if let frontPayload = flashcardPayload(in: trimmed, marker: "FRONT") {
                    appendFlashcardBuffer()
                    frontLines = [frontPayload]
                    mode = .flashcardFront
                } else if isMarkdownHeader(trimmed) {
                    appendFlashcardBuffer()
                    markdownLines.append(line)
                    mode = .markdown
                } else if !trimmed.isEmpty {
                    frontLines.append(trimmed)
                }
            case .flashcardBack:
                if let frontPayload = flashcardPayload(in: trimmed, marker: "FRONT") {
                    appendFlashcardBuffer()
                    frontLines = [frontPayload]
                    mode = .flashcardFront
                } else if isMarkdownHeader(trimmed) {
                    appendFlashcardBuffer()
                    markdownLines.append(line)
                    mode = .markdown
                } else if !trimmed.isEmpty {
                    backLines.append(trimmed)
                }
            }
            i += 1
        }

        switch mode {
        case .markdown:
            appendMarkdownBuffer()
        case .flashcardFront, .flashcardBack:
            appendFlashcardBuffer()
        case .codeBlock:
            appendCodeBlockBuffer()
        }

        if !sections.contains(where: {
            if case .diagram = $0 { return true }
            return false
        }), let inferredSimulation = fallbackSimulation(for: normalized) {
            sections.append(.diagram(inferredSimulation))
        }

        return sections.isEmpty ? [.markdown(normalized)] : sections
    }

    nonisolated static func attributedMarkdown(from source: String) -> AttributedString? {
        let processed = displayFriendlyMarkdown(
            normalizeResponseText(convertInlineMathToReadableText(in: source))
        )
        let options = AttributedString.MarkdownParsingOptions()
        return try? AttributedString(markdown: processed, options: options)
    }

    // MARK: Normalization

    nonisolated static func normalizeResponseText(_ source: String) -> String {
        var result = source.replacingOccurrences(of: "\r\n", with: "\n")
        // NBSP -> space (P0 text correctness)
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")
        result = normalizeMathDelimiters(in: result)
        result = replaceRegex(frontBackDashRegex, template: "\n\n$1", in: result)
        result = replaceRegex(headingMissingSpaceRegex, template: "$1 $2", in: result)
        result = replaceRegex(headingPrefixNewlineRegex, template: "\n\n$1", in: result)
        result = replaceRegex(emptyHeadingRegex, template: "", in: result)
        result = replaceRegex(emptyBulletRegex, template: "", in: result)
        result = replaceRegex(frontInlineRegex, template: "\n\n$1", in: result)
        result = replaceRegex(backInlineRegex, template: "\n$1", in: result)
        result = replaceRegex(consecutiveHeadingRegex, template: "$1\n\n$2", in: result)
        result = collapseNewlinesPreservingCodeBlocks(in: result)
        result = replaceRegex(tripleNewlineRegex, template: "\n\n", in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func canonicalDisplayLatex(_ source: String) -> String {
        var value = source.replacingOccurrences(of: "\u{00A0}", with: " ")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for delimiters in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)")] {
            if value.hasPrefix(delimiters.0), value.hasSuffix(delimiters.1), value.count >= delimiters.0.count + delimiters.1.count {
                value.removeFirst(delimiters.0.count)
                value.removeLast(delimiters.1.count)
                break
            }
        }
        return value
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func displayFriendlyMarkdown(_ source: String) -> String {
        MessageRenderingPolicy.displaySafeMarkdown(source)
    }

    // MARK: Structured markdown

    private nonisolated static func appendStructuredMarkdownSections(
        from markdown: String,
        into sections: inout [FormattedMessageSection]
    ) {
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                appendMathAwareSections(from: paragraph, into: &sections)
            }
            paragraphLines.removeAll()
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = heading(from: trimmed) {
                flushParagraph()
                sections.append(.heading(level: heading.level, text: heading.text))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                sections.append(.divider)
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                sections.append(.quote(String(trimmed.dropFirst(2))))
            } else if let item = listItem(from: trimmed) {
                flushParagraph()
                sections.append(.listItem(marker: item.marker, text: item.text))
            } else {
                paragraphLines.append(line)
            }
        }

        flushParagraph()
    }

    private nonisolated static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let remainder = line.dropFirst(hashes.count)
        guard remainder.first?.isWhitespace == true else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (hashes.count, text)
    }

    private nonisolated static func listItem(from line: String) -> (marker: String, text: String)? {
        for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) {
            let text = String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ("•", text)
        }

        let components = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard components.count == 2 else { return nil }
        let marker = String(components[0])
        let number = marker.dropLast()
        guard (marker.hasSuffix(".") || marker.hasSuffix(")")),
              Int(number) != nil else {
            return nil
        }
        let text = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (marker, text)
    }

    private nonisolated static func collapseNewlinesPreservingCodeBlocks(in source: String) -> String {
        var result = ""
        var inCodeBlock = false
        var consecutiveNewlines = 0

        for char in source {
            if char == "`" {
                let lastThree = result.suffix(2)
                if lastThree == "``" {
                    inCodeBlock.toggle()
                    result.append(char)
                    consecutiveNewlines = 0
                    continue
                }
            }

            if char == "\n" {
                if inCodeBlock {
                    result.append(char)
                    consecutiveNewlines = 0
                } else {
                    consecutiveNewlines += 1
                    if consecutiveNewlines <= 2 {
                        result.append(char)
                    }
                }
            } else {
                consecutiveNewlines = 0
                result.append(char)
            }
        }

        return result
    }

    private nonisolated static func normalizeMathDelimiters(in source: String) -> String {
        source
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
    }

    private nonisolated static func appendMathAwareSections(from source: String, into sections: inout [FormattedMessageSection]) {
        let paragraphs = source.components(separatedBy: "\n\n")

        for paragraph in paragraphs {
            let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedParagraph.isEmpty else { continue }

            if trimmedParagraph.hasPrefix("```") {
                if let codeBlock = parseCodeBlock(from: trimmedParagraph) {
                    sections.append(.codeBlock(code: codeBlock.code, language: codeBlock.language))
                    continue
                }
            }

            if trimmedParagraph.contains("$") {
                var buffer = ""
                var index = trimmedParagraph.startIndex

                while index < trimmedParagraph.endIndex {
                    let remaining = trimmedParagraph[index...]
                    let delimiter: String?
                    if remaining.hasPrefix("$$"), !isEscapedDelimiter(at: index, in: trimmedParagraph) {
                        delimiter = "$$"
                    } else if remaining.hasPrefix("$"), !isEscapedDelimiter(at: index, in: trimmedParagraph) {
                        delimiter = "$"
                    } else {
                        delimiter = nil
                    }

                    if let delimiter {
                        let contentStart = trimmedParagraph.index(index, offsetBy: delimiter.count)

                        if let closingRange = nextMathDelimiter(
                            delimiter,
                            in: trimmedParagraph,
                            from: contentStart
                        ) {
                            let mathContent = String(trimmedParagraph[contentStart..<closingRange.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            // Inline math must not span lines and must be non-empty; otherwise treat delimiter as literal
                            if delimiter == "$" {
                                if mathContent.isEmpty || mathContent.contains("\n") {
                                    buffer.append(trimmedParagraph[index])
                                    index = trimmedParagraph.index(after: index)
                                    continue
                                }
                                // Require closing delimiter not to be followed immediately by digit (avoid $5 case swallowing)
                                // But we treat anyway; if mathContent is just number, still render inline.
                                if !mathContent.isEmpty {
                                    buffer += MathRenderingPolicy.inlineText(mathContent)
                                }
                            } else {
                                let markdown = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !markdown.isEmpty {
                                    sections.append(.markdown(markdown))
                                }
                                buffer = ""

                                if !mathContent.isEmpty {
                                    sections.append(.mathBlock(mathContent))
                                }
                            }

                            index = closingRange.upperBound
                            continue
                        } else {
                            // Unclosed delimiter -> treat as literal without swallowing
                            buffer.append(trimmedParagraph[index])
                            index = trimmedParagraph.index(after: index)
                            continue
                        }
                    }

                    buffer.append(trimmedParagraph[index])
                    index = trimmedParagraph.index(after: index)
                }

                let markdown = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !markdown.isEmpty {
                    sections.append(.markdown(markdown))
                }
            } else {
                sections.append(.markdown(trimmedParagraph))
            }
        }
    }

    private nonisolated static func nextMathDelimiter(
        _ delimiter: String,
        in source: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var index = start
        while index < source.endIndex {
            let remaining = source[index...]
            let isSingleDollarInsideDisplayMath = delimiter == "$" && remaining.hasPrefix("$$")
            if remaining.hasPrefix(delimiter),
               !isSingleDollarInsideDisplayMath,
               !isEscapedDelimiter(at: index, in: source) {
                // For inline $, ensure content between start and this delimiter does not contain newline
                if delimiter == "$" {
                    let candidate = source[start..<index]
                    if candidate.contains("\n") {
                        // Don't treat as closing if contains newline -> skip this delimiter and continue searching?
                        // Actually we should not close across lines, so treat opening as literal. Return nil.
                        return nil
                    }
                }
                let upperBound = source.index(index, offsetBy: delimiter.count)
                return index..<upperBound
            }
            index = source.index(after: index)
        }
        return nil
    }

    private nonisolated static func isEscapedDelimiter(at index: String.Index, in source: String) -> Bool {
        guard index > source.startIndex else { return false }
        var cursor = source.index(before: index)
        var slashCount = 0
        while source[cursor] == "\\" {
            slashCount += 1
            guard cursor > source.startIndex else { break }
            cursor = source.index(before: cursor)
        }
        return slashCount.isMultiple(of: 2) == false
    }

    private nonisolated static func parseCodeBlock(from source: String) -> (code: String, language: String)? {
        let lines = source.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.hasPrefix("```") else { return nil }

        let language = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)

        var codeLines: [String] = []
        var foundClosing = false
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                foundClosing = true
                break
            }
            codeLines.append(line)
        }

        guard foundClosing || codeLines.count > 0 else { return nil }
        let code = codeLines.joined(separator: "\n")
        guard !code.isEmpty else { return nil }

        return (code: code, language: language)
    }

    private nonisolated static func convertInlineMathToReadableText(in source: String) -> String {
        var result = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "$" {
                let next = source.index(after: index)

                if next < source.endIndex,
                   source[next] != "$",
                   let closing = source[next...].firstIndex(of: "$") {
                    // Ensure not escaped and not across newline
                    let candidate = String(source[next..<closing])
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmed.isEmpty && !candidate.contains("\n") && !isEscapedDelimiter(at: closing, in: source) {
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

    private nonisolated static func replaceRegex(_ regex: NSRegularExpression, template: String, in source: String) -> String {
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    private nonisolated static func replaceRegex(pattern: String, template: String, in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    private enum FlashcardParseMode {
        case idle
        case front
        case back
    }

    private nonisolated static func flashcardPayload(in line: String, marker: String) -> String? {
        let stripped = stripFlashcardLinePrefix(from: line)
        let uppercased = stripped.uppercased()
        let markerPrefix = "\(marker.uppercased()):"
        guard uppercased.hasPrefix(markerPrefix) else { return nil }
        return String(stripped.dropFirst(markerPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func stripFlashcardLinePrefix(from line: String) -> String {
        var stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        stripped = replaceRegex(bulletPrefixRegex, template: "", in: stripped)
        stripped = replaceRegex(numberedPrefixRegex, template: "", in: stripped)
        stripped = replaceRegex(cardPrefixRegex, template: "", in: stripped)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isMarkdownHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") || (trimmed.hasPrefix("**") && trimmed.hasSuffix("**"))
    }

    private nonisolated static func diagramSpec(from code: String, language: String) -> ARIADiagramSpec? {
        ARIAContentContract.decodeDiagram(from: code, language: language)
    }

    private nonisolated static func fallbackSimulation(for source: String) -> ARIADiagramSpec? {
        let normalized = source.lowercased()
        let refusalTerms = [
            "cannot embed",
            "can't embed",
            "cannot render",
            "can't render",
            "compatible viewer",
            "canvas-ready"
        ]
        guard refusalTerms.contains(where: normalized.contains) else { return nil }

        if normalized.contains("atom") || normalized.contains("electron") {
            return ARIADiagramSpec(
                type: "simulation",
                title: "Atom simulation",
                xLabel: nil,
                yLabel: nil,
                series: nil,
                nodes: nil,
                edges: nil,
                simulation: "atoms",
                particleCount: 12
            )
        }
        guard normalized.contains("particle") || normalized.contains("velocity") || normalized.contains("motion") else {
            return nil
        }
        return ARIADiagramSpec(
            type: "simulation",
            title: "Particle simulation",
            xLabel: nil,
            yLabel: nil,
            series: nil,
            nodes: nil,
            edges: nil,
            simulation: "particles",
            particleCount: 20
        )
    }

    // MARK: Async debounced parsing

    nonisolated static func debouncedSections(
        from text: String,
        debounceNanoseconds: UInt64 = 80_000_000
    ) async -> [FormattedMessageSection] {
        try? await Task.sleep(nanoseconds: debounceNanoseconds)
        if Task.isCancelled { return [] }
        return await Task.detached(priority: .userInitiated) {
            sections(from: text)
        }.value
    }
}
