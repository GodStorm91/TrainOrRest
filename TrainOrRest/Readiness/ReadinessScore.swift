import Foundation

/// Derives a 0–100 readiness score from the same signals the verdict uses, so
/// the design's circular gauge has a real number behind it. Pure and
/// deterministic. The score is clamped into the verdict's band so the number
/// can never contradict the word (Train ≥70, Easy 50–69, Rest <50).
enum ReadinessScore {
    /// Verdict → allowed score band.
    static func band(for verdict: ReadinessVerdict) -> ClosedRange<Int>? {
        switch verdict {
        case .train: 70...100
        case .goEasy: 50...69
        case .rest: 12...49
        case .insufficientData: nil
        }
    }

    /// Returns nil when the verdict is insufficientData.
    static func score(snapshot: ReadinessAssessment.Snapshot, verdict: ReadinessVerdict) -> Int? {
        guard let band = band(for: verdict) else { return nil }

        var subs: [Double] = []
        if let s = hrvSub(snapshot) { subs.append(s) }
        if let s = rhrSub(snapshot) { subs.append(s) }
        if let s = sleepSub(snapshot) { subs.append(s) }
        if let s = loadSub(snapshot) { subs.append(s) }

        // No evaluable signal → sit at the middle of the band.
        let raw = subs.isEmpty ? 60 : subs.reduce(0, +) / Double(subs.count)
        let clamped = min(Double(band.upperBound), max(Double(band.lowerBound), raw))
        return Int(clamped.rounded())
    }

    // MARK: - Per-signal sub-scores (each 0–100, higher = more ready)

    /// Recent HRV vs the 60-day baseline: at/above baseline is excellent.
    private static func hrvSub(_ s: ReadinessAssessment.Snapshot) -> Double? {
        guard let hrv7 = s.hrvMean7, let hrv28 = s.hrvMean28, hrv28 > 0 else { return nil }
        let ratio = hrv7 / hrv28
        return clamp((ratio - 0.70) / (1.10 - 0.70) * 100)
    }

    /// Recent resting HR vs baseline: below/equal is best, +5 bpm lands low.
    private static func rhrSub(_ s: ReadinessAssessment.Snapshot) -> Double? {
        guard let rhr7 = s.rhrMean7, let rhr28 = s.rhrMean28 else { return nil }
        let delta = rhr7 - rhr28
        return clamp((5 - delta) / 8 * 100)
    }

    /// Last night's sleep against an 8h target.
    private static func sleepSub(_ s: ReadinessAssessment.Snapshot) -> Double? {
        guard let hours = s.sleepLastNight else { return nil }
        return clamp(hours / 8 * 100, min: 15)
    }

    /// Acute:chronic load ratio: penalize both overreaching (>1.3) and heavy
    /// detraining (<0.8).
    private static func loadSub(_ s: ReadinessAssessment.Snapshot) -> Double? {
        guard let acwr = s.acuteChronicRatio else { return nil }
        let over = max(0, acwr - 1.3) * 130
        let under = max(0, 0.8 - acwr) * 80
        return clamp(100 - over - under)
    }

    private static func clamp(_ value: Double, min lower: Double = 0, max upper: Double = 100) -> Double {
        Swift.min(upper, Swift.max(lower, value))
    }
}
