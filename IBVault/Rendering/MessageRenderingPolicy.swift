import Foundation

/// Canonical authority for provider text before it enters SwiftUI's Markdown
/// renderer. It removes formats that do not adapt reliably to narrow chat rows.
nonisolated enum MessageRenderingPolicy: Sendable {
    static func displaySafeMarkdown(_ source: String) -> String {
        let normalized = source
            .replacingOccurrences(of: "—", with: " - ")
            .replacingOccurrences(of: "–", with: " - ")
        return convertTables(in: normalized)
    }

    private static func convertTables(in source: String) -> String {
        var output: [String] = []
        var headers: [String] = []

        for line in source.components(separatedBy: .newlines) {
            guard let cells = tableCells(in: line) else {
                headers = []
                output.append(line)
                continue
            }
            if isSeparatorRow(cells) { continue }
            if headers.isEmpty {
                headers = cells
                continue
            }

            let title = cells.first.flatMap { $0.isEmpty ? nil : $0 } ?? "Item"
            let details = cells.enumerated().dropFirst().compactMap { index, value -> String? in
                guard !value.isEmpty else { return nil }
                let label = index < headers.count && !headers[index].isEmpty ? headers[index] : "Detail"
                return "**\(label):** \(value)"
            }
            output.append("**\(title)**")
            if !details.isEmpty {
                output.append(details.joined(separator: " · "))
            }
            output.append("")
        }

        return output.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }
        return trimmed
            .dropFirst()
            .dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace }
        }
    }
}
