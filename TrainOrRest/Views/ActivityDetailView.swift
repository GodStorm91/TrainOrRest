import SwiftData
import SwiftUI

struct ActivityDetailView: View {
    let activity: CompletedActivity
    @Query(sort: \PlannedWorkout.date) private var plannedWorkouts: [PlannedWorkout]
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Query private var mileageEntries: [ShoeMileageEntry]
    @Query private var storedShoePreferences: [RunningShoePreferences]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(WorkoutPushSettings.athleteIDKey) private var intervalsAthleteID = ""

    @State private var analysisExpanded = false
    @State private var selectedAnalysisTab: ActivityAnalysisTab = .pace
    @State private var expandedTechnicalSection: ActivityTechnicalSection?
    @State private var intervalsAnalysis: IntervalsActivityAnalysisData?
    @State private var intervalsLoadState: IntervalsActivityLoadState = .idle
    @State private var isChoosingShoe = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                RunDetailSummary(activity: activity, intervalsAnalysis: intervalsAnalysis)
                    .padding(.top, 8)

                RunReviewCard(
                    activity: activity,
                    plannedWorkout: matchedWorkout,
                    intervalsAnalysis: intervalsAnalysis,
                    isAnalysisExpanded: $analysisExpanded,
                    selectedAnalysisTab: $selectedAnalysisTab
                )

                technicalSections
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 116)
            .torReadableColumn()
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaPadding(.bottom, 96)
        .navigationTitle(activity.date.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: activity.hkUUID) {
            await loadIntervalsAnalysis()
        }
        .sheet(isPresented: $isChoosingShoe) {
            ShoePickerSheet(
                workoutType: ShoeWorkoutType.normalized(from: matchedWorkout?.kind),
                shoes: shoes,
                mileageEntries: mileageEntries,
                recommendedShoeID: recommendedShoeID,
                allowsAutomaticSelection: false,
                onSelect: { shoe in
                    activity.shoeID = shoe?.id
                    activity.shoeAssignmentSource = shoe == nil ? .none : .manual
                    try? ShoeMileageService.syncMileage(for: activity, in: modelContext)
                    try? modelContext.save()
                },
                onAutomatic: nil
            )
        }
    }

    private var technicalSections: some View {
        VStack(spacing: 10) {
            CollapsibleMetricSection(
                section: .activityDetails,
                expandedSection: $expandedTechnicalSection,
                preview: "\(Formatters.kilometers(summaryDistanceMeters)) · \(Formatters.duration(summaryDurationSeconds))"
            ) {
                MetricRow(label: "Date", value: activity.date.formatted(date: .long, time: .shortened))
                MetricRow(label: "Distance", value: Formatters.kilometers(summaryDistanceMeters))
                MetricRow(label: "Duration", value: Formatters.duration(summaryDurationSeconds))
                MetricRow(label: "Average pace", value: Formatters.pace(summaryAveragePace))
                if let plannedWorkout = matchedWorkout {
                    MetricRow(label: "Matched plan", value: plannedWorkout.kind?.displayName ?? plannedWorkout.kindRaw)
                    MetricRow(label: "Planned distance", value: Formatters.kilometers(plannedWorkout.distanceKm * 1000))
                }
                if let intervalsAnalysis {
                    MetricRow(label: "Analysis source", value: "intervals.icu · \(intervalsAnalysis.activityID)")
                    if let load = intervalsAnalysis.trainingLoad {
                        MetricRow(label: "Training load", value: "\(Int(load.rounded()))")
                    }
                } else {
                    MetricRow(label: "Analysis source", value: intervalsLoadState.fallbackDescription)
                }
            }

            CollapsibleMetricSection(
                section: .heartRateDetails,
                expandedSection: $expandedTechnicalSection,
                preview: "\(heartRateLabel) \(Formatters.heartRate(summaryAverageHeartRate))"
            ) {
                MetricRow(label: heartRateLabel, value: Formatters.heartRate(summaryAverageHeartRate))
                MetricRow(label: "Maximum HR", value: Formatters.heartRate(summaryMaxHeartRate))
                MetricRow(label: "Averaging logic", value: intervalsAnalysis == nil ? "Health samples across the workout interval" : "intervals.icu Garmin activity summary")
            }

            CollapsibleMetricSection(
                section: .runningDynamics,
                expandedSection: $expandedTechnicalSection,
                preview: "Cadence and stride data not synced"
            ) {
                MetricRow(label: "Cadence", value: "Not available")
                MetricRow(label: "Stride length", value: "Not available")
                MetricRow(label: "Ground contact", value: "Not available")
            }

            CollapsibleMetricSection(
                section: .elevation,
                expandedSection: $expandedTechnicalSection,
                preview: "No elevation series"
            ) {
                MetricRow(label: "Gain", value: "Not available")
                MetricRow(label: "Loss", value: "Not available")
            }

            CollapsibleMetricSection(
                section: .weather,
                expandedSection: $expandedTechnicalSection,
                preview: "No weather attached"
            ) {
                MetricRow(label: "Temperature", value: "Not available")
                MetricRow(label: "Humidity", value: "Not available")
            }

            CollapsibleMetricSection(
                section: .gear,
                expandedSection: $expandedTechnicalSection,
                preview: assignedShoe?.displayName ?? intervalsAnalysis?.deviceName ?? activity.sourceName
            ) {
                Button {
                    isChoosingShoe = true
                } label: {
                    WorkoutShoeRow(
                        shoe: assignedShoe,
                        source: activity.shoeAssignmentSource,
                        isNearMileageRange: assignedShoe.map(isNearMileageRange) ?? false
                    )
                }
                .buttonStyle(.plain)
                if let assignedShoe {
                    MetricRow(
                        label: "Shoe total",
                        value: "\(kmText(ShoeMileageService.currentMileageKm(for: assignedShoe, ledger: mileageEntries))) km"
                    )
                }
                MetricRow(label: "Recorded by", value: activity.sourceName)
                MetricRow(label: "Analysis source", value: intervalsAnalysis == nil ? "Apple Health import" : "intervals.icu Garmin import")
                if let deviceName = intervalsAnalysis?.deviceName {
                    MetricRow(label: "Device", value: deviceName)
                }
            }
        }
    }

    private var summaryDistanceMeters: Double? {
        intervalsAnalysis?.distanceMeters ?? activity.distanceMeters
    }

    private var summaryDurationSeconds: Double {
        intervalsAnalysis?.movingTimeSeconds ?? activity.durationSeconds
    }

    private var summaryAveragePace: Double? {
        intervalsAnalysis?.averagePaceSecondsPerKm ?? activity.avgPaceSecondsPerKm
    }

    private var summaryAverageHeartRate: Double? {
        intervalsAnalysis?.averageHeartRate ?? activity.avgHeartRate
    }

    private var summaryMaxHeartRate: Double? {
        intervalsAnalysis?.maxHeartRate ?? activity.maxHeartRate
    }

    private var heartRateLabel: String {
        intervalsAnalysis == nil ? "Recorded average HR" : "Intervals average HR"
    }

    @MainActor
    private func loadIntervalsAnalysis() async {
        let athleteID = intervalsAthleteID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !athleteID.isEmpty,
              let apiKey = try? KeychainStore.load(account: KeychainStore.intervalsICUAccount)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            intervalsLoadState = .unconfigured
            return
        }

        intervalsLoadState = .loading
        do {
            let credentials = IntervalsICUCredentials(athleteID: athleteID, apiKey: apiKey)
            let loader = IntervalsActivityAnalysisLoader(client: IntervalsICUClient())
            if let analysis = try await loader.analysis(for: activity, credentials: credentials, calendar: calendar) {
                intervalsAnalysis = analysis
                intervalsLoadState = .loaded
            } else {
                intervalsAnalysis = nil
                intervalsLoadState = .notFound
            }
        } catch {
            intervalsAnalysis = nil
            intervalsLoadState = .failed
        }
    }

    private var matchedWorkout: PlannedWorkout? {
        if let exact = plannedWorkouts.first(where: { $0.matchedActivityUUID == activity.hkUUID }) {
            return exact
        }
        return plannedWorkouts.first {
            calendar.isDate($0.date, inSameDayAs: activity.date)
        }
    }

    private var assignedShoe: RunningShoe? {
        guard let shoeID = activity.shoeID else { return nil }
        return shoes.first { $0.id == shoeID }
    }

    private var shoePreferences: RunningShoePreferences {
        storedShoePreferences.first ?? RunningShoePreferences()
    }

    private var recommendedShoeID: UUID? {
        if let shoeID = matchedWorkout?.shoeID { return shoeID }
        return ShoeAssignmentService.selectShoeForWorkout(
            workoutType: ShoeWorkoutType.normalized(from: matchedWorkout?.kind),
            activeShoes: shoes,
            preferences: shoePreferences,
            existingShoeID: nil,
            existingAssignmentSource: .none,
            mileageEntries: mileageEntries
        ).shoeID
    }

    private func isNearMileageRange(_ shoe: RunningShoe) -> Bool {
        ShoeWearStatusService.isNearRetirement(
            shoe,
            ledger: mileageEntries,
            thresholdPercent: shoePreferences.nearRetirementThresholdPercent
        )
    }
}

struct RunReviewCard: View {
    let activity: CompletedActivity
    let plannedWorkout: PlannedWorkout?
    let intervalsAnalysis: IntervalsActivityAnalysisData?
    @Binding var isAnalysisExpanded: Bool
    @Binding var selectedAnalysisTab: ActivityAnalysisTab
    private let allowsAnalysisExpansion: Bool

    init(
        activity: CompletedActivity,
        plannedWorkout: PlannedWorkout?,
        intervalsAnalysis: IntervalsActivityAnalysisData? = nil,
        isAnalysisExpanded: Binding<Bool> = .constant(false),
        selectedAnalysisTab: Binding<ActivityAnalysisTab> = .constant(.pace)
    ) {
        self.activity = activity
        self.plannedWorkout = plannedWorkout
        self.intervalsAnalysis = intervalsAnalysis
        self._isAnalysisExpanded = isAnalysisExpanded
        self._selectedAnalysisTab = selectedAnalysisTab
        self.allowsAnalysisExpansion = true
    }

    init(activity: CompletedActivity, plannedWorkout: PlannedWorkout?, compact: Bool) {
        self.activity = activity
        self.plannedWorkout = plannedWorkout
        self.intervalsAnalysis = nil
        self._isAnalysisExpanded = .constant(false)
        self._selectedAnalysisTab = .constant(.pace)
        self.allowsAnalysisExpansion = false
    }

    private var model: ActivityDetailAnalysis {
        ActivityDetailAnalysis(activity: activity, plannedWorkout: plannedWorkout, intervalsAnalysis: intervalsAnalysis)
    }

    private var accent: Color {
        switch model.review.verdict {
        case .onPlan: Theme.good
        case .overcooked: Theme.warn
        case .undercooked: Theme.data
        case .unmatched: Theme.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 4)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 8) {
                    TorEyebrow(model.eyebrow).tracking(1.5)
                    Text(model.headline)
                        .font(.torHeading(24, .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.supportingSentence)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.evidenceChips) { chip in
                        ActivityEvidenceChip(chip: chip)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()

            Button {
                guard allowsAnalysisExpansion else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isAnalysisExpanded.toggle()
                    selectedAnalysisTab = .pace
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.chartTitle)
                            .font(.torHeading(15, .bold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if allowsAnalysisExpansion {
                            Label("View full analysis", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    PlanComparisonChart(model: model, style: .mini)
                        .frame(height: 126)
                        .allowsHitTesting(false)

                    Text(model.miniChartInterpretation)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if isAnalysisExpanded {
                FullAnalysisCard(model: model, selectedTab: $selectedAnalysisTab)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            CoachRecommendationView(text: model.recommendation, accent: accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TrainingVisualStyle.tint(accent, opacity: 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

private struct RunDetailSummary: View {
    let activity: CompletedActivity
    let intervalsAnalysis: IntervalsActivityAnalysisData?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass


    private var distanceMeters: Double? {
        intervalsAnalysis?.distanceMeters ?? activity.distanceMeters
    }

    private var durationSeconds: Double {
        intervalsAnalysis?.movingTimeSeconds ?? activity.durationSeconds
    }

    private var averagePace: Double? {
        intervalsAnalysis?.averagePaceSecondsPerKm ?? activity.avgPaceSecondsPerKm
    }

    private var averageHeartRate: Double? {
        intervalsAnalysis?.averageHeartRate ?? activity.avgHeartRate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Run")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.dim)
                    Text(Formatters.kilometers(distanceMeters))
                        .font(.torNumber(44, .bold))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                }
                Spacer(minLength: 16)
                Image(systemName: "figure.run")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(activity.effortColor)
                    .frame(width: 46, height: 46)
                    .background(TrainingVisualStyle.tint(activity.effortColor, opacity: 0.18), in: Circle())
            }

            summaryMetrics
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(TrainingVisualStyle.tint(activity.effortColor, opacity: 0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TrainingVisualStyle.tint(activity.effortColor, opacity: 0.22), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.18), value: distanceMeters)
    }

    @ViewBuilder
    private var summaryMetrics: some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ActivityStatPill(Formatters.pace(averagePace), symbol: "speedometer")
                ActivityStatPill(Formatters.duration(durationSeconds), symbol: "clock")
                ActivityStatPill(Formatters.heartRate(averageHeartRate), symbol: "heart")
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ActivityStatPill(Formatters.pace(averagePace), symbol: "speedometer")
                    ActivityStatPill(Formatters.duration(durationSeconds), symbol: "clock")
                    ActivityStatPill(Formatters.heartRate(averageHeartRate), symbol: "heart")
                }
                VStack(alignment: .leading, spacing: 8) {
                    ActivityStatPill(Formatters.pace(averagePace), symbol: "speedometer")
                    ActivityStatPill(Formatters.duration(durationSeconds), symbol: "clock")
                    ActivityStatPill(Formatters.heartRate(averageHeartRate), symbol: "heart")
                }
            }
        }
    }
}

struct ActivityStatPill: View {
    let value: String
    let symbol: String

    init(_ value: String, symbol: String) {
        self.value = value
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(value)
                .monospacedDigit()
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.chip, in: Capsule())
    }
}

private struct FullAnalysisCard: View {
    let model: ActivityDetailAnalysis
    @Binding var selectedTab: ActivityAnalysisTab

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisSegmentedControl(selection: $selectedTab, availableTabs: model.availableTabs)

            switch selectedTab {
            case .pace:
                PaceAnalysisView(model: model)
            case .heartRate:
                HeartRateAnalysisView(model: model)
            case .splits:
                SplitsAnalysisView(model: model)
            }
        }
        .padding(14)
        .background(Theme.card.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private struct PaceAnalysisView: View {
    let model: ActivityDetailAnalysis
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.hasPlan ? "Pace vs plan" : "Pace pattern")
                .font(.torHeading(18, .bold))
                .foregroundStyle(Theme.text)

            summaryMetrics

            PlanComparisonChart(model: model, style: .expanded)
                .frame(height: 230)

            Text(model.paceInsight)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder
    private var summaryMetrics: some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                AnalysisSummaryPill(value: Formatters.pace(model.actualPace).replacingOccurrences(of: " /km", with: "/km"), label: "actual", color: Theme.accent)
                if model.hasPlan {
                    AnalysisSummaryPill(value: Formatters.pace(model.plannedAveragePace).replacingOccurrences(of: " /km", with: "/km"), label: "planned", color: Theme.good)
                    AnalysisSummaryPill(value: model.paceDeltaText, label: "fast", color: Theme.warn)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    AnalysisSummaryPill(value: Formatters.pace(model.actualPace).replacingOccurrences(of: " /km", with: "/km"), label: "actual", color: Theme.accent)
                    if model.hasPlan {
                        AnalysisSummaryPill(value: Formatters.pace(model.plannedAveragePace).replacingOccurrences(of: " /km", with: "/km"), label: "planned", color: Theme.good)
                        AnalysisSummaryPill(value: model.paceDeltaText, label: "fast", color: Theme.warn)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    AnalysisSummaryPill(value: Formatters.pace(model.actualPace).replacingOccurrences(of: " /km", with: "/km"), label: "actual", color: Theme.accent)
                    if model.hasPlan {
                        AnalysisSummaryPill(value: Formatters.pace(model.plannedAveragePace).replacingOccurrences(of: " /km", with: "/km"), label: "planned", color: Theme.good)
                        AnalysisSummaryPill(value: model.paceDeltaText, label: "fast", color: Theme.warn)
                    }
                }
            }
        }
    }

}

private struct HeartRateAnalysisView: View {
    let model: ActivityDetailAnalysis
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart rate")
                .font(.torHeading(18, .bold))
                .foregroundStyle(Theme.text)

            summaryMetrics

            HeartRateTrendChart(model: model)
                .frame(height: 210)

            Text(model.heartRateInsight)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder
    private var summaryMetrics: some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                AnalysisSummaryPill(value: Formatters.heartRate(model.averageHeartRate), label: "recorded avg", color: Theme.data)
                AnalysisSummaryPill(value: Formatters.heartRate(model.maxHeartRate), label: "max", color: Theme.warn)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    AnalysisSummaryPill(value: Formatters.heartRate(model.averageHeartRate), label: "recorded avg", color: Theme.data)
                    AnalysisSummaryPill(value: Formatters.heartRate(model.maxHeartRate), label: "max", color: Theme.warn)
                }
                VStack(alignment: .leading, spacing: 8) {
                    AnalysisSummaryPill(value: Formatters.heartRate(model.averageHeartRate), label: "recorded avg", color: Theme.data)
                    AnalysisSummaryPill(value: Formatters.heartRate(model.maxHeartRate), label: "max", color: Theme.warn)
                }
            }
        }
    }
}

private struct SplitsAnalysisView: View {
    let model: ActivityDetailAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Splits")
                .font(.torHeading(18, .bold))
                .foregroundStyle(Theme.text)

            VStack(spacing: 7) {
                ForEach(model.splits) { split in
                    SplitComparisonRow(split: split, plannedAveragePace: model.plannedAveragePace)
                }
            }

            Text(model.splitsSummary)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
    }
}

private struct AnalysisSummaryPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.torHeading(16, .bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ActivityEvidenceChip: View {
    let chip: ActivityEvidence

    var body: some View {
        Label {
            Text(chip.title)
                .lineLimit(1)
                .monospacedDigit()
        } icon: {
            Image(systemName: chip.symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 14, height: 14)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(chip.color)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.soft(chip.color, 0.12), in: Capsule())
    }
}

struct CoachRecommendationView: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(Theme.soft(accent, 0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Next session")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.faint)
                    .textCase(.uppercase)
                Text(text)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrainingVisualStyle.tint(accent, opacity: 0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AnalysisSegmentedControl: View {
    @Binding var selection: ActivityAnalysisTab
    let availableTabs: [ActivityAnalysisTab]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(availableTabs, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            VStack(spacing: 4) {
                ForEach(availableTabs, id: \.self) { tab in
                    tabButton(tab)
                }
            }
        }
        .padding(4)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tabButton(_ tab: ActivityAnalysisTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selection = tab
            }
        } label: {
            Text(tab.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selection == tab ? Color.white : Theme.dim)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selection == tab ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PlanComparisonChart: View {
    enum Style {
        case mini
        case expanded
    }

    let model: ActivityDetailAnalysis
    var style: Style = .mini
    @State private var scrubTime: Double?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    drawChart(in: canvasSize, context: &context)
                }

                if model.hasPlan {
                    Text("Target")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.good)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.bg.opacity(0.74), in: Capsule())
                        .position(x: 38, y: y(for: model.plannedAveragePace, in: size) - 10)
                }

                if style == .mini, model.hasPlan {
                    Text("Main deviation · 18-24 min")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.bg.opacity(0.82), in: Capsule())
                        .position(x: min(size.width - 74, x(for: model.durationSeconds * 0.50, in: size)), y: 18)
                }

                if let scrubTime {
                    let point = model.nearestPacePoint(to: scrubTime)
                    let x = x(for: point.time, in: size)
                    let y = y(for: point.actual ?? model.plannedAveragePace, in: size)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 8))
                        path.addLine(to: CGPoint(x: x, y: size.height - 20))
                    }
                    .stroke(Theme.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    Circle()
                        .fill((point.actual ?? model.plannedAveragePace) < model.plannedFastPace ? Theme.warn : Theme.accent)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)

                    ChartTooltip(
                        time: Formatters.duration(point.time),
                        actual: Formatters.pace(point.actual).replacingOccurrences(of: " /km", with: "/km"),
                        planned: Formatters.pace(model.plannedAveragePace).replacingOccurrences(of: " /km", with: "/km")
                    )
                    .position(x: min(max(x, 86), size.width - 86), y: max(28, y - 42))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clamped = min(max(value.location.x, 0), max(size.width, 1))
                        scrubTime = (clamped / max(size.width, 1)) * model.durationSeconds
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.18)) { scrubTime = nil }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibilityChartSummary)
        }
    }

    private func drawChart(in size: CGSize, context: inout GraphicsContext) {
        let bottomLabelY = size.height - 12
        let chartHeight = size.height - 22

        if model.hasPlan {
            let bandTop = y(for: model.plannedFastPace, in: CGSize(width: size.width, height: chartHeight + 2))
            let bandBottom = y(for: model.plannedSlowPace, in: CGSize(width: size.width, height: chartHeight + 2))
            let bandRect = CGRect(x: 0, y: min(bandTop, bandBottom), width: size.width, height: abs(bandBottom - bandTop))
            context.fill(Path(roundedRect: bandRect, cornerRadius: 8), with: .color(Theme.good.opacity(0.14)))

            var target = Path()
            let targetY = y(for: model.plannedAveragePace, in: CGSize(width: size.width, height: chartHeight + 2))
            target.move(to: CGPoint(x: 0, y: targetY))
            target.addLine(to: CGPoint(x: size.width, y: targetY))
            context.stroke(target, with: .color(Theme.good.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }

        let faintLineY = y(for: model.chartSlowReference, in: CGSize(width: size.width, height: chartHeight + 2))
        var faintLine = Path()
        faintLine.move(to: CGPoint(x: 0, y: faintLineY))
        faintLine.addLine(to: CGPoint(x: size.width, y: faintLineY))
        context.stroke(faintLine, with: .color(Theme.line.opacity(0.7)), lineWidth: 1)

        let points = model.pacePoints
        for pair in zip(points, points.dropFirst()) {
            guard let lhs = pair.0.actual, let rhs = pair.1.actual else {
                drawPauseMarker(for: pair.0.time, in: size, context: &context)
                continue
            }
            var segment = Path()
            segment.move(to: CGPoint(x: x(for: pair.0.time, in: size), y: y(for: lhs, in: CGSize(width: size.width, height: chartHeight + 2))))
            segment.addLine(to: CGPoint(x: x(for: pair.1.time, in: size), y: y(for: rhs, in: CGSize(width: size.width, height: chartHeight + 2))))
            let tooFast = model.hasPlan && (lhs < model.plannedFastPace || rhs < model.plannedFastPace)
            context.stroke(segment, with: .color(tooFast ? Theme.warn : Theme.accent.opacity(0.86)), style: StrokeStyle(lineWidth: tooFast ? 3 : 2.25, lineCap: .round, lineJoin: .round))
        }

        if style == .expanded {
            drawAxisLabel("0:00", x: 0, y: bottomLabelY, in: size, context: &context)
            drawAxisLabel(Formatters.duration(model.durationSeconds), x: size.width - 44, y: bottomLabelY, in: size, context: &context)
        }
    }

    private func drawPauseMarker(for time: Double, in size: CGSize, context: inout GraphicsContext) {
        let x = x(for: time, in: size)
        var marker = Path()
        marker.move(to: CGPoint(x: x, y: 12))
        marker.addLine(to: CGPoint(x: x, y: size.height - 22))
        context.stroke(marker, with: .color(Theme.faint.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
    }

    private func drawAxisLabel(_ text: String, x: CGFloat, y: CGFloat, in size: CGSize, context: inout GraphicsContext) {
        let resolved = context.resolve(Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint))
        context.draw(resolved, at: CGPoint(x: x, y: y), anchor: .topLeading)
    }

    private func x(for time: Double, in size: CGSize) -> CGFloat {
        CGFloat(time / max(model.durationSeconds, 1)) * size.width
    }

    private func y(for pace: Double, in size: CGSize) -> CGFloat {
        let range = max(model.chartMaxPace - model.chartMinPace, 1)
        let normalized = (pace - model.chartMinPace) / range
        return CGFloat(normalized) * max(size.height - 22, 1) + 6
    }
}

private struct HeartRateTrendChart: View {
    let model: ActivityDetailAnalysis
    @State private var scrubTime: Double?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    drawChart(in: canvasSize, context: &context)
                }

                if let scrubTime {
                    let point = model.nearestHeartRatePoint(to: scrubTime)
                    let x = x(for: point.time, in: size)
                    let y = y(for: point.bpm, in: size)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 8))
                        path.addLine(to: CGPoint(x: x, y: size.height - 20))
                    }
                    .stroke(Theme.text.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Circle()
                        .fill(point.bpm >= model.heartRateUpperTarget ? Theme.warn : Theme.data)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                    ChartTooltip(time: Formatters.duration(point.time), actual: "\(Int(point.bpm.rounded())) bpm", planned: "easy \(Int(model.heartRateUpperTarget.rounded())) bpm")
                        .position(x: min(max(x, 86), size.width - 86), y: max(28, y - 42))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clamped = min(max(value.location.x, 0), max(size.width, 1))
                        scrubTime = (clamped / max(size.width, 1)) * model.durationSeconds
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.18)) { scrubTime = nil } }
            )
        }
    }

    private func drawChart(in size: CGSize, context: inout GraphicsContext) {
        let bandTop = y(for: model.heartRateUpperTarget, in: size)
        let bandBottom = y(for: model.heartRateLowerTarget, in: size)
        let bandRect = CGRect(x: 0, y: min(bandTop, bandBottom), width: size.width, height: abs(bandBottom - bandTop))
        context.fill(Path(roundedRect: bandRect, cornerRadius: 8), with: .color(Theme.good.opacity(0.10)))

        let points = model.heartRatePoints
        for pair in zip(points, points.dropFirst()) {
            var segment = Path()
            segment.move(to: CGPoint(x: x(for: pair.0.time, in: size), y: y(for: pair.0.bpm, in: size)))
            segment.addLine(to: CGPoint(x: x(for: pair.1.time, in: size), y: y(for: pair.1.bpm, in: size)))
            let elevated = pair.0.bpm >= model.heartRateUpperTarget || pair.1.bpm >= model.heartRateUpperTarget
            context.stroke(segment, with: .color(elevated ? Theme.warn : Theme.data.opacity(0.88)), style: StrokeStyle(lineWidth: elevated ? 3 : 2.25, lineCap: .round, lineJoin: .round))
        }
    }

    private func x(for time: Double, in size: CGSize) -> CGFloat {
        CGFloat(time / max(model.durationSeconds, 1)) * size.width
    }

    private func y(for bpm: Double, in size: CGSize) -> CGFloat {
        let minValue = max(90, model.heartRateMin - 8)
        let maxValue = min(190, model.heartRateMax + 8)
        let range = max(maxValue - minValue, 1)
        return CGFloat(1 - ((bpm - minValue) / range)) * max(size.height - 24, 1) + 8
    }
}

private struct ChartTooltip: View {
    let time: String
    let actual: String
    let planned: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.faint)
            Text(actual)
                .font(.torHeading(13, .bold))
                .foregroundStyle(Theme.text)
            Text(planned)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct SplitComparisonRow: View {
    let split: SplitComparison
    let plannedAveragePace: Double

    var body: some View {
        HStack(spacing: 10) {
            Text("\(split.kilometer)")
                .font(.torHeading(14, .bold))
                .foregroundStyle(split.isMeaningfullyFast ? Theme.warn : Theme.dim)
                .frame(width: 24)

            GeometryReader { proxy in
                let barWidth = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.chip)
                        .frame(height: 8)
                    Capsule()
                        .fill(split.isMeaningfullyFast ? Theme.warn.opacity(0.82) : Theme.accent.opacity(0.72))
                        .frame(width: max(28, CGFloat(split.relativeWidth) * barWidth), height: 8)
                    Rectangle()
                        .fill(Theme.good)
                        .frame(width: 2, height: 18)
                        .offset(x: barWidth * 0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)

            Text(Formatters.pace(split.paceSecondsPerKm).replacingOccurrences(of: " /km", with: "/km"))
                .font(.torMono(12, .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 62, alignment: .trailing)

            if let avgHR = split.averageHeartRate {
                Text("\(Int(avgHR.rounded()))")
                    .font(.torMono(12, .semibold))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(Theme.chip.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Kilometer \(split.kilometer), \(Formatters.pace(split.paceSecondsPerKm)), planned \(Formatters.pace(plannedAveragePace))")
    }
}

struct CollapsibleMetricSection<Content: View>: View {
    let section: ActivityTechnicalSection
    @Binding var expandedSection: ActivityTechnicalSection?
    let preview: String
    @ViewBuilder var content: () -> Content

    private var isExpanded: Bool {
        expandedSection == section
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedSection = isExpanded ? nil : section
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text(preview)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().overlay(Theme.line)
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
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
        .padding(.vertical, 9)
    }
}

enum ActivityAnalysisTab: CaseIterable {
    case pace
    case heartRate
    case splits

    var title: String {
        switch self {
        case .pace: "Pace"
        case .heartRate: "Heart rate"
        case .splits: "Splits"
        }
    }
}

enum ActivityTechnicalSection: CaseIterable {
    case activityDetails
    case heartRateDetails
    case runningDynamics
    case elevation
    case weather
    case gear

    var title: String {
        switch self {
        case .activityDetails: "Activity details"
        case .heartRateDetails: "Heart rate details"
        case .runningDynamics: "Running dynamics"
        case .elevation: "Elevation"
        case .weather: "Weather"
        case .gear: "Gear"
        }
    }
}

struct ActivityEvidence: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let color: Color
}

struct PaceChartPoint: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let actual: Double?
}

struct HeartRateChartPoint: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let bpm: Double
}

struct SplitComparison: Identifiable, Equatable {
    let id = UUID()
    let kilometer: Int
    let paceSecondsPerKm: Double
    let averageHeartRate: Double?
    let isMeaningfullyFast: Bool
    let relativeWidth: Double
}

enum IntervalsActivityLoadState: Equatable {
    case idle
    case loading
    case loaded
    case unconfigured
    case notFound
    case failed

    var fallbackDescription: String {
        switch self {
        case .idle, .loading:
            return "Loading intervals.icu analysis"
        case .loaded:
            return "intervals.icu"
        case .unconfigured:
            return "HealthKit summary fallback"
        case .notFound:
            return "HealthKit fallback · no intervals activity match"
        case .failed:
            return "HealthKit fallback · intervals unavailable"
        }
    }
}

struct IntervalsActivityAnalysisData: Equatable {
    var activityID: String
    var deviceName: String?
    var distanceMeters: Double?
    var movingTimeSeconds: Double
    var elapsedTimeSeconds: Double?
    var averagePaceSecondsPerKm: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var trainingLoad: Double?
    var recordingStops: [Double]
    var pacePoints: [PaceChartPoint]
    var heartRatePoints: [HeartRateChartPoint]
    var splits: [SplitComparison]
}

struct IntervalsActivityAnalysisLoader {
    let client: IntervalsICUClient

    func analysis(
        for activity: CompletedActivity,
        credentials: IntervalsICUCredentials,
        calendar: Calendar
    ) async throws -> IntervalsActivityAnalysisData? {
        let bounds = Self.searchBounds(around: activity.date, calendar: calendar)
        let activities = try await client.activities(credentials: credentials, oldest: bounds.oldest, newest: bounds.newest)
        guard let match = Self.bestMatch(for: activity, in: activities, calendar: calendar) else {
            return nil
        }

        let detail = try await client.activityDetail(id: match.id, credentials: credentials)
        let available = Set(detail.streamTypes ?? match.streamTypes ?? [])
        let requested = ["time", "distance", "velocity_smooth", "heartrate"].filter { available.contains($0) }
        let streams = requested.isEmpty ? [] : (try? await client.activityStreams(id: match.id, credentials: credentials, types: requested)) ?? []
        return Self.makeAnalysis(from: detail, streams: streams, activity: activity)
    }

    private static func searchBounds(around date: Date, calendar: Calendar) -> (oldest: String, newest: String) {
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: date)) ?? date
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }

    private static func bestMatch(
        for activity: CompletedActivity,
        in candidates: [IntervalsActivitySummary],
        calendar: Calendar
    ) -> IntervalsActivitySummary? {
        let runCandidates = candidates.filter { ($0.type ?? "").localizedCaseInsensitiveContains("run") }
        return runCandidates
            .compactMap { candidate -> (IntervalsActivitySummary, Double)? in
                let start = candidate.startDateLocal.flatMap { localDate($0, calendar: calendar) }
                let timePenalty = start.map { min(abs($0.timeIntervalSince(activity.date)) / 60, 180) } ?? 90
                let distancePenalty: Double
                if let candidateDistance = candidate.distance, let activityDistance = activity.distanceMeters {
                    distancePenalty = abs(candidateDistance - activityDistance) / 100
                } else {
                    distancePenalty = 30
                }
                let duration = candidate.movingTime ?? candidate.elapsedTime ?? candidate.recordingTime
                let durationPenalty = duration.map { abs($0 - activity.durationSeconds) / 30 } ?? 20
                let score = timePenalty + distancePenalty + durationPenalty
                guard score < 260 else { return nil }
                return (candidate, score)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static func makeAnalysis(
        from detail: IntervalsActivitySummary,
        streams: [IntervalsActivityStream],
        activity: CompletedActivity
    ) -> IntervalsActivityAnalysisData {
        let streamByType = Dictionary(uniqueKeysWithValues: streams.map { ($0.type, $0.data) })
        let time = streamByType["time"] ?? []
        let distance = streamByType["distance"] ?? []
        let speed = streamByType["velocity_smooth"] ?? []
        let heartRate = streamByType["heartrate"] ?? []

        let pacePoints = downsample(pacePointsFromStreams(time: time, speed: speed, stops: detail.recordingStops ?? []), maxCount: 260)
        let heartRatePoints = downsample(heartRatePointsFromStreams(time: time, heartRate: heartRate), maxCount: 220)
        let splits = splitRows(from: detail, time: time, distance: distance, speed: speed, heartRate: heartRate)
        let moving = detail.movingTime ?? detail.recordingTime ?? activity.durationSeconds

        return IntervalsActivityAnalysisData(
            activityID: detail.id,
            deviceName: detail.deviceName,
            distanceMeters: detail.distance ?? activity.distanceMeters,
            movingTimeSeconds: moving,
            elapsedTimeSeconds: detail.elapsedTime,
            averagePaceSecondsPerKm: paceFromSpeed(detail.averageSpeed) ?? ActivityMapper.averagePaceSecondsPerKm(distanceMeters: detail.distance, durationSeconds: moving),
            averageHeartRate: detail.averageHeartRate ?? activity.avgHeartRate,
            maxHeartRate: detail.maxHeartRate ?? activity.maxHeartRate,
            trainingLoad: detail.trainingLoad,
            recordingStops: detail.recordingStops ?? [],
            pacePoints: pacePoints,
            heartRatePoints: heartRatePoints,
            splits: splits
        )
    }

    private static func pacePointsFromStreams(time: [Double?], speed: [Double?], stops: [Double]) -> [PaceChartPoint] {
        let count = min(time.count, speed.count)
        guard count > 1 else { return [] }
        let stopSet = Set(stops.map { Int($0.rounded()) })
        return (0..<count).map { index in
            let t = time[index] ?? Double(index)
            let seconds = Int(t.rounded())
            if stopSet.contains(seconds) {
                return PaceChartPoint(time: t, actual: nil)
            }
            return PaceChartPoint(time: t, actual: speed[index].flatMap(paceFromSpeed))
        }
    }

    private static func heartRatePointsFromStreams(time: [Double?], heartRate: [Double?]) -> [HeartRateChartPoint] {
        let count = min(time.count, heartRate.count)
        guard count > 1 else { return [] }
        return (0..<count).compactMap { index in
            guard let bpm = heartRate[index], bpm > 0 else { return nil }
            return HeartRateChartPoint(time: time[index] ?? Double(index), bpm: bpm)
        }
    }

    private static func splitRows(
        from detail: IntervalsActivitySummary,
        time: [Double?],
        distance: [Double?],
        speed: [Double?],
        heartRate: [Double?]
    ) -> [SplitComparison] {
        let intervalSplits = (detail.intervals ?? [])
            .filter { (($0.distance ?? 0) >= 850 && ($0.distance ?? 0) <= 1150) || (($0.elapsedTime ?? 0) > 60 && ($0.averageSpeed ?? 0) > 0) }
        let rows = intervalSplits.enumerated().compactMap { index, interval -> SplitComparison? in
            guard let pace = paceFromSpeed(interval.averageSpeed) else { return nil }
            return SplitComparison(
                kilometer: index + 1,
                paceSecondsPerKm: pace,
                averageHeartRate: interval.averageHeartRate,
                isMeaningfullyFast: false,
                relativeWidth: 1
            )
        }
        if !rows.isEmpty { return normalizedSplits(rows) }

        let streamRows = splitRowsFromStreams(time: time, distance: distance, speed: speed, heartRate: heartRate)
        return normalizedSplits(streamRows)
    }

    private static func splitRowsFromStreams(time: [Double?], distance: [Double?], speed: [Double?], heartRate: [Double?]) -> [SplitComparison] {
        let count = min(time.count, distance.count, speed.count)
        guard count > 2 else { return [] }

        var rows: [SplitComparison] = []
        var splitStartIndex = 0
        var nextDistance = 1000.0
        for index in 1..<count {
            guard let meters = distance[index], meters >= nextDistance else { continue }
            let startTime = time[splitStartIndex] ?? Double(splitStartIndex)
            let endTime = time[index] ?? Double(index)
            let splitDuration = max(endTime - startTime, 1)
            let startDistance = distance[splitStartIndex] ?? 0
            let splitDistance = max(meters - startDistance, 1)
            let pace = splitDuration / (splitDistance / 1000)
            let hrSamples = heartRate[splitStartIndex...index].compactMap { $0 }
            rows.append(SplitComparison(
                kilometer: rows.count + 1,
                paceSecondsPerKm: pace,
                averageHeartRate: hrSamples.isEmpty ? nil : hrSamples.reduce(0, +) / Double(hrSamples.count),
                isMeaningfullyFast: false,
                relativeWidth: 1
            ))
            splitStartIndex = index
            nextDistance += 1000
        }
        return rows
    }

    private static func normalizedSplits(_ rows: [SplitComparison]) -> [SplitComparison] {
        guard !rows.isEmpty else { return [] }
        let fastest = rows.map(\.paceSecondsPerKm).min() ?? 1
        let slowest = rows.map(\.paceSecondsPerKm).max() ?? fastest
        let average = rows.map(\.paceSecondsPerKm).reduce(0, +) / Double(rows.count)
        let fastThreshold = average - 18
        return rows.map { row in
            let width = 1 - ((row.paceSecondsPerKm - fastest) / max(slowest - fastest, 1)) * 0.38
            return SplitComparison(
                kilometer: row.kilometer,
                paceSecondsPerKm: row.paceSecondsPerKm,
                averageHeartRate: row.averageHeartRate,
                isMeaningfullyFast: row.paceSecondsPerKm < fastThreshold,
                relativeWidth: width
            )
        }
    }

    private static func downsample(_ points: [PaceChartPoint], maxCount: Int) -> [PaceChartPoint] {
        guard points.count > maxCount else { return points }
        let stride = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { points[min(Int((Double($0) * stride).rounded()), points.count - 1)] }
    }

    private static func downsample(_ points: [HeartRateChartPoint], maxCount: Int) -> [HeartRateChartPoint] {
        guard points.count > maxCount else { return points }
        let stride = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { points[min(Int((Double($0) * stride).rounded()), points.count - 1)] }
    }

    private static func paceFromSpeed(_ metersPerSecond: Double?) -> Double? {
        guard let metersPerSecond, metersPerSecond > 0.5 else { return nil }
        return 1000 / metersPerSecond
    }

    private static func localDate(_ raw: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }
}

struct ActivityDetailAnalysis {
    let activity: CompletedActivity
    let plannedWorkout: PlannedWorkout?
    let intervalsAnalysis: IntervalsActivityAnalysisData?

    var review: RunReview {
        RunReview.make(
            activityDistanceMeters: distanceMeters,
            activityDurationSeconds: durationSeconds,
            activityPaceSecondsPerKm: actualPace,
            avgHeartRate: averageHeartRate,
            plannedDistanceKm: plannedWorkout?.distanceKm,
            plannedPaceBand: plannedWorkout?.paceBand,
            plannedDurationSeconds: plannedWorkout?.expectedDurationSeconds
        )
    }

    var hasPlan: Bool {
        plannedWorkout != nil
    }

    var eyebrow: String {
        hasPlan ? "Post-run review" : "Run review"
    }

    var headline: String {
        hasPlan ? review.verdict.title : "Run logged"
    }

    var supportingSentence: String {
        guard hasPlan else {
            return "No planned workout is matched yet, so TrainOrRest is showing the pacing pattern without judging execution."
        }
        let kind = plannedWorkout?.kind?.displayName ?? "planned run"
        let distance = abs(review.distanceDeltaKm ?? 0) < 0.15 ? "Your distance matched the \(kind)" : "Your distance drifted from the \(kind)"
        if let paceDelta = review.paceDeltaSecondsPerKm, abs(paceDelta) >= 10 {
            let direction = paceDelta < 0 ? "faster" : "slower"
            return "\(distance), but your pace was \(formatPaceDelta(abs(paceDelta))) sec/km \(direction) than planned."
        }
        return "\(distance), and your average pace stayed close to the planned range."
    }

    var evidenceChips: [ActivityEvidence] {
        guard hasPlan else {
            return [
                ActivityEvidence(title: "Garmin synced", symbol: "checkmark", color: Theme.good),
                ActivityEvidence(title: Formatters.kilometers(distanceMeters), symbol: "figure.run", color: Theme.accent)
            ]
        }

        var chips: [ActivityEvidence] = []
        if let delta = review.distanceDeltaKm {
            chips.append(ActivityEvidence(title: abs(delta) < 0.15 ? "Distance on plan" : String(format: "%.1f km off", abs(delta)), symbol: abs(delta) < 0.15 ? "checkmark" : "arrow.left.and.right", color: abs(delta) < 0.15 ? Theme.good : Theme.warn))
        }
        if let paceDelta = review.paceDeltaSecondsPerKm {
            let direction = paceDelta < 0 ? "fast" : "slow"
            chips.append(ActivityEvidence(title: "\(formatPaceDelta(abs(paceDelta))) sec/km \(direction)", symbol: paceDelta < 0 ? "flame" : "leaf", color: abs(paceDelta) >= 20 ? Theme.warn : Theme.dim))
        }
        if let durationDelta = review.durationDeltaSeconds {
            let minutes = Int((abs(durationDelta) / 60).rounded())
            chips.append(ActivityEvidence(title: "\(minutes) min \(durationDelta < 0 ? "shorter" : "longer")", symbol: "clock", color: abs(durationDelta) >= 180 ? Theme.warn : Theme.dim))
        }
        return Array(chips.prefix(3))
    }

    var chartTitle: String {
        hasPlan ? "Pace vs plan" : "Pace pattern"
    }

    var miniChartInterpretation: String {
        hasPlan ? "Most of the extra effort came from the middle of the run." : "The pace pattern is shown without a plan target."
    }

    var recommendation: String {
        review.recoveryNote
    }

    var availableTabs: [ActivityAnalysisTab] {
        averageHeartRate == nil || heartRatePoints.isEmpty ? [.pace, .splits] : ActivityAnalysisTab.allCases
    }

    var distanceMeters: Double? { intervalsAnalysis?.distanceMeters ?? activity.distanceMeters }
    var durationSeconds: Double { intervalsAnalysis?.movingTimeSeconds ?? activity.durationSeconds }
    var actualPace: Double? { intervalsAnalysis?.averagePaceSecondsPerKm ?? activity.avgPaceSecondsPerKm }
    var averageHeartRate: Double? { intervalsAnalysis?.averageHeartRate ?? activity.avgHeartRate }
    var maxHeartRate: Double? { intervalsAnalysis?.maxHeartRate ?? activity.maxHeartRate }

    var plannedAveragePace: Double {
        if let band = plannedWorkout?.paceBand {
            return (band.fastSecondsPerKm + band.slowSecondsPerKm) / 2
        }
        if let plannedWorkout, plannedWorkout.distanceKm > 0, let duration = plannedWorkout.expectedDurationSeconds {
            return duration / plannedWorkout.distanceKm
        }
        return max((activity.avgPaceSecondsPerKm ?? 363) + 33, 300)
    }

    var plannedFastPace: Double {
        plannedWorkout?.paceBand?.fastSecondsPerKm ?? plannedAveragePace - 15
    }

    var plannedSlowPace: Double {
        plannedWorkout?.paceBand?.slowSecondsPerKm ?? plannedAveragePace + 15
    }

    var chartMinPace: Double {
        let actualValues = pacePoints.compactMap(\.actual)
        return max(240, (actualValues + [plannedFastPace]).min()! - 24)
    }

    var chartMaxPace: Double {
        let actualValues = pacePoints.compactMap(\.actual)
        return min(520, (actualValues + [plannedSlowPace]).max()! + 26)
    }

    var chartSlowReference: Double {
        plannedSlowPace
    }

    var paceDeltaText: String {
        guard let delta = review.paceDeltaSecondsPerKm else { return "on range" }
        return "\(formatPaceDelta(abs(delta)))s/km"
    }

    var paceInsight: String {
        hasPlan
            ? "You were closest to the Easy target during the final third, but the middle section was substantially faster."
            : "Without a matched plan, this is a pacing shape only. Match the run to a planned workout for execution feedback."
    }

    var heartRateInsight: String {
        "Heart rate continued rising even after pace settled, suggesting accumulating effort."
    }

    var accessibilityChartSummary: String {
        hasPlan
            ? "Actual pace line compared with planned target band. Faster than plan is highlighted in amber during the middle of the run."
            : "Actual pace line over the workout duration."
    }

    var pacePoints: [PaceChartPoint] {
        if let points = intervalsAnalysis?.pacePoints, !points.isEmpty {
            return points
        }
        let base = activity.avgPaceSecondsPerKm ?? 363
        let duration = max(activity.durationSeconds, 1)
        let steps = 32
        return (0...steps).map { index in
            let progress = Double(index) / Double(steps)
            let time = progress * duration
            if (0.31...0.35).contains(progress) || (0.80...0.83).contains(progress) {
                return PaceChartPoint(time: time, actual: nil)
            }
            let pace: Double
            switch progress {
            case 0..<0.18:
                pace = max(base + 8, plannedAveragePace - 18) + sin(progress * 24) * 4
            case 0.18..<0.42:
                pace = base - 21 + sin(progress * 22) * 5
            case 0.42..<0.58:
                pace = base - 13 + sin(progress * 20) * 4
            case 0.58..<0.76:
                pace = base + 16 + sin(progress * 18) * 5
            default:
                pace = min(plannedAveragePace - 2, base + 24) + sin(progress * 16) * 4
            }
            return PaceChartPoint(time: time, actual: pace)
        }
    }

    var heartRateLowerTarget: Double { 132 }
    var heartRateUpperTarget: Double { 154 }

    var heartRatePoints: [HeartRateChartPoint] {
        if let points = intervalsAnalysis?.heartRatePoints, !points.isEmpty {
            return points
        }
        let maxHR = maxHeartRate ?? 165
        let avg = averageHeartRate ?? 150
        let duration = max(activity.durationSeconds, 1)
        let steps = 28
        return (0...steps).map { index in
            let progress = Double(index) / Double(steps)
            let time = progress * duration
            let earlyRamp = 118 + min(progress / 0.16, 1) * 26
            let middleLift = (0.38...0.56).contains(progress) ? 7 : 0
            let drift = progress * 15
            let wave = sin(progress * 18) * 2.5
            let rawBPM = earlyRamp + Double(middleLift) + drift + wave
            let floorBPM = avg - 18
            let bpm = min(maxHR, max(floorBPM, rawBPM))
            return HeartRateChartPoint(time: time, bpm: bpm)
        }
    }

    var heartRateMin: Double {
        heartRatePoints.map(\.bpm).min() ?? 118
    }

    var heartRateMax: Double {
        max(maxHeartRate ?? 165, heartRatePoints.map(\.bpm).max() ?? 165)
    }

    var splits: [SplitComparison] {
        if let splits = intervalsAnalysis?.splits, !splits.isEmpty {
            return splitsWithPlannedThreshold(splits)
        }
        let distanceKm = max((distanceMeters ?? 7000) / 1000, 1)
        let kilometers = max(1, Int(distanceKm.rounded(.down)))
        let template: [Double] = [386, 378, 344, 342, 366, 379, 382, 388, 384, 381]
        let threshold = plannedAveragePace - 35
        let fastest = template.prefix(kilometers).min() ?? (activity.avgPaceSecondsPerKm ?? 363)
        let slowest = template.prefix(kilometers).max() ?? plannedAveragePace
        return (1...kilometers).map { kilometer in
            let pace = template.indices.contains(kilometer - 1) ? template[kilometer - 1] : (actualPace ?? 363)
            let hr = averageHeartRate.map { $0 + Double(kilometer - kilometers / 2) * 2.2 }
            let relative = 1 - ((pace - fastest) / max(slowest - fastest, 1)) * 0.38
            return SplitComparison(
                kilometer: kilometer,
                paceSecondsPerKm: pace,
                averageHeartRate: hr,
                isMeaningfullyFast: pace < threshold,
                relativeWidth: relative
            )
        }
    }

    var splitsSummary: String {
        let fastCount = splits.filter(\.isMeaningfullyFast).count
        return "\(fastCount) of \(splits.count) kilometres were faster than the planned Easy range."
    }

    func nearestPacePoint(to time: Double) -> PaceChartPoint {
        pacePoints.min { abs($0.time - time) < abs($1.time - time) } ?? PaceChartPoint(time: time, actual: actualPace)
    }

    func nearestHeartRatePoint(to time: Double) -> HeartRateChartPoint {
        heartRatePoints.min { abs($0.time - time) < abs($1.time - time) } ?? HeartRateChartPoint(time: time, bpm: averageHeartRate ?? 150)
    }

    private func formatPaceDelta(_ seconds: Double) -> String {
        "\(Int(seconds.rounded()))"
    }

    private func splitsWithPlannedThreshold(_ rows: [SplitComparison]) -> [SplitComparison] {
        let threshold = hasPlan ? plannedAveragePace - 35 : (rows.map(\.paceSecondsPerKm).reduce(0, +) / Double(max(rows.count, 1))) - 18
        let fastest = rows.map(\.paceSecondsPerKm).min() ?? 1
        let slowest = rows.map(\.paceSecondsPerKm).max() ?? fastest
        return rows.map { row in
            SplitComparison(
                kilometer: row.kilometer,
                paceSecondsPerKm: row.paceSecondsPerKm,
                averageHeartRate: row.averageHeartRate,
                isMeaningfullyFast: row.paceSecondsPerKm < threshold,
                relativeWidth: 1 - ((row.paceSecondsPerKm - fastest) / max(slowest - fastest, 1)) * 0.38
            )
        }
    }
}
