import SwiftData
import SwiftUI

/// Redesigned Today screen: wordmark bar, greeting, hero readiness gauge with
/// driver chips, suggested session, coach entry, and the "what's driving this"
/// metric grid. All values are real (readiness snapshot, HealthKit wellness,
/// training history); no fabricated metrics.
struct TodayView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessDays: [DailyReadiness]
    @Query(sort: \DailyWellness.date, order: .reverse) private var wellness: [DailyWellness]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    @Query(sort: \PlannedWorkout.date) private var plannedWorkouts: [PlannedWorkout]
    @Query private var goals: [Goal]

    @State private var showGoalEntry = false
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    greeting
                    heroCard
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
            .sheet(isPresented: $showGoalEntry) { GoalEntryView() }
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
            if streak > 0 {
                HStack(spacing: 5) {
                    Text("🔥").font(.system(size: 12))
                    Text("\(streak)").font(.torHeading(13, .bold)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.chip, in: Capsule())
            }
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 34, height: 34)
                    .background(Theme.chip, in: Circle())
                    .frame(width: 44, height: 44)      // 44pt tap target
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            TorEyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).tracking(2)
            Text(greetingText)
                .font(.torHeading(25, .bold))
                .foregroundStyle(Theme.text)
        }
    }

    private var greetingText: String {
        switch calendar.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        TorCard(padding: 22, cornerRadius: 26) {
            VStack(spacing: 6) {
                TorEyebrow("Today's readiness").tracking(2)
                ReadinessGauge(score: todayReadiness?.score, verdict: verdict)
                    .padding(.top, 2)
                    .background(
                        RadialGradient(colors: [Theme.accentSoft, .clear], center: .center, startRadius: 0, endRadius: 150)
                    )
                Text(verdict.torWord)
                    .font(.torHeading(32, .bold)).tracking(4)
                    .foregroundStyle(verdict.torColor)
                Text(verdict.torSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
                if verdict == .insufficientData {
                    baselineProgress
                } else if !driverChips.isEmpty {
                    FlowChips(chips: driverChips)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var baselineProgress: some View {
        let days = min(todayReadiness?.baselineDayCount ?? 0, ReadinessEngine.Tuning.minBaselineDays)
        return VStack(spacing: 6) {
            Text("Collecting baseline — day \(days)/\(ReadinessEngine.Tuning.minBaselineDays)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
            ProgressView(value: Double(days), total: Double(ReadinessEngine.Tuning.minBaselineDays))
                .tint(Theme.accent)
        }
        .padding(.top, 8)
    }

    /// Short green/amber chips for the top driving signals.
    private var driverChips: [FlowChips.Chip] {
        guard let r = todayReadiness else { return [] }
        var chips: [FlowChips.Chip] = []
        if let hrv7 = r.hrvMean7, let hrv28 = r.hrvMean28 {
            let up = hrv7 >= hrv28
            chips.append(.init(text: "HRV \(up ? "▲" : "▼") \(Int(abs(hrv7 - hrv28)))", dot: up ? Theme.good : Theme.warn))
        }
        if let sleep = r.sleepLastNight {
            chips.append(.init(text: "Slept \(Formatters.sleep(sleep))", dot: sleep >= 7 ? Theme.good : Theme.warn))
        }
        if let acwr = r.acuteChronicRatio {
            let ok = acwr <= 1.3 && acwr >= 0.8
            chips.append(.init(text: ok ? "Load optimal" : String(format: "Load %.2f", acwr), dot: ok ? Theme.accent : Theme.warn))
        }
        return chips
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
                    TorEyebrow("Suggested session").tracking(1.5)
                    Text(workout.kind?.displayName ?? "Run")
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

    private var setGoalCard: some View {
        Button { showGoalEntry = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "target").font(.system(size: 22)).foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set a race goal").font(.torHeading(17, .bold)).foregroundStyle(Theme.text)
                    Text("Generate your training plan").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Coach").font(.torHeading(16, .bold)).foregroundStyle(Theme.text)
                        Text("Adapts your plan to how you feel")
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.faint)
                }
                HStack(spacing: 9) {
                    Text("Ask your coach…").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.faint)
                    Spacer()
                    Image(systemName: "paperplane.fill").font(.system(size: 13)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Theme.accent, in: Circle())
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(Theme.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            }
            .padding(15)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drivers grid

    private var driversGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow("What's driving this").tracking(2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(driverMetrics) { DriverCard(metric: $0) }
            }
        }
    }

    private var driverMetrics: [DriverMetric] {
        let r = todayReadiness
        return [
            DriverMetric(label: "HRV", value: r?.hrvMean7.map { "\(Int($0))" } ?? "–", unit: "ms",
                         delta: delta(r?.hrvMean7, r?.hrvMean28, higherIsBetter: true), caption: r?.hrvMean28.map { "vs \(Int($0)) ms baseline" } ?? "baseline building"),
            DriverMetric(label: "Resting HR", value: r?.rhrMean7.map { "\(Int($0))" } ?? "–", unit: "bpm",
                         delta: delta(r?.rhrMean7, r?.rhrMean28, higherIsBetter: false), caption: r?.rhrMean28.map { "vs \(Int($0)) bpm baseline" } ?? "baseline building"),
            DriverMetric(label: "Sleep", value: r?.sleepLastNight.map { Formatters.sleep($0) } ?? "–", unit: "",
                         delta: nil, caption: "last night"),
            DriverMetric(label: "VO₂max", value: latestVO2.map { String(format: "%.1f", $0) } ?? "–", unit: "",
                         delta: nil, caption: "ml/kg/min"),
            DriverMetric(label: "Load · ACWR", value: r?.acuteChronicRatio.map { String(format: "%.2f", $0) } ?? "–", unit: "",
                         delta: nil, caption: loadCaption, badge: loadBadge),
            DriverMetric(label: "Streak", value: "\(streak)", unit: streak == 1 ? "day" : "days",
                         delta: nil, caption: streak > 0 ? "keep it going" : "run to start"),
        ]
    }

    private func delta(_ a: Double?, _ b: Double?, higherIsBetter: Bool) -> DriverMetric.Delta? {
        guard let a, let b else { return nil }
        let diff = a - b
        guard abs(diff) >= 1 else { return .init(text: "flat", good: true) }
        let good = higherIsBetter ? diff > 0 : diff < 0
        let arrow = diff > 0 ? "▲" : "▼"
        return .init(text: "\(arrow) \(Int(abs(diff)))", good: good)
    }

    private var loadBadge: (String, Bool)? {
        guard let acwr = todayReadiness?.acuteChronicRatio else { return nil }
        let ok = acwr >= 0.8 && acwr <= 1.3
        return (ok ? "OPTIMAL" : "WATCH", ok)
    }

    private var loadCaption: String {
        guard let acwr = todayReadiness?.acuteChronicRatio else { return "building history" }
        return acwr > 1.3 ? "ramping fast" : acwr < 0.8 ? "detraining" : "balanced training"
    }

    // MARK: - Derived data

    // Only today's row — never fall back to a stale day under today's date.
    private var todayReadiness: DailyReadiness? {
        readinessDays.first { calendar.isDateInToday($0.date) }
    }

    private var verdict: ReadinessVerdict { todayReadiness?.verdict ?? .insufficientData }

    private var todayWorkout: PlannedWorkout? {
        plannedWorkouts.first { calendar.isDateInToday($0.date) }
    }

    private var latestVO2: Double? {
        wellness.first { $0.vo2Max != nil }?.vo2Max
    }

    private var streak: Int {
        TrainingStreak.current(activityDates: activities.map(\.date), today: .now, calendar: calendar)
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

    struct Delta { var text: String; var good: Bool }
}

struct DriverCard: View {
    let metric: DriverMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                TorEyebrow(metric.label).tracking(1.2)
                Spacer()
                if let delta = metric.delta {
                    Text(delta.text).font(.torHeading(11, .bold))
                        .foregroundStyle(delta.good ? Theme.good : Theme.warn)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.soft(delta.good ? Theme.good : Theme.warn), in: RoundedRectangle(cornerRadius: 6))
                } else if let badge = metric.badge {
                    Text(badge.0).font(.torHeading(11, .bold))
                        .foregroundStyle(badge.1 ? Theme.accent : Theme.warn)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.soft(badge.1 ? Theme.accent : Theme.warn), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value).font(.torNumber(29)).foregroundStyle(Theme.text)
                if !metric.unit.isEmpty {
                    Text(metric.unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                }
            }
            Text(metric.caption).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
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
