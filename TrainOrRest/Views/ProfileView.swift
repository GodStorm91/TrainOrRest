import SwiftData
import SwiftUI

/// Profile = athlete identity, active goal, plan stage, and personal history.
/// Configuration lives in SettingsView.
struct ProfileView: View {
    @Query private var goals: [Goal]
    @Query private var plans: [TrainingPlan]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readiness: [DailyReadiness]

    @AppStorage(PersonalCoachSettings.weightKgKey) private var weightKg = ""

    @State private var showGoalEntry = false
    @State private var showAthleteProfile = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                athleteSummaryCard
                goalAndPlanCard
                personalNavigationRows
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
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
            Text("Profile")
                .font(.torHeading(28, .bold))
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
            .accessibilityLabel("Open Settings")
        }
    }

    private var athleteSummaryCard: some View {
        TorCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(athleteName)
                        .font(.torHeading(22, .bold))
                        .foregroundStyle(Theme.text)
                    Text(athleteType)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                let metrics = athleteMetrics
                if metrics.isEmpty {
                    Text("Add a few athlete details so Coach can personalize training targets.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
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
                        Text(metrics.count < 2 ? "Complete athlete profile" : "Edit athlete profile")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.torHeading(14, .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44, alignment: .center)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(metrics.count < 2 ? "Complete athlete profile" : "Edit athlete profile")
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
            .accessibilityLabel("Open active training plan details")
        } else {
            Button { showGoalEntry = true } label: {
                emptyPlanCard
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create training plan")
        }
    }

    private func activePlanCard(_ summary: ActivePlanSummary) -> some View {
        TorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        TorEyebrow(summary.health.status.eyebrowText)
                            .foregroundStyle(statusColor(summary.health.status))
                        Text(summary.title)
                            .font(.torHeading(22, .bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(raceLine(summary))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 44, height: 44)
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

                VStack(spacing: 9) {
                    if let phase = summary.currentPhase {
                        profileRow("Current phase", phase.displayName)
                    }
                    if let thisWeek = summary.thisWeek, thisWeek.plannedSessions > 0 {
                        profileRow("This week", thisWeekLine(thisWeek))
                    }
                    profileRow("Next workout", nextWorkoutLine(summary))
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
                TorEyebrow("PLAN")
                Text("Set a goal and let Coach create a structured plan around your schedule.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Create training plan")
                    .font(.torHeading(15, .bold))
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

    private var personalNavigationRows: some View {
        VStack(spacing: 10) {
            navRow("Run history", systemImage: "figure.run") { ActivityListView() }
            navRow("Running Shoes", systemImage: "shoeprints.fill") { RunningShoesView() }
        }
    }

    private func navRow<Destination: View>(
        _ label: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                Text(label)
                    .font(.torHeading(16, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(16)
            .frame(minHeight: 56)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(label.lowercased())")
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private var athleteName: String {
        return "Khanh Nguyen"
    }

    private var athleteType: String {
        if goals.first?.spec?.distance == .marathon { return "Marathon runner" }
        if let distance = goals.first?.spec?.distance { return "\(distance.displayName) runner" }
        return "Runner"
    }

    private var athleteMetrics: [ProfileMetric] {
        var metrics: [ProfileMetric] = []
        if let pace = thresholdPaceText {
            metrics.append(ProfileMetric(label: "Threshold pace", value: pace))
        }
        if let rhr = readiness.first(where: { $0.rhrMean7 != nil || $0.rhrMean28 != nil })?.rhrMean7
            ?? readiness.first(where: { $0.rhrMean28 != nil })?.rhrMean28 {
            metrics.append(ProfileMetric(label: "Resting HR", value: Formatters.heartRate(rhr)))
        }
        if let weight = cleanDouble(weightKg) {
            metrics.append(ProfileMetric(label: "Weight", value: String(format: "%.1f kg", weight)))
        }
        if let vdot = fitnessProfile?.vdot, vdot.isFinite, vdot > 0 {
            metrics.append(ProfileMetric(label: "VO₂ max", value: String(format: "%.0f", vdot)))
        }
        return Array(metrics.prefix(4))
    }

    private var thresholdPaceText: String? {
        if let threshold = currentThresholdBand {
            let midpoint = (threshold.fastSecondsPerKm + threshold.slowSecondsPerKm) / 2
            return Formatters.pace(midpoint).replacingOccurrences(of: " /km", with: "/km")
        }
        if let goal = goals.first?.spec {
            return Formatters.pace(goal.goalPaceSecondsPerKm).replacingOccurrences(of: " /km", with: "/km")
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

    private func raceLine(_ summary: ActivePlanSummary) -> String {
        if summary.isRaceDay {
            return "\(summary.raceDate.formatted(date: .long, time: .omitted)) · Race day"
        }
        if summary.health.status == .completed {
            return "\(summary.raceDate.formatted(date: .long, time: .omitted)) · Completed"
        }
        if let days = summary.daysRemaining {
            return "\(summary.raceDate.formatted(date: .long, time: .omitted)) · \(days) days left"
        }
        return summary.raceDate.formatted(date: .long, time: .omitted)
    }

    private func thisWeekLine(_ week: ActivePlanWeekSummary) -> String {
        "\(week.completedSessions) of \(week.plannedSessions) runs · \(distanceText(week.completedDistanceKm)) of \(distanceText(week.plannedDistanceKm))"
    }

    private func nextWorkoutLine(_ summary: ActivePlanSummary) -> String {
        if summary.health.status == .completed { return "Plan completed" }
        if summary.health.status == .paused { return "Plan is paused" }
        guard let next = summary.nextWorkout else { return "No upcoming workout" }
        return "\(next.displayName) \(distanceText(next.distanceKm)) · \(relativeDay(next.date))"
    }

    private func distanceText(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    private func relativeDay(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(metric.value)
                .font(.torHeading(17, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
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
    @AppStorage(PersonalCoachSettings.ageKey) private var age = ""
    @AppStorage(PersonalCoachSettings.heightCmKey) private var heightCm = ""
    @AppStorage(PersonalCoachSettings.weightKgKey) private var weightKg = ""

    var body: some View {
        Form {
            Section("Athlete") {
                numberField("Age", text: $age, unit: "years", allowsDecimal: false)
                numberField("Height", text: $heightCm, unit: "cm", allowsDecimal: true)
                numberField("Weight", text: $weightKg, unit: "kg", allowsDecimal: true)
            }
        }
        .navigationTitle("Athlete Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
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
