import Foundation

enum ReadinessVerdict: String, Codable {
    case train, goEasy, rest, insufficientData
}

/// A day of wellness metrics reduced to what readiness scoring needs.
struct WellnessSample: Equatable {
    var date: Date
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var sleepHours: Double?
}

struct ReadinessAssessment: Equatable {
    var verdict: ReadinessVerdict
    /// 0–100 readiness score driving the gauge; nil when insufficientData.
    var score: Int? = nil
    /// Human-readable explanation per triggered flag, worst first.
    var reasons: [String]
    /// True when the evidence is soft or not persistent enough to cut volume.
    var hedged: Bool = false
    /// Primary deterministic rule responsible for a visible adjustment.
    var primaryRule: ReadinessRule? = nil
    /// Number of confirmed flags after subjective corroborators are applied.
    var corroboratedFlagCount: Int = 0
    /// Distinct days of wellness history available (baseline progress).
    var baselineDayCount: Int
    var snapshot: Snapshot

    /// Input values the verdict was computed from, for persistence/debugging.
    struct Snapshot: Equatable {
        var hrvMean7: Double?
        var hrvMean28: Double?
        var rhrMean7: Double?
        var rhrMean28: Double?
        var sleepLastNight: Double?
        var sleepMean14: Double?
        var acuteChronicRatio: Double?
        var hrvBaseline: Double? = nil
        var hrvSD: Double? = nil
        var rhrBaseline: Double? = nil
        var rhrSD: Double? = nil
    }
}

/// Daily Train / Go easy / Rest verdict from wellness baselines and training
/// load. Pure: caller supplies samples, loads, `today`, and a calendar.
enum ReadinessEngine {
    enum Tuning {
        /// RHR flag: recent mean this many bpm above the 60-day baseline at minimum.
        static let rhrRiseBpm = 5.0
        /// Sleep flags: last night under this many hours…
        static let sleepMinHours = 6.0
        /// …or under this fraction of the 14-day mean.
        static let sleepDropRatio = 0.75
        /// Load flag: acute:chronic ratio above this.
        static let acwrLimit = 1.3
        /// Days of wellness history required before any verdict.
        static let minBaselineDays = 14
        /// Personal baseline window.
        static let baselineWindowDays = 60
        /// Recent wearable reading window.
        static let recentMetricDays = 3
    }

    private struct MetricStats {
        var median: Double
        var standardDeviation: Double
        var count: Int
    }

    private struct DayEvaluation {
        var verdict: ReadinessVerdict
        var reasons: [String]
        var hedged: Bool
        var baselineDayCount: Int
        var snapshot: ReadinessAssessment.Snapshot
        var corroboratedFlagCount: Int
        var forceRest: Bool
        var primaryRule: ReadinessRule?
        var hasSorenessFlag: Bool
    }

    static func assess(
        wellness: [WellnessSample],
        loads: [(date: Date, load: Double)],
        today: Date,
        calendar: Calendar,
        checkIns: [CheckInSignal] = [],
        overrides: [(date: Date, rule: ReadinessRule)] = [],
        checkInHistory: [(date: Date, signals: [CheckInSignal])] = [],
        disputedMetrics: Set<ReadinessRule> = []
    ) -> ReadinessAssessment {
        let todaySignals = Set(checkIns)
        let multipliers = ruleMultipliers(overrides: overrides, today: today, calendar: calendar)
        var current = evaluateDay(
            wellness: wellness,
            loads: loads,
            day: today,
            calendar: calendar,
            checkIns: signals(
                for: today,
                today: today,
                todaySignals: todaySignals,
                checkInHistory: checkInHistory,
                calendar: calendar
            ),
            checkInHistory: checkInHistory,
            multipliers: multipliers,
            disputedMetrics: disputedMetrics
        )

        if current.verdict.needsVolumeCut && !current.forceRest && !current.hasSorenessFlag {
            let persistentDays = (0..<3).filter { offset in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
                return evaluateDay(
                    wellness: wellness,
                    loads: loads,
                    day: day,
                    calendar: calendar,
                    checkIns: signals(
                        for: day,
                        today: today,
                        todaySignals: todaySignals,
                        checkInHistory: checkInHistory,
                        calendar: calendar
                    ),
                    checkInHistory: checkInHistory,
                    multipliers: multipliers,
                    disputedMetrics: calendar.isDate(day, inSameDayAs: today) ? disputedMetrics : []
                ).corroboratedFlagCount >= 2
            }.count

            if persistentDays < 2 {
                current.verdict = .train
                current.hedged = true
            }
        }

        let score = ReadinessScore.score(snapshot: current.snapshot, verdict: current.verdict)
        let primaryRule = (current.verdict.needsVolumeCut || (current.hedged && current.corroboratedFlagCount == 1))
            ? current.primaryRule
            : nil
        return ReadinessAssessment(
            verdict: current.verdict,
            score: score,
            reasons: current.reasons,
            hedged: current.hedged,
            primaryRule: primaryRule,
            corroboratedFlagCount: current.corroboratedFlagCount,
            baselineDayCount: current.baselineDayCount,
            snapshot: current.snapshot
        )
    }

    private static func evaluateDay(
        wellness: [WellnessSample],
        loads: [(date: Date, load: Double)],
        day: Date,
        calendar: Calendar,
        checkIns: Set<CheckInSignal>,
        checkInHistory: [(date: Date, signals: [CheckInSignal])],
        multipliers: [ReadinessRule: Double],
        disputedMetrics: Set<ReadinessRule>
    ) -> DayEvaluation {
        let dayStart = calendar.startOfDay(for: day)
        let hrvStats = metricStats(wellness, day: dayStart, calendar: calendar, metric: \.hrvSDNN)
        let rhrStats = metricStats(wellness, day: dayStart, calendar: calendar, metric: \.restingHeartRate)
        let recentHRV = recentMean(wellness, day: dayStart, calendar: calendar, metric: \.hrvSDNN)
        let recentRHR = recentMean(wellness, day: dayStart, calendar: calendar, metric: \.restingHeartRate)
        let sleepLastNight = dayValue(wellness, day: dayStart, calendar: calendar, metric: \.sleepHours)
        let sleepValues14 = dailyValues(wellness, day: dayStart, days: 14, calendar: calendar, metric: \.sleepHours)
        let sleepMean14 = mean(sleepValues14.map(\.value))
        let acwr = TrainingLoad.acuteChronicRatio(loads: loads, today: dayStart, calendar: calendar)

        let snapshot = ReadinessAssessment.Snapshot(
            hrvMean7: recentHRV,
            hrvMean28: hrvStats?.median,
            rhrMean7: recentRHR,
            rhrMean28: rhrStats?.median,
            sleepLastNight: sleepLastNight,
            sleepMean14: sleepMean14,
            acuteChronicRatio: acwr,
            hrvBaseline: hrvStats?.median,
            hrvSD: hrvStats?.standardDeviation,
            rhrBaseline: rhrStats?.median,
            rhrSD: rhrStats?.standardDeviation
        )

        let forceRest = checkIns.contains(.ill)
        let baselineDays = baselineDayCount(wellness, day: dayStart, calendar: calendar)
        if forceRest {
            return DayEvaluation(
                verdict: .rest,
                reasons: ["Reported illness"],
                hedged: false,
                baselineDayCount: baselineDays,
                snapshot: snapshot,
                corroboratedFlagCount: 3,
                forceRest: true,
                primaryRule: nil,
                hasSorenessFlag: false
            )
        }

        guard baselineDays >= Tuning.minBaselineDays else {
            return DayEvaluation(
                verdict: .insufficientData,
                reasons: [],
                hedged: false,
                baselineDayCount: baselineDays,
                snapshot: snapshot,
                corroboratedFlagCount: 0,
                forceRest: false,
                primaryRule: nil,
                hasSorenessFlag: false
            )
        }

        var reasons: [String] = []
        var hrvLow = false
        var rhrHigh = false
        var sleepShort = false
        var acwrHigh = false
        var hasDisputedHRV = false

        let hrvMultiplier = multipliers[.hrv] ?? 1.0
        if let recentHRV, let hrvStats, hrvStats.count >= Tuning.minBaselineDays, hrvStats.standardDeviation > 0,
           recentHRV < hrvStats.median - hrvMultiplier * hrvStats.standardDeviation {
            if disputedMetrics.contains(.hrv) {
                hasDisputedHRV = true
                reasons.append("HRV disputed between sources — not counted")
            } else {
                hrvLow = true
                reasons.append(String(
                    format: "HRV %.0f ms below %.0f ms baseline band",
                    recentHRV,
                    hrvStats.median
                ))
            }
        }

        let rhrMultiplier = multipliers[.rhr] ?? 1.0
        if let recentRHR, let rhrStats, rhrStats.count >= Tuning.minBaselineDays, rhrStats.standardDeviation > 0,
           recentRHR > rhrStats.median + max(Tuning.rhrRiseBpm, rhrMultiplier * rhrStats.standardDeviation) {
            rhrHigh = true
            let rise = Int((recentRHR - rhrStats.median).rounded())
            reasons.append("Resting HR \(rise) bpm above baseline")
        }

        if let sleepLastNight, sleepValues14.count >= Tuning.minBaselineDays {
            let belowFloor = sleepLastNight < Tuning.sleepMinHours
            let belowMean = sleepMean14.map { sleepLastNight < Tuning.sleepDropRatio * $0 } ?? false
            if belowFloor || belowMean {
                sleepShort = true
                reasons.append(String(format: "Slept %.1f h last night", sleepLastNight))
            }
        }

        if let acwr, acwr > Tuning.acwrLimit {
            acwrHigh = true
            reasons.append(String(format: "Training load ramping fast (%.2f× your usual)", acwr))
        }

        let wearableCount = [hrvLow, rhrHigh, sleepShort, acwrHigh].filter { $0 }.count
        var corroboratedFlagCount = wearableCount

        let hasSorenessFlag = checkIns.contains(.sore) && didReportSoreOnPreviousDay(
            day: dayStart,
            checkInHistory: checkInHistory,
            calendar: calendar
        )
        if checkIns.contains(.sore) {
            if hasSorenessFlag {
                corroboratedFlagCount += 1
                reasons.append("Reported soreness for 2 consecutive days")
            } else {
                reasons.append("Reported soreness; watching for a second day")
            }
        }

        if wearableCount > 0 {
            let corroborators = corroboratingReasons(for: checkIns)
            corroboratedFlagCount += corroborators.count
            reasons.append(contentsOf: corroborators)
        }

        let verdict: ReadinessVerdict
        var hedged: Bool
        if hrvLow && acwrHigh {
            verdict = .rest
            hedged = false
        } else {
            switch corroboratedFlagCount {
            case 0:
                verdict = .train
                hedged = false
            case 1:
                verdict = .train
                hedged = true
            case 2:
                verdict = .goEasy
                hedged = false
            default:
                verdict = .rest
                hedged = false
            }
        }
        if hasDisputedHRV {
            hedged = true
        }

        let primaryRule = primaryRule(hrvLow: hrvLow, acwrHigh: acwrHigh, rhrHigh: rhrHigh, sleepShort: sleepShort)
        return DayEvaluation(
            verdict: verdict,
            reasons: reasons,
            hedged: hedged,
            baselineDayCount: baselineDays,
            snapshot: snapshot,
            corroboratedFlagCount: corroboratedFlagCount,
            forceRest: false,
            primaryRule: primaryRule,
            hasSorenessFlag: hasSorenessFlag
        )
    }

    private static func ruleMultipliers(
        overrides: [(date: Date, rule: ReadinessRule)],
        today: Date,
        calendar: Calendar
    ) -> [ReadinessRule: Double] {
        let todayStart = calendar.startOfDay(for: today)
        guard let start = calendar.date(byAdding: .day, value: -14, to: todayStart),
              let end = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else { return [:] }

        var counts: [ReadinessRule: Int] = [:]
        for override in overrides {
            let day = calendar.startOfDay(for: override.date)
            guard day >= start && day < end else { continue }
            counts[override.rule, default: 0] += 1
        }

        return ReadinessRule.allCases.reduce(into: [:]) { result, rule in
            let count = counts[rule, default: 0]
            result[rule] = min(2.0, 1.0 + 0.25 * floor(Double(count) / 2.0))
        }
    }

    private static func signals(
        for day: Date,
        today: Date,
        todaySignals: Set<CheckInSignal>,
        checkInHistory: [(date: Date, signals: [CheckInSignal])],
        calendar: Calendar
    ) -> Set<CheckInSignal> {
        let dayStart = calendar.startOfDay(for: day)
        if calendar.isDate(dayStart, inSameDayAs: today) {
            if !todaySignals.isEmpty {
                return todaySignals
            }
            return Set(checkInHistory.first {
                calendar.isDate($0.date, inSameDayAs: dayStart)
            }?.signals ?? [])
        }
        return Set(checkInHistory.first {
            calendar.isDate($0.date, inSameDayAs: dayStart)
        }?.signals ?? [])
    }

    private static func didReportSoreOnPreviousDay(
        day: Date,
        checkInHistory: [(date: Date, signals: [CheckInSignal])],
        calendar: Calendar
    ) -> Bool {
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { return false }
        return checkInHistory.contains {
            calendar.isDate($0.date, inSameDayAs: previousDay) && $0.signals.contains(.sore)
        }
    }

    private static func primaryRule(
        hrvLow: Bool,
        acwrHigh: Bool,
        rhrHigh: Bool,
        sleepShort: Bool
    ) -> ReadinessRule? {
        if hrvLow { return .hrv }
        if acwrHigh { return .load }
        if rhrHigh { return .rhr }
        if sleepShort { return .sleep }
        return nil
    }

    private static func baselineDayCount(_ wellness: [WellnessSample], day: Date, calendar: Calendar) -> Int {
        let days = dailyValues(wellness, day: day, days: Tuning.baselineWindowDays, calendar: calendar) {
            sample in
            sample.hrvSDNN ?? sample.restingHeartRate ?? sample.sleepHours
        }
        return days.count
    }

    private static func metricStats(
        _ wellness: [WellnessSample],
        day: Date,
        calendar: Calendar,
        metric: (WellnessSample) -> Double?
    ) -> MetricStats? {
        let values = dailyValues(
            wellness,
            day: day,
            days: Tuning.baselineWindowDays,
            calendar: calendar,
            metric: metric
        ).map(\.value)
        guard !values.isEmpty else { return nil }
        let median = median(values)
        let average = mean(values) ?? median
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        return MetricStats(median: median, standardDeviation: sqrt(variance), count: values.count)
    }

    private static func recentMean(
        _ wellness: [WellnessSample],
        day: Date,
        calendar: Calendar,
        metric: (WellnessSample) -> Double?
    ) -> Double? {
        let values = dailyValues(
            wellness,
            day: day,
            days: Tuning.baselineWindowDays,
            calendar: calendar,
            metric: metric
        )
        .suffix(Tuning.recentMetricDays)
        .map(\.value)
        return mean(values)
    }

    private static func dayValue(
        _ wellness: [WellnessSample],
        day: Date,
        calendar: Calendar,
        metric: (WellnessSample) -> Double?
    ) -> Double? {
        dailyValues(wellness, day: day, days: 1, calendar: calendar, metric: metric).last?.value
    }

    private static func dailyValues(
        _ wellness: [WellnessSample],
        day: Date,
        days: Int,
        calendar: Calendar,
        metric: (WellnessSample) -> Double?
    ) -> [(date: Date, value: Double)] {
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: day) else { return [] }
        var grouped: [Date: [Double]] = [:]
        for sample in wellness {
            let sampleDay = calendar.startOfDay(for: sample.date)
            guard sampleDay >= start, sampleDay <= day, let value = metric(sample) else { continue }
            grouped[sampleDay, default: []].append(value)
        }
        return grouped
            .map { (date: $0.key, value: mean($0.value) ?? 0) }
            .sorted { $0.date < $1.date }
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func corroboratingReasons(for checkIns: Set<CheckInSignal>) -> [String] {
        CheckInSignal.allCases
            .filter { $0.role == .corroborator && checkIns.contains($0) }
            .map { "Reported \($0.displayName.lowercased()) (corroborates recovery signals)" }
    }
}

private extension ReadinessVerdict {
    var needsVolumeCut: Bool {
        self == .goEasy || self == .rest
    }
}
