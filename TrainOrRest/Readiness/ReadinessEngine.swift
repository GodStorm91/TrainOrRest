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
    /// Human-readable explanation per triggered flag, worst first.
    var reasons: [String]
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
    }
}

/// Daily Train / Go easy / Rest verdict from wellness baselines and training
/// load. Pure: caller supplies samples, loads, `today`, and a calendar.
enum ReadinessEngine {
    enum Tuning {
        /// HRV flag: 7-day mean below this fraction of the 28-day baseline.
        static let hrvDropRatio = 0.85
        /// RHR flag: 7-day mean this many bpm above the 28-day baseline.
        static let rhrRiseBpm = 5.0
        /// Sleep flags: last night under this many hours…
        static let sleepMinHours = 6.0
        /// …or under this fraction of the 14-day mean.
        static let sleepDropRatio = 0.75
        /// Load flag: acute:chronic ratio above this.
        static let acwrLimit = 1.3
        /// Days of wellness history required before any verdict.
        static let minBaselineDays = 14
    }

    static func assess(
        wellness: [WellnessSample],
        loads: [(date: Date, load: Double)],
        today: Date,
        calendar: Calendar
    ) -> ReadinessAssessment {
        let dayStart = calendar.startOfDay(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -27, to: dayStart) ?? .distantPast
        let recent = wellness.filter { $0.date >= windowStart && $0.date <= dayStart }

        let baselineDays = Set(recent
            .filter { $0.hrvSDNN != nil || $0.restingHeartRate != nil || $0.sleepHours != nil }
            .map { calendar.startOfDay(for: $0.date) }
        ).count

        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        func windowMean(_ metric: (WellnessSample) -> Double?, days: Int) -> Double? {
            guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: dayStart) else { return nil }
            return mean(recent.filter { $0.date >= start }.compactMap(metric))
        }

        let snapshot = ReadinessAssessment.Snapshot(
            hrvMean7: windowMean(\.hrvSDNN, days: 7),
            hrvMean28: windowMean(\.hrvSDNN, days: 28),
            rhrMean7: windowMean(\.restingHeartRate, days: 7),
            rhrMean28: windowMean(\.restingHeartRate, days: 28),
            sleepLastNight: recent.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.sleepHours,
            sleepMean14: windowMean(\.sleepHours, days: 14),
            acuteChronicRatio: TrainingLoad.acuteChronicRatio(loads: loads, today: today, calendar: calendar)
        )

        guard baselineDays >= Tuning.minBaselineDays else {
            return ReadinessAssessment(
                verdict: .insufficientData, reasons: [], baselineDayCount: baselineDays, snapshot: snapshot
            )
        }

        var hrvFlag = false, acwrFlag = false
        var reasons: [String] = []

        if let hrv7 = snapshot.hrvMean7, let hrv28 = snapshot.hrvMean28, hrv28 > 0,
           hrv7 < Tuning.hrvDropRatio * hrv28 {
            hrvFlag = true
            let dropPercent = Int(((1 - hrv7 / hrv28) * 100).rounded())
            reasons.append("HRV \(dropPercent)% below baseline")
        }
        if let rhr7 = snapshot.rhrMean7, let rhr28 = snapshot.rhrMean28,
           rhr7 > rhr28 + Tuning.rhrRiseBpm {
            let rise = Int((rhr7 - rhr28).rounded())
            reasons.append("Resting HR \(rise) bpm above baseline")
        }
        if let lastNight = snapshot.sleepLastNight {
            let belowFloor = lastNight < Tuning.sleepMinHours
            let belowMean = snapshot.sleepMean14.map { lastNight < Tuning.sleepDropRatio * $0 } ?? false
            if belowFloor || belowMean {
                reasons.append(String(format: "Slept %.1f h last night", lastNight))
            }
        }
        if let acwr = snapshot.acuteChronicRatio, acwr > Tuning.acwrLimit {
            acwrFlag = true
            reasons.append(String(format: "Training load ramping fast (%.2f× your usual)", acwr))
        }

        // No signal evaluable at all → don't fake a "Train" verdict.
        let anySignalPresent = snapshot.hrvMean7 != nil
            || snapshot.rhrMean7 != nil
            || snapshot.sleepLastNight != nil
            || snapshot.acuteChronicRatio != nil
        guard anySignalPresent else {
            return ReadinessAssessment(
                verdict: .insufficientData, reasons: [], baselineDayCount: baselineDays, snapshot: snapshot
            )
        }

        let verdict: ReadinessVerdict = switch reasons.count {
        case 0: .train
        case 1: .goEasy
        default: .rest
        }
        // Suppressed recovery and rising load together is the classic
        // overreaching pattern — always rest, regardless of other flags.
        let finalVerdict = (hrvFlag && acwrFlag) ? .rest : verdict

        return ReadinessAssessment(
            verdict: finalVerdict, reasons: reasons, baselineDayCount: baselineDays, snapshot: snapshot
        )
    }
}
