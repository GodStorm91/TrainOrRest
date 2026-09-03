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

enum GlossaryMode {
    case off
    case structured
    case legacy
}

/// Converts leaf inline text to an `AttributedString` while preserving author
/// line breaks. The default `.full` markdown syntax collapses soft newlines to
/// spaces (and eats ordered-list markers), which flattens multi-line coach
/// replies into an unreadable wall. Block structure is already resolved by
/// `MarkdownBlockParser`, so only inline syntax needs interpreting here.
enum InlineMarkdown {
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

struct MarkdownMessageView: View {
    let text: String
    var tone: MarkdownTone = .standard
    var allowsRuleTokens = true
    var glossary: GlossaryMode = .off
    var language: CoachLanguage = .current

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
            MarkdownInlineText(text, allowsRuleTokens: allowsRuleTokens, glossary: glossary, language: language, color: tone.primary)
                .font(level == 1 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, level == 1 ? 2 : 0)
        case .paragraph(let text):
            MarkdownInlineText(text, allowsRuleTokens: allowsRuleTokens, glossary: glossary, language: language, color: tone.primary)
                .font(.body)
        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                MarkdownInlineText(text, allowsRuleTokens: allowsRuleTokens, glossary: glossary, language: language, color: tone.primary)
                    .font(.body)
            }
        case .quote(let text):
            MarkdownInlineText(text, allowsRuleTokens: allowsRuleTokens, glossary: glossary, language: language, color: tone.secondary)
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
            MarkdownTableView(
                table: table,
                tone: tone,
                allowsRuleTokens: allowsRuleTokens,
                glossary: glossary,
                language: language
            )
        }
    }
}

private struct MarkdownInlineText: View {
    let text: String
    let allowsRuleTokens: Bool
    let glossary: GlossaryMode
    let language: CoachLanguage
    let color: Color
    @State private var selectedRuleID: ReadinessRuleID?
    @State private var selectedGlossaryTerm: CoachGlossarySelectedTerm?

    init(
        _ text: String,
        allowsRuleTokens: Bool = true,
        glossary: GlossaryMode = .off,
        language: CoachLanguage = .current,
        color: Color = Theme.text
    ) {
        self.text = text
        self.allowsRuleTokens = allowsRuleTokens
        self.glossary = glossary
        self.language = language
        self.color = color
    }

    var body: some View {
        Text(attributedText)
            .tint(Theme.accent)
            .environment(\.openURL, OpenURLAction { url in
                switch glossary {
                case .off:
                    break
                case .structured, .legacy:
                    if let id = CoachGlossaryTokenURL.termID(from: url) {
                        guard CoachGlossary.term(id: id) != nil else {
                            return .systemAction
                        }
                        selectedGlossaryTerm = CoachGlossarySelectedTerm(id: id)
                        return .handled
                    }
                }

                guard let ruleID = RuleTokenURL.ruleID(from: url) else {
                    return .systemAction
                }
                selectedRuleID = ruleID
                return .handled
            })
            .sheet(item: $selectedRuleID) { ruleID in
                RuleDefinitionSheet(ruleID: ruleID, language: language)
            }
            .sheet(item: $selectedGlossaryTerm) { selectedTerm in
                CoachGlossarySheet(termId: selectedTerm.id, language: language)
            }
    }

    private var attributedText: AttributedString {
        switch glossary {
        case .structured:
            return CoachGlossaryAttributedBuilder.attributed(
                for: CoachGlossaryMarkup.firstOccurrenceOnly(CoachGlossaryMarkup.parse(text)),
                baseColor: color
            )
        case .legacy:
            return CoachGlossaryAttributedBuilder.attributed(
                for: CoachGlossaryMarkup.legacySegments(text),
                baseColor: color
            )
        case .off:
            guard allowsRuleTokens else {
                return Self.markdown(text)
            }
            return RuleAttributedStringBuilder.attributedString(from: text)
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        InlineMarkdown.attributed(text)
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    var tone: MarkdownTone = .standard
    var allowsRuleTokens = true
    var glossary: GlossaryMode = .off
    var language: CoachLanguage = .current

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
        MarkdownInlineText(text, allowsRuleTokens: allowsRuleTokens, glossary: glossary, language: language, color: tone.primary)
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

private enum RuleAttributedStringBuilder {
    static func attributedString(from text: String) -> AttributedString {
        let spans = RuleTokenizer.tokens(in: text)
        guard !spans.isEmpty else {
            return markdown(text)
        }

        var output = AttributedString()
        var cursor = text.startIndex

        for span in spans {
            guard let range = Range(NSRange(location: span.lowerBound, length: span.upperBound - span.lowerBound), in: text) else {
                continue
            }
            if cursor < range.lowerBound {
                output += markdown(String(text[cursor..<range.lowerBound]))
            }

            var token = AttributedString(span.code)
            token.link = RuleTokenURL.url(for: span.ruleID)
            token.foregroundColor = Theme.accent
            token.backgroundColor = Theme.accent.opacity(0.14)
            token.font = .system(.caption, design: .monospaced).weight(.semibold)
            output += token
            cursor = range.upperBound
        }

        if cursor < text.endIndex {
            output += markdown(String(text[cursor..<text.endIndex]))
        }

        return output
    }

    private static func markdown(_ text: String) -> AttributedString {
        InlineMarkdown.attributed(text)
    }
}

private struct RuleDefinitionSheet: View {
    let ruleID: ReadinessRuleID
    let language: CoachLanguage

    var body: some View {
        ReceiptSheet(
            title: language.ruleSheetTitle(ruleID.code),
            subtitle: language.ruleTitle(ruleID),
            rows: [
                .detail(language.ruleDefinitionLabel, value: language.ruleDetail(ruleID), symbol: "checkmark.seal")
            ]
        )
    }
}
