import SwiftUI

/// The trust ledger shared by every plan-edit card. One component so the fixed
/// Proposed/Validated/Awaits sequence and its receipt cannot drift between cards.
struct CoachTrustLedger: View {
    let language: CoachLanguage

    @State private var showsReceipt = false

    var body: some View {
        HStack(spacing: 6) {
            chip(language.ledgerProposedLabel, symbol: "sparkles", tint: Theme.accent)

            Button { showsReceipt = true } label: {
                chip(language.ledgerValidatedLabel, symbol: "checkmark.seal", tint: Theme.good)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.showValidationReceiptLabel)

            chip(language.ledgerAwaitsLabel, symbol: "person", tint: Theme.dim)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .sheet(isPresented: $showsReceipt) {
            ReceiptSheet(
                title: language.validationReceiptTitle,
                subtitle: language.validationReceiptSubtitle,
                rows: language.planValidationChecks.map { .check($0.title, value: $0.detail) }
            )
        }
    }

    private func chip(_ title: String, symbol: String, tint: Color) -> some View {
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
}

/// The coach's proposed swap, shown inline above the composer instead of a
/// system alert. Every value comes from the staged replacement — the card shows
/// the real before/after workouts and the real weekly-volume delta, and claims
/// nothing the plan engine cannot compute.
struct PlanUpdateCard: View {
    let pending: PendingWorkoutReplacement
    let language: CoachLanguage
    var isApplying: Bool = false
    let onApply: () -> Void
    let onKeep: () -> Void
    let onAskWhy: () -> Void

    private var weekday: String {
        pending.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private var applyLabel: String {
        pending.expected.weekIndex >= 0
            ? language.applyToWeekLabel(pending.expected.weekIndex + 1)
            : language.applyChangesLabel
    }

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if isApplying {
                    applyingRow
                } else {
                    titleRow
                    CoachTrustLedger(language: language)
                    planChangedBanner
                    diffRow

                    Rectangle().fill(Theme.line).frame(height: 1)

                    Text(language.weeklyVolumeDeltaText(pending.volumeDeltaKm))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.dim)

                    actions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
        )
    }

    private var applyingRow: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.accent)
            Text(language.updatingPlanTitle)
                .font(.torHeading(15, .bold))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    private var titleRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .bold))
            Text(language.planProposalEyebrow)
                .font(.torLabel(11, .bold))
                .tracking(1.4)
        }
        .foregroundStyle(Theme.accent)
    }

    @ViewBuilder
    private var planChangedBanner: some View {
        if pending.planChangedSinceProposed {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.warn)
                    .accessibilityHidden(true)

                Text(language.planChangedBannerText)
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
            .accessibilityLabel(language.planChangedBannerText)
        }
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
                secondaryButton(language.keepOldPlanLabel, action: onKeep)
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

/// A multi-change plan proposal awaiting confirmation. Renders the real per-change
/// rows from `proposal.changes`, not only the summary sentence.
struct PlanProposalCard: View {
    let pending: PendingPlanProposal
    let language: CoachLanguage
    var isApplying: Bool = false
    let onApply: () -> Void
    let onKeep: () -> Void

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if isApplying {
                    applyingRow
                } else {
                    titleRow
                    CoachTrustLedger(language: language)

                    Text(pending.summary)
                        .font(.torHeading(15, .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !pending.proposal.changes.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(pending.proposal.changes.enumerated()), id: \.offset) { _, change in
                                changeRow(change)
                            }
                        }
                    }

                    Text(language.proposalNoChangeYetText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)

                    actions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
        )
    }

    private var applyingRow: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.accent)
            Text(language.updatingPlanTitle)
                .font(.torHeading(15, .bold))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    private var titleRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 11, weight: .bold))
            Text(language.planProposalEyebrow)
                .font(.torLabel(11, .bold))
                .tracking(1.4)
        }
        .foregroundStyle(Theme.accent)
    }

    private func changeRow(_ change: PlanAdjustmentProposal.Change) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(language.planChangeActionLabel(change.action))
                .font(.torLabel(10, .bold))
                .tracking(0.5)
                .foregroundStyle(Theme.dim)
                .frame(minWidth: 46, alignment: .leading)
            Text(changeDescription(change))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func changeDescription(_ change: PlanAdjustmentProposal.Change) -> String {
        if let detail = change.detail, !detail.isEmpty { return detail }
        if let kind = change.workout?.kind, !kind.isEmpty { return kind.capitalized }
        return change.date
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onKeep) {
                Text(language.keepOldPlanLabel)
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
            .accessibilityLabel(language.applyChangesLabel)
        }
    }
}
