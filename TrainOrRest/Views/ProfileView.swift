import SwiftData
import SwiftUI

/// Profile = athlete identity, active goal, plan stage, and personal history.
/// Configuration lives in SettingsView.
struct ProfileView: View {
    @Query private var goals: [Goal]
    @Query private var plans: [TrainingPlan]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readiness: [DailyReadiness]

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(PersonalCoachSettings.weightKgKey) private var weightKg = ""
    @AppStorage(PersonalCoachSettings.ageKey) private var age = ""
    @AppStorage(PersonalCoachSettings.heightCmKey) private var heightCm = ""

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize


    @State private var showGoalEntry = false
    @State private var showAthleteProfile = false

    private let calendar = Calendar.current
    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                goalAndPlanCard
                athleteSummaryCard
                personalHistorySection
            }
            .padding(.horizontal, 16)
            .padding(.top, verticalSizeClass == .compact ? 4 : 12)
            .padding(.bottom, 24)
            .torReadableColumn()
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 82)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showGoalEntry) { GoalEntryView() }
        .sheet(isPresented: $showAthleteProfile) { NavigationStack { AthleteProfileEditView() } }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(language.settings.profileTitle)
                .font(dynamicTypeSize.isAccessibilitySize ? .largeTitle.weight(.bold) : .torHeading(28, .bold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.settings.openSettingsAccessibilityLabel)
        }
    }

    private var athleteSummaryCard: some View {
        TorCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    TorEyebrow(language.settings.athleteEyebrow)
                    Text(athleteDetailSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let metrics = athleteMetrics
                if !metrics.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(metrics) { metric in
                            MetricChip(metric: metric)
                        }
                    }
                }

                Button {
                    showAthleteProfile = true
                } label: {
                    HStack(spacing: 8) {
                        Text(filledAthleteInputs < 3 ? language.settings.completeAthleteProfile : language.settings.editAthleteProfile)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.torHeading(14, .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44, alignment: .center)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filledAthleteInputs < 3 ? language.settings.completeAthleteProfile : language.settings.editAthleteProfile)
            }
        }
    }

    @ViewBuilder
    private var goalAndPlanCard: some View {
        if let summary = activePlanSummary {
            NavigationLink {
                TrainingPlanDetailView()
            } label: {
                activePlanCard(summary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.settings.openActivePlanDetailsAccessibilityLabel)
        } else {
            Button { showGoalEntry = true } label: {
                emptyPlanCard
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.settings.setRaceEnteredAccessibilityLabel)
        }
    }

    private func activePlanCard(_ summary: ActivePlanSummary) -> some View {
        TorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        TorEyebrow(language.settings.planStatusEyebrow(summary.health.status))
                            .foregroundStyle(statusColor(summary.health.status))
                        Text(planTitle(summary))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(raceLine(summary))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.dim)
                        Text("\(athleteName) · \(athleteType)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.faint)
                        if let detail = planStatusDetail(summary) {
                            Text(detail)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(statusColor(summary.health.status))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 44, height: 44)
                }

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
                        .tint(statusColor(summary.health.status))
                        .accessibilityLabel(language.settings.weekProgress(current: summary.currentWeek, total: summary.totalWeeks))
                }

                VStack(spacing: 9) {
                    if let phase = summary.currentPhase {
                        profileRow(language.settings.currentPhase, language.name(phase.phase))
                    }
                    if let thisWeek = summary.thisWeek, thisWeek.plannedSessions > 0 {
                        profileRow(language.settings.thisWeek, thisWeekLine(thisWeek))
                    }
                    profileRow(language.settings.nextWorkout, nextWorkoutLine(summary))
                }
            }
        }
    }

    private var emptyPlanCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                TorEyebrow(language.settings.planEyebrow)
                Text(language.settings.emptyPlanDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.settings.setRaceEntered)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 28, alignment: .leading)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var personalHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow(language.settings.personalHistoryEyebrow)
                .padding(.horizontal, 4)
            navRow(language.settings.runHistory, systemImage: "figure.run", subtitle: language.settings.runHistorySubtitle) { ActivityListView() }
            navRow(language.settings.runningShoes, systemImage: "shoeprints.fill", subtitle: language.settings.runningShoesSubtitle) { RunningShoesView() }
        }
    }

    private func navRow<Destination: View>(
        _ label: String,
        systemImage: String,
        subtitle: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.settings.openAccessibilityLabel(label))
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

    private var athleteName: String {
        language.settings.athleteName
    }

    private var athleteType: String {
        if goals.first?.spec?.distance == .marathon { return language.settings.marathonRunner }
        if let distance = goals.first?.spec?.distance { return language.settings.distanceRunner(distance) }
        return language.settings.runner
    }

    private var filledAthleteInputs: Int {
        [age, heightCm, weightKg]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private var athleteDetailSummary: String {
        switch filledAthleteInputs {
        case 0: language.settings.athleteDetailsMissing
        case 1, 2: language.settings.athleteDetailsPartial(filledAthleteInputs)
        default: language.settings.athleteDetailsComplete
        }
    }

    private var athleteMetrics: [ProfileMetric] {
        var metrics: [ProfileMetric] = []
        if let pace = thresholdPaceText {
            metrics.append(ProfileMetric(label: language.settings.thresholdPace, value: pace))
        }
        if let rhr = readiness.first(where: { $0.rhrMean7 != nil || $0.rhrMean28 != nil })?.rhrMean7
            ?? readiness.first(where: { $0.rhrMean28 != nil })?.rhrMean28 {
            metrics.append(ProfileMetric(label: language.settings.restingHeartRate, value: language.settings.heartRateValue(rhr)))
        }
        if let weight = cleanDouble(weightKg) {
            metrics.append(ProfileMetric(label: language.settings.weight, value: language.settings.weightValue(weight)))
        }
        if let vdot = fitnessProfile?.vdot, vdot.isFinite, vdot > 0 {
            metrics.append(ProfileMetric(label: language.settings.vo2Max, value: String(format: "%.0f", locale: language.uiLocale, vdot)))
        }
        return Array(metrics.prefix(4))
    }

    private var thresholdPaceText: String? {
        if let threshold = currentThresholdBand {
            let midpoint = (threshold.fastSecondsPerKm + threshold.slowSecondsPerKm) / 2
            return language.settings.paceValue(midpoint)
        }
        if let goal = goals.first?.spec {
            return language.settings.paceValue(goal.goalPaceSecondsPerKm)
        }
        return nil
    }

    private var currentThresholdBand: PaceBand? {
        guard let fitnessProfile else { return nil }
        return VDOTTable.trainingPaces(vdot: fitnessProfile.vdot).threshold
    }

    private var fitnessProfile: FitnessProfile? {
        FitnessEstimator.estimate(samples: runSamples, today: .now, calendar: calendar)
    }

    private var runSamples: [RunSample] {
        activities.compactMap { activity in
            guard let meters = activity.distanceMeters, meters > 0, activity.durationSeconds > 0 else { return nil }
            return RunSample(date: activity.date, distanceKm: meters / 1000, durationSeconds: activity.durationSeconds)
        }
    }

    private var activePlan: TrainingPlan? { plans.first }

    private var activePlanSummary: ActivePlanSummary? {
        ActivePlanSummaryBuilder.build(goal: goals.first, plan: activePlan, activities: activities, calendar: calendar)
    }

    private func planTitle(_ summary: ActivePlanSummary) -> String {
        guard let distance = goals.first?.spec?.distance else { return language.settings.trainingPlan }
        return language.settings.planTitle(distance: distance, targetTime: summary.targetTimeSeconds)
    }

    private func raceLine(_ summary: ActivePlanSummary) -> String {
        if summary.isRaceDay {
            return language.settings.raceDay(summary.raceDate)
        }
        if summary.health.status == .completed {
            return language.settings.raceCompleted(summary.raceDate)
        }
        if let days = summary.daysRemaining {
            return language.settings.raceDaysLeft(date: summary.raceDate, days: days)
        }
        return language.settings.longDateWithYear(summary.raceDate)
    }

    private func thisWeekLine(_ week: ActivePlanWeekSummary) -> String {
        language.settings.thisWeekProgress(
            completed: week.completedSessions,
            planned: week.plannedSessions,
            completedDistance: distanceText(week.completedDistanceKm),
            plannedDistance: distanceText(week.plannedDistanceKm)
        )
    }

    private func nextWorkoutLine(_ summary: ActivePlanSummary) -> String {
        if summary.health.status == .completed { return language.settings.planCompleted }
        if summary.health.status == .paused { return language.settings.planPaused }
        guard let next = summary.nextWorkout else { return language.settings.noUpcomingWorkout }
        return language.settings.workoutSummary(
            name: language.settings.workoutName(kind: next.kind, raw: next.kindRaw),
            distance: distanceText(next.distanceKm),
            day: relativeDay(next.date)
        )
    }

    private func distanceText(_ kilometers: Double) -> String {
        language.settings.distanceText(kilometers)
    }

    private func relativeDay(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return language.todayLabel }
        if calendar.isDateInTomorrow(date) { return language.tomorrowLabel }
        return language.shortWeekdayDate(date)
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

    private func planStatusDetail(_ summary: ActivePlanSummary) -> String? {
        let health = summary.health
        if summary.isRaceDay || health.reasons.contains(.raceDay) || health.reasons.contains(.raceDatePassed) {
            return nil
        }
        switch health.status {
        case .needsAttention:
            if let keys = missedKeyCount(health), keys > 0 {
                return language.settings.missedKeySessions(keys)
            }
            if health.reasons.contains(.weeklyVolumeBehind) {
                return language.settings.weeklyVolumeBehind
            }
            if let missed = missedCount(health), missed > 0 {
                return language.settings.missedRecentRuns(missed)
            }
            if health.reasons.contains(.insufficientData) {
                return language.settings.insufficientPlanHealthData
            }
            return language.settings.planSessionsSlipped
        case .active:
            if health.reasons.contains(.insufficientData) {
                return language.settings.logRunsForPlanHealth
            }
            return nil
        default:
            return nil
        }
    }

    private func missedKeyCount(_ health: PlanHealth) -> Int? {
        for reason in health.reasons {
            if case .missedKeySessions(let count) = reason { return count }
        }
        return nil
    }

    private func missedCount(_ health: PlanHealth) -> Int? {
        for reason in health.reasons {
            if case .missedSessions(let count) = reason { return count }
        }
        return nil
    }

    private func cleanDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}

private struct ProfileMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct MetricChip: View {
    let metric: ProfileMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.faint)
            Text(metric.value)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct AthleteProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(PersonalCoachSettings.ageKey) private var age = ""
    @AppStorage(PersonalCoachSettings.heightCmKey) private var heightCm = ""
    @AppStorage(PersonalCoachSettings.weightKgKey) private var weightKg = ""

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        Form {
            Section(language.settings.athleteSection) {
                numberField(language.settings.age, text: $age, unit: language.settings.years, allowsDecimal: false)
                numberField(language.settings.height, text: $heightCm, unit: language.settings.centimeters, allowsDecimal: true)
                numberField(language.settings.weight, text: $weightKg, unit: language.settings.kilograms, allowsDecimal: true)
            }
        }
        .navigationTitle(language.settings.athleteProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button(language.doneLabel) { dismiss() } }
    }

    private func numberField(
        _ title: String,
        text: Binding<String>,
        unit: String,
        allowsDecimal: Bool
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: text)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, newValue in
                    let sanitized = PersonalCoachSettings.sanitizedNumber(newValue, allowsDecimal: allowsDecimal)
                    if sanitized != newValue { text.wrappedValue = sanitized }
                }
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
