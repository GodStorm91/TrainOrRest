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
    @State private var isShowingGoalMetricDetail = false
    @State private var isShowingGoalAssessmentDetail = false
    @State private var isShowingPlanAdjustmentPreview = false
    @State private var planAdjustmentError: String?
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private let calendar = Calendar.current

    private var summary: ActivePlanSummary? {
        ActivePlanSummaryBuilder.build(goal: goals.first, plan: plans.first, activities: activities, calendar: calendar)
    }

    private var language: CoachLanguage {
        CoachLanguage(rawValue: languageRaw) ?? .en
    }

    private var goalAssessment: GoalAssessment? {
        guard let goal = goals.first, let plan = plans.first else { return nil }
        return GoalAssessmentBuilder.build(goal: goal, plan: plan, activities: activities, calendar: calendar)
    }

    var body: some View {
        ScrollView {
            if let summary {
                VStack(alignment: .leading, spacing: 18) {
                    if let assessment = goalAssessment {
                        RaceGoalStatusCard(
                            assessment: assessment,
                            summary: summary,
                            language: language,
                            onAdjustPlan: { isShowingPlanAdjustmentPreview = true },
                            onShowMetricDetail: { isShowingGoalMetricDetail = true },
                            onShowAssessmentDetail: { isShowingGoalAssessmentDetail = true }
                        )
                        if let attention = GoalAssessmentBuilder.primaryAttentionItem(for: assessment) {
                            PrimaryAttentionCard(
                                assessment: assessment,
                                item: attention,
                                language: language,
                                onShowDetails: { isShowingGoalAssessmentDetail = true },
                                coachRequest: goalAttentionCoachRequest(assessment: assessment, item: attention)
                            )
                        }
                    } else {
                        hero(summary)
                    }
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
        .sheet(isPresented: $isShowingGoalMetricDetail) {
            if let assessment = goalAssessment {
                GoalMetricDetailSheet(assessment: assessment, language: language)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $isShowingGoalAssessmentDetail) {
            if let assessment = goalAssessment {
                GoalAssessmentDetailSheet(assessment: assessment, language: language)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $isShowingPlanAdjustmentPreview) {
            if let assessment = goalAssessment, let plan = plans.first {
                PlanAdjustmentPreviewSheet(
                    proposal: GoalPlanAdjustmentEngine.proposal(
                        assessment: assessment,
                        summary: summary,
                        plan: plan,
                        today: .now,
                        calendar: calendar,
                        language: language
                    ),
                    language: language
                ) { proposal in
                    do {
                        try GoalPlanAdjustmentEngine.apply(
                            proposal,
                            to: plan,
                            in: modelContext,
                            today: .now,
                            calendar: calendar
                        )
                        isShowingPlanAdjustmentPreview = false
                        planAdjustmentError = nil
                    } catch {
                        planAdjustmentError = error.localizedDescription
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .alert("Plan adjustment failed", isPresented: Binding(
            get: { planAdjustmentError != nil },
            set: { if !$0 { planAdjustmentError = nil } }
        )) {
            Button("OK", role: .cancel) { planAdjustmentError = nil }
        } message: {
            Text(planAdjustmentError ?? "")
        }
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

    private func goalAttentionCoachRequest(
        assessment: GoalAssessment,
        item: GoalAttentionItem
    ) -> CalendarReviewChatRequest {
        let evidence = item.evidence.map { "- \(goalEvidenceText($0, language: language))" }.joined(separator: "\n")
        let factorLines = assessment.factors.map {
            "- \(language.goalAssessmentText($0.labelKey)): \(goalFactorValueText($0, language: language)), \(localizedStatus($0.status))"
        }.joined(separator: "\n")
        let upcoming = summary?.upcomingWorkouts.map {
            "- \($0.displayName), \(distanceText($0.distanceKm)), \($0.date.formatted(.dateTime.year().month().day()))"
        }.joined(separator: "\n") ?? "- None"
        let metricLine = assessment.metric.map {
            "\(metricLabel($0)): \($0.value)%"
        } ?? language.goalAssessmentText(.insufficientData)

        return CalendarReviewChatRequest(
            id: "goal-attention-\(assessment.goalId)-\(item.id)",
            displayText: language.goalAssessmentText(.viewRecommendation),
            prompt: """
            Propose a concrete training-plan adjustment for this race-goal attention item.

            Rules:
            - Do not modify the calendar directly.
            - Use the existing confirmation flow before applying any plan change.
            - Base the recommendation only on the structured context below.
            - End with a structured single-choice interaction using the provided next-step choices.

            Goal ID: \(assessment.goalId)
            Attention item ID: \(item.id)
            Race: \(assessment.raceName)
            Race date: \(assessment.raceDate.formatted(.dateTime.year().month().day()))
            Target: \(assessment.targetLabel)
            Goal metric: \(metricLine)

            Main issue: \(language.goalAssessmentText(item.titleKey))
            Evidence:
            \(evidence)

            Factors:
            \(factorLines)

            Upcoming workouts:
            \(upcoming)
            """,
            threadTitle: goalAttentionCoachThreadTitle,
            actionTypeOverride: .readOnly,
            autoSubmit: true,
            expectedResponseInteraction: goalAttentionExpectedInteraction,
            contextSnapshotId: "goal-assessment-\(assessment.goalId)-\(item.id)",
            contextItems: goalAttentionContextItems(assessment: assessment, item: item),
            shouldFocusComposer: false
        )
    }

    private func goalAttentionContextItems(
        assessment: GoalAssessment,
        item: GoalAttentionItem
    ) -> [CoachContextItem] {
        [
            CoachContextItem(type: .raceGoal, label: assessment.targetLabel),
            CoachContextItem(type: .planAssessment, label: language.goalAssessmentText(item.titleKey)),
            CoachContextItem(type: .remainingPlan, label: language.goalAssessmentText(.remainingPlan)),
            CoachContextItem(type: .trainingPlan, label: language.goalAssessmentText(.currentTrainingPlan)),
            CoachContextItem(type: .healthData, label: language.goalAssessmentText(.healthData))
        ]
    }

    private var goalAttentionExpectedInteraction: CoachResponseInteraction {
        switch language {
        case .vi:
            return CoachResponseInteraction(
                id: "goal_plan_adjustment_next_step",
                type: .singleChoice,
                title: "Chọn bước tiếp theo",
                options: [
                    CoachChoiceOption(
                        id: "keep_plan",
                        label: "Giữ nguyên kế hoạch",
                        description: "Không thay đổi các buổi tập sắp tới",
                        value: "Giữ nguyên kế hoạch hiện tại."
                    ),
                    CoachChoiceOption(
                        id: "adjust_plan",
                        label: "Xem bản nháp điều chỉnh",
                        description: "Coach chuẩn bị đề xuất để bạn xem trước rồi mới xác nhận",
                        value: "Hãy tạo bản nháp điều chỉnh kế hoạch đã được kiểm tra để tôi xem trước."
                    )
                ],
                allowOther: true,
                otherLabel: "Yêu cầu khác…",
                otherPlaceholder: "Bạn muốn Coach điều chỉnh như thế nào?",
                status: .pending
            )
        case .ja:
            return CoachResponseInteraction(
                id: "goal_plan_adjustment_next_step",
                type: .singleChoice,
                title: "次のステップを選択",
                options: [
                    CoachChoiceOption(
                        id: "keep_plan",
                        label: "現在の計画を維持",
                        description: "今後のワークアウトを変更しません",
                        value: "現在の計画を維持します。"
                    ),
                    CoachChoiceOption(
                        id: "adjust_plan",
                        label: "調整案の下書きを見る",
                        description: "確認してから適用できる提案を Coach が作成します",
                        value: "確認用の計画調整案を作成してください。"
                    )
                ],
                allowOther: true,
                otherLabel: "別のリクエスト…",
                otherPlaceholder: "Coach にどう調整してほしいですか？",
                status: .pending
            )
        case .en:
            return CoachResponseInteraction(
                id: "goal_plan_adjustment_next_step",
                type: .singleChoice,
                title: "Choose next step",
                options: [
                    CoachChoiceOption(
                        id: "keep_plan",
                        label: "Keep current plan",
                        description: "Do not change upcoming workouts",
                        value: "Keep the current plan."
                    ),
                    CoachChoiceOption(
                        id: "adjust_plan",
                        label: "View adjustment draft",
                        description: "Coach prepares a proposal for review before confirmation",
                        value: "Create a validated plan-adjustment draft for me to review."
                    )
                ],
                allowOther: true,
                otherLabel: "Other request...",
                otherPlaceholder: "How would you like Coach to adjust?",
                status: .pending
            )
        }
    }

    private var goalAttentionCoachThreadTitle: String {
        switch language {
        case .vi: "Đề xuất mục tiêu cuộc đua"
        case .ja: "レース目標の提案"
        case .en: "Race goal recommendation"
        }
    }

    private func metricLabel(_ metric: GoalAssessmentMetric) -> String {
        switch metric {
        case .calibratedProbability: language.goalAssessmentText(.goalConfidence)
        case .goalAlignmentScore: language.goalAssessmentText(.goalAlignment)
        }
    }

    private func localizedStatus(_ status: GoalAssessmentFactorStatus) -> String {
        switch status {
        case .positive: language.goalAssessmentText(.good)
        case .neutral: language.goalAssessmentText(.stable)
        case .negative: language.goalAssessmentText(.needsAdjustment)
        case .unknown: language.goalAssessmentText(.unknown)
        }
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

private func goalEvidenceText(_ evidence: GoalAttentionEvidence, language: CoachLanguage) -> String {
    switch evidence.kind {
    case .missingQualifyingRuns:
        switch language {
        case .vi: return "Cần thêm \(evidence.primaryValue) buổi chạy hợp lệ, tối thiểu 3 km và 12 phút, để ước tính ổn định hơn."
        case .ja: return "安定した推定には、3km以上かつ12分以上の有効なランがあと\(evidence.primaryValue)回必要です。"
        case .en: return "Need \(evidence.primaryValue) more qualifying runs of at least 3 km and 12 minutes for a stable estimate."
        }
    case .completedPlannedDistance:
        switch language {
        case .vi: return "Đã hoàn thành \(evidence.primaryValue)% quãng đường đã đến hạn trong kế hoạch."
        case .ja: return "期限到来済みの計画距離の\(evidence.primaryValue)%を完了。"
        case .en: return "Completed \(evidence.primaryValue)% of due planned distance."
        }
    case .missedKeyWorkouts:
        switch language {
        case .vi: return "Đã bỏ lỡ \(evidence.primaryValue) buổi tập trọng điểm đến hạn."
        case .ja: return "期限到来済みの重要練習を\(evidence.primaryValue)回未完了。"
        case .en: return "Missed \(evidence.primaryValue) due key workout\(evidence.primaryValue == "1" ? "" : "s")."
        }
    case .completedPlannedSessions:
        switch language {
        case .vi: return "Đã hoàn thành \(evidence.primaryValue)% số buổi tập đã đến hạn."
        case .ja: return "期限到来済みの計画セッションの\(evidence.primaryValue)%を完了。"
        case .en: return "Completed \(evidence.primaryValue)% of due planned sessions."
        }
    case .longestRunBehind:
        switch language {
        case .vi: return "Long run gần đây nhất đang \(goalLocalizedShortfall(evidence.primaryValue, language: language)) so với mốc sức bền cần có."
        case .ja: return "直近の最長ランは、レース向け持久力目標に対して\(goalLocalizedShortfall(evidence.primaryValue, language: language))です。"
        case .en: return "Longest recent run is \(goalLocalizedShortfall(evidence.primaryValue, language: language)) versus the race-specific endurance target."
        }
    }
}

private func goalFactorValueText(_ factor: GoalAssessmentFactor, language: CoachLanguage) -> String {
    if factor.displayValue == "—" {
        switch language {
        case .vi: return "Chưa đủ"
        case .ja: return "不足"
        case .en: return "Not enough"
        }
    }
    switch factor.id {
    case "key_workout_performance":
        let count = factor.displayValue.split(separator: " ").first.map(String.init) ?? factor.displayValue
        switch language {
        case .vi: return "\(count) buổi lỡ"
        case .ja: return "\(count)回未完了"
        case .en: return factor.displayValue
        }
    case "long_run_progression":
        return goalLocalizedShortfall(factor.displayValue, language: language)
    case "time_remaining":
        let weeks = factor.displayValue.split(separator: " ").first.map(String.init) ?? factor.displayValue
        switch language {
        case .vi: return "\(weeks) tuần"
        case .ja: return "\(weeks)週"
        case .en: return factor.displayValue
        }
    case "data_quality":
        if factor.displayValue.hasPrefix("Need ") {
            let missing = factor.displayValue
                .replacingOccurrences(of: "Need ", with: "")
                .replacingOccurrences(of: " more", with: "")
            switch language {
            case .vi: return "Cần thêm \(missing)"
            case .ja: return "あと\(missing)回"
            case .en: return factor.displayValue
            }
        }
        let count = factor.displayValue.split(separator: " ").first.map(String.init) ?? factor.displayValue
        switch language {
        case .vi: return "\(count) buổi"
        case .ja: return "\(count)回"
        case .en: return factor.displayValue
        }
    default:
        return factor.displayValue
    }
}

private func goalLocalizedShortfall(_ value: String, language: CoachLanguage) -> String {
    guard value.hasPrefix("Short ") else { return value }
    let amount = value.replacingOccurrences(of: "Short ", with: "")
    switch language {
    case .vi: return "thiếu \(amount)"
    case .ja: return "\(amount)不足"
    case .en: return value.lowercased()
    }
}

private func goalDataSourceValueText(_ value: String, language: CoachLanguage) -> String {
    guard value == "—" else { return value }
    switch language {
    case .vi: return "Chưa có"
    case .ja: return "未取得"
    case .en: return "Not available"
    }
}

struct RaceGoalStatusCard: View {
    let assessment: GoalAssessment
    let summary: ActivePlanSummary
    let language: CoachLanguage
    let onAdjustPlan: () -> Void
    let onShowMetricDetail: () -> Void
    let onShowAssessmentDetail: () -> Void

    private var metricValue: Int? { assessment.metric?.value }
    @State private var selectedWeekID: Int?

    init(
        assessment: GoalAssessment,
        summary: ActivePlanSummary? = nil,
        language: CoachLanguage,
        initialSelectedWeekID: Int? = nil,
        onAdjustPlan: @escaping () -> Void = {},
        onShowMetricDetail: @escaping () -> Void,
        onShowAssessmentDetail: @escaping () -> Void
    ) {
        self.assessment = assessment
        self.summary = summary ?? Self.fallbackSummary(for: assessment)
        self.language = language
        self.onAdjustPlan = onAdjustPlan
        self.onShowMetricDetail = onShowMetricDetail
        self.onShowAssessmentDetail = onShowAssessmentDetail
        self._selectedWeekID = State(initialValue: initialSelectedWeekID)
    }

    var body: some View {
        TorCard(padding: 18, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack(alignment: .center, spacing: 16) {
                    predictionBlock
                    VStack(alignment: .leading, spacing: 7) {
                        Text(language.goalAssessmentText(assessment.summaryKey))
                            .font(.torHeading(22, .bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(language.goalAssessmentText(assessment.summaryDetailKey))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        if let trend = assessment.trend {
                            trendRow(trend)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                targetComparison
                planActualChart
                compactMetrics
                actionButtons
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            TorEyebrow(language.goalAssessmentText(.raceGoal))
            Text(assessment.raceName)
                .font(.torHeading(24, .bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(raceDateText) · \(weeksRemainingText)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var predictionBlock: some View {
        VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.card2)
                VStack(spacing: 5) {
                    Text(primaryAssessmentValue)
                        .font(.torNumber(34, .bold))
                        .monospacedDigit()
                        .foregroundStyle(metricColor)
                        .minimumScaleFactor(0.68)
                    Text(primaryAssessmentLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
                .padding(10)
            }
            .frame(width: 124, height: 108)
            .accessibilityLabel(primaryAssessmentAccessibility)

            if let metricValue {
                Button {
                    onShowMetricDetail()
                } label: {
                    Label(language.goalAssessmentText(.whyMetric, value: metricValue), systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(language.goalAssessmentText(.whyMetric, value: metricValue))
            }
        }
        .frame(width: 124)
    }

    private var targetComparison: some View {
        HStack(spacing: 10) {
            comparisonColumn(
                label: language.goalAssessmentText(.targetTime),
                value: assessment.targetFinishTimeSeconds.map(Formatters.duration) ?? assessment.targetLabel
            )
            comparisonColumn(
                label: language.goalAssessmentText(.currentPrediction),
                value: predictionText
            )
            comparisonColumn(
                label: language.goalAssessmentText(.targetGap),
                value: gapText
            )
        }
    }

    private func comparisonColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.torHeading(18, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var factorSummary: some View {
        VStack(spacing: 9) {
            ForEach(Array(assessment.factors.prefix(3))) { factor in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(color(for: factor.status))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(language.goalAssessmentText(factor.labelKey))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text("\(goalFactorValueText(factor, language: language)) · \(statusText(factor.status))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(for: factor.status))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(language.goalAssessmentText(factor.labelKey)), \(goalFactorValueText(factor, language: language)), \(statusText(factor.status))")
            }
            Button {
                onShowAssessmentDetail()
            } label: {
                HStack {
                    Text(language.goalAssessmentText(.why))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.torHeading(14, .bold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var planActualChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.goalAssessmentText(.planAndActual))
                    .font(.torHeading(16, .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                legend
            }
            Chart(chartWeeks) { week in
                BarMark(
                    x: .value("Week", week.weekIndex + 1),
                    y: .value(language.goalAssessmentText(.planned), week.plannedDistanceKm)
                )
                .foregroundStyle(week.isFutureWeek ? Theme.faint.opacity(0.18) : Theme.faint.opacity(0.34))
                .position(by: .value("Metric", language.goalAssessmentText(.planned)))

                if !week.isFutureWeek {
                    BarMark(
                        x: .value("Week", week.weekIndex + 1),
                        y: .value(language.goalAssessmentText(.actual), week.completedDistanceKm)
                    )
                    .foregroundStyle(Theme.accent)
                    .position(by: .value("Metric", language.goalAssessmentText(.actual)))
                }
                if week.isCurrentWeek {
                    RuleMark(x: .value(language.goalAssessmentText(.currentWeek), week.weekIndex + 1))
                        .foregroundStyle(Theme.warn)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: chartWeeks.map { $0.weekIndex + 1 }) { value in
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("W\(intValue)")
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 164)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                guard let plot = proxy.plotFrame else { return }
                                let origin = geo[plot].origin
                                let x = value.location.x - origin.x
                                if let weekNumber: Int = proxy.value(atX: x) {
                                    selectedWeekID = chartWeeks.min(by: {
                                        abs(($0.weekIndex + 1) - weekNumber) < abs(($1.weekIndex + 1) - weekNumber)
                                    })?.weekIndex
                                }
                            }
                        )
                }
            }
            .accessibilityLabel(chartAccessibility)

            if let selectedWeek {
                weekDetail(selectedWeek)
            }
        }
        .padding(12)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: Theme.faint.opacity(0.34), label: language.goalAssessmentText(.planned))
            legendItem(color: Theme.accent, label: language.goalAssessmentText(.actual))
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.faint)
        }
    }

    private func weekDetail(_ week: ActivePlanWeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(weekRangeText(week))
                .font(.torHeading(14, .bold))
                .foregroundStyle(Theme.text)
            detailLine(language.goalAssessmentText(.planned), distanceText(week.plannedDistanceKm))
            if !week.isFutureWeek {
                detailLine(language.goalAssessmentText(.actual), distanceText(week.completedDistanceKm))
                detailLine(language.goalAssessmentText(.targetGap), signedDistanceText(week.completedDistanceKm - week.plannedDistanceKm))
                detailLine(language.goalAssessmentText(.keyWorkout), "\(week.completedKeySessions)/\(week.plannedKeySessions)")
                if let plannedLong = week.plannedLongRunKm {
                    detailLine(language.goalAssessmentText(.longRunProgression), "\(distanceText(week.completedLongRunKm ?? 0))/\(distanceText(plannedLong))")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).foregroundStyle(Theme.text).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
    }

    private var compactMetrics: some View {
        HStack(spacing: 8) {
            compactMetric(language.goalAssessmentText(.completedVolume), completedVolumeText, status: volumeStatusText)
            compactMetric(language.goalAssessmentText(.keyWorkout), keyWorkoutText, status: keyWorkoutStatusText)
            compactMetric(language.goalAssessmentText(.latestLongRun), longRunText, status: longRunStatusText)
        }
    }

    private func compactMetric(_ label: String, _ value: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.faint)
            Text(value).font(.torHeading(14, .bold)).foregroundStyle(Theme.text).monospacedDigit()
            Text(status).font(.caption2.weight(.medium)).foregroundStyle(Theme.dim).lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onAdjustPlan) {
                Label(language.goalAssessmentText(.adjustPlan), systemImage: "slider.horizontal.3")
                    .font(.torHeading(15, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.goalAssessmentText(.adjustPlan))

            Button(action: onShowAssessmentDetail) {
                Text(language.goalAssessmentText(.assessmentMethod))
                    .font(.torHeading(15, .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func trendRow(_ trend: GoalAssessmentTrend) -> some View {
        let positive = trend.delta >= 0
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
            Text(trendText(trend))
                .fixedSize(horizontal: false, vertical: true)
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(positive ? Theme.good : Theme.warn)
            .accessibilityLabel(trendText(trend))
    }

    private var weeksRemainingText: String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: assessment.raceDate).day ?? 0
        let weeks = max(0, Int((Double(days) / 7).rounded()))
        switch language {
        case .vi: return "Còn \(weeks) tuần"
        case .ja: return "あと\(weeks)週"
        case .en: return "\(weeks) weeks remaining"
        }
    }

    private var raceDateText: String {
        switch language {
        case .vi:
            return assessment.raceDate.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
        case .ja:
            return assessment.raceDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP")))
        case .en:
            return assessment.raceDate.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
        }
    }

    private var metricLabel: String {
        guard let metric = assessment.metric else { return language.goalAssessmentText(.insufficientData) }
        switch metric {
        case .calibratedProbability: return language.goalAssessmentText(.goalConfidence)
        case .goalAlignmentScore: return language.goalAssessmentText(.goalAlignment)
        }
    }

    private var metricDisplayText: String {
        guard let metricValue else {
            switch language {
            case .vi: return "Chưa đủ"
            case .ja: return "不足"
            case .en: return "Not enough"
            }
        }
        return "\(metricValue)%"
    }

    private var metricColor: Color {
        switch assessment.summaryStatus {
        case .onTrack: Theme.good
        case .closeToTarget: Theme.accent
        case .adjustmentRecommended: Theme.warn
        case .atRisk: Theme.bad
        case .insufficientData: Theme.faint
        }
    }

    private var predictionText: String {
        guard let predicted = assessment.predictedFinishTime else {
            return language.goalAssessmentText(.insufficientPrediction)
        }
        let lower = Formatters.duration(predicted.lowerSeconds)
        let upper = Formatters.duration(predicted.upperSeconds)
        return lower == upper ? lower : "\(lower)-\(upper)"
    }

    private var metricAccessibilityLabel: String {
        guard let metricValue else { return language.goalAssessmentText(.insufficientData) }
        return "\(metricValue)%, \(metricLabel)"
    }

    private var accessibilitySummary: String {
        "\(assessment.raceName), \(primaryAssessmentAccessibility), \(gapText), \(language.goalAssessmentText(assessment.summaryKey)). \(language.goalAssessmentText(assessment.summaryDetailKey))"
    }

    private func trendText(_ trend: GoalAssessmentTrend) -> String {
        let points = abs(trend.delta)
        switch language {
        case .vi: return trend.delta >= 0 ? "Tăng \(points) điểm so với lần trước" : "Giảm \(points) điểm so với lần trước"
        case .ja: return trend.delta >= 0 ? "前回より\(points)ポイント上昇" : "前回より\(points)ポイント低下"
        case .en: return trend.delta >= 0 ? "Up \(points) points from last check" : "Down \(points) points from last check"
        }
    }

    private func statusText(_ status: GoalAssessmentFactorStatus) -> String {
        switch status {
        case .positive: language.goalAssessmentText(.good)
        case .neutral: language.goalAssessmentText(.stable)
        case .negative: language.goalAssessmentText(.needsAdjustment)
        case .unknown: language.goalAssessmentText(.unknown)
        }
    }

    private func color(for status: GoalAssessmentFactorStatus) -> Color {
        switch status {
        case .positive: Theme.good
        case .neutral: Theme.dim
        case .negative: Theme.warn
        case .unknown: Theme.faint
        }
    }

    private var primaryAssessmentValue: String {
        if let prediction = assessment.raceTimePrediction {
            return shortTime(prediction.predictedTimeSeconds)
        }
        if let metricValue {
            return "\(metricValue)/100"
        }
        return language.goalAssessmentText(.insufficientData)
    }

    private var primaryAssessmentLabel: String {
        if assessment.raceTimePrediction != nil {
            return language.goalAssessmentText(.currentPrediction)
        }
        if metricValue != nil {
            switch language {
            case .vi: return "Mức độ sẵn sàng cho mục tiêu"
            case .ja: return "目標への準備度"
            case .en: return "Goal readiness"
            }
        }
        return language.goalAssessmentText(.insufficientData)
    }

    private var primaryAssessmentAccessibility: String {
        "\(primaryAssessmentValue), \(primaryAssessmentLabel)"
    }

    private var gapText: String {
        guard let prediction = assessment.raceTimePrediction else {
            return language.goalAssessmentText(.insufficientPrediction)
        }
        return Self.targetGapText(predictedSeconds: prediction.predictedTimeSeconds, targetSeconds: prediction.targetTimeSeconds, language: language)
    }

    static func targetGapText(predictedSeconds: Double, targetSeconds: Double, language: CoachLanguage) -> String {
        let gap = predictedSeconds - targetSeconds
        let minutes = Int((abs(gap) / 60).rounded())
        switch language {
        case .vi:
            if gap > 0 { return "+\(minutes) phút so với mục tiêu" }
            if gap < 0 { return "Nhanh hơn mục tiêu \(minutes) phút" }
            return "Đúng thời gian mục tiêu"
        case .ja:
            if gap > 0 { return "目標より+\(minutes)分" }
            if gap < 0 { return "目標より\(minutes)分速い" }
            return "目標タイム通り"
        case .en:
            if gap > 0 { return "+\(minutes) min vs target" }
            if gap < 0 { return "\(minutes) min faster than target" }
            return "On target time"
        }
    }

    private var chartWeeks: [ActivePlanWeekSummary] {
        let current = max(summary.currentWeek - 1, 0)
        let lower = max(0, current - 4)
        let upper = min(summary.weeklyProgress.count - 1, current + 3)
        guard lower <= upper else { return summary.weeklyProgress }
        return Array(summary.weeklyProgress[lower...upper])
    }

    private var selectedWeek: ActivePlanWeekSummary? {
        let id = selectedWeekID ?? summary.currentWeek - 1
        return chartWeeks.first { $0.weekIndex == id }
    }

    private var completedVolumeText: String {
        let due = summary.weeklyProgress.filter { !$0.isFutureWeek }
        let planned = due.reduce(0) { $0 + $1.plannedDistanceKm }
        guard planned > 0 else { return "—" }
        let actual = due.reduce(0) { $0 + $1.completedDistanceKm }
        return "\(Int((actual / planned * 100).rounded()))%"
    }

    private var volumeStatusText: String {
        switch language {
        case .vi: return (summary.health.volumeCompliance ?? 1) < 0.75 ? "Thấp hơn kế hoạch" : "Ổn định"
        case .ja: return (summary.health.volumeCompliance ?? 1) < 0.75 ? "計画より低い" : "安定"
        case .en: return (summary.health.volumeCompliance ?? 1) < 0.75 ? "Below plan" : "Stable"
        }
    }

    private var keyWorkoutText: String {
        let dueKeys = summary.health.missedWorkoutAudit.entries.filter {
            ($0.reason == .missed || $0.reason == .completed) && $0.isKeyWorkout
        }.count
        let completed = max(0, dueKeys - summary.health.missedKeySessions)
        return "\(completed)/\(dueKeys)"
    }

    private var keyWorkoutStatusText: String {
        switch language {
        case .vi: return summary.health.missedKeySessions > 0 ? "Chưa đủ" : "Ổn định"
        case .ja: return summary.health.missedKeySessions > 0 ? "不足" : "安定"
        case .en: return summary.health.missedKeySessions > 0 ? "Not enough" : "Stable"
        }
    }

    private var longRunText: String {
        guard let component = assessment.factors.first(where: { $0.type == .longRunProgression }) else { return "—" }
        return goalFactorValueText(component, language: language)
    }

    private var longRunStatusText: String {
        guard let component = assessment.factors.first(where: { $0.type == .longRunProgression }) else { return language.goalAssessmentText(.unknown) }
        return statusText(component.status)
    }

    private var chartAccessibility: String {
        let planned = chartWeeks.reduce(0) { $0 + $1.plannedDistanceKm }
        let actual = chartWeeks.filter { !$0.isFutureWeek }.reduce(0) { $0 + $1.completedDistanceKm }
        return "\(language.goalAssessmentText(.planAndActual)). \(language.goalAssessmentText(.planned)) \(distanceText(planned)). \(language.goalAssessmentText(.actual)) \(distanceText(actual)). \(language.goalAssessmentText(.currentWeek)) \(summary.currentWeek)."
    }

    private func weekRangeText(_ week: ActivePlanWeekSummary) -> String {
        switch language {
        case .vi: return "Tuần \(week.startDate.formatted(.dateTime.day().month()))-\(week.endDate.formatted(.dateTime.day().month()))"
        case .ja: return "\(week.startDate.formatted(.dateTime.month().day()))-\(week.endDate.formatted(.dateTime.month().day()))"
        case .en: return "\(week.startDate.formatted(.dateTime.month(.abbreviated).day()))-\(week.endDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private func signedDistanceText(_ km: Double) -> String {
        let rounded = abs(km)
        if km > 0 { return "+\(distanceText(rounded))" }
        if km < 0 { return "-\(distanceText(rounded))" }
        return distanceText(0)
    }

    private func distanceText(_ km: Double) -> String {
        String(format: "%.0f km", km)
    }

    private func shortTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private static func fallbackSummary(for assessment: GoalAssessment) -> ActivePlanSummary {
        let start = Calendar.current.date(byAdding: .day, value: -28, to: assessment.raceDate) ?? assessment.raceDate
        let weeks = (0..<4).map { index in
            ActivePlanWeekSummary(
                weekIndex: index,
                startDate: Calendar.current.date(byAdding: .day, value: index * 7, to: start) ?? start,
                endDate: Calendar.current.date(byAdding: .day, value: index * 7 + 6, to: start) ?? start,
                plannedSessions: 0,
                completedSessions: 0,
                plannedDistanceKm: 0,
                completedDistanceKm: 0,
                plannedKeySessions: 0,
                completedKeySessions: 0,
                plannedLongRunKm: nil,
                completedLongRunKm: nil,
                isCurrentWeek: index == 0,
                isFutureWeek: index > 0
            )
        }
        return ActivePlanSummary(
            title: assessment.raceName,
            raceDate: assessment.raceDate,
            targetTimeSeconds: assessment.targetFinishTimeSeconds ?? 0,
            runningDaysPerWeek: 0,
            startDate: start,
            endDate: assessment.raceDate,
            currentWeek: 1,
            totalWeeks: 4,
            timelineProgress: 0.25,
            daysRemaining: nil,
            isRaceDay: false,
            health: PlanHealth(
                status: .active,
                reasons: [.insufficientData],
                adherenceRate: nil,
                volumeCompliance: nil,
                missedKeySessions: 0,
                missedWorkoutAudit: MissedWorkoutAudit(),
                evaluatedAt: assessment.readiness.calculatedAt
            ),
            currentPhase: nil,
            thisWeek: weeks.first,
            nextWorkout: nil,
            upcomingWorkouts: [],
            weeklyProgress: weeks,
            phases: []
        )
    }
}

struct PrimaryAttentionCard: View {
    let assessment: GoalAssessment
    let item: GoalAttentionItem
    let language: CoachLanguage
    let onShowDetails: () -> Void
    let coachRequest: CalendarReviewChatRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Theme.soft(tint, 0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    TorEyebrow(language.goalAssessmentText(.mostImportantAdjustment), color: tint)
                    Text(language.goalAssessmentText(item.titleKey))
                        .font(.torHeading(22, .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            labeledBlock(.evidence, text: item.evidence.map { goalEvidenceText($0, language: language) }.joined(separator: "\n"))
            labeledBlock(.impact, text: impactText)

            HStack(spacing: 10) {
                NavigationLink {
                    ChatView(reviewRequest: coachRequest)
                } label: {
                    Label(language.goalAssessmentText(.viewRecommendation), systemImage: "sparkles")
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(Color.white)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.goalAssessmentText(.viewRecommendation))

                Button {
                    onShowDetails()
                } label: {
                    Text(language.goalAssessmentText(.why))
                        .font(.torHeading(15, .bold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(language.goalAssessmentText(.why))
            }

            let remaining = assessment.attentionItems.filter { $0.id != item.id }.count
            if remaining > 0 {
                Button {
                    onShowDetails()
                } label: {
                    HStack {
                        Text(language.goalAssessmentText(.viewMoreItems, value: remaining))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.soft(tint, 0.36), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func labeledBlock(_ key: GoalAssessmentLabelKey, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.goalAssessmentText(key))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.faint)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var impactText: String {
        if let points = item.estimatedImpactPoints, item.severity == .highRisk {
            switch language {
            case .vi: return "Yếu tố này đang kéo mức độ bám mục tiêu giảm khoảng \(points) điểm."
            case .ja: return "この要因は目標整合度を約\(points)ポイント下げています。"
            case .en: return "This factor is reducing goal alignment by about \(points) points."
            }
        }
        return language.goalAssessmentText(item.impactExplanationKey)
    }

    private var iconName: String {
        switch item.severity {
        case .info: "info.circle"
        case .adjustment: "exclamationmark.triangle"
        case .highRisk: "exclamationmark.octagon"
        }
    }

    private var tint: Color {
        switch item.severity {
        case .info: Theme.data
        case .adjustment: Theme.warn
        case .highRisk: Theme.bad
        }
    }

    private var surface: Color {
        switch item.severity {
        case .info: Theme.soft(Theme.data, 0.10)
        case .adjustment: Theme.soft(Theme.warn, 0.12)
        case .highRisk: Theme.soft(Theme.bad, 0.12)
        }
    }
}

struct GoalMetricDetailSheet: View {
    let assessment: GoalAssessment
    let language: CoachLanguage

    var body: some View {
        NavigationStack {
            List {
                Section(language.goalAssessmentText(.metricMeaning)) {
                    Text(metricMeaning)
                }
                Section(language.goalAssessmentText(.metricDataUsed)) {
                    ForEach(assessment.dataSources) { source in
                        LabeledContent(language.goalAssessmentText(source.labelKey), value: goalDataSourceValueText(source.value, language: language))
                    }
                }
                Section(language.goalAssessmentText(.metricCalculatedAt)) {
                    Text(calculatedAtText)
                }
                Section(language.goalAssessmentText(.metricFactors)) {
                    ForEach(assessment.factors) { factor in
                        LabeledContent(language.goalAssessmentText(factor.labelKey), value: "\(goalFactorValueText(factor, language: language)) · \(statusText(factor.status))")
                    }
                }
                Section {
                    Text(language.goalAssessmentText(.metricEstimateCaveat))
                }
            }
            .navigationTitle(assessment.metric.map { language.goalAssessmentText(.whyMetric, value: $0.value) } ?? language.goalAssessmentText(.insufficientData))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var metricMeaning: String {
        guard let metric = assessment.metric else { return language.goalAssessmentText(.insufficientDataSummary) }
        switch metric {
        case .calibratedProbability: return language.goalAssessmentText(.metricProbabilityExplanation)
        case .goalAlignmentScore: return language.goalAssessmentText(.metricAlignmentExplanation)
        }
    }

    private var calculatedAtText: String {
        guard let metric = assessment.metric else { return language.goalAssessmentText(.insufficientData) }
        return metric.calculatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func statusText(_ status: GoalAssessmentFactorStatus) -> String {
        switch status {
        case .positive: language.goalAssessmentText(.good)
        case .neutral: language.goalAssessmentText(.stable)
        case .negative: language.goalAssessmentText(.needsAdjustment)
        case .unknown: language.goalAssessmentText(.unknown)
        }
    }
}

struct GoalAssessmentDetailSheet: View {
    let assessment: GoalAssessment
    let language: CoachLanguage

    var body: some View {
        NavigationStack {
            ScrollView {
                GoalAssessmentDetailContent(assessment: assessment, language: language)
                    .padding(16)
            }
            .navigationTitle(language.goalAssessmentText(.raceGoal))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GoalAssessmentDetailContent: View {
    let assessment: GoalAssessment
    let language: CoachLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailSection(language.goalAssessmentText(.mostImportantAdjustment)) {
                if let item = GoalAssessmentBuilder.primaryAttentionItem(for: assessment) {
                    attentionRow(item)
                } else {
                    Text(language.goalAssessmentText(.noAttention))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                }
            }

            detailSection(language.goalAssessmentText(.metricFactors)) {
                VStack(spacing: 10) {
                    ForEach(assessment.factors) { factor in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(language.goalAssessmentText(factor.labelKey))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            Text("\(goalFactorValueText(factor, language: language)) · \(statusText(factor.status))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.dim)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !assessment.attentionItems.isEmpty {
                detailSection(language.goalAssessmentText(.needsAdjustment)) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(assessment.attentionItems) { item in
                            attentionRow(item)
                        }
                    }
                }
            }
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow(title)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func attentionRow(_ item: GoalAttentionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.goalAssessmentText(item.titleKey))
                .font(.headline)
            Text(item.evidence.map { goalEvidenceText($0, language: language) }.joined(separator: "\n"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(item.estimatedImpactPoints.map { impactText($0) } ?? language.goalAssessmentText(item.impactExplanationKey))
                .font(.subheadline.weight(.medium))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func impactText(_ points: Int) -> String {
        switch language {
        case .vi: return "Giảm khoảng \(points) điểm."
        case .ja: return "約\(points)ポイント低下。"
        case .en: return "Down about \(points) points."
        }
    }

    private func statusText(_ status: GoalAssessmentFactorStatus) -> String {
        switch status {
        case .positive: language.goalAssessmentText(.good)
        case .neutral: language.goalAssessmentText(.stable)
        case .negative: language.goalAssessmentText(.needsAdjustment)
        case .unknown: language.goalAssessmentText(.unknown)
        }
    }
}

struct GoalPlanAdjustmentProposal: Identifiable, Equatable {
    var id: String
    var goalId: String
    var basedOnAssessmentId: String
    var explanation: String
    var changes: [GoalPlanAdjustmentChange]
    var warnings: [String]
    var createdAt: Date
}

struct GoalPlanAdjustmentChange: Identifiable, Equatable {
    enum ChangeType: String, Equatable {
        case distanceChange
        case intensityChange
        case recoveryChange
    }

    var id: String
    var type: ChangeType
    var workoutId: UUID
    var reason: String
    var before: PlanWorkoutSnapshot
    var after: PlanWorkoutSnapshot?
}

struct PlanWorkoutSnapshot: Equatable {
    var date: Date
    var kindRaw: String
    var distanceKm: Double
    var details: String
}

enum GoalPlanAdjustmentEngine {
    static func proposal(
        assessment: GoalAssessment,
        summary: ActivePlanSummary?,
        plan: TrainingPlan,
        today: Date,
        calendar: Calendar,
        language: CoachLanguage
    ) -> GoalPlanAdjustmentProposal {
        let dayStart = calendar.startOfDay(for: today)
        let future = plan.workouts
            .filter { calendar.startOfDay(for: $0.date) >= dayStart && $0.status == .planned && !$0.isScheduleLocked && $0.kind != .race }
            .sorted { ($0.date, $0.uuid.uuidString) < ($1.date, $1.uuid.uuidString) }
        var changes: [GoalPlanAdjustmentChange] = []

        if let longRun = future.first(where: { $0.kind == .long }) {
            let target = min(longRun.distanceKm + 2, longRun.distanceKm * 1.10)
            if target > longRun.distanceKm + 0.1 {
                changes.append(change(
                    workout: longRun,
                    type: .distanceChange,
                    afterDistance: PlanGenerator.rounded(target),
                    afterKind: longRun.kind ?? .long,
                    reason: localized(
                        vi: "Tăng dần sức bền, không bù toàn bộ phần còn thiếu.",
                        en: "Build endurance gradually without cramming all missed volume.",
                        ja: "不足分を一気に詰め込まず、持久力を段階的に伸ばします。",
                        language: language
                    )
                ))
            }
        }

        if let quality = future.first(where: { $0.kind == .tempo || $0.kind == .threshold || $0.kind == .intervals }) {
            let reduced = max(5, quality.distanceKm - 1)
            changes.append(change(
                workout: quality,
                type: .intensityChange,
                afterDistance: PlanGenerator.rounded(reduced),
                afterKind: quality.kind ?? .tempo,
                reason: localized(
                    vi: "Giảm nhẹ tải buổi chất lượng để cân bằng với long run.",
                    en: "Trim one quality session slightly to balance the long run.",
                    ja: "ロングランとのバランスを取るため重要練習を少し軽くします。",
                    language: language
                )
            ))
        }

        if let easy = future.first(where: { $0.kind == .easy }) {
            changes.append(GoalPlanAdjustmentChange(
                id: "recovery-\(easy.uuid.uuidString)",
                type: .recoveryChange,
                workoutId: easy.uuid,
                reason: localized(
                    vi: "Tạo khoảng hồi phục sau hai buổi chất lượng.",
                    en: "Create recovery space after the harder sessions.",
                    ja: "強度の高い練習後に回復余地を作ります。",
                    language: language
                ),
                before: PlanWorkoutSnapshot(workout: easy),
                after: nil
            ))
        }

        let limited = Array(changes.prefix(4))
        return GoalPlanAdjustmentProposal(
            id: "goal-plan-adjustment-\(assessment.goalId)-\(Int(today.timeIntervalSince1970))",
            goalId: assessment.goalId,
            basedOnAssessmentId: "\(assessment.goalId)-\(assessment.readiness.calculatedAt.timeIntervalSince1970)",
            explanation: localized(
                vi: "Coach đề xuất \(limited.count) thay đổi cho phần kế hoạch còn lại. Các buổi đã lỡ sẽ không được dồn toàn bộ vào lịch mới.",
                en: "Coach suggests \(limited.count) changes for the remaining plan. Missed workouts are not blindly stacked into the new calendar.",
                ja: "残りの計画に\(limited.count)件の変更を提案します。未完了分を新しい予定に一気に積みません。",
                language: language
            ),
            changes: limited,
            warnings: future.contains(where: \.isScheduleLocked) ? [
                localized(
                    vi: "Một số buổi đã khóa lịch được giữ nguyên.",
                    en: "Locked workouts are preserved.",
                    ja: "ロックされた練習は維持されます。",
                    language: language
                )
            ] : [],
            createdAt: today
        )
    }

    static func apply(
        _ proposal: GoalPlanAdjustmentProposal,
        to plan: TrainingPlan,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        guard !proposal.changes.isEmpty else { return }
        let originalTargets = plan.weekTargetVolumesKm
        var applied: [(workout: PlannedWorkout, snapshot: PlanWorkoutSnapshot, targetBefore: Double)] = []
        do {
            for change in proposal.changes {
                guard let workout = plan.workouts.first(where: { $0.uuid == change.workoutId }) else {
                    throw CoachTools.ValidationError("Workout changed before confirmation.")
                }
                guard calendar.startOfDay(for: workout.date) >= calendar.startOfDay(for: today),
                      workout.status == .planned,
                      !workout.isScheduleLocked,
                      workout.kind != .race else {
                    throw CoachTools.ValidationError("Workout is locked, completed, or no longer editable.")
                }
                guard plan.weekTargetVolumesKm.indices.contains(workout.weekIndex) else {
                    throw CoachTools.ValidationError("Plan week is missing.")
                }
                let before = PlanWorkoutSnapshot(workout: workout)
                let weekTargetBefore = plan.weekTargetVolumesKm[workout.weekIndex]
                applied.append((workout, before, weekTargetBefore))
                let after = change.after
                let afterDistanceForWorkout = after?.distanceKm ?? workout.distanceKm
                let weekTargetAfter = if let after {
                    PlanGenerator.rounded(weekTargetBefore + after.distanceKm - workout.distanceKm)
                } else {
                    PlanGenerator.rounded(weekTargetBefore - workout.distanceKm)
                }
                let edit = PlanEdit(
                    appliedAt: today,
                    workout: workout,
                    weekTargetVolumeKmBefore: weekTargetBefore,
                    afterKindRaw: after?.kindRaw ?? workout.kindRaw,
                    afterDistanceKm: afterDistanceForWorkout,
                    afterPaceFastSecondsPerKm: workout.paceFastSecondsPerKm,
                    afterPaceSlowSecondsPerKm: workout.paceSlowSecondsPerKm,
                    afterDetails: after?.details ?? workout.details,
                    afterStructure: workout.structure,
                    afterStatusRaw: after == nil ? WorkoutStatus.skipped.rawValue : WorkoutStatus.planned.rawValue,
                    afterManuallyOverridden: true,
                    afterMatchedActivityUUID: nil,
                    weekTargetVolumeKmAfter: weekTargetAfter,
                    source: "goal_assessment"
                )
                context.insert(edit)

                if let after {
                    workout.kindRaw = after.kindRaw
                    workout.distanceKm = after.distanceKm
                    workout.details = after.details
                    workout.manuallyOverridden = true
                    workout.matchedActivityUUID = nil
                } else {
                    workout.status = .skipped
                    workout.manuallyOverridden = true
                    workout.matchedActivityUUID = nil
                }
                var targets = plan.weekTargetVolumesKm
                targets[workout.weekIndex] = edit.weekTargetVolumeKmAfter
                plan.weekTargetVolumesKm = targets
            }
            try context.save()
            NotificationCenter.default.post(name: .planDidChange, object: nil)
        } catch {
            for item in applied {
                item.workout.kindRaw = item.snapshot.kindRaw
                item.workout.distanceKm = item.snapshot.distanceKm
                item.workout.details = item.snapshot.details
                item.workout.status = .planned
                var targets = plan.weekTargetVolumesKm
                if targets.indices.contains(item.workout.weekIndex) {
                    targets[item.workout.weekIndex] = item.targetBefore
                    plan.weekTargetVolumesKm = targets
                }
            }
            plan.weekTargetVolumesKm = originalTargets
            throw error
        }
    }

    private static func change(
        workout: PlannedWorkout,
        type: GoalPlanAdjustmentChange.ChangeType,
        afterDistance: Double,
        afterKind: WorkoutKind,
        reason: String
    ) -> GoalPlanAdjustmentChange {
        GoalPlanAdjustmentChange(
            id: "\(type.rawValue)-\(workout.uuid.uuidString)",
            type: type,
            workoutId: workout.uuid,
            reason: reason,
            before: PlanWorkoutSnapshot(workout: workout),
            after: PlanWorkoutSnapshot(
                date: workout.date,
                kindRaw: afterKind.rawValue,
                distanceKm: afterDistance,
                details: workout.details
            )
        )
    }

    private static func localized(vi: String, en: String, ja: String, language: CoachLanguage) -> String {
        switch language {
        case .vi: vi
        case .en: en
        case .ja: ja
        }
    }
}

extension PlanWorkoutSnapshot {
    init(workout: PlannedWorkout) {
        self.date = workout.date
        self.kindRaw = workout.kindRaw
        self.distanceKm = workout.distanceKm
        self.details = workout.details
    }
}

struct PlanAdjustmentPreviewSheet: View {
    let proposal: GoalPlanAdjustmentProposal
    let language: CoachLanguage
    let onApply: (GoalPlanAdjustmentProposal) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(proposal.explanation)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    if proposal.changes.isEmpty {
                        ContentUnavailableView(
                            language.goalAssessmentText(.noAttention),
                            systemImage: "checkmark.seal",
                            description: Text(language.goalAssessmentText(.onTrackSummary))
                        )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(proposal.changes) { change in
                                PlanAdjustmentPreviewRow(change: change, language: language)
                            }
                        }
                    }

                    ForEach(proposal.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "lock")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.warn)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.soft(Theme.warn, 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(language.goalAssessmentText(.planAdjustmentProposal))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        onApply(proposal)
                    } label: {
                        Text(language.goalAssessmentText(.applyChanges, value: proposal.changes.count))
                            .font(.torHeading(15, .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(proposal.changes.isEmpty)

                    Button {
                        dismiss()
                    } label: {
                        Text(language.goalAssessmentText(.keepCurrentPlan))
                            .font(.torHeading(15, .bold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(.bar)
            }
        }
    }
}

struct PlanAdjustmentPreviewRow: View {
    let change: GoalPlanAdjustmentChange
    let language: CoachLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.torHeading(16, .bold))
                        .foregroundStyle(Theme.text)
                    Text(change.before.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                Image(systemName: symbol)
                    .foregroundStyle(Theme.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshotText(change.before))
                    .foregroundStyle(Theme.faint)
                    .strikethrough(change.after != nil)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.dim)
                Text(change.after.map(snapshotText) ?? restText)
                    .foregroundStyle(Theme.text)
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()

            Text(change.reason)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        WorkoutKind(rawValue: change.before.kindRaw)?.displayName ?? change.before.kindRaw.capitalized
    }

    private var symbol: String {
        switch change.type {
        case .distanceChange: "arrow.up.forward"
        case .intensityChange: "slider.horizontal.3"
        case .recoveryChange: "bed.double"
        }
    }

    private var restText: String {
        switch language {
        case .vi: "Nghỉ"
        case .ja: "休み"
        case .en: "Rest"
        }
    }

    private func snapshotText(_ snapshot: PlanWorkoutSnapshot) -> String {
        let kind = WorkoutKind(rawValue: snapshot.kindRaw)?.displayName ?? snapshot.kindRaw.capitalized
        return "\(kind) \(String(format: "%.0f", snapshot.distanceKm)) km"
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
