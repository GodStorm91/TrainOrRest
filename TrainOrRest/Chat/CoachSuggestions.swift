import Foundation

/// Contextual "Ask Next" quick prompts for the coach chat. Pure and testable:
/// the set adapts to conversation state, the most recent run, and today's
/// planned session, and renders in the chosen `CoachLanguage`. Nothing here is
/// fabricated — callers derive the context from real SwiftData rows.
enum CoachSuggestions {
    struct Context: Equatable {
        var hasMessages: Bool
        /// The last message in the thread came from the coach (a reply the user
        /// might want to follow up on).
        var lastMessageIsAssistant: Bool
        /// A running activity was completed within the recency window.
        var hasRecentRun: Bool
        /// That recent run was a hard effort (high HR / fast pace).
        var recentRunWasHard: Bool
        /// The kind of workout planned for today, if any.
        var todayWorkoutKind: WorkoutKind?
    }

    /// The prompts, as language-independent keys, so ordering/selection logic
    /// stays separate from translation.
    private enum Key: Equatable {
        case recoverFromRun
        case wasTooHard
        case pushHarder
        case whatToEat
        case whyTodaysWorkout(WorkoutKind)
        case canIMoveSession
        case loadTrending
        case explainReadiness
        case weekFocus
    }

    /// Ordered quick prompts for `language`, most relevant first (index 0 is the
    /// primary chip). De-duplicated and capped at `limit`.
    static func prompts(for context: Context, language: CoachLanguage = .en, limit: Int = 4) -> [String] {
        var keys: [Key] = []

        // Just finished a run and the coach has spoken → recovery follow-ups.
        if context.hasRecentRun, context.lastMessageIsAssistant || !context.hasMessages {
            keys.append(.recoverFromRun)
            keys.append(context.recentRunWasHard ? .wasTooHard : .pushHarder)
            keys.append(.whatToEat)
        }

        // Today has a planned session → questions about it.
        if let kind = context.todayWorkoutKind {
            keys.append(.whyTodaysWorkout(kind))
            keys.append(.canIMoveSession)
        }

        // General follow-ups, always available to round out the row.
        keys.append(.loadTrending)
        keys.append(.explainReadiness)
        keys.append(.weekFocus)

        var seen = Set<String>()
        return keys
            .map { render($0, language: language) }
            .filter { seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private static func render(_ key: Key, language: CoachLanguage) -> String {
        switch key {
        case .recoverFromRun:
            switch language {
            case .en: return "How do I recover from this run?"
            case .ja: return "どうやって回復すればいい？"
            case .vi: return "Làm sao để hồi phục?"
            }
        case .wasTooHard:
            switch language {
            case .en: return "Was that session too hard?"
            case .ja: return "今のはきつすぎた？"
            case .vi: return "Buổi này có quá sức không?"
            }
        case .pushHarder:
            switch language {
            case .en: return "Should I push harder next time?"
            case .ja: return "次回はもっと追い込むべき？"
            case .vi: return "Lần tới có nên đẩy mạnh hơn không?"
            }
        case .whatToEat:
            switch language {
            case .en: return "What should I eat to recover?"
            case .ja: return "回復のために何を食べればいい？"
            case .vi: return "Nên ăn gì để hồi phục?"
            }
        case .whyTodaysWorkout(let kind):
            let name = kindName(kind, language: language)
            switch language {
            case .en: return "Why is today's \(name) right for me?"
            case .ja: return "今日の\(name)はなぜ自分に合ってるの？"
            case .vi: return "Vì sao buổi \(name) hôm nay phù hợp với tôi?"
            }
        case .canIMoveSession:
            switch language {
            case .en: return "Can I move today's session?"
            case .ja: return "今日のセッションを別の日にできる？"
            case .vi: return "Tôi có thể dời buổi tập hôm nay không?"
            }
        case .loadTrending:
            switch language {
            case .en: return "How's my training load trending?"
            case .ja: return "トレーニング負荷の傾向は？"
            case .vi: return "Tải tập luyện của tôi đang theo xu hướng nào?"
            }
        case .explainReadiness:
            switch language {
            case .en: return "Explain my readiness score"
            case .ja: return "レディネススコアを説明して"
            case .vi: return "Giải thích điểm sẵn sàng của tôi"
            }
        case .weekFocus:
            switch language {
            case .en: return "What should I focus on this week?"
            case .ja: return "今週は何に集中すべき？"
            case .vi: return "Tuần này tôi nên tập trung vào điều gì?"
            }
        }
    }

    private static func kindName(_ kind: WorkoutKind, language: CoachLanguage) -> String {
        switch language {
        case .en:
            return kind.displayName.lowercased()
        case .ja:
            switch kind {
            case .easy: return "イージー"
            case .long: return "ロング走"
            case .tempo: return "テンポ走"
            case .intervals: return "インターバル"
            case .race: return "レース"
            }
        case .vi:
            switch kind {
            case .easy: return "chạy nhẹ"
            case .long: return "chạy dài"
            case .tempo: return "tempo"
            case .intervals: return "interval"
            case .race: return "chạy đua"
            }
        }
    }
}
