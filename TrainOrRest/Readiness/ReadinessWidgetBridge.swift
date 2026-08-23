import Foundation
import WidgetKit

@MainActor
enum ReadinessWidgetBridge {
    static func publish(_ readiness: DailyReadiness?) {
        let snapshot: ReadinessWidgetSnapshot
        if let readiness {
            snapshot = ReadinessWidgetSnapshot(
                score: readiness.score,
                verdictRaw: readiness.verdictRaw,
                verdictText: readiness.verdict.widgetText,
                reason: readiness.reasons.first ?? readiness.verdict.widgetReason,
                computedAt: readiness.computedAt,
                updatedAt: .now
            )
        } else {
            snapshot = .unavailable
        }

        ReadinessWidgetSnapshot.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "ReadinessWidget")
    }
}

private extension ReadinessVerdict {
    var widgetText: String {
        switch self {
        case .train: "Train"
        case .goEasy: "Go easy"
        case .rest: "Rest"
        case .insufficientData: "Baseline"
        }
    }

    var widgetReason: String {
        switch self {
        case .train: "Ready for the planned session"
        case .goEasy: "Keep the effort controlled today"
        case .rest: "Recovery comes first today"
        case .insufficientData: "Collecting your baseline"
        }
    }
}
