import Foundation

/// The language the coach speaks and suggests in. Chosen in Settings, stored in
/// UserDefaults, and read both by SwiftUI views (`@AppStorage`) and by the chat
/// store (`.current`). English is the default and leaves existing behavior
/// unchanged.
enum CoachLanguage: String, CaseIterable, Identifiable {
    case en, ja, vi

    var id: String { rawValue }

    static let storageKey = "coachLanguage"

    /// The current selection, read from UserDefaults (falls back to English).
    static var current: CoachLanguage {
        CoachLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .en
    }

    /// Endonym shown as the primary label in the picker.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .ja: "日本語"
        case .vi: "Tiếng Việt"
        }
    }

    /// English name shown as the picker sub-label.
    var englishName: String {
        switch self {
        case .en: "English (US)"
        case .ja: "Japanese"
        case .vi: "Vietnamese"
        }
    }

    var flag: String {
        switch self {
        case .en: "🇺🇸"
        case .ja: "🇯🇵"
        case .vi: "🇻🇳"
        }
    }

    /// Coach header subtitle.
    var coachStatus: String {
        switch self {
        case .en: "Adapting to today's readiness"
        case .ja: "今日のコンディションに合わせて調整中"
        case .vi: "Đang điều chỉnh theo thể trạng hôm nay"
        }
    }

    /// Composer placeholder.
    var composerPlaceholder: String {
        switch self {
        case .en: "Ask your coach…"
        case .ja: "コーチに質問…"
        case .vi: "Hỏi huấn luyện viên…"
        }
    }

    /// "Ask Next" strip eyebrow.
    var askNextLabel: String {
        switch self {
        case .en: "ASK NEXT"
        case .ja: "次に聞く"
        case .vi: "HỎI TIẾP"
        }
    }

    /// Appended to the coach system prompt so replies match the chosen language.
    /// Empty for English (no behavior change).
    var systemPromptDirective: String {
        switch self {
        case .en: ""
        case .ja: "Always respond in Japanese (日本語), regardless of the language the user writes in."
        case .vi: "Always respond in Vietnamese (Tiếng Việt), regardless of the language the user writes in."
        }
    }

    var replacementFailureMessage: String {
        switch self {
        case .en: "The workout was not replaced. Please ask your coach again."
        case .ja: "ワークアウトは置き換えられませんでした。コーチにもう一度聞いてください。"
        case .vi: "Không thể thay bài tập. Hãy hỏi huấn luyện viên lại."
        }
    }

    var replacementPendingMessage: String {
        switch self {
        case .en: "Choose whether to replace the scheduled workout first."
        case .ja: "先に予定済みワークアウトを置き換えるか選択してください。"
        case .vi: "Hãy chọn có thay bài tập đã lên lịch hay không trước."
        }
    }

    func replacementPresentation(
        date: Date,
        existing: WorkoutReplacementSummary,
        proposed: WorkoutReplacementSummary
    ) -> WorkoutReplacementPresentation {
        let day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(locale))
        let existingText = workoutDescription(existing)
        let proposedText = workoutDescription(proposed)

        switch self {
        case .en:
            return .init(
                title: "Replace scheduled workout?",
                message: "\(day) already has \(existingText). Replace it with \(proposedText)?",
                replaceAction: "Replace Workout",
                keepAction: "Keep Existing"
            )
        case .ja:
            return .init(
                title: "予定のワークアウトを置き換えますか？",
                message: "\(day)にはすでに\(existingText)があります。\(proposedText)に置き換えますか？",
                replaceAction: "置き換える",
                keepAction: "そのままにする"
            )
        case .vi:
            return .init(
                title: "Thay bài tập đã lên lịch?",
                message: "\(day) đã có \(existingText). Thay bằng \(proposedText)?",
                replaceAction: "Thay bài tập",
                keepAction: "Giữ bài hiện tại"
            )
        }
    }

    func replacementAppliedSummary(
        date: Date,
        existing: WorkoutReplacementSummary,
        proposed: WorkoutReplacementSummary
    ) -> String {
        let day = date.formatted(.dateTime.month().day().locale(locale))
        switch self {
        case .en: return "Replaced \(workoutDescription(existing)) with \(workoutDescription(proposed)) on \(day)."
        case .ja: return "\(day)の\(workoutDescription(existing))を\(workoutDescription(proposed))に置き換えました。"
        case .vi: return "Đã thay \(workoutDescription(existing)) bằng \(workoutDescription(proposed)) vào \(day)."
        }
    }

    func replacementSuccessMessage(date: Date, proposed: WorkoutReplacementSummary) -> String {
        let day = date.formatted(.dateTime.month().day().locale(locale))
        switch self {
        case .en: return "Your \(workoutDescription(proposed)) is scheduled for \(day)."
        case .ja: return "\(day)に\(workoutDescription(proposed))を予定しました。"
        case .vi: return "Đã lên lịch \(workoutDescription(proposed)) vào \(day)."
        }
    }

    private var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .ja: Locale(identifier: "ja_JP")
        case .vi: Locale(identifier: "vi_VN")
        }
    }

    private func workoutDescription(_ workout: WorkoutReplacementSummary) -> String {
        let distance = String(format: "%.1f km", workout.distanceKm)
        let kind: String
        switch (self, workout.kind) {
        case (.en, .easy): kind = "easy run"
        case (.en, .long): kind = "long run"
        case (.en, .tempo): kind = "tempo workout"
        case (.en, .intervals): kind = "interval workout"
        case (.en, .race): kind = "race"
        case (.ja, .easy): kind = "イージーラン"
        case (.ja, .long): kind = "ロングラン"
        case (.ja, .tempo): kind = "テンポ走"
        case (.ja, .intervals): kind = "インターバル"
        case (.ja, .race): kind = "レース"
        case (.vi, .easy): kind = "chạy dễ"
        case (.vi, .long): kind = "chạy dài"
        case (.vi, .tempo): kind = "bài tempo"
        case (.vi, .intervals): kind = "bài interval"
        case (.vi, .race): kind = "cuộc đua"
        }
        return "\(distance) \(kind)"
    }
}
