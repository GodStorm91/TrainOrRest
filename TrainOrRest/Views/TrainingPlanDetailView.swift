import Charts
import SwiftData
import SwiftUI

struct TrainingPlanDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Query private var goals: [Goal]
    @Query private var plans: [TrainingPlan]
    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query private var googleConnections: [GoogleCalendarConnection]
    @Query(sort: \DayAvailability.date) private var availabilityDays: [DayAvailability]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    @State private var showGoalEntry = false
    @State private var weeklySuggestions: [WeeklySmartSchedulingSuggestion] = []
    @State private var isShowingWeeklyScheduleReview = false

    private let calendar = Calendar.current

    private var summary: ActivePlanSummary? {
        ActivePlanSummaryBuilder.build(goal: goals.first, plan: plans.first, activities: activities, calendar: calendar)
    }

    var body: some View {
        ScrollView {
            if let summary {
                VStack(alignment: .leading, spacing: 18) {
                    hero(summary)
                    if let phase = summary.currentPhase {
                        currentPhase(phase)
                    }
                    if let week = summary.thisWeek {
                        weekAdherence(week)
                    }
                    scheduleFit
                    upcoming(summary)
                    progress(summary)
                    phaseTimeline(summary)
                    aboutPlan
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            } else {
                ContentUnavailableView(
                    "Could not load plan details",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Try again from Profile or create a training plan.")
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            }
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let plan = plans.first {
                    Button {
                        togglePause(plan)
                    } label: {
                        Image(systemName: plan.pausedAt == nil ? "pause.circle" : "play.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(plan.pausedAt == nil ? "Pause training plan" : "Resume training plan")
                }
                if !goals.isEmpty {
                    Button {
                        showGoalEntry = true
                    } label: {
                        Image(systemName: "target")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Adjust training plan")
                }
            }
        }
        .sheet(isPresented: $showGoalEntry) { GoalEntryView() }
        .sheet(isPresented: $isShowingWeeklyScheduleReview) {
            WeeklySmartSchedulingReviewView(suggestions: weeklySuggestions) { suggestions in
                suggestions.forEach { googleCalendar.acceptSmartSchedulingCandidate($0.candidate) }
                isShowingWeeklyScheduleReview = false
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: true)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: false)
        }
    }

    private func hero(_ summary: ActivePlanSummary) -> some View {
        TorCard(padding: 18, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    TorEyebrow(summary.health.status.displayName.uppercased())
                        .foregroundStyle(statusColor(summary.health.status))
                    Text(summary.title)
                        .font(.torHeading(25, .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary.raceDate.formatted(date: .long, time: .omitted))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], alignment: .leading, spacing: 10) {
                    detailMetric("Target", Formatters.duration(summary.targetTimeSeconds))
                    detailMetric("Running days", "\(summary.runningDaysPerWeek)/week")
                    if let days = summary.daysRemaining {
                        detailMetric("Time remaining", summary.isRaceDay ? "Race day" : "\(days) days")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Week \(summary.currentWeek) of \(summary.totalWeeks)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("Timeline")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.faint)
                    }
                    ProgressView(value: summary.timelineProgress)
                        .tint(Theme.accent)
                        .accessibilityLabel("Week \(summary.currentWeek) of \(summary.totalWeeks)")
                }
            }
        }
    }

    private func currentPhase(_ phase: ActivePlanPhaseSummary) -> some View {
        section("CURRENT PHASE") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(phase.displayName)
                        .font(.torHeading(21, .bold))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    if let week = phase.currentWeekInPhase {
                        Text("Week \(week) of \(phase.totalWeeks)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.faint)
                    }
                }
                Text("\(phase.startDate.formatted(.dateTime.month(.abbreviated).day())) - \(phase.endDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.dim)
                Text(phase.phase.summaryPurpose)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let range = phase.targetVolumeRangeKm {
                    detailRow("Weekly target", "\(distanceText(range.lowerBound))-\(distanceText(range.upperBound))")
                }
                if let week = phase.currentWeekInPhase {
                    ProgressView(value: Double(week), total: Double(max(phase.totalWeeks, 1)))
                        .tint(phase.phase.styleColor)
                        .accessibilityLabel("Phase progress week \(week) of \(phase.totalWeeks)")
                }
            }
        }
    }

    private func weekAdherence(_ week: ActivePlanWeekSummary) -> some View {
        section("THIS WEEK") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(week.completedSessions) of \(week.plannedSessions) sessions completed")
                    .font(.torHeading(20, .bold))
                    .foregroundStyle(Theme.text)
                Text("\(distanceText(week.completedDistanceKm)) of \(distanceText(week.plannedDistanceKm))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                ProgressView(value: week.volumeCompliance.map { min($0, 1) } ?? 0)
                    .tint(Theme.accent)
                    .accessibilityLabel("Weekly distance \(distanceText(week.completedDistanceKm)) of \(distanceText(week.plannedDistanceKm))")
            }
        }
    }

    @ViewBuilder
    private var scheduleFit: some View {
        if let connection = googleConnections.first, connection.smartSchedulingEnabled, let plan = plans.first, let goal = goals.first?.spec {
            let weekStart = PlanGenerator.mondayOfWeek(containing: Date(), calendar: calendar)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let weekWorkouts = workouts.filter { $0.date >= weekStart && $0.date < weekEnd }
            let engine = SmartSchedulingEngine(calendar: calendar)
            let preferences = SmartSchedulingPreferences(
                preferredTime: connection.preferredTrainingTime,
                earliestStartMinutes: connection.smartSchedulingEarliestStartOrDefault,
                latestFinishMinutes: connection.smartSchedulingLatestFinishOrDefault,
                bufferBeforeMinutes: connection.smartSchedulingBufferBeforeOrDefault,
                bufferAfterMinutes: connection.smartSchedulingBufferAfterOrDefault
            )
            let fit = engine.weekFit(workouts: weekWorkouts, availability: availabilityDays.filter { $0.connectionID == connection.uuid }) { workout in
                SchedulingRequest(
                    workout: workout,
                    candidateDates: (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) },
                    currentTrainingWeek: workout.weekIndex,
                    surroundingWorkouts: workouts,
                    userPreferences: preferences,
                    availability: availabilityDays.filter { $0.connectionID == connection.uuid },
                    timezone: .current,
                    plan: plan,
                    goal: goal
                )
            }
            section("SCHEDULE FIT") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(scheduleFitTitle(fit))
                        .font(.torHeading(20, .bold))
                        .foregroundStyle(Theme.text)
                    Text(scheduleFitDetail(fit))
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        weeklySuggestions = buildWeeklySuggestions(weekWorkouts: weekWorkouts)
                        isShowingWeeklyScheduleReview = true
                    } label: {
                        Label("Review schedule", systemImage: "calendar")
                            .frame(minHeight: 44)
                    }
                    .disabled(fit.availableValidSlots == 0)
                    .accessibilityLabel("Review weekly schedule")
                }
            }
        }
    }

    private func upcoming(_ summary: ActivePlanSummary) -> some View {
        section("UP NEXT") {
            VStack(spacing: 10) {
                if summary.upcomingWorkouts.isEmpty {
                    Text(summary.health.status == .completed ? "Plan completed" : "No upcoming workout")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(summary.upcomingWorkouts) { workout in
                        if let planned = plannedWorkout(for: workout.id) {
                            NavigationLink {
                                WorkoutDetailView(workout: planned)
                            } label: {
                                upcomingRow(workout)
                            }
                            .buttonStyle(.plain)
                        } else {
                            upcomingRow(workout)
                        }
                    }
                    NavigationLink {
                        PlanCalendarView()
                    } label: {
                        HStack {
                            Text("View in Calendar")
                            Spacer()
                            Image(systemName: "calendar")
                        }
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View training plan in Calendar")
                }
            }
        }
    }

    private func progress(_ summary: ActivePlanSummary) -> some View {
        section("PLANNED VS COMPLETED") {
            VStack(alignment: .leading, spacing: 12) {
                if let text = progressSummary(summary) {
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Chart(summary.weeklyProgress) { week in
                    BarMark(
                        x: .value("Week", week.weekIndex + 1),
                        y: .value("Planned", week.plannedDistanceKm)
                    )
                    .foregroundStyle(Theme.faint.opacity(0.28))
                    .position(by: .value("Metric", "Planned"))

                    BarMark(
                        x: .value("Week", week.weekIndex + 1),
                        y: .value("Completed", week.completedDistanceKm)
                    )
                    .foregroundStyle(Theme.accent)
                    .position(by: .value("Metric", "Completed"))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("W\(intValue)")
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 170)
                .accessibilityLabel(chartAccessibility(summary))
            }
        }
    }

    private func phaseTimeline(_ summary: ActivePlanSummary) -> some View {
        section("PLAN PHASES") {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(summary.phases) { phase in
                    HStack(spacing: 10) {
                        Image(systemName: phaseSymbol(phase, currentWeek: summary.currentWeek - 1))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(phaseColor(phase, currentWeek: summary.currentWeek - 1))
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Weeks \(phase.startWeekIndex + 1)-\(phase.endWeekIndex + 1)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.faint)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var aboutPlan: some View {
        section("ABOUT THIS PLAN") {
            Text("This plan gradually builds weekly volume and race-specific endurance while adapting recommendations to your schedule and available training data.")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow(title).tracking(1.5)
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
    }

    private func detailMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.torHeading(17, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
    }

    private func upcomingRow(_ workout: ActivePlanWorkoutSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind?.symbolName ?? "figure.run")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(workout.kind?.styleColor ?? Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.soft(workout.kind?.styleColor ?? Theme.accent), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(relativeDay(workout.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.faint)
                Text("\(workout.displayName) \(distanceText(workout.distanceKm))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let band = workout.paceBand {
                    Text(Formatters.paceBand(band).replacingOccurrences(of: " /km", with: "/km"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.faint)
        }
        .frame(minHeight: 56)
        .accessibilityLabel("Open next workout: \(workout.displayName) \(distanceText(workout.distanceKm)) \(relativeDay(workout.date))")
    }

    private func plannedWorkout(for id: UUID) -> PlannedWorkout? {
        plans.first?.workouts.first { $0.uuid == id }
    }

    private func progressSummary(_ summary: ActivePlanSummary) -> String? {
        let recent = summary.weeklyProgress.filter { $0.startDate <= calendar.startOfDay(for: .now) }.suffix(4)
        let planned = recent.reduce(0) { $0 + $1.plannedDistanceKm }
        guard planned > 0 else { return nil }
        let completed = recent.reduce(0) { $0 + $1.completedDistanceKm }
        return "You completed \(Int((completed / planned * 100).rounded()))% of planned distance over the last \(recent.count) weeks."
    }

    private func chartAccessibility(_ summary: ActivePlanSummary) -> String {
        let planned = summary.weeklyProgress.reduce(0) { $0 + $1.plannedDistanceKm }
        let completed = summary.weeklyProgress.reduce(0) { $0 + $1.completedDistanceKm }
        return "Planned versus completed weekly distance. Completed \(distanceText(completed)) of \(distanceText(planned))."
    }

    private func scheduleFitTitle(_ fit: WeekScheduleFit) -> String {
        switch fit.status {
        case .fitsWell:
            return "This week fits your current availability"
        case .needsScheduling:
            return "\(fit.unscheduledWorkouts) workouts need scheduling"
        case .scheduleConflict:
            return "\(fit.conflictingWorkouts) workout timing conflicts"
        }
    }

    private func scheduleFitDetail(_ fit: WeekScheduleFit) -> String {
        switch fit.status {
        case .fitsWell:
            return "\(fit.scheduledWorkouts) workouts are scheduled and no busy-time conflicts were found."
        case .needsScheduling:
            return "\(fit.availableValidSlots) valid Smart Scheduling slots are available this week."
        case .scheduleConflict:
            return "At least one workout overlaps busy time. Review options before changing the plan."
        }
    }

    private func buildWeeklySuggestions(weekWorkouts: [PlannedWorkout]) -> [WeeklySmartSchedulingSuggestion] {
        weekWorkouts.compactMap { workout in
            guard !workout.isScheduleLocked else { return nil }
            guard let candidate = googleCalendar.smartSchedulingCandidates(for: workout, limit: 1).first else { return nil }
            return WeeklySmartSchedulingSuggestion(workout: workout, candidate: candidate)
        }
    }

    private func relativeDay(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func distanceText(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    private func statusColor(_ status: ActivePlanStatus) -> Color {
        switch status {
        case .onTrack: Theme.good
        case .needsAttention: Theme.warn
        case .paused: Theme.dim
        case .completed: Theme.accent
        case .active: Theme.accent
        }
    }

    private func phaseSymbol(_ phase: ActivePlanPhaseSummary, currentWeek: Int) -> String {
        if currentWeek > phase.endWeekIndex { return "checkmark.circle.fill" }
        if phase.startWeekIndex...phase.endWeekIndex ~= currentWeek { return "circle.fill" }
        return "circle"
    }

    private func phaseColor(_ phase: ActivePlanPhaseSummary, currentWeek: Int) -> Color {
        if currentWeek > phase.endWeekIndex { return Theme.good }
        if phase.startWeekIndex...phase.endWeekIndex ~= currentWeek { return phase.phase.styleColor }
        return Theme.faint
    }

    private func togglePause(_ plan: TrainingPlan) {
        plan.pausedAt = plan.pausedAt == nil ? .now : nil
        try? modelContext.save()
    }
}

private struct WeeklySmartSchedulingSuggestion: Identifiable {
    var id: UUID { workout.uuid }
    var workout: PlannedWorkout
    var candidate: SchedulingCandidate
}

private struct WeeklySmartSchedulingReviewView: View {
    let suggestions: [WeeklySmartSchedulingSuggestion]
    let onApply: ([WeeklySmartSchedulingSuggestion]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No suitable slot",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Smart Scheduling could not find safe available windows for this week.")
                    )
                } else {
                    Section {
                        ForEach(suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(suggestion.workout.kind?.displayName ?? "Workout")
                                    .font(.headline)
                                Text("\(suggestion.candidate.startTime.formatted(date: .abbreviated, time: .shortened))-\(suggestion.candidate.endTime.formatted(date: .omitted, time: .shortened))")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(suggestion.candidate.reasons.prefix(3), id: \.self) { reason in
                                    Text("• \(reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Best scheduling option for \(suggestion.workout.kind?.displayName ?? "workout")")
                        }
                    } header: {
                        Text("Suggested schedule adjustment")
                    } footer: {
                        Text("RestOrTrain validates recovery and plan rules before showing these options. No workout moves until you apply the changes.")
                    }
                }
            }
            .navigationTitle("Review schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep current") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply changes") { onApply(suggestions) }
                        .disabled(suggestions.isEmpty)
                        .accessibilityLabel("Apply Smart Scheduling changes")
                }
            }
        }
    }
}
