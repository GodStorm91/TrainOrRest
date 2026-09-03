import SwiftUI

struct CoachGlossarySheet: View {
    let termId: String
    var currentValue: String? = nil
    let language: CoachLanguage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let term = CoachGlossary.term(id: termId) {
            let content = term.content(for: language)

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.glossaryTitle(term: term.canonicalLabel))
                                .font(.torHeading(20, .bold))
                                .foregroundStyle(Theme.text)
                                .accessibilityAddTraits(.isHeader)

                            Text(content.title)
                                .font(.subheadline)
                                .foregroundStyle(Theme.dim)

                            if let fullName = content.fullName, fullName != content.title {
                                Text(fullName)
                                    .font(.caption)
                                    .foregroundStyle(Theme.faint)
                            }
                        }

                        glossarySection(language.glossarySimpleTerms, text: content.simpleExplanation)
                        glossarySection(language.glossaryWhyItMatters, text: content.whyItMatters)

                        if let currentValue {
                            glossarySection(language.glossaryCurrentValue, text: currentValue)
                        }

                        glossarySection(language.glossaryInterpretation, text: content.interpretation)
                        glossarySection(language.glossaryCaution, text: content.caution)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.glossaryGotIt) {
                            dismiss()
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func glossarySection(_ title: String, text: String?) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                    .accessibilityAddTraits(.isHeader)

                Text(text)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
