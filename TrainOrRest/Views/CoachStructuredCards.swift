import SwiftUI

struct CoachRationaleCard: View {
    let rationale: ReadinessRationale
    let language: CoachLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        CoachVerdictChip(verdict: rationale.verdict, language: language, prefix: language.coachEngineLabel)
                        if let score = rationale.score {
                            Text(language.readinessScoreLabel(score))
                                .font(.torMono(11, .medium))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)

                    VStack(alignment: .leading, spacing: 4) {
                        CoachVerdictChip(verdict: rationale.verdict, language: language, prefix: language.coachEngineLabel)
                        if let score = rationale.score {
                            Text(language.readinessScoreLabel(score))
                                .font(.torMono(11, .medium))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }

                if !rationale.signals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rationale.signals.prefix(3)) { signal in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: signal.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.data)
                                    .frame(width: 18, height: 18)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language.readinessSignalLabel(for: signal.id, fallback: signal.label))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.text)
                                    Text(language.readinessSignalValue(id: signal.id, rawValue: signal.value))
                                        .font(.caption)
                                        .foregroundStyle(Theme.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                if !rationale.ruleIDs.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(rationale.ruleIDs) { ruleID in
                            RuleCodeChip(ruleID: ruleID, language: language, tint: rationale.verdict.torColor)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct CoachWorkoutCard: View {
    let workout: CoachWorkoutSummary
    let language: CoachLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(workout: PlannedWorkout, language: CoachLanguage) {
        self.language = language
        self.workout = CoachWorkoutSummary(from: workout, language: language)
    }

    init(spec: PlannedWorkoutSpec, language: CoachLanguage) {
        self.language = language
        self.workout = CoachWorkoutSummary(from: spec, language: language)
    }

    init(workout: CoachWorkoutSummary, language: CoachLanguage) {
        self.language = language
        self.workout = workout
    }

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: workout.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.data)
                        .frame(width: 28, height: 28)
                        .background(Theme.data.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(workout.targets.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        metricChips
                    }
                    .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)

                    VStack(alignment: .leading, spacing: 8) {
                        metricChips
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metricChips: some View {
        WorkoutMetricChip(label: language.distanceLabel, value: workout.distance)
        if let duration = workout.duration {
            WorkoutMetricChip(label: language.durationLabel, value: duration)
        }
        if let paceBand = workout.paceBand {
            WorkoutMetricChip(label: language.paceLabel, value: paceBand)
        }
    }
}

struct CoachWorkoutSummary: Equatable {
    var title: String
    var targets: [String]
    var distance: String
    var duration: String?
    var paceBand: String?
    var symbolName: String

    init(from workout: PlannedWorkout, language: CoachLanguage) {
        self.init(
            kind: workout.kind,
            distanceKm: workout.distanceKm,
            paceBand: workout.paceBand,
            details: workout.details,
            language: language
        )
    }

    init(from spec: PlannedWorkoutSpec, language: CoachLanguage) {
        self.init(
            kind: spec.kind,
            distanceKm: spec.distanceKm,
            paceBand: spec.paceBand,
            details: spec.details,
            language: language
        )
    }

    private init(kind: WorkoutKind?, distanceKm: Double, paceBand: PaceBand?, details: String, language: CoachLanguage) {
        title = kind.map { language.name($0) } ?? language.genericRunLabel
        targets = Self.targets(kind: kind, details: details, language: language)
        distance = Formatters.kilometers(distanceKm * 1000)
        self.paceBand = paceBand.map(Formatters.paceBand)
        duration = Self.duration(distanceKm: distanceKm, paceBand: paceBand)
        symbolName = kind?.symbolName ?? "figure.run"
    }

    private static func targets(kind: WorkoutKind?, details: String, language: CoachLanguage) -> [String] {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return [trimmed] }
        return [language.workoutTarget(for: kind)]
    }

    private static func duration(distanceKm: Double, paceBand: PaceBand?) -> String? {
        guard let paceBand else { return nil }
        let midPace = (paceBand.fastSecondsPerKm + paceBand.slowSecondsPerKm) / 2
        return Formatters.duration(distanceKm * midPace)
    }
}

struct CoachVerdictChip: View {
    let verdict: ReadinessVerdict
    let language: CoachLanguage
    var prefix: String? = nil

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: verdict.bannerSymbol)
                .accessibilityHidden(true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(verdict.torColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.soft(verdict.torColor), in: Capsule())
        .lineLimit(1)
    }

    private var text: String {
        if let prefix {
            return "\(prefix) · \(language.verdictWord(verdict))"
        }
        return language.verdictWord(verdict)
    }
}

struct RuleCodeChip: View {
    let ruleID: ReadinessRuleID
    let language: CoachLanguage
    var tint: Color = Theme.accent

    var body: some View {
        Text(ruleID.code)
            .font(.torMono(11, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.soft(tint), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel("\(language.ruleSheetTitle(ruleID.code)), \(language.ruleTitle(ruleID))")
    }
}

private struct WorkoutMetricChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.torMono(11, .medium))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let intrinsic = subviews[index].sizeThatFits(.unspecified)
            let size = intrinsic.width > maxWidth
                ? subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                : intrinsic
            if !current.items.isEmpty, current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row(y: (rows.last.map { $0.y + $0.height + lineSpacing }) ?? 0)
            }
            let x = current.items.isEmpty ? 0 : current.width + spacing
            current.items.append(Item(index: index, x: x, size: size))
            current.width = x + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
        var items: [Item] = []
    }

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }
}

#Preview("Coach rationale card") {
    CoachRationaleCard(
        rationale: ReadinessRationale(
            readinessVersion: 1,
            verdict: .rest,
            score: 42,
            signals: [
                .init(id: "hrv", label: "HRV", value: "7-day 44 ms vs baseline 60 ms", symbol: "waveform.path.ecg"),
                .init(id: "sleep", label: "Sleep", value: "5h 40m last night", symbol: "bed.double"),
                .init(id: "load", label: "Load", value: "1.36 acute:chronic load", symbol: "chart.line.uptrend.xyaxis")
            ],
            ruleIDs: [.hrvLow, .illness],
            summary: "Recovery signals are strained.",
            computedAt: .now
        ),
        language: .en
    )
}

#Preview("Coach workout card") {
    CoachWorkoutCard(
        spec: PlannedWorkoutSpec(
            date: .now,
            kind: .tempo,
            distanceKm: 9,
            paceBand: PaceBand(fastSecondsPerKm: 265, slowSecondsPerKm: 285),
            details: "2 km easy + 5 km threshold + 2 km easy"
        ),
        language: .en
    )
}
