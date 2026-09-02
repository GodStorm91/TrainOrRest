import SwiftUI

struct CoachSourcesSheet: View {
    let sources: [CoachDataSource]
    let language: CoachLanguage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sources) { source in
                Label(language.sourceLabel(for: source.type), systemImage: Self.symbol(for: source.type))
                    .accessibilityLabel(language.sourceLabel(for: source.type))
            }
            .navigationTitle(language.contextSourcesSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.coachDetailDoneLabel) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    static func symbol(for kind: CoachDataSource.Kind) -> String {
        switch kind {
        case .healthData: "heart.text.square"
        case .completedWorkout: "figure.run"
        case .trainingPlan: "calendar"
        case .upcomingWorkouts: "calendar.badge.clock"
        case .raceGoal: "flag.checkered"
        }
    }
}

#Preview {
    CoachSourcesSheet(
        sources: [
            .init(id: "health", type: .healthData, label: "Health data", updatedAt: nil),
            .init(id: "plan", type: .trainingPlan, label: "Training plan", updatedAt: nil)
        ],
        language: .en
    )
}
