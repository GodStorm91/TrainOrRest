import SwiftUI

struct CoachGlossaryText: View {
    enum Mode {
        case structured
        case legacy
    }

    let text: String
    var mode: Mode = .structured
    let language: CoachLanguage
    var font: Font = .body
    var color: Color = Theme.text
    var values: [String: String] = [:]

    @State private var selectedTerm: CoachGlossarySelectedTerm?

    private var segments: [CoachGlossarySegment] {
        switch mode {
        case .structured:
            CoachGlossaryMarkup.firstOccurrenceOnly(CoachGlossaryMarkup.parse(text))
        case .legacy:
            CoachGlossaryMarkup.legacySegments(text)
        }
    }

    var body: some View {
        Text(CoachGlossaryAttributedBuilder.attributed(for: segments, baseColor: color))
            .font(font)
            .tint(Theme.accent)
            .textSelection(.enabled)
            .accessibilityLabel(accessibilityText)
            .environment(\.openURL, OpenURLAction { url in
                guard let id = CoachGlossaryTokenURL.termID(from: url), CoachGlossary.term(id: id) != nil else {
                    return .systemAction
                }
                selectedTerm = CoachGlossarySelectedTerm(id: id)
                return .handled
            })
            .sheet(item: $selectedTerm) { selectedTerm in
                CoachGlossarySheet(
                    termId: selectedTerm.id,
                    currentValue: currentValue(for: selectedTerm.id),
                    language: language
                )
            }
    }

    private var accessibilityText: String {
        segments.map { segment in
            switch segment {
            case .text(let value):
                value
            case .term(_, let label):
                "\(label), \(language.glossaryAccessibilityRole)"
            }
        }.joined()
    }

    private func currentValue(for termID: String) -> String? {
        values[termID]
    }
}

struct CoachGlossarySelectedTerm: Identifiable {
    let id: String
}

enum CoachGlossaryAttributedBuilder {
    static func attributed(for segments: [CoachGlossarySegment], baseColor: Color) -> AttributedString {
        var output = AttributedString()

        for segment in segments {
            switch segment {
            case .text(let value):
                var text = AttributedString(value)
                text.foregroundColor = baseColor
                output += text
            case .term(let id, let label):
                let url = CoachGlossaryTokenURL.url(for: id)

                var labelRun = AttributedString(label)
                labelRun.foregroundColor = baseColor
                labelRun.link = url
                labelRun.underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.accent.opacity(0.55))
                output += labelRun

                var starRun = AttributedString("*")
                starRun.font = .system(.caption2)
                starRun.baselineOffset = 4
                starRun.foregroundColor = Theme.accent
                starRun.link = url
                output += starRun
            }
        }

        return output
    }
}
