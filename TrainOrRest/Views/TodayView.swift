import SwiftData
import SwiftUI

/// Redesigned Today screen: wordmark bar, greeting, verdict banner, suggested
/// session, coach entry, and the "what's driving this"
/// metric grid. All values are real (readiness snapshot, HealthKit wellness,
/// training history); no fabricated metrics.
struct TodayView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessDays: [DailyReadiness]
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]
    @Query(sort: \DailyWellness.date, order: .reverse) private var wellness: [DailyWellness]
    @Query(sort: \PlannedWorkout.date) private var plannedWorkouts: [PlannedWorkout]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @Query private var syncStates: [SyncState]
    @Query private var goals: [Goal]
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    @State private var showGoalEntry = false
    @State private var checkInSaveFailed = false
    @State private var postRunReviewActivityID: UUID?
    private let calendar = Calendar.current

    private var language: CoachLanguage {
        CoachLanguage(rawValue: languageRaw) ?? .en
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    greeting
                    heroCard
                    checkInCard
                    if let latestTodayActivity {
                        latestRunReviewCard(latestTodayActivity)
                    }
                    if goals.isEmpty {
                        setGoalCard
                    } else if let workout = todayWorkout {
                        suggestedSession(workout)
                    }
                    coachEntry
                    driversGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollIndicators(.hidden)
            .refreshable { await engine.syncAll() }
            .navigationBarHidden(true)
            .task { presentLatestRunReviewIfNeeded() }
            .onChange(of: completedActivities.map(\.hkUUID)) { _, _ in
                presentLatestRunReviewIfNeeded()
            }
            .sheet(isPresented: $showGoalEntry) { GoalEntryView() }
            .sheet(isPresented: postRunReviewBinding) {
                if let activity = postRunReviewActivity {
                    PostRunReviewSheet(activity: activity, plannedWorkout: matchedWorkout(for: activity))
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Circle().fill(Theme.accent).frame(width: 9, height: 9)
                    .shadow(color: Theme.accent, radius: 5)
                Text("TRAINORREST")
                    .font(.torLabel(14, .bold)).tracking(1.8)
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 34, height: 34)
                    .background(Theme.chip, in: Circle())
                    .frame(width: 44, height: 44)      // 44pt tap target
                    .contentShape(Rectangle())
            }
        .accessibilityLabel(language.today.settingsAccessibilityLabel)
        }
        .padding(.top, 8)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            TorEyebrow(language.longDate(.now)).tracking(2)
            Text(greetingText)
                .font(.torHeading(25, .bold))
                .foregroundStyle(Theme.text)
        }
    }

    private var greetingText: String {
        language.today.greeting(hour: calendar.component(.hour, from: .now))
    }

    // MARK: - Hero

    private var heroCard: some View {
        VerdictBannerView(
            readiness: todayReadiness,
            workout: todayWorkout,
            lastSyncAt: latestSyncAt,
            language: language,
            onKeepPlanned: keepPlannedSession
        )
    }

    private var checkInCard: some View {
        TodayCheckInCard(
            language: language,
            selected: Set(todayCheckIn?.signals ?? []),
            saveFailed: checkInSaveFailed,
            onToggle: toggleCheckIn
        )
    }

    // MARK: - Suggested session / goal

    private func suggestedSession(_ workout: PlannedWorkout) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workout.kind?.symbolName ?? "figure.run")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    TorEyebrow(language.today.suggestedSession).tracking(1.5)
                    Text(workout.kind.map(language.name) ?? language.genericRunLabel)
                        .font(.torHeading(17, .bold)).foregroundStyle(Theme.text)
                    Text(sessionSubtitle(workout))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sessionSubtitle(_ workout: PlannedWorkout) -> String {
        var parts = [Formatters.kilometers(workout.distanceKm * 1000)]
        if let band = workout.paceBand { parts.append(Formatters.paceBand(band)) }
        return parts.joined(separator: " · ")
    }

    private func latestRunReviewCard(_ activity: CompletedActivity) -> some View {
        NavigationLink {
            ActivityDetailView(activity: activity)
        } label: {
            RunReviewCard(activity: activity, plannedWorkout: matchedWorkout(for: activity))
        }
        .buttonStyle(.plain)
    }

    private var latestTodayActivity: CompletedActivity? {
        completedActivities.first { calendar.isDate($0.date, inSameDayAs: .now) }
    }

    private var postRunReviewActivity: CompletedActivity? {
        guard let postRunReviewActivityID else { return nil }
        return completedActivities.first { $0.hkUUID == postRunReviewActivityID }
    }

    private var postRunReviewBinding: Binding<Bool> {
        Binding(
            get: { postRunReviewActivity != nil },
            set: { isPresented in
                if !isPresented {
                    postRunReviewActivity?.postRunReviewDismissedAt = .now
                    try? modelContext.save()
                    postRunReviewActivityID = nil
                }
            }
        )
    }

    private func presentLatestRunReviewIfNeeded() {
        guard postRunReviewActivityID == nil,
              let activity = completedActivities.first(where: {
                  calendar.isDate($0.date, inSameDayAs: .now) && $0.postRunReviewDismissedAt == nil
              }) else { return }
        postRunReviewActivityID = activity.hkUUID
    }

    private func matchedWorkout(for activity: CompletedActivity) -> PlannedWorkout? {
        if let exact = plannedWorkouts.first(where: { $0.matchedActivityUUID == activity.hkUUID }) {
            return exact
        }
        return plannedWorkouts.first { calendar.isDate($0.date, inSameDayAs: activity.date) }
    }

    private var setGoalCard: some View {
        Button { showGoalEntry = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "target").font(.system(size: 22)).foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.today.setRaceGoal).font(.torHeading(17, .bold)).foregroundStyle(Theme.text)
                    Text(language.today.generateTrainingPlan).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Coach entry

    private var coachEntry: some View {
        NavigationLink {
            ChatView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "message")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(language.today.askCoach)
                    .font(.torHeading(16, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.today.askCoach)
    }

    // MARK: - Drivers grid

    private var driversGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow(language.today.driversHeading).tracking(2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(driverMetrics) { DriverCard(metric: $0, language: language) }
            }
        }
    }

    private var driverMetrics: [DriverMetric] {
        let r = todayReadiness
        return [
            DriverMetric(label: "HRV", value: r?.hrvMean7.map { "\(Int($0))" } ?? "–", unit: "ms",
                         delta: delta(r?.hrvMean7, r?.hrvBaseline ?? r?.hrvMean28, higherIsBetter: true),
                         caption: (r?.hrvBaseline ?? r?.hrvMean28).map { language.today.versusBaseline(Int($0), unit: "ms") } ?? language.today.baselineBuilding,
                         sourceConflict: hrvSourceConflict,
                         isDisputed: todayWellness?.hrvDisputed ?? false,
                         sparkline: wellnessSeries(\.hrvSDNN),
                         sparkColor: (todayWellness?.hrvDisputed ?? false) ? Theme.warn : Theme.data),
            DriverMetric(label: language.today.restingHeartRate, value: r?.rhrMean7.map { "\(Int($0))" } ?? "–", unit: "bpm",
                         delta: delta(r?.rhrMean7, r?.rhrBaseline ?? r?.rhrMean28, higherIsBetter: false),
                         caption: (r?.rhrBaseline ?? r?.rhrMean28).map { language.today.versusBaseline(Int($0), unit: "bpm") } ?? language.today.baselineBuilding,
                         sparkline: wellnessSeries(\.restingHeartRate), sparkColor: Theme.data),
            DriverMetric(label: language.sleepLabel, value: r?.sleepLastNight.map { language.today.sleepDuration($0) } ?? "–", unit: "",
                         delta: nil, caption: language.today.lastNight,
                         sparkline: wellnessSeries(\.sleepHours), sparkColor: Theme.data),
            DriverMetric(label: language.today.vo2Max, value: latestVO2.map { String(format: "%.1f", locale: language.uiLocale, $0) } ?? "–", unit: "",
                         delta: nil, caption: "ml/kg/min"),
            DriverMetric(label: language.today.trainingLoadACWR, value: r?.acuteChronicRatio.map { String(format: "%.2f", locale: language.uiLocale, $0) } ?? "–", unit: "",
                         delta: nil, caption: loadCaption, badge: loadBadge,
                         sparkline: readinessSeries(\.acuteChronicRatio), sparkColor: Theme.data),
        ]
    }

    /// Recent history for a wellness metric, oldest→newest, capped at 14 points.
    private func wellnessSeries(_ metric: (DailyWellness) -> Double?) -> [Double] {
        Array(wellness.prefix(14).compactMap(metric).reversed())
    }

    private func readinessSeries(_ metric: (DailyReadiness) -> Double?) -> [Double] {
        Array(readinessDays.prefix(14).compactMap(metric).reversed())
    }

    private func delta(_ a: Double?, _ b: Double?, higherIsBetter: Bool) -> DriverMetric.Delta? {
        guard let a, let b else { return nil }
        let diff = a - b
        guard abs(diff) >= 1 else { return .init(text: language.today.flat, good: true) }
        let good = higherIsBetter ? diff > 0 : diff < 0
        let arrow = diff > 0 ? "▲" : "▼"
        return .init(text: "\(arrow) \(Int(abs(diff)))", good: good)
    }

    private var loadBadge: (String, Bool)? {
        guard let acwr = todayReadiness?.acuteChronicRatio else { return nil }
        let ok = acwr >= 0.8 && acwr <= 1.3
        return (ok ? language.today.optimal : language.today.watch, ok)
    }

    private var loadCaption: String {
        guard let acwr = todayReadiness?.acuteChronicRatio else { return language.today.buildingHistory }
        return acwr > 1.3 ? language.today.rampingFast : acwr < 0.8 ? language.today.detraining : language.today.balancedTraining
    }

    // MARK: - Derived data

    // Only today's row — never fall back to a stale day under today's date.
    private var todayReadiness: DailyReadiness? {
        readinessDays.first { calendar.isDateInToday($0.date) }
    }

    private var todayCheckIn: DailyCheckIn? {
        checkIns.first { calendar.isDateInToday($0.date) }
    }

    private var todayWorkout: PlannedWorkout? {
        plannedWorkouts.first { calendar.isDateInToday($0.date) }
    }

    private var latestSyncAt: Date? {
        syncStates.compactMap(\.lastSyncAt).max()
    }

    private var latestVO2: Double? {
        wellness.first { $0.vo2Max != nil }?.vo2Max
    }

    private var todayWellness: DailyWellness? {
        wellness.first { calendar.isDateInToday($0.date) }
    }

    private var hrvSourceConflict: DriverMetric.SourceConflict? {
        guard let row = todayWellness,
              let primaryValue = row.hrvSDNN,
              let altValue = row.hrvAltValue,
              let altSource = row.hrvAltSource
        else { return nil }
        return DriverMetric.SourceConflict(
            primarySource: sourceDisplayName(row.hrvPrimarySource ?? "Garmin"),
            primaryValue: primaryValue,
            altSource: sourceDisplayName(altSource),
            altValue: altValue
        )
    }

    private func sourceDisplayName(_ sourceName: String) -> String {
        sourceName.hasPrefix(GarminSource.namePrefix) ? "Garmin" : sourceName
    }

    private func toggleCheckIn(_ signal: CheckInSignal) {
        let day = calendar.startOfDay(for: .now)
        let row: DailyCheckIn
        if let todayCheckIn {
            row = todayCheckIn
        } else {
            row = DailyCheckIn(date: day)
            modelContext.insert(row)
        }

        var signals = Set(row.signals)
        if signals.contains(signal) {
            signals.remove(signal)
        } else {
            signals.insert(signal)
        }
        row.signals = CheckInSignal.allCases.filter { signals.contains($0) }

        do {
            try modelContext.save()
            checkInSaveFailed = false
        } catch {
            checkInSaveFailed = true
            return
        }
        _ = try? ReadinessStore.runDailyPipeline(in: modelContext, today: .now, calendar: calendar)
    }

    private func keepPlannedSession(for rule: ReadinessRule) {
        let day = calendar.startOfDay(for: .now)
        modelContext.insert(RuleOverride(date: day, rule: rule))
        do {
            try modelContext.save()
            _ = try ReadinessStore.runDailyPipeline(in: modelContext, today: .now, calendar: calendar)
            checkInSaveFailed = false
        } catch {
            checkInSaveFailed = true
        }
    }
}

struct TodayCheckInCard: View {
    let language: CoachLanguage
    let selected: Set<CheckInSignal>
    let saveFailed: Bool
    let onToggle: (CheckInSignal) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(language.today.checkInTitle)
                        .font(.torHeading(16, .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(CheckInSignal.allCases, id: \.self) { signal in
                        CheckInChip(
                            language: language,
                            signal: signal,
                            isSelected: selected.contains(signal),
                            onToggle: { onToggle(signal) }
                        )
                    }
                }

                if saveFailed {
                    Text(language.today.checkInSaveFailed)
                        .font(.caption)
                        .foregroundStyle(Theme.bad)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CheckInChip: View {
    let language: CoachLanguage
    let signal: CheckInSignal
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: signal.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)
                Text(language.name(signal))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(isSelected ? Theme.text : Theme.dim)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .background(isSelected ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.today.checkInAccessibility(signal))
        .accessibilityValue(isSelected ? language.today.selected : language.today.notSelected)
    }
}

// MARK: - Driver card

struct DriverMetric: Identifiable {
    let id = UUID()
    var label: String
    var value: String
    var unit: String
    var delta: Delta?
    var caption: String
    var badge: (String, Bool)?
    var sourceConflict: SourceConflict?
    var isDisputed: Bool = false
    var sparkline: [Double] = []
    var sparkColor: Color = Theme.data

    struct Delta { var text: String; var good: Bool }
    struct SourceConflict {
        var primarySource: String
        var primaryValue: Double
        var altSource: String
        var altValue: Double
    }
}

/// Thin normalized trend line for a driver card. Renders nothing under 2 points.
struct Sparkline: View {
    let values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let range = max(hi - lo, 0.0001)
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((value - lo) / range))
                        let point = CGPoint(x: x, y: y)
                        index == 0 ? path.move(to: point) : path.addLine(to: point)
                    }
                }
                .stroke(color, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

struct DriverCard: View {
    let metric: DriverMetric
    let language: CoachLanguage
    @State private var showSourceReceipt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                TorEyebrow(metric.label, color: metric.isDisputed ? Theme.warn : Theme.faint).tracking(1.2)
                Spacer()
                if metric.sourceConflict != nil {
                    Button {
                        showSourceReceipt = true
                    } label: {
                        Text(language.today.sourceCount(2))
                            .font(.torHeading(11, .bold))
                            .foregroundStyle(metric.isDisputed ? Theme.warn : Theme.data)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Theme.soft(metric.isDisputed ? Theme.warn : Theme.data),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(language.today.showHRVSources)
                }
                if let delta = metric.delta {
                    Text(delta.text).font(.torHeading(11, .bold))
                        .foregroundStyle(delta.good ? Theme.good : Theme.warn)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.soft(delta.good ? Theme.good : Theme.warn), in: RoundedRectangle(cornerRadius: 6))
                } else if let badge = metric.badge {
                    Text(badge.0).font(.torHeading(11, .bold))
                        .foregroundStyle(badge.1 ? Theme.data : Theme.warn)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.soft(badge.1 ? Theme.data : Theme.warn), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value).font(.torNumber(29)).foregroundStyle(Theme.text)
                if !metric.unit.isEmpty {
                    Text(metric.unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                }
            }
            if metric.sparkline.count >= 2 {
                Sparkline(values: metric.sparkline, color: metric.sparkColor)
            }
            Text(metric.caption).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(
            metric.isDisputed ? Theme.soft(Theme.warn, 0.08) : Theme.card,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(metric.isDisputed ? Theme.warn.opacity(0.45) : Theme.border, lineWidth: 1)
        )
        .sheet(isPresented: $showSourceReceipt) {
            if let conflict = metric.sourceConflict {
                ReceiptSheet(
                    title: language.today.hrvSourcesTitle,
                    subtitle: language.today.primaryHRVSource(conflict.primarySource),
                    rows: [
                        .detail(
                            conflict.primarySource,
                            value: language.today.usedHRVValue(conflict.primaryValue),
                            symbol: "checkmark.circle"
                        ),
                        .detail(
                            conflict.altSource,
                            value: language.today.hrvValue(conflict.altValue),
                            symbol: "waveform.path.ecg"
                        )
                    ]
                )
            }
        }
        .accessibilityElement(children: metric.sourceConflict == nil ? .combine : .contain)
    }
}

/// Simple wrapping row of small labelled dot-chips.
struct FlowChips: View {
    struct Chip: Identifiable { let id = UUID(); var text: String; var dot: Color }
    let chips: [Chip]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(chips) { chip in
                HStack(spacing: 6) {
                    Circle().fill(chip.dot).frame(width: 6, height: 6)
                    Text(chip.text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.chip, in: Capsule())
            }
        }
    }
}
