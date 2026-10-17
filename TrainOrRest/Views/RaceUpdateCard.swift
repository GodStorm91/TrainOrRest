import SwiftUI

struct RaceUpdateCard: View {
    let candidate: CoachRaceCandidate
    let language: CoachLanguage
    let onSave: () -> Void
    let onDismiss: () -> Void

    private static let visibleDayLimit = 6

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                eyebrow
                headlineRow
                if let suggestion = candidate.suggestion, !suggestionRepeatsWarning {
                    Text(language.season.prioritySuggestion(
                        suggestion.priority,
                        reason: suggestion.reason,
                        weeks: suggestion.weeksToARace
                    ))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                }
                warningRows
                dayChangeRows
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var eyebrow: some View {
        HStack(spacing: 7) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 11, weight: .bold))
            Text(language.season.confirmEyebrow)
                .font(.torLabel(11, .bold))
                .tracking(1.4)
        }
        .foregroundStyle(Theme.dim)
    }

    @ViewBuilder
    private var headlineRow: some View {
        if let race = headlineRace {
            HStack(alignment: .top, spacing: 10) {
                RacePriorityBadge(priority: race.priority)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.torHeading(15, .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(raceDetailLine(race))
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(headline)
                .font(.torHeading(15, .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var warningRows: some View {
        if !candidate.change.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(candidate.change.warnings) { warning in
                    Text(language.season.warningText(warning))
                        .font(.footnote)
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var dayChangeRows: some View {
        if candidate.change.dayChanges.isEmpty {
            Text(language.season.noDayChanges)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.faint)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(visibleDayChanges) { dayChange in
                    dayRow(dayChange)
                }
                if hiddenDayCount > 0 {
                    Text(language.season.moreDays(hiddenDayCount))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.faint)
                }
            }
        }
    }

    private func dayRow(_ dayChange: RaceDayChange) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.shortWeekdayDate(dayChange.date))
                    .font(.torLabel(10, .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.faint)
                Text(tag(for: dayChange.intent))
                    .font(.caption2.weight(dayChange.intent == .raceDay ? .bold : .semibold))
                    .foregroundStyle(dayChange.intent == .raceDay ? Theme.text : Theme.dim)
            }
            .frame(width: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if let before = dayChange.beforeSummary, before != dayChange.afterSummary {
                    Text(before)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.faint)
                        .strikethrough(true, color: Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(dayChange.afterSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                Text(language.season.confirmLater)
                    .font(.torHeading(13, .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)

            Button(action: onSave) {
                Label(language.season.confirmSave, systemImage: "checkmark")
                    .font(.torHeading(13, .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 8)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.season.confirmSave)
        }
    }

    private var visibleDayChanges: [RaceDayChange] {
        Array(candidate.change.dayChanges.prefix(Self.visibleDayLimit))
    }

    private var hiddenDayCount: Int {
        max(candidate.change.dayChanges.count - Self.visibleDayLimit, 0)
    }

    private var suggestionRepeatsWarning: Bool {
        guard let reason = candidate.suggestion?.reason else { return false }
        let codes = Set(candidate.change.warnings.map(\.code))
        switch reason {
        case .insideARaceTaper: return codes.contains(.insideARaceTaper)
        case .insideRecoveryWindow: return codes.contains(.insideRecoveryWindow)
        case .noARaceYet, .farFromARace, .closeToARace: return false
        }
    }

    private var headlineRace: RaceSpec? {
        switch candidate.intent {
        case .add(let race), .remove(let race), .result(let race, _): race
        case .update(_, let after): after
        case .rebalance: nil
        }
    }

    private var headline: String {
        switch candidate.intent {
        case .add(let race): language.season.addRaceHeadline(race.name)
        case .update(_, let after): language.season.updateRaceHeadline(after.name)
        case .remove(let race): language.season.removeRaceHeadline(race.name)
        case .result(let race, _): language.season.resultRaceHeadline(race.name)
        case .rebalance: language.season.rebalanceHeadline
        }
    }

    private func raceDetailLine(_ race: RaceSpec) -> String {
        let distance = race.standardDistance.map { language.name($0) }
            ?? language.settings.distanceText(race.kilometers)
        return "\(language.settings.longDateWithYear(race.date)) · \(distance)"
    }

    private func tag(for intent: RaceDayChange.Intent) -> String {
        switch intent {
        case .raceDay: language.season.raceDayTag
        case .replacesQuality: language.season.runAsWorkoutTag
        case .taper: language.season.taperTag
        case .miniTaper: language.season.miniTaperTag
        case .recovery: language.season.recoveryTag
        }
    }
}
