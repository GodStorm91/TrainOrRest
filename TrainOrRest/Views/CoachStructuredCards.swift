import SwiftUI

struct CoachRationaleCard: View {
    let rationale: ReadinessRationale

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CoachVerdictChip(verdict: rationale.verdict, prefix: "Engine")
                    if let score = rationale.score {
                        Text("readiness \(score)")
                            .font(.torMono(11, .medium))
                            .foregroundStyle(Theme.dim)
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
                                    Text(signal.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.text)
                                    Text(signal.value)
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
                            RuleCodeChip(ruleID: ruleID, tint: rationale.verdict.torColor)
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

    init(workout: PlannedWorkout) {
        self.workout = CoachWorkoutSummary(from: workout)
    }

    init(spec: PlannedWorkoutSpec) {
        self.workout = CoachWorkoutSummary(from: spec)
    }

    init(workout: CoachWorkoutSummary) {
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

                HStack(spacing: 8) {
                    WorkoutMetricChip(label: "Distance", value: workout.distance)
                    if let duration = workout.duration {
                        WorkoutMetricChip(label: "Duration", value: duration)
                    }
                    if let paceBand = workout.paceBand {
                        WorkoutMetricChip(label: "Pace", value: paceBand)
                    }
                }
            }
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

    init(from workout: PlannedWorkout) {
        self.init(
            kind: workout.kind,
            kindRaw: workout.kindRaw,
            distanceKm: workout.distanceKm,
            paceBand: workout.paceBand,
            details: workout.details
        )
    }

    init(from spec: PlannedWorkoutSpec) {
        self.init(
            kind: spec.kind,
            kindRaw: spec.kind.rawValue,
            distanceKm: spec.distanceKm,
            paceBand: spec.paceBand,
            details: spec.details
        )
    }

    private init(kind: WorkoutKind?, kindRaw: String, distanceKm: Double, paceBand: PaceBand?, details: String) {
        let displayName = kind?.displayName ?? kindRaw.capitalized
        title = displayName
        targets = Self.targets(kind: kind, details: details)
        distance = Formatters.kilometers(distanceKm * 1000)
        self.paceBand = paceBand.map(Formatters.paceBand)
        duration = Self.duration(distanceKm: distanceKm, paceBand: paceBand)
        symbolName = kind?.symbolName ?? "figure.run"
    }

    private static func targets(kind: WorkoutKind?, details: String) -> [String] {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return [trimmed] }
        guard let kind else { return ["Planned run"] }
        switch kind {
        case .easy:
            return ["Aerobic"]
        case .long:
            return ["Endurance"]
        case .tempo:
            return ["Threshold"]
        case .threshold:
            return ["Threshold"]
        case .intervals:
            return ["Speed"]
        case .race:
            return ["Race effort"]
        }
    }

    private static func duration(distanceKm: Double, paceBand: PaceBand?) -> String? {
        guard let paceBand else { return nil }
        let midPace = (paceBand.fastSecondsPerKm + paceBand.slowSecondsPerKm) / 2
        return Formatters.duration(distanceKm * midPace)
    }
}

struct CoachVerdictChip: View {
    let verdict: ReadinessVerdict
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
            return "\(prefix) · \(verdict.bannerWord)"
        }
        return verdict.bannerWord
    }
}

struct RuleCodeChip: View {
    let ruleID: ReadinessRuleID
    var tint: Color = Theme.accent

    var body: some View {
        Text(ruleID.code)
            .font(.torMono(11, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.soft(tint), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityLabel("Rule \(ruleID.code), \(ruleID.title)")
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
                .lineLimit(1)
                .minimumScaleFactor(0.82)
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
        )
    )
    .padding()
    .background(Theme.bg)
}

#Preview("Coach workout card") {
    CoachWorkoutCard(
        spec: PlannedWorkoutSpec(
            date: .now,
            kind: .tempo,
            distanceKm: 9,
            paceBand: PaceBand(fastSecondsPerKm: 265, slowSecondsPerKm: 285),
            details: "2 km easy + 5 km threshold + 2 km easy"
        )
    )
    .padding()
    .background(Theme.bg)
}
