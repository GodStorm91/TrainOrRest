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
}
