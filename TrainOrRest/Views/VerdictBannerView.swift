import SwiftUI

/// Today's verdict banner: recommendation first, score de-emphasized, drivers inline.
struct VerdictBannerView: View {
    let readiness: DailyReadiness?
    let workout: PlannedWorkout?
    let lastSyncAt: Date?
    let onKeepPlanned: (ReadinessRule) -> Void

    @State private var showsDrivers = false
    @State private var showsRuleReceipt = false
    @State private var keepsPlannedSession = false

    init(
        readiness: DailyReadiness?,
        workout: PlannedWorkout?,
        lastSyncAt: Date?,
        onKeepPlanned: @escaping (ReadinessRule) -> Void = { _ in }
    ) {
        self.readiness = readiness
        self.workout = workout
        self.lastSyncAt = lastSyncAt
        self.onKeepPlanned = onKeepPlanned
    }

    private var verdict: ReadinessVerdict {
        readiness?.verdict ?? .insufficientData
    }

    private var hasPlanConflict: Bool {
        guard let workout, !keepsPlannedSession else { return false }
        return verdict.needsRecovery && workout.isQualitySession
    }

    var body: some View {
        TorCard(padding: 20, cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: verdict.bannerSymbol)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(displayWord)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Spacer(minLength: 8)
                    if isStale {
                        syncChip
                    }
                }
                .foregroundStyle(verdict.torColor)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)

                if let workout {
                    sessionRow(workout)
                }

                Text(rationale)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                HStack(alignment: .center, spacing: 12) {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showsDrivers.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Why?")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: showsDrivers ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsDrivers ? "Hide readiness drivers" : "Show readiness drivers")

                    Spacer()

                    Text(scoreText)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(Theme.dim)
                        .accessibilityHidden(true)
                }

                if showsDrivers {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(driverRows, id: \.self) { row in
                            Text(row)
                                .font(.caption)
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.86)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if hasPlanConflict {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            keepsPlannedSession = true
                        }
                        if let rule = readiness?.primaryRule {
                            onKeepPlanned(rule)
                        }
                    } label: {
                        Text("Keep planned session")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Keep planned session")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showsRuleReceipt) {
            ReceiptSheet(
                title: "Adjusted by rule",
                subtitle: "Deterministic training rule — no AI involved.",
                rows: ruleAdjustmentRows
            )
        }
    }

    @ViewBuilder
    private func sessionRow(_ workout: PlannedWorkout) -> some View {
        if hasPlanConflict {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(sessionText(for: workout))
                    .strikethrough()
                    .foregroundStyle(Theme.faint)
                Text("->")
                    .foregroundStyle(Theme.faint)
                Text(adjustedSessionText(for: workout))
                    .foregroundStyle(Theme.text)
                Button {
                    showsRuleReceipt = true
                } label: {
                    Text("Adjusted · rule")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .background(Theme.soft(Theme.warn), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show rule adjustment receipt")
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        } else {
            Text("Planned: \(sessionText(for: workout))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var displayWord: String {
        if (readiness?.hedged == true || isStale), verdict != .insufficientData {
            return "Likely \(verdict.bannerWord.lowercased())"
        }
        return verdict.bannerWord
    }

    private var rationale: String {
        if let workout, hasPlanConflict {
            let reason = readiness?.reasons.first ?? "recovery signals are mixed"
            return "Plan calls for \(sessionText(for: workout)), but \(reason)."
        }
        if let reason = readiness?.reasons.first {
            return reason
        }
        if verdict == .insufficientData {
            let days = min(readiness?.baselineDayCount ?? 0, ReadinessEngine.Tuning.minBaselineDays)
            return "Collecting baseline, day \(days) of \(ReadinessEngine.Tuning.minBaselineDays)."
        }
        return "HRV normal · sleep steady · load balanced"
    }

    private var driverRows: [String] {
        [hrvDriver, sleepDriver, loadDriver]
    }

    private var ruleAdjustmentRows: [ReceiptSheet.Row] {
        var rows: [ReceiptSheet.Row] = [
            .detail("HRV band", value: hrvDriver, symbol: "waveform.path.ecg"),
            .detail("Load", value: loadDriver, symbol: "chart.line.uptrend.xyaxis")
        ]

        if let workout, hasPlanConflict {
            rows.append(
                .detail(
                    "Adjustment",
                    value: "\(sessionText(for: workout)) -> \(adjustedSessionText(for: workout))",
                    symbol: "arrow.triangle.2.circlepath"
                )
            )
        }

        rows.append(
            .detail("Source", value: "Adjusted by a deterministic local training rule.", symbol: "checkmark.shield")
        )
        return rows
    }

    private var hrvDriver: String {
        guard let readiness, let hrv7 = readiness.hrvMean7,
              let baseline = readiness.hrvBaseline ?? readiness.hrvMean28
        else {
            return "HRV: baseline building"
        }
        if baseline > 0 {
            let percent = Int(((hrv7 / baseline - 1) * 100).rounded())
            let band = percent >= 0 ? "\(percent)% above baseline" : "\(abs(percent))% below baseline"
            return "HRV: \(Int(hrv7.rounded())) ms, \(band)"
        }
        return "HRV: \(Int(hrv7.rounded())) ms"
    }

    private var sleepDriver: String {
        guard let sleep = readiness?.sleepLastNight else {
            return "Sleep: no sleep sample last night"
        }
        return "Sleep: \(Formatters.sleep(sleep)) last night"
    }

    private var loadDriver: String {
        guard let acwr = readiness?.acuteChronicRatio else {
            return "Load: building training history"
        }
        let caption = acwr > ReadinessEngine.Tuning.acwrLimit
            ? "ramping fast"
            : acwr < 0.8 ? "light" : "balanced"
        return String(format: "Load: %.2f ACWR, %@", acwr, caption)
    }

    private var scoreText: String {
        guard let score = readiness?.score else { return "readiness --" }
        return "readiness \(score)"
    }

    private var accessibilityLabel: String {
        guard let score = readiness?.score else {
            return "Readiness not yet available, \(displayWord)"
        }
        return "Readiness \(score) out of 100, \(displayWord)"
    }

    private var isStale: Bool {
        guard let lastSyncAt else { return true }
        return Date.now.timeIntervalSince(lastSyncAt) > 12 * 60 * 60
    }

    private var syncChip: some View {
        Text(syncText)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(Theme.warn)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.soft(Theme.warn), in: Capsule())
    }

    private var syncText: String {
        guard let lastSyncAt else { return "never synced" }
        let hours = max(1, Int(Date.now.timeIntervalSince(lastSyncAt) / 3600))
        return "sync \(hours)h ago"
    }

    private func sessionText(for workout: PlannedWorkout) -> String {
        var parts: [String] = []
        let details = workout.details.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(details.isEmpty ? (workout.kind?.displayName ?? "Run") : compactSession(details))
        if let seconds = workout.expectedDurationSeconds {
            parts.append("\(Int((seconds / 60).rounded())) min")
        }
        return parts.joined(separator: " · ")
    }

    private func adjustedSessionText(for workout: PlannedWorkout) -> String {
        if workout.kind == .intervals {
            return "shorter reps or easy 40 min"
        }
        if workout.kind == .tempo {
            return "easy 40 min"
        }
        return "easy 30 min"
    }

    private func compactSession(_ details: String) -> String {
        details
            .replacingOccurrences(of: " at ", with: " @ ")
    }
}

private extension ReadinessVerdict {
    var needsRecovery: Bool {
        self == .goEasy || self == .rest
    }
}

private extension PlannedWorkout {
    var isQualitySession: Bool {
        kind == .tempo || kind == .intervals || kind == .race
    }
}
