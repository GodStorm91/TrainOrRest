import SwiftUI

struct SeasonCard: View {
    let season: RaceSeason
    let summary: ActivePlanSummary?
    let warnings: [RaceWarning]
    let language: CoachLanguage
    var onSelectRace: (RaceSpec) -> Void
    var onAddRace: () -> Void
    var onOpenWarning: (RaceWarning) -> Void

    private let calendar = Calendar.current

    var body: some View {
        TorCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(language.season.raceCount(season.upcoming.count))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)

                if season.upcoming.isEmpty {
                    emptySeason
                    if let summary {
                        profileRow(language.settings.nextWorkout, nextWorkoutLine(summary))
                    }
                } else {
                    raceRows
                    warningRow
                    planSummary
                }

                addRaceButton
            }
        }
    }

    private var emptySeason: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.season.noRacesYet)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text(language.season.noRacesDescription)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var raceRows: some View {
        VStack(spacing: 10) {
            ForEach(season.upcoming) { race in
                Button {
                    onSelectRace(race)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        RacePriorityBadge(priority: race.priority)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(race.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(raceDateText(race.date)) · \(language.season.daysLeft(daysLeft(to: race.date)))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.dim)
                            Text(language.settings.distanceText(race.kilometers))
                                .font(.caption)
                                .foregroundStyle(Theme.faint)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(raceAccessibilityLabel(race))
            }
        }
    }

    @ViewBuilder
    private var warningRow: some View {
        if let warning = warnings.first {
            Button {
                onOpenWarning(warning)
            } label: {
                HStack(spacing: 6) {
                    Text(language.season.warningText(warning))
                        .font(.footnote)
                        .foregroundStyle(Theme.warn)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text(language.season.viewSuggestion)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(language.season.warningText(warning)). \(language.season.viewSuggestion)")
        }
    }

    @ViewBuilder
    private var planSummary: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(language.settings.weekProgress(current: summary.currentWeek, total: summary.totalWeeks))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(language.settings.timeline)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.faint)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.settings.weekProgress(current: summary.currentWeek, total: summary.totalWeeks))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(language.settings.timeline)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.faint)
                    }
                }
                ProgressView(value: summary.timelineProgress)
                    .tint(progressColor(summary.health.status))
                    .accessibilityLabel(language.settings.weekProgress(current: summary.currentWeek, total: summary.totalWeeks))
            }

            VStack(spacing: 9) {
                if let phase = summary.currentPhase {
                    profileRow(language.settings.currentPhase, phaseLine(phase))
                }
                profileRow(language.settings.nextWorkout, nextWorkoutLine(summary))
            }
        }
    }

    private var addRaceButton: some View {
        Button(action: onAddRace) {
            Text(language.season.addRace)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.season.addRace)
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 16)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private func phaseLine(_ phase: ActivePlanPhaseSummary) -> String {
        let phaseName = language.name(phase.phase)
        guard let aRace = season.aRace else { return phaseName }
        return "\(phaseName) · \(aRace.name)"
    }

    private func nextWorkoutLine(_ summary: ActivePlanSummary) -> String {
        if summary.health.status == .completed { return language.settings.planCompleted }
        if summary.health.status == .paused { return language.settings.planPaused }
        guard let next = summary.nextWorkout else { return language.settings.noUpcomingWorkout }
        return language.settings.workoutSummary(
            name: language.settings.workoutName(kind: next.kind, raw: next.kindRaw),
            distance: language.settings.distanceText(next.distanceKm),
            day: relativeDay(next.date)
        )
    }

    private func relativeDay(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return language.todayLabel }
        if calendar.isDateInTomorrow(date) { return language.tomorrowLabel }
        return language.shortWeekdayDate(date, calendar: calendar)
    }

    private func progressColor(_ status: ActivePlanStatus) -> Color {
        switch status {
        case .onTrack: Theme.good
        case .needsAttention: Theme.warn
        case .paused: Theme.dim
        case .completed, .active: Theme.accent
        }
    }

    private func daysLeft(to date: Date) -> Int {
        max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0)
    }

    private func raceDateText(_ date: Date) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        return sameYear ? language.shortDate(date) : language.settings.longDateWithYear(date)
    }

    private func raceAccessibilityLabel(_ race: RaceSpec) -> String {
        "\(race.name), \(language.settings.longDateWithYear(race.date)), \(language.season.daysLeft(daysLeft(to: race.date))), \(language.settings.distanceText(race.kilometers))"
    }
}

struct RacePriorityBadge: View {
    let priority: RacePriority

    var body: some View {
        Text(priority.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(foregroundColor)
            .frame(width: 22, height: 22)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: priority == .a ? 0 : 1)
            )
    }

    private var backgroundColor: Color {
        priority == .a ? Theme.accent : .clear
    }

    private var foregroundColor: Color {
        switch priority {
        case .a: .white
        case .b: Theme.accent
        case .c: Theme.dim
        }
    }

    private var borderColor: Color {
        priority == .b ? Theme.accent : Theme.border
    }
}
