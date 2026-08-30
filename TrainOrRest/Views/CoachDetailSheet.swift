import SwiftUI

struct CoachDetailSheet: View {
    let details: CoachResponseDetails
    let language: CoachLanguage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(details.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.torHeading(18, .bold))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)

                            MarkdownMessageView(
                                text: section.markdown,
                                tone: .standard,
                                allowsRuleTokens: false
                            )
                            .textSelection(.enabled)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(language.coachDetailSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.coachDetailDoneLabel) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    CoachDetailSheet(
        details: CoachResponseDetails(
            title: "Detailed analysis",
            sections: [
                CoachDetailSection(
                    id: "load",
                    title: "Training load",
                    markdown: "Your recent effort is elevated. Keep the next run easy."
                ),
                CoachDetailSection(
                    id: "recovery",
                    title: "Recovery",
                    markdown: "Prioritize sleep and hydration tonight."
                )
            ]
        ),
        language: .en
    )
}
