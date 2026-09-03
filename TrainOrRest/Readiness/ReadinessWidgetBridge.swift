import Foundation
import SwiftData
import WidgetKit

@MainActor
enum ReadinessWidgetBridge {
    static func publish(_ readiness: DailyReadiness?) {
        let language = CoachLanguage.current
        let snapshot: ReadinessWidgetSnapshot
        if let readiness {
            snapshot = ReadinessWidgetSnapshot(
                score: readiness.score,
                verdictRaw: readiness.verdictRaw,
                verdictText: language.verdictWord(readiness.verdict),
                reason: readiness.reasonCodes.first.map(language.today.reason)
                    ?? readiness.reasons.first
                    ?? language.today.widgetReason(readiness.verdict),
                languageRaw: language.rawValue,
                computedAt: readiness.computedAt,
                updatedAt: .now
            )
        } else {
            snapshot = .unavailable(languageRaw: language.rawValue)
        }

        ReadinessWidgetSnapshot.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "ReadinessWidget")
    }

    static func republishForLanguageChange(in context: ModelContext) {
        var descriptor = FetchDescriptor<DailyReadiness>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        publish(try? context.fetch(descriptor).first)
    }
}
