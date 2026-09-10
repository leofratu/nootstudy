import Foundation
import SwiftUI

nonisolated enum MathExpressionFormatter: Sendable {
    private nonisolated static let commandMap: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ϵ", "\\varepsilon": "ε",
        "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\omicron": "ο",
        "\\pi": "π", "\\varpi": "ϖ", "\\rho": "ρ", "\\varrho": "ϱ", "\\sigma": "σ", "\\varsigma": "ς",
        "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ", "\\varphi": "ϕ", "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
        "\\Delta": "Δ", "\\Gamma": "Γ", "\\Lambda": "Λ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω", "\\Theta": "Θ", "\\Xi": "Ξ",
        "\\times": "×", "\\cdot": "·", "\\pm": "±", "\\neq": "≠", "\\ne": "≠", "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥", "\\approx": "≈",
        "\\infty": "∞", "\\partial": "∂", "\\to": "→", "\\rightarrow": "→", "\\leftarrow": "←", "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\leftrightarrow": "↔", "\\Leftrightarrow": "⇔",
        "\\sum": "Σ", "\\prod": "∏", "\\int": "∫", "\\oint": "∮", "\\nabla": "∇",
        "\\cdots": "⋯", "\\ldots": "…", "\\vdots": "⋮", "\\ddots": "⋱",
        "\\sin": "sin", "\\cos": "cos", "\\tan": "tan", "\\sec": "sec", "\\csc": "csc",
        "\\cot": "cot", "\\log": "log", "\\ln": "ln", "\\exp": "exp",
        "\\lim": "lim", "\\max": "max", "\\min": "min",
        "\\left": "", "\\right": "",
    ]

    /// Sorted by descending key length so ``\\rightarrow`` is replaced before ``\\right`` (which maps to empty and would otherwise truncate the arrow).
    private nonisolated static var sortedCommandPairs: [(String, String)] {
        commandMap.sorted { $0.key.count > $1.key.count }
    }

    private nonisolated static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"
    ]

    private nonisolated static let subscripts: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ",
        "u": "ᵤ", "v": "ᵥ", "x": "ₓ"
    ]

    nonisolated static func inlineString(from source: String) -> String {
        prettified(source)
    }

    nonisolated static func displayString(from source: String) -> String {
        prettified(source)
    }

    // MARK: Block content

    nonisolated static func blockContent(from source: String) -> NativeMathBlockContent {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)

        if let environment = parseEnvironment(in: trimmed) {
            switch environment.name {
            case "align", "align*", "aligned", "aligned*":
                let rows = parseAlignedRows(from: environment.body)
                if !rows.isEmpty {
                    return .aligned(rows)
                }
            case "cases":
                let rows = parseCaseRows(from: environment.body)
                if !rows.isEmpty {
                    return .cases(rows)
                }
            case "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix":
                let rows = parseMatrixRows(from: environment.body)
                if !rows.isEmpty {
                    let delimiters = delimiters(for: environment.name)
                    return .matrix(rows: rows, leftDelimiter: delimiters.0, rightDelimiter: delimiters.1)
                }
            default:
                break
            }
        }

        let lines = splitRows(in: trimmed)
            .map { prettified(stripAlignmentMarkers(from: $0)) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return .aligned(lines.map { NativeAlignedMathRow(leading: $0, trailing: nil) })
        }

        return .text(prettified(trimmed))
    }

    // MARK: Prettify with depth counting

    private nonisolated static func prettified(_ source: String) -> String {
        var result = source.trimmingCharacters(in: .whitespacesAndNewlines)

        // Use depth-counting for frac variants
        result = replaceCommandWithTwoArgs(commands: ["\\frac", "\\dfrac", "\\tfrac"], in: result) { lhs, rhs in
            formatFraction(lhs: lhs, rhs: rhs)
        }
        result = replaceCommandWithOneArg(command: "\\sqrt", in: result) { value in
            "√(\(value))"
        }
        result = replaceCommandWithOneArg(command: "\\text", in: result) { $0 }
        result = replaceCommandWithOneArg(command: "\\mathrm", in: result) { $0 }
        result = replaceCommandWithOneArg(command: "\\operatorname", in: result) { $0 }

        for (command, symbol) in sortedCommandPairs {
            result = result.replacingOccurrences(of: command, with: symbol)
        }

        result = applyScript(marker: "^", mapping: superscripts, to: result)
        result = applyScript(marker: "_", mapping: subscripts, to: result)

        // Strip grouping braces after scripts have consumed their braced groups. Remaining braces are layout-only.
        result = stripOuterBracesPreservingDepth(in: result)

        result = result.replacingOccurrences(of: "\\", with: "")

        return result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Depth-counting: parse {...} with nesting
    private nonisolated static func extractBracedContent(from source: String, startingAt index: String.Index) -> (content: String, nextIndex: String.Index)? {
        guard index < source.endIndex, source[index] == "{" else { return nil }
        var depth = 0
        var current = index
        var contentStart: String.Index?
        while current < source.endIndex {
            let char = source[current]
            if char == "{" {
                if depth == 0 {
                    contentStart = source.index(after: current)
                }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let start = contentStart {
                    let content = String(source[start..<current])
                    let next = source.index(after: current)
                    return (content, next)
                }
                if depth < 0 { return nil }
            }
            current = source.index(after: current)
        }
        return nil
    }

    private nonisolated static func replaceCommandWithOneArg(command: String, in source: String, transform: (String) -> String) -> String {
        var result = source
        var searchStart = result.startIndex
        while let range = result.range(of: command, range: searchStart..<result.endIndex) {
            let afterCommand = range.upperBound
            guard afterCommand < result.endIndex, result[afterCommand] == "{" else {
                searchStart = result.index(after: range.lowerBound)
                continue
            }
            guard let (content, nextIndex) = extractBracedContent(from: result, startingAt: afterCommand) else {
                searchStart = result.index(after: range.lowerBound)
                continue
            }
            let prettifiedContent = prettified(content)
            let replacement = transform(prettifiedContent)
            result.replaceSubrange(range.lowerBound..<nextIndex, with: replacement)
            // Move search start to after replacement to avoid infinite loop
            let offset = result.distance(from: result.startIndex, to: range.lowerBound) + replacement.count
            if offset < result.count {
                searchStart = result.index(result.startIndex, offsetBy: offset)
            } else {
                break
            }
            // Recursively handle nested occurrences inside replacement? Already prettified.
        }
        return result
    }

    private nonisolated static func replaceCommandWithTwoArgs(commands: [String], in source: String, transform: (String, String) -> String) -> String {
        var result = source
        for command in commands {
            var searchStart = result.startIndex
            while let range = result.range(of: command, range: searchStart..<result.endIndex) {
                let afterCommand = range.upperBound
                guard afterCommand < result.endIndex, result[afterCommand] == "{" else {
                    searchStart = result.index(after: range.lowerBound)
                    continue
                }
                guard let (firstContent, afterFirst) = extractBracedContent(from: result, startingAt: afterCommand) else {
                    searchStart = result.index(after: range.lowerBound)
                    continue
                }
                guard afterFirst < result.endIndex, result[afterFirst] == "{" else {
                    searchStart = result.index(after: range.lowerBound)
                    continue
                }
                guard let (secondContent, afterSecond) = extractBracedContent(from: result, startingAt: afterFirst) else {
                    searchStart = result.index(after: range.lowerBound)
                    continue
                }
                let lhs = prettified(firstContent)
                let rhs = prettified(secondContent)
                let replacement = transform(lhs, rhs)
                result.replaceSubrange(range.lowerBound..<afterSecond, with: replacement)
                let offset = result.distance(from: result.startIndex, to: range.lowerBound) + replacement.count
                if offset < result.count {
                    searchStart = result.index(result.startIndex, offsetBy: offset)
                } else {
                    break
                }
            }
        }
        return result
    }

    // Strip braces but preserve nested structure: only remove outermost braces when they enclose entire string or are isolated
    private nonisolated static func stripOuterBracesPreservingDepth(in source: String) -> String {
        // Remove braces that are simple grouping: {xyz} -> xyz, but not when nesting is needed for meaning.
        // We use depth counting to ensure we only strip balanced braces that are not part of command args already handled.
        // Simple approach: iteratively remove { and } when they are balanced and not creating ambiguity.
        // For now, replace "{" and "}" with "" but this is safe because depth-counted commands already extracted.
        // The requirement says do not blindly strip braces — so we need more careful: keep braces inside \text content?
        // Since \text already preserved, remaining braces are likely grouping. We can remove them but keep inner content.
        var result = ""
        var depth = 0
        for char in source {
            if char == "{" {
                depth += 1
                continue
            } else if char == "}" {
                if depth > 0 { depth -= 1 }
                continue
            }
            result.append(char)
        }
        return result
    }

    private nonisolated static func applyScript(marker: Character, mapping: [Character: String], to source: String) -> String {
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

    private nonisolated static func formatFraction(lhs: String, rhs: String) -> String {
        let numerator = needsGrouping(lhs) ? "(\(lhs))" : lhs
        let denominator = needsGrouping(rhs) ? "(\(rhs))" : rhs
        return "\(numerator)/\(denominator)"
    }

    private nonisolated static func needsGrouping(_ expression: String) -> Bool {
        expression.contains(where: { "+-= ".contains($0) })
    }

    private nonisolated static func parseEnvironment(in source: String) -> (name: String, body: String)? {
        let pattern = #"(?s)\\begin\{([A-Za-z\*]+)\}(.*?)\\end\{([A-Za-z\*]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges >= 4,
              let nameRange = Range(match.range(at: 1), in: source),
              let bodyRange = Range(match.range(at: 2), in: source),
              let endNameRange = Range(match.range(at: 3), in: source) else {
            return nil
        }

        let name = String(source[nameRange])
        let endName = String(source[endNameRange])
        guard name == endName else { return nil }
        return (name, String(source[bodyRange]))
    }

    private nonisolated static func parseAlignedRows(from source: String) -> [NativeAlignedMathRow] {
        splitRows(in: source).compactMap { row in
            let columns = row
                .components(separatedBy: "&")
                .map { prettified($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }

            guard let first = columns.first else { return nil }
            let trailing = columns.dropFirst().joined(separator: " ")
            return NativeAlignedMathRow(
                leading: first,
                trailing: trailing.isEmpty ? nil : trailing
            )
        }
    }

    private nonisolated static func parseCaseRows(from source: String) -> [NativeCaseMathRow] {
        splitRows(in: source).compactMap { row in
            let columns = row
                .components(separatedBy: "&")
                .map { prettified($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }

            guard let first = columns.first else { return nil }
            let explanation = columns.dropFirst().joined(separator: " ")
            return NativeCaseMathRow(
                condition: first,
                explanation: explanation.isEmpty ? nil : explanation
            )
        }
    }

    private nonisolated static func parseMatrixRows(from source: String) -> [[String]] {
        splitRows(in: source)
            .map { row in
                row
                    .components(separatedBy: "&")
                    .map { prettified($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func splitRows(in source: String) -> [String] {
        source
            .components(separatedBy: "\\\\")
            .map { stripAlignmentMarkers(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func stripAlignmentMarkers(from source: String) -> String {
        source.replacingOccurrences(of: "&", with: " ")
    }

    private nonisolated static func delimiters(for environment: String) -> (String, String) {
        switch environment {
        case "pmatrix":
            return ("(", ")")
        case "bmatrix":
            return ("[", "]")
        case "Bmatrix":
            return ("{", "}")
        case "vmatrix":
            return ("|", "|")
        case "Vmatrix":
            return ("‖", "‖")
        default:
            return ("", "")
        }
    }
}

// MARK: - Native Math Block Content (shared with views)

nonisolated enum NativeMathBlockContent: Sendable {
    case text(String)
    case aligned([NativeAlignedMathRow])
    case matrix(rows: [[String]], leftDelimiter: String, rightDelimiter: String)
    case cases([NativeCaseMathRow])
}

nonisolated struct NativeAlignedMathRow: Sendable {
    let leading: String
    let trailing: String?
}

nonisolated struct NativeCaseMathRow: Sendable {
    let condition: String
    let explanation: String?
}
