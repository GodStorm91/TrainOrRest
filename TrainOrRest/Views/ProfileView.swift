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
        if let goal = goals.first?.spec {
            TorCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            TorEyebrow("\(goal.distance.displayName) goal")
                            Text(goalTitle(for: goal))
                                .font(.torHeading(22, .bold))
                                .foregroundStyle(Theme.text)
                            Text(goal.raceDate.formatted(date: .long, time: .omitted))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Button {
                            showGoalEntry = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit race goal")
                    }

                    VStack(spacing: 9) {
                        profileRow("Target", Formatters.duration(goal.targetTimeSeconds))
                        profileRow("Running days", "\(goal.availableDays.count)/week")
                        profileRow("Current phase", currentPhaseText)
                        profileRow("Time remaining", timeRemainingText(until: goal.raceDate))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: planProgress)
                            .tint(Theme.accent)
                            .accessibilityLabel("Training plan progress")
                            .accessibilityValue("Phase \(currentPhaseNumber) of \(totalPhaseCount)")
                        Text("Phase \(currentPhaseNumber) of \(totalPhaseCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.faint)
                    }

                    NavigationLink {
                        PlanCalendarView()
                    } label: {
                        HStack {
                            Text("View training plan")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View training plan")
                }
            }
        } else {
            Button { showGoalEntry = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Set a race goal")
                            .font(.torHeading(18, .bold))
                            .foregroundStyle(Theme.text)
                        Text("Tell RestOrTrain what you are training for.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.faint)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set a race goal")
        }
    }

    private var personalNavigationRows: some View {
        VStack(spacing: 10) {
            navRow("Run history", systemImage: "figure.run") { ActivityListView() }
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

    private var currentWeekIndex: Int {
        guard let plan = activePlan else { return 0 }
        let today = calendar.startOfDay(for: .now)
        let sorted = plan.workouts.sorted { $0.date < $1.date }
        if let upcoming = sorted.first(where: { calendar.startOfDay(for: $0.date) >= today }) {
            return upcoming.weekIndex
        }
        return sorted.last?.weekIndex ?? 0
    }

    private var currentPhaseText: String {
        activePlan?.phase(forWeek: currentWeekIndex)?.displayName ?? "Plan setup"
    }

    private var totalPhaseCount: Int {
        max(activePlan?.weekPhasesRaw.count ?? 1, 1)
    }

    private var currentPhaseNumber: Int {
        min(max(currentWeekIndex + 1, 1), totalPhaseCount)
    }

    private var planProgress: Double {
        guard totalPhaseCount > 0 else { return 0 }
        return Double(currentPhaseNumber) / Double(totalPhaseCount)
    }

    private func timeRemainingText(until raceDate: Date) -> String {
        let today = calendar.startOfDay(for: .now)
        let raceDay = calendar.startOfDay(for: raceDate)
        let days = max(calendar.dateComponents([.day], from: today, to: raceDay).day ?? 0, 0)
        if days >= 14 { return "\(Int((Double(days) / 7).rounded())) weeks" }
        return "\(days) days"
    }

    private func goalTitle(for goal: GoalSpec) -> String {
        if goal.distance == .marathon, goal.targetTimeSeconds <= 4 * 3600 {
            return "Sub-4:00 Marathon"
        }
        return "\(goal.distance.displayName) in \(Formatters.duration(goal.targetTimeSeconds))"
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
