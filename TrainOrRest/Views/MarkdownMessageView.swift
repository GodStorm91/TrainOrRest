import SwiftUI

/// Whether markdown renders on the neutral card surface (assistant) or on the
/// accent-filled user bubble, where text must stay white for contrast.
enum MarkdownTone {
    case standard
    case onAccent

    var primary: Color { self == .onAccent ? .white : Theme.text }
    var secondary: Color { self == .onAccent ? .white.opacity(0.82) : Theme.dim }
    var fill: Color { self == .onAccent ? .white.opacity(0.16) : Theme.chip }
    var headerFill: Color { self == .onAccent ? .white.opacity(0.20) : Theme.accentSoft }
    var stroke: Color { self == .onAccent ? .white.opacity(0.28) : Theme.line }
}

struct MarkdownMessageView: View {
    let text: String
    var tone: MarkdownTone = .standard

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .foregroundStyle(tone.primary)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            MarkdownInlineText(text)
                .font(level == 1 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, level == 1 ? 2 : 0)
        case .paragraph(let text):
            MarkdownInlineText(text)
                .font(.body)
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.body.weight(.semibold))
                MarkdownInlineText(text)
                    .font(.body)
            }
        case .quote(let text):
            MarkdownInlineText(text)
                .font(.callout)
                .foregroundStyle(tone.secondary)
                .padding(8)
                .background(tone.fill, in: RoundedRectangle(cornerRadius: 8))
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(tone.fill, in: RoundedRectangle(cornerRadius: 8))
        case .table(let table):
            MarkdownTableView(table: table, tone: tone)
        }
    }
}

private struct MarkdownInlineText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    var tone: MarkdownTone = .standard

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        tableCell(header, isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(normalized(row).enumerated()), id: \.offset) { _, cell in
                            tableCell(cell, isHeader: false)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tone.stroke, lineWidth: 1)
        }
    }

    private func normalized(_ row: [String]) -> [String] {
        var cells = row
        while cells.count < table.headers.count {
            cells.append("")
        }
        return Array(cells.prefix(table.headers.count))
    }

    private func tableCell(_ text: String, isHeader: Bool) -> some View {
        MarkdownInlineText(text)
            .font(isHeader ? .caption.weight(.semibold) : .caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 96, alignment: .leading)
            .background(isHeader ? tone.headerFill : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tone.stroke)
                    .frame(height: 1)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(tone.stroke)
                    .frame(width: 1)
            }
    }
}
