import SwiftUI

/// Today's verdict banner: recommendation first, score de-emphasized, drivers inline.
struct VerdictBannerView: View {
    let readiness: DailyReadiness?
    let workout: PlannedWorkout?
    let lastSyncAt: Date?
    let language: CoachLanguage
    let onKeepPlanned: (ReadinessRule) -> Void

    @State private var showsDrivers = false
    @State private var showsRuleReceipt = false
    @State private var keepsPlannedSession = false

    init(
        readiness: DailyReadiness?,
        workout: PlannedWorkout?,
        lastSyncAt: Date?,
        language: CoachLanguage = .en,
        onKeepPlanned: @escaping (ReadinessRule) -> Void = { _ in }
    ) {
        self.readiness = readiness
        self.workout = workout
        self.lastSyncAt = lastSyncAt
        self.language = language
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
                            Text(language.today.why)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: showsDrivers ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsDrivers ? language.today.hideReadinessDrivers : language.today.showReadinessDrivers)

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
                        Text(language.today.keepPlannedSession)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.today.keepPlannedSession)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showsRuleReceipt) {
            ReceiptSheet(
                title: language.today.adjustedByRule,
                subtitle: language.today.deterministicRuleSubtitle,
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
                    Text(adjustedRuleTagText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .background(Theme.soft(Theme.warn), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.today.showRuleAdjustmentReceipt)
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        } else {
            Text(language.today.plannedSession(sessionText(for: workout)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var displayWord: String {
        if (readiness?.hedged == true || isStale), verdict != .insufficientData {
            return language.today.likely(verdict)
        }
        return language.verdictWord(verdict)
    }

    private var rationale: String {
        if let workout, hasPlanConflict {
            return language.today.planCallsFor(
                sessionText(for: workout),
                but: firstReason ?? language.today.recoverySignalsMixed
            )
        }
        if let reason = firstReason {
            return reason
        }
        if verdict == .insufficientData {
            let days = min(readiness?.baselineDayCount ?? 0, ReadinessEngine.Tuning.minBaselineDays)
            return language.today.collectingBaseline(day: days, total: ReadinessEngine.Tuning.minBaselineDays)
        }
        return language.today.normalDrivers
    }

    private var firstReason: String? {
        readiness?.reasonCodes.first.map(language.today.reason) ?? readiness?.reasons.first
    }

    private var driverRows: [String] {
        [hrvDriver, sleepDriver, loadDriver]
    }

    private var ruleAdjustmentRows: [ReceiptSheet.Row] {
        var rows = readiness?.ruleIDs.map { id in
            ReceiptSheet.Row.detail(
                language.today.ruleLabel(id),
                value: language.today.ruleDetail(id),
                symbol: "checkmark.seal"
            )
        } ?? []

        rows.append(contentsOf: [
            .detail(language.today.hrvBand, value: hrvDriver, symbol: "waveform.path.ecg"),
            .detail(language.today.load, value: loadDriver, symbol: "chart.line.uptrend.xyaxis")
        ])

        if let workout, hasPlanConflict {
            rows.append(
                .detail(
                    language.today.adjustment,
                    value: "\(sessionText(for: workout)) -> \(adjustedSessionText(for: workout))",
                    symbol: "arrow.triangle.2.circlepath"
                )
            )
        }

        rows.append(
            .detail(language.today.source, value: language.today.localRuleSource, symbol: "checkmark.shield")
        )
        return rows
    }

    private var adjustedRuleTagText: String {
        language.today.adjustedRuleTag(primaryRuleID?.code ?? readiness?.ruleIDs.first?.code)
    }

    private var primaryRuleID: ReadinessRuleID? {
        guard let primaryRule = readiness?.primaryRule else { return nil }
        switch primaryRule {
        case .hrv:
            return .hrvLow
        case .rhr:
            return .rhrElevated
        case .sleep:
            return .shortSleep
        case .load:
            return .loadRamp
        }
    }

    private var hrvDriver: String {
        guard let readiness, let hrv7 = readiness.hrvMean7,
              let baseline = readiness.hrvBaseline ?? readiness.hrvMean28
        else {
            return language.today.hrvBaselineBuilding
        }
        let percent = baseline > 0
            ? Int(((hrv7 / baseline - 1) * 100).rounded())
            : nil
        return language.today.hrvDriver(value: hrv7, percent: percent)
    }

    private var sleepDriver: String {
        guard let sleep = readiness?.sleepLastNight else {
            return language.today.sleepNoSample
        }
        return language.today.sleepDriver(language.today.sleepDuration(sleep))
    }

    private var loadDriver: String {
        guard let acwr = readiness?.acuteChronicRatio else {
            return language.today.loadBuildingHistory
        }
        let caption = acwr > ReadinessEngine.Tuning.acwrLimit
            ? language.today.rampingFast
            : acwr < 0.8 ? language.today.detraining : language.today.balancedTraining
        return language.today.loadDriver(acwr: acwr, status: caption)
    }

    private var scoreText: String {
        language.today.readinessScore(readiness?.score)
    }

    private var accessibilityLabel: String {
        language.today.readinessAccessibility(score: readiness?.score, verdict: displayWord)
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
        guard let lastSyncAt else { return language.today.neverSynced }
        let hours = max(1, Int(Date.now.timeIntervalSince(lastSyncAt) / 3600))
        return language.today.syncAgo(hours: hours)
    }

    private func sessionText(for workout: PlannedWorkout) -> String {
        let details = workout.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationMinutes = workout.expectedDurationSeconds.map { Int(($0 / 60).rounded()) }
        return language.today.sessionText(
            fallbackKind: workout.kind,
            details: details,
            durationMinutes: durationMinutes
        )
    }

    private func adjustedSessionText(for workout: PlannedWorkout) -> String {
        language.today.adjustedSession(kind: workout.kind)
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
