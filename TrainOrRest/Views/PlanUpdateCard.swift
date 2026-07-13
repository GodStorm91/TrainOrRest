import SwiftUI

/// The coach's proposed swap, shown inline above the composer instead of a
/// system alert. Every value comes from the staged replacement — the card shows
/// the real before/after workouts and the real weekly-volume delta, and claims
/// nothing the plan engine cannot compute.
struct PlanUpdateCard: View {
    let pending: PendingWorkoutReplacement
    let language: CoachLanguage
    let onApply: () -> Void
    let onKeep: () -> Void
    let onAskWhy: () -> Void

    private var weekday: String {
        pending.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card
            actions
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                Text(language.planUpdateTitle)
                    .font(.torLabel(11, .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(Theme.accent)

            HStack(alignment: .top, spacing: 12) {
                Text(weekday)
                    .font(.torLabel(10, .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.faint)
                    .frame(width: 34, alignment: .leading)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(language.workoutRowText(pending.existing))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.faint)
                        .strikethrough(true, color: Theme.faint)

                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.good)
                        Text(language.workoutRowText(pending.proposed))
                            .font(.torHeading(15, .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 6)
                        Text(language.planUpdateNewBadge)
                            .font(.torLabel(10, .bold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.good)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.soft(Theme.good), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            Rectangle().fill(Theme.line).frame(height: 1)

            Text(language.weeklyVolumeDeltaText(pending.volumeDeltaKm))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.faint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onApply) {
                Text(language.applyChangesLabel)
                    .font(.torHeading(13, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)

            secondaryButton(language.keepExistingLabel(pending.existing.kind), action: onKeep)
            secondaryButton(language.whySwapPrompt, action: onAskWhy)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.torHeading(13, .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
