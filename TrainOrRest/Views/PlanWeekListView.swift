import SwiftData
import SwiftUI

/// TrainOrRest-style week mode: collapsed weekly summaries, expandable current
/// week, and completed Garmin runs rendered as post-run cards inside the week.
struct PlanWeekListView: View {
    /// Bumping this value scrolls the list to the current week.
    var scrollToTodayToken: Int
    let language: CoachLanguage
    var onReviewRunInChat: (CompletedActivity) -> Void = { _ in }

    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Query private var plans: [TrainingPlan]

    @State private var expandedWeekStarts: Set<Date> = []
    private var calendar: Calendar { .current }

    var body: some View {
        let index = WeekIndex(workouts: workouts, activities: completedActivities, calendar: calendar)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(index.weekStarts, id: \.self) { weekStart in
                        VStack(alignment: .leading, spacing: 10) {
                            weekHeader(weekStart, index: index)
                                .id(weekStart)
                            if expandedWeekStarts.contains(weekStart) {
                                weekDays(weekStart, index: index)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .onAppear {
                expandedWeekStarts.insert(todayWeekStart)
                scrollToToday(proxy, weekStarts: index.weekStarts, animated: false)
            }
            .onChange(of: scrollToTodayToken) {
                expandedWeekStarts.insert(todayWeekStart)
                scrollToToday(proxy, weekStarts: index.weekStarts, animated: true)
            }
        }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, weekStarts: [Date], animated: Bool) {
        guard weekStarts.contains(todayWeekStart) else { return }
        DispatchQueue.main.async {
            let action = { proxy.scrollTo(todayWeekStart, anchor: .top) }
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { action() }
            } else {
                action()
            }
        }
    }

    private func weekHeader(_ weekStart: Date, index: WeekIndex) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { toggleWeek(weekStart) }
        } label: {
            HStack(spacing: 10) {
                Text("🗓️")
                    .font(.system(size: 21))
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekTitle(weekStart))
                        .font(.torHeading(20, .bold))
                        .foregroundStyle(Theme.text)
                    Text(weekSummary(weekStart, index: index))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.faint)
                Image(systemName: expandedWeekStarts.contains(weekStart) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func weekDays(_ weekStart: Date, index: WeekIndex) -> some View {
        VStack(spacing: 10) {
            ForEach(days(inWeekStarting: weekStart), id: \.self) { date in
                dayRow(date, index: index)
            }
        }
    }

    private func dayRow(_ date: Date, index: WeekIndex) -> some View {
        HStack(alignment: .top, spacing: 12) {
            dayRail(date)

            VStack(alignment: .leading, spacing: 8) {
                if let activity = index.activity(on: date) {
                    CalendarRunSummaryCard(
                        activity: activity,
                        plannedWorkout: index.matchedWorkout(for: activity),
                        compact: true,
                        reviewDestination: ChatView(contextualCompletedActivityID: activity.hkUUID),
                        onReview: { onReviewRunInChat(activity) }
                    )
                } else if let workout = index.workouts(on: date).first {
                    plannedDayCard(workout)
                } else {
                    restPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func dayRail(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 2) {
            Text(language.shortName(Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isToday ? Color.white : Theme.dim)
            Text("\(calendar.component(.day, from: date))")
                .font(.torHeading(22, .bold))
                .foregroundStyle(isToday ? Color.white : Theme.text)
        }
        .frame(width: 50)
        .frame(minHeight: 68)
        .padding(.vertical, 8)
        .background(isToday ? Color(hex: 0x334155) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func plannedDayCard(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: workout.kind?.symbolName ?? "figure.run")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(workout.kind?.styleColor ?? Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(Theme.soft(workout.kind?.styleColor ?? Theme.accent), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Circle().fill(workout.kind?.styleColor ?? Theme.dim).frame(width: 7, height: 7)
                        TorEyebrow(workout.kind.map(language.name) ?? language.plan.sessionLabel).tracking(1.5)
                    }
                    Text(workout.kind.map(language.name) ?? language.genericRunLabel)
                        .font(.torHeading(17, .bold))
                        .foregroundStyle(Theme.text)
                    Text(plannedSubtitle(workout))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    if let shoe = assignedShoe(for: workout) {
                        HStack(spacing: 5) {
                            Image(systemName: "shoeprints.fill")
                            Text(workout.shoeAssignmentSource == .auto ? "\(shoe.displayName) · \(language.plan.autoLabel)" : shoe.displayName)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
                Spacer(minLength: 8)
                statusBadge(workout)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    coachAction(workout, fixedWidth: true)
                    detailsAction(workout, fixedWidth: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    coachAction(workout, fixedWidth: false)
                    detailsAction(workout, fixedWidth: false)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(calendar.isDateInToday(workout.date) ? Theme.accent : Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func coachAction(_ workout: PlannedWorkout, fixedWidth: Bool) -> some View {
        if let actionTitle = contextualCoachActionTitle(for: workout) {
            NavigationLink {
                ChatView(contextualWorkoutID: workout.uuid)
            } label: {
                Label(actionTitle, systemImage: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: fixedWidth, vertical: !fixedWidth)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.plan.coachActionAccessibility(actionTitle, workout: workout.kind.map(language.name) ?? language.plan.workout))
        }
    }

    private func detailsAction(_ workout: PlannedWorkout, fixedWidth: Bool) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            Label(language.detailsLabel, systemImage: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: fixedWidth, vertical: !fixedWidth)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.plan.openWorkoutDetailsAccessibility)
    }


    private func contextualCoachActionTitle(for workout: PlannedWorkout) -> String? {
        switch workout.status {
        case .planned:
            return workout.isScheduleLocked || workout.kind == .race ? language.plan.reviewWithCoach : language.plan.editWithCoach
        case .done:
            return language.plan.reviewWithCoach
        case .skipped:
            return nil
        }
    }

    private var restPlaceholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Theme.border.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .frame(height: 86)
            .overlay(alignment: .leading) {
                Text(language.restDayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.faint)
                    .padding(.leading, 16)
            }
    }

    @ViewBuilder
    private func statusBadge(_ workout: PlannedWorkout) -> some View {
        switch workout.status {
        case .done: badge(language.name(.done).uppercased(), Theme.good)
        case .skipped: badge(language.name(.skipped).uppercased(), Theme.warn)
        case .planned:
            if calendar.isDateInToday(workout.date) { badge(language.todayLabel.uppercased(), Theme.accent) }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.torLabel(10, .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.soft(color), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func plannedSubtitle(_ workout: PlannedWorkout) -> String {
        var parts = [String(format: "%.2f km", workout.distanceKm)]
        if let band = workout.paceBand { parts.append(Formatters.paceBand(band).replacingOccurrences(of: " /km", with: "/km")) }
        if let seconds = workout.expectedDurationSeconds { parts.append("~\(Int((seconds / 60).rounded())) min") }
        return parts.joined(separator: " · ")
    }

    private func toggleWeek(_ weekStart: Date) {
        if expandedWeekStarts.contains(weekStart) {
            expandedWeekStarts.remove(weekStart)
        } else {
            expandedWeekStarts.insert(weekStart)
        }
    }

    /// Lookup tables built once per body evaluation so week headers and day
    /// rows do not each regroup every workout and activity.
    private struct WeekIndex {
        let weekStarts: [Date]
        let workoutsByWeekStart: [Date: [PlannedWorkout]]
        let activitiesByWeekStart: [Date: [CompletedActivity]]
        private let workoutsByDay: [Date: [PlannedWorkout]]
        private let activityByDay: [Date: CompletedActivity]
        private let workoutByMatchedActivity: [UUID: PlannedWorkout]
        private let calendar: Calendar

        init(workouts: [PlannedWorkout], activities: [CompletedActivity], calendar: Calendar) {
            self.calendar = calendar
            workoutsByWeekStart = Dictionary(grouping: workouts) { PlanGenerator.mondayOfWeek(containing: $0.date, calendar: calendar) }
            activitiesByWeekStart = Dictionary(grouping: activities) { PlanGenerator.mondayOfWeek(containing: $0.date, calendar: calendar) }
            weekStarts = Set(workoutsByWeekStart.keys).union(activitiesByWeekStart.keys).sorted()
            workoutsByDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.date) }
            // Activities arrive newest-first; keep the first seen per day like the old scan did.
            activityByDay = Dictionary(activities.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
            workoutByMatchedActivity = Dictionary(
                workouts.compactMap { workout in workout.matchedActivityUUID.map { ($0, workout) } },
                uniquingKeysWith: { first, _ in first }
            )
        }

        func workouts(on date: Date) -> [PlannedWorkout] {
            workoutsByDay[calendar.startOfDay(for: date)] ?? []
        }

        func activity(on date: Date) -> CompletedActivity? {
            activityByDay[calendar.startOfDay(for: date)]
        }

        func matchedWorkout(for activity: CompletedActivity) -> PlannedWorkout? {
            workoutByMatchedActivity[activity.hkUUID] ?? workouts(on: activity.date).first
        }
    }

    private var todayWeekStart: Date {
        PlanGenerator.mondayOfWeek(containing: .now, calendar: calendar)
    }

    private func weekTitle(_ weekStart: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return language.plan.weekRange(weekStart, end)
    }

    private func weekSummary(_ weekStart: Date, index: WeekIndex) -> String {
        let workouts = index.workoutsByWeekStart[weekStart] ?? []
        let activities = index.activitiesByWeekStart[weekStart] ?? []
        let plannedMinutes = workouts.compactMap(\.expectedDurationSeconds).reduce(0, +) / 60
        let doneMinutes = activities.reduce(0) { $0 + $1.durationSeconds } / 60
        let plannedLoad = workouts.compactMap { $0.expectedDurationSeconds }.reduce(0) { $0 + TrainingLoad.sessionLoad(durationSeconds: $1, avgPaceSecondsPerKm: nil, paces: nil) }
        let doneLoad = activities.reduce(0) { $0 + TrainingLoad.sessionLoad(durationSeconds: $1.durationSeconds, avgPaceSecondsPerKm: $1.avgPaceSecondsPerKm, paces: nil) }
        if doneMinutes > 0 {
            return language.plan.weekSummary(
                completed: minutes(doneMinutes),
                planned: minutes(plannedMinutes),
                completedLoad: Int(doneLoad.rounded()),
                plannedLoad: Int(plannedLoad.rounded())
            )
        }
        return language.plan.weekSummary(
            completed: nil,
            planned: minutes(plannedMinutes),
            completedLoad: nil,
            plannedLoad: Int(plannedLoad.rounded())
        )
    }

    private func minutes(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded >= 60 {
            let hours = rounded / 60
            let minutes = rounded % 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        return "\(rounded)m"
    }

    private func days(inWeekStarting weekStart: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func assignedShoe(for workout: PlannedWorkout) -> RunningShoe? {
        guard let shoeID = workout.shoeID else { return nil }
        return shoes.first { $0.id == shoeID }
    }
}
