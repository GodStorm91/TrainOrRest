import SwiftData
import SwiftUI

/// "What changed & why": today's plan vs this morning's snapshot.
struct PlanDiffView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var changes: [PlanDiff.DayChange] = []

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        List {
            if changes.isEmpty {
                ContentUnavailableView(
                    language.plan.noChanges,
                    systemImage: "checkmark.circle",
                    description: Text(language.plan.planMatchesYesterday)
                )
            } else {
                Section {
                    Label(language.plan.changesLimitedNotice, systemImage: "checkmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(changes.indices, id: \.self) { index in
                    DiffRow(change: changes[index], language: language)
                }
            }
        }
        .navigationTitle(language.plan.planChangesTitle)
        .task {
            changes = (try? ReadinessStore.todaysChanges(
                in: modelContext, today: .now, calendar: .current
            )) ?? []
        }
    }
}

private struct DiffRow: View {
    let change: PlanDiff.DayChange
    let language: CoachLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.shortWeekdayDate(change.date))
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ChangePill(title: language.plan.beforeLabel, value: summary(change.before), symbol: "clock")
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ChangePill(title: language.plan.nowLabel, value: summary(change.after), symbol: "checkmark.circle")
            }

            VStack(alignment: .leading, spacing: 3) {
                Label(reasonText, systemImage: reasonSymbol)
                Label(impactText, systemImage: "chart.line.uptrend.xyaxis")
                Label(language.plan.reviewedByRules, systemImage: "checkmark.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func summary(_ entry: PlanDiff.Entry?) -> String {
        guard let entry else { return language.restDayLabel }
        return "\(language.name(entry.kind)) \(Formatters.kilometers(entry.distanceKm * 1000))"
    }

    private var reasonText: String {
        switch change.reason {
        case .readiness(let verdict):
            language.plan.readinessReason(verdict)
        case .volumeRefit:
            language.plan.volumeRefitReason
        }
    }

    private var reasonSymbol: String {
        switch change.reason {
        case .readiness:
            "heart.text.square"
        case .volumeRefit:
            "arrow.triangle.2.circlepath"
        }
    }

    private var impactText: String {
        switch (change.before, change.after) {
        case let (before?, after?):
            let delta = after.distanceKm - before.distanceKm
            if before.kind != after.kind {
                return language.plan.intensityChanged(from: language.name(before.kind), to: language.name(after.kind))
            }
            if abs(delta) >= 0.05 {
                return language.plan.distanceChanged(delta)
            }
            return language.plan.workoutUpdatedDetails
        case (_?, nil):
            return language.plan.workoutRemovedRecovery
        case (nil, let after?):
            return language.plan.workoutAddedBalanced(language.name(after.kind))
        case (nil, nil):
            return language.plan.noWorkoutImpact
        }
    }
}

private struct ChangePill: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
    }
}
