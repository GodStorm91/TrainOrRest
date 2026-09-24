import SwiftUI

/// The trust ledger shared by every plan-edit card. One component so the fixed
/// Proposed/Validated/Awaits sequence and its receipt cannot drift between cards.
struct CoachTrustLedger: View {
    let language: CoachLanguage
    /// Issues the user must acknowledge before Apply. Drive the chip and the sheet title.
    var loadRisks: [PlanValidator.Issue] = []
    /// Informational issues. Listed in the receipt, never change the chip.
    var notes: [PlanValidator.Issue] = []

    @State private var showsReceipt = false

    private var hasLoadWarning: Bool { !loadRisks.isEmpty }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ledger(horizontal: true, compactLabels: true)
            ledger(horizontal: false, compactLabels: false)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .sheet(isPresented: $showsReceipt) {
            ReceiptSheet(
                title: hasLoadWarning ? language.validationReceiptWarningTitle : language.validationReceiptTitle,
                subtitle: hasLoadWarning ? language.validationReceiptWarningSubtitle : language.validationReceiptSubtitle,
                rows: receiptRows
            )
        }
    }

    @ViewBuilder
    private func ledger(horizontal: Bool, compactLabels: Bool) -> some View {
        if horizontal {
            HStack(spacing: 6) {
                proposedChip(compactLabels: compactLabels)
                validationReceiptButton(compactLabels: compactLabels)
                awaitsChip(compactLabels: compactLabels)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                proposedChip(compactLabels: compactLabels)
                validationReceiptButton(compactLabels: compactLabels)
                awaitsChip(compactLabels: compactLabels)
            }
        }
    }

    private func proposedChip(compactLabels: Bool) -> some View {
        chip(
            language.ledgerProposedLabel,
            symbol: "sparkles",
            tint: Theme.dim,
            background: Theme.chip,
            compactLabels: compactLabels
        )
    }

    private func validationReceiptButton(compactLabels: Bool) -> some View {
        Button { showsReceipt = true } label: {
            if hasLoadWarning {
                chip(
                    language.ledgerValidatedWithWarningLabel,
                    symbol: "exclamationmark.triangle.fill",
                    tint: Theme.warn,
                    compactLabels: compactLabels
                )
            } else {
                chip(
                    language.ledgerValidatedLabel,
                    symbol: "checkmark.seal",
                    tint: Theme.good,
                    compactLabels: compactLabels
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.showValidationReceiptLabel)
    }

    private func awaitsChip(compactLabels: Bool) -> some View {
        chip(
            language.ledgerAwaitsLabel,
            symbol: "person",
            tint: Theme.dim,
            compactLabels: compactLabels
        )
    }

    /// `Issue.Kind.allCases` order matches `planValidationChecks`.
    private var receiptRows: [ReceiptSheet.Row] {
        let checks = language.planValidationChecks
        let kinds = PlanValidator.Issue.Kind.allCases
        let flagged = loadRisks + notes
        let warned = Set(flagged.map(\.kind))
        var rows: [ReceiptSheet.Row] = []
        for warning in flagged {
            let title: String
            if let index = kinds.firstIndex(of: warning.kind), index < checks.count {
                title = checks[index].title
            } else {
                title = language.planLoadWarningTitle
            }
            rows.append(.warning(title, value: warning.message))
        }
        for (kind, check) in zip(kinds, checks) where !warned.contains(kind) {
            rows.append(.check(check.title, value: check.detail))
        }
        return rows
    }

    private func chip(
        _ title: String,
        symbol: String,
        tint: Color,
        background: Color? = nil,
        compactLabels: Bool
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            if compactLabels {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } else {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(background ?? Theme.soft(tint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CoachPlanChangedBanner: View {
    let isVisible: Bool
    let language: CoachLanguage

    var body: some View {
        if isVisible {
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
}

private struct CoachLoadWarningBanner: View {
    let warnings: [PlanValidator.Issue]
    let language: CoachLanguage

    var body: some View {
        if !warnings.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.planLoadWarningTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.warn)
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning.message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(language.planLoadWarningConfirmHint)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.soft(Theme.warn), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Facts about the change the runner should know. Nothing here gates Apply.
private struct CoachPlanNoteRow: View {
    let notes: [PlanValidator.Issue]

    var body: some View {
        if !notes.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note.message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.soft(Theme.dim), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

/// The coach's proposed swap, shown inline above the composer instead of a
/// system alert. Every value comes from the staged replacement — the card shows
/// the real before/after workouts and the real weekly-volume delta, and claims
/// nothing the plan engine cannot compute.
struct PlanUpdateCard: View {
    let candidate: CoachPlanCandidate
    let language: CoachLanguage
    var isApplying: Bool = false
    let onApply: () -> Void
    let onKeep: () -> Void
    let onAskWhy: () -> Void

    private var replacement: (
        date: Date,
        existing: WorkoutReplacementSummary,
        proposed: WorkoutReplacementSummary,
        volumeDeltaKm: Double
    ) {
        guard case .replacement(let date, let existing, let proposed, _, let volumeDeltaKm) = candidate.presentation else {
            preconditionFailure("PlanUpdateCard requires a replacement candidate")
        }
        return (date, existing, proposed, volumeDeltaKm)
    }

    private var weekday: String {
        let day = Weekday(rawValue: Calendar.current.component(.weekday, from: replacement.date)) ?? .monday
        return language.shortName(day).uppercased()
    }

    private var applyLabel: String {
        guard candidate.loadRisks.isEmpty else { return language.applyDespiteLoadRiskLabel }
        guard let weekIndex = candidate.transaction.operations.first?.after?.weekIndex else {
            return language.applyChangesLabel
        }
        return language.applyToWeekLabel(weekIndex + 1)
    }

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if isApplying {
                    applyingRow
                } else {
                    titleRow
                    CoachTrustLedger(language: language, loadRisks: candidate.loadRisks, notes: candidate.notes)
                    CoachPlanChangedBanner(isVisible: candidate.changedSinceProposed, language: language)
                    CoachLoadWarningBanner(warnings: candidate.loadRisks, language: language)
                    CoachPlanNoteRow(notes: candidate.notes)
                    diffRow

                    Rectangle().fill(Theme.line).frame(height: 1)

                    Text(language.weeklyVolumeDeltaText(replacement.volumeDeltaKm))
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
        Text(language.workoutRowText(replacement.existing))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.faint)
            .strikethrough(true, color: Theme.faint)
            .lineLimit(singleLine ? 1 : nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func afterLine(singleLine: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(language.workoutRowText(replacement.proposed))
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
                Label(
                    applyLabel,
                    systemImage: candidate.loadRisks.isEmpty ? "checkmark" : "exclamationmark.triangle.fill"
                )
                    .font(.torHeading(13, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(applyLabel)
            .accessibilityHint(candidate.loadRisks.isEmpty ? "" : language.planLoadWarningConfirmHint)
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
    let candidate: CoachPlanCandidate
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
                    CoachTrustLedger(language: language, loadRisks: candidate.loadRisks, notes: candidate.notes)
                    CoachPlanChangedBanner(isVisible: candidate.changedSinceProposed, language: language)
                    CoachLoadWarningBanner(warnings: candidate.loadRisks, language: language)
                    CoachPlanNoteRow(notes: candidate.notes)


                    Text(candidate.summary)
                        .font(.torHeading(15, .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !candidate.proposal.changes.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(candidate.proposal.changes.enumerated()), id: \.offset) { _, change in
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
                .strokeBorder(Theme.border, lineWidth: 1)
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
        .foregroundStyle(Theme.dim)
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
        if let kind = change.workout?.kind, !kind.isEmpty {
            return WorkoutKind(rawValue: kind).map(language.name) ?? language.genericRunLabel
        }
        return (try? CoachTools.parseDay(change.date, calendar: .current)).map { language.shortWeekdayDate($0) } ?? change.date
    }

    private var applyLabel: String {
        candidate.loadRisks.isEmpty ? language.applyChangesLabel : language.applyDespiteLoadRiskLabel
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
                Label(
                    applyLabel,
                    systemImage: candidate.loadRisks.isEmpty ? "checkmark" : "exclamationmark.triangle.fill"
                )
                .font(.torHeading(13, .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(applyLabel)
            .accessibilityHint(candidate.loadRisks.isEmpty ? "" : language.planLoadWarningConfirmHint)
        }
    }
}
