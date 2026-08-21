import SwiftData
import SwiftUI

/// RestOrTrain-style week mode: collapsed weekly summaries, expandable current
/// week, and completed Garmin runs rendered as post-run cards inside the week.
struct PlanWeekListView: View {
    /// Bumping this value scrolls the list to the current week.
    var scrollToTodayToken: Int
    var onReviewRunInChat: (CompletedActivity) -> Void = { _ in }

    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @Query private var plans: [TrainingPlan]

    @State private var expandedWeekStarts: Set<Date> = []
    private var calendar: Calendar { .current }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(weekStarts, id: \.self) { weekStart in
                        VStack(alignment: .leading, spacing: 10) {
                            weekHeader(weekStart)
                                .id(weekStart)
                            if expandedWeekStarts.contains(weekStart) {
                                weekDays(weekStart)
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
                scrollToToday(proxy, animated: false)
            }
            .onChange(of: scrollToTodayToken) {
                expandedWeekStarts.insert(todayWeekStart)
                scrollToToday(proxy, animated: true)
            }
        }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, animated: Bool) {
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

    private func weekHeader(_ weekStart: Date) -> some View {
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
                    Text(weekSummary(weekStart))
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

    private func weekDays(_ weekStart: Date) -> some View {
        VStack(spacing: 10) {
            ForEach(days(inWeekStarting: weekStart), id: \.self) { date in
                dayRow(date)
            }
        }
    }

    private func dayRow(_ date: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            dayRail(date)

            VStack(alignment: .leading, spacing: 8) {
                if let activity = completedActivity(on: date) {
                    CalendarRunSummaryCard(
                        activity: activity,
                        plannedWorkout: matchedWorkout(for: activity) ?? workouts(on: date).first,
                        compact: true,
                        reviewDestination: AnyView(ChatView(contextualCompletedActivityID: activity.hkUUID)),
                        onReview: { onReviewRunInChat(activity) }
                    )
                } else if let workout = workouts(on: date).first {
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
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
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
                        TorEyebrow(workout.kind?.displayName ?? "Session").tracking(1.5)
                    }
                    Text(workout.kind?.displayName ?? "Run")
                        .font(.torHeading(17, .bold))
                        .foregroundStyle(Theme.text)
                    Text(plannedSubtitle(workout))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
                statusBadge(workout)
            }

            HStack(spacing: 8) {
                if let actionTitle = contextualCoachActionTitle(for: workout) {
                    NavigationLink {
                        ChatView(contextualWorkoutID: workout.uuid)
                    } label: {
                        Label(actionTitle, systemImage: "sparkles")
                            .font(.torHeading(13, .bold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(actionTitle) \(workout.kind?.displayName ?? "workout")")
                }

                NavigationLink {
                    WorkoutDetailView(workout: workout)
                } label: {
                    Label("Details", systemImage: "chevron.right")
                        .font(.torHeading(13, .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 104, height: 44)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open workout details")
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(calendar.isDateInToday(workout.date) ? Theme.accent : Theme.border, lineWidth: 1))
    }

    private func contextualCoachActionTitle(for workout: PlannedWorkout) -> String? {
        switch workout.status {
        case .planned:
            return workout.isScheduleLocked || workout.kind == .race ? "Review with Coach" : "Edit with Coach"
        case .done:
            return "Review with Coach"
        case .skipped:
            return nil
        }
    }

    private var restPlaceholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Theme.border.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .frame(height: 86)
            .overlay(alignment: .leading) {
                Text("Rest")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.faint)
                    .padding(.leading, 16)
            }
    }

    @ViewBuilder
    private func statusBadge(_ workout: PlannedWorkout) -> some View {
        switch workout.status {
        case .done: badge("DONE", Theme.good)
        case .skipped: badge("SKIPPED", Theme.warn)
        case .planned:
            if calendar.isDateInToday(workout.date) { badge("TODAY", Theme.accent) }
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

    private var workoutsByWeekStart: [Date: [PlannedWorkout]] {
        Dictionary(grouping: workouts) { PlanGenerator.mondayOfWeek(containing: $0.date, calendar: calendar) }
    }

    private var activitiesByWeekStart: [Date: [CompletedActivity]] {
        Dictionary(grouping: completedActivities) { PlanGenerator.mondayOfWeek(containing: $0.date, calendar: calendar) }
    }

    private var weekStarts: [Date] {
        Set(workoutsByWeekStart.keys).union(activitiesByWeekStart.keys).sorted()
    }

    private var todayWeekStart: Date {
        PlanGenerator.mondayOfWeek(containing: .now, calendar: calendar)
    }

    private func weekTitle(_ weekStart: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let month1 = weekStart.formatted(.dateTime.month(.abbreviated))
        let month2 = end.formatted(.dateTime.month(.abbreviated))
        if month1 == month2 {
            return "\(month1) \(calendar.component(.day, from: weekStart)) - \(calendar.component(.day, from: end))"
        }
        return "\(month1) \(calendar.component(.day, from: weekStart)) - \(month2) \(calendar.component(.day, from: end))"
    }

    private func weekSummary(_ weekStart: Date) -> String {
        let workouts = workoutsByWeekStart[weekStart] ?? []
        let activities = activitiesByWeekStart[weekStart] ?? []
        let plannedMinutes = workouts.compactMap(\.expectedDurationSeconds).reduce(0, +) / 60
        let doneMinutes = activities.reduce(0) { $0 + $1.durationSeconds } / 60
        let plannedLoad = workouts.compactMap { $0.expectedDurationSeconds }.reduce(0) { $0 + TrainingLoad.sessionLoad(durationSeconds: $1, avgPaceSecondsPerKm: nil, paces: nil) }
        let doneLoad = activities.reduce(0) { $0 + TrainingLoad.sessionLoad(durationSeconds: $1.durationSeconds, avgPaceSecondsPerKm: $1.avgPaceSecondsPerKm, paces: nil) }
        if doneMinutes > 0 {
            return "\(minutes(doneMinutes)) / \(minutes(plannedMinutes))  \(Int(doneLoad.rounded())) / \(Int(plannedLoad.rounded())) Load"
        }
        return "\(minutes(plannedMinutes))  \(Int(plannedLoad.rounded())) Load"
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

    private func workouts(on date: Date) -> [PlannedWorkout] {
        workouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func completedActivity(on date: Date) -> CompletedActivity? {
        completedActivities.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func matchedWorkout(for activity: CompletedActivity) -> PlannedWorkout? {
        workouts.first(where: { $0.matchedActivityUUID == activity.hkUUID }) ?? workouts(on: activity.date).first
    }
}
