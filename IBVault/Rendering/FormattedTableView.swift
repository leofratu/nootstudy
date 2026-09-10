import SwiftUI

/// GFM table rendered as a SwiftUI Grid with header styling and horizontal scroll for wide content.
struct FormattedTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(FormattedMessageFormatter.attributedMarkdown(from: header) ?? AttributedString(header))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(IBColors.ink)
                            .lineSpacing(2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(IBColors.canvasDeep)
                    }
                }
                .background(IBColors.canvasDeep)

                Divider()
                    .gridCellUnsizedAxes(.horizontal)

                // Rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            let attributed = FormattedMessageFormatter.attributedMarkdown(from: cell) ?? AttributedString(cell)
                            Text(attributed)
                                .font(.caption)
                                .foregroundStyle(IBColors.ink)
                                .lineSpacing(2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(rowIdx % 2 == 1 ? IBColors.canvas.opacity(0.6) : Color.clear)
                        }
                    }
                    if rowIdx < rows.count - 1 {
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                            .opacity(0.5)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(IBColors.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
