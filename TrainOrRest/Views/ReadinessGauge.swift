import SwiftUI

/// The hero 270° readiness ring: a track arc with a gradient progress arc and
/// the score + verdict stacked in the center. Matches the design's gauge.
struct ReadinessGauge: View {
    /// 0–100; nil renders an empty track (insufficient data).
    let score: Int?
    let verdict: ReadinessVerdict

    private let sweep = 0.75 // 270° of the circle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Theme.chip, style: .init(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: sweep * fraction)
                .stroke(
                    AngularGradient(
                        colors: [Theme.accent2, Color(uiColor: .init(red: 0.71, green: 0.61, blue: 0.96, alpha: 1))],
                        center: .center,
                        angle: .degrees(135)
                    ),
                    style: .init(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: Theme.accent.opacity(0.5), radius: 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: fraction)

            VStack(spacing: 2) {
                Text(score.map(String.init) ?? "–")
                    .font(.torNumber(64))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                TorEyebrow("/ 100 ready")
                    .tracking(2.5)
            }
        }
        .frame(width: 210, height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Readiness \($0) out of 100, \(verdict.torWord)" } ?? "Readiness not yet available")
    }

    private var fraction: Double {
        Double(score ?? 0) / 100
    }
}

extension ReadinessVerdict {
    /// Big verdict word shown under the gauge.
    var torWord: String {
        switch self {
        case .train: "TRAIN"
        case .goEasy: "EASY"
        case .rest: "REST"
        case .insufficientData: "BASELINE"
        }
    }

    /// Verdict accent color per the design (train = purple accent).
    var torColor: Color {
        switch self {
        case .train: Theme.accent
        case .goEasy: Theme.warn
        case .rest: Theme.bad
        case .insufficientData: Theme.dim
        }
    }

    var torSubtitle: String {
        switch self {
        case .train: "Primed for a quality session"
        case .goEasy: "Keep it light — active recovery"
        case .rest: "Recovery comes first today"
        case .insufficientData: "Collecting your baseline"
        }
    }
}
