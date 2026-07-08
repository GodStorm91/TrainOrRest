import SwiftUI

/// Dashboard verdict card: Train / Go easy / Rest with the triggered
/// reasons, or baseline-collection progress while data is insufficient.
struct ReadinessCardView: View {
    let readiness: DailyReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: readiness.verdict.cardSymbol)
                    .font(.title2)
                Text(readiness.verdict.cardTitle)
                    .font(.title3.bold())
                Spacer()
            }
            .foregroundStyle(readiness.verdict.cardColor)

            if let guidance = readiness.verdict.guidanceText {
                Label(guidance, systemImage: "figure.run.circle")
                    .font(.subheadline.weight(.medium))
            }
            if let rationale = readiness.verdict.rationaleText {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if readiness.verdict == .insufficientData {
                Text("Collecting baseline — day \(min(readiness.baselineDayCount, ReadinessEngine.Tuning.minBaselineDays))/\(ReadinessEngine.Tuning.minBaselineDays)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(
                    value: Double(min(readiness.baselineDayCount, ReadinessEngine.Tuning.minBaselineDays)),
                    total: Double(ReadinessEngine.Tuning.minBaselineDays)
                )
            } else if readiness.reasons.isEmpty {
                Text("All recovery signals look good.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(readiness.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Based on data as of \(readiness.computedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

extension ReadinessVerdict {
    var cardTitle: String {
        switch self {
        case .train: "Train"
        case .goEasy: "Go Easy"
        case .rest: "Rest"
        case .insufficientData: "Building Your Baseline"
        }
    }

    var cardSymbol: String {
        switch self {
        case .train: "bolt.fill"
        case .goEasy: "tortoise.fill"
        case .rest: "moon.zzz.fill"
        case .insufficientData: "chart.line.uptrend.xyaxis"
        }
    }

    var cardColor: Color {
        switch self {
        case .train: .green
        case .goEasy: .orange
        case .rest: .red
        case .insufficientData: .secondary
        }
    }

    var guidanceText: String? {
        switch self {
        case .train:
            "Follow today's planned session."
        case .goEasy:
            "Keep today's effort easy."
        case .rest:
            "Make today recovery-focused."
        case .insufficientData:
            nil
        }
    }

    var rationaleText: String? {
        switch self {
        case .train:
            nil
        case .goEasy:
            "The plan stays conservative while recovery signals are mixed."
        case .rest:
            "Rest protects the next sessions when recovery signals are stressed."
        case .insufficientData:
            nil
        }
    }
}
