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

    @State private var showsValidationReceipt = false

    private var weekday: String {
        pending.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    var body: some View {
        card
            .sheet(isPresented: $showsValidationReceipt) {
                ReceiptSheet(
                    title: "Validated",
                    subtitle: "Checked by local training rules before it can change your plan.",
                    rows: validationRows
                )
            }
    }

    private var validationRows: [ReceiptSheet.Row] {
        [
            .check("Workout uses available days", value: "No workout on an unavailable day."),
            .check("Long-run length within limit", value: "Long runs stay within absolute and weekly-share caps."),
            .check("Ramp rate safe", value: "Weekly volume does not grow faster than the plan allows."),
            .check("Taper stays monotonic", value: "Taper volume does not climb toward race day."),
            .check("Quality sessions spaced", value: "Hard sessions keep the required recovery gap."),
            .check("Race day present", value: "The plan still includes exactly one race workout."),
            .check("Weekly volume within cap", value: "Week volume remains under the athlete's peak cap."),
            .check("No duplicate workout day", value: "Each date has at most one workout."),
            .check("Workout stays inside plan week", value: "The workout date matches its plan week."),
            .check("Distances valid", value: "Workout distances are finite and above zero."),
            .check("Structure matches distance", value: "Structured steps add up to the workout distance.")
        ]
    }

    private var applyLabel: String {
        if pending.expected.weekIndex >= 0 {
            return "Apply to week \(pending.expected.weekIndex + 1)"
        }
        return "Apply to this week"
    }

    private var card: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                titleRow
                ledgerRow
                planChangedBanner
                diffRow

                Rectangle().fill(Theme.line).frame(height: 1)

                Text(language.weeklyVolumeDeltaText(pending.volumeDeltaKm))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.faint)

                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
        )
    }

    private var titleRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .bold))
            Text(language.planUpdateTitle)
                .font(.torLabel(11, .bold))
                .tracking(1.4)
        }
        .foregroundStyle(Theme.accent)
    }

    private var ledgerRow: some View {
        HStack(spacing: 6) {
            ledgerChip("Proposed", symbol: "sparkles", tint: Theme.accent)

            Button {
                showsValidationReceipt = true
            } label: {
                ledgerChip("Validated", symbol: "checkmark.seal", tint: Theme.good)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show validation receipt")

            ledgerChip("Awaits you", symbol: "person", tint: Theme.dim)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    @ViewBuilder
    private var planChangedBanner: some View {
        if pending.planChangedSinceProposed {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.warn)
                    .accessibilityHidden(true)

                Text("Plan changed since this was proposed — review the updated change.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.soft(Theme.warn, 0.16),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityLabel("Plan changed since this was proposed. Review the updated change.")
        }
    }

    private func ledgerChip(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Theme.soft(tint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var diffRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(weekday)
                .font(.torLabel(10, .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.faint)
                .frame(width: 34, alignment: .leading)
                .padding(.top, 2)

            ViewThatFits(in: .horizontal) {
                horizontalDiff
                verticalDiff
            }
        }
    }

    private var horizontalDiff: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            beforeLine(singleLine: true)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.good)
                .accessibilityHidden(true)

            afterLine(singleLine: true)
        }
    }

    private var verticalDiff: some View {
        VStack(alignment: .leading, spacing: 7) {
            beforeLine(singleLine: false)
            afterLine(singleLine: false)
        }
    }

    private func beforeLine(singleLine: Bool) -> some View {
        Text(language.workoutRowText(pending.existing))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.faint)
            .strikethrough(true, color: Theme.faint)
            .lineLimit(singleLine ? 1 : nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func afterLine(singleLine: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(language.workoutRowText(pending.proposed))
                .font(.torHeading(15, .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(singleLine ? 1 : nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(language.planUpdateNewBadge)
                .font(.torLabel(10, .bold))
                .tracking(0.5)
                .foregroundStyle(Theme.good)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.soft(Theme.good), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                secondaryButton(language.keepExistingLabel(pending.existing.kind), action: onKeep)
                secondaryButton(language.whySwapPrompt, action: onAskWhy)
            }

            Button(action: onApply) {
                Label(applyLabel, systemImage: "checkmark")
                    .font(.torHeading(13, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(applyLabel)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.torHeading(13, .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 10)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct PlanProposalCard: View {
    let pending: PendingPlanProposal
    let language: CoachLanguage
    let onApply: () -> Void
    let onKeep: () -> Void

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("CALENDAR UPDATE")
                        .font(.torLabel(11, .bold))
                        .tracking(1.4)
                }
                .foregroundStyle(Theme.accent)

                HStack(spacing: 6) {
                    chip("Proposed", symbol: "sparkles", tint: Theme.accent)
                    chip("Needs approval", symbol: "person.crop.circle.badge.checkmark", tint: Theme.good)
                    chip("Pushes intervals.icu", symbol: "arrow.triangle.2.circlepath", tint: Theme.dim)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                Text(pending.summary)
                    .font(.torHeading(15, .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Nothing is saved to Calendar until you apply it. After applying, TrainOrRest will trigger the intervals.icu sync if watch push is enabled.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: onKeep) {
                        Text("Keep current plan")
                            .font(.torHeading(13, .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
                    }
                    .buttonStyle(.plain)

                    Button(action: onApply) {
                        Label(language.applyChangesLabel, systemImage: "checkmark")
                            .font(.torHeading(13, .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
        )
    }

    private func chip(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Theme.soft(tint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
