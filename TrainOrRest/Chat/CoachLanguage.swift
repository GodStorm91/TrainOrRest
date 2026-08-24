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

    /// Copy-to-clipboard action under a chat bubble.
    var copyLabel: String {
        switch self {
        case .en: "Copy"
        case .ja: "コピー"
        case .vi: "Sao chép"
        }
    }

    /// Transient confirmation shown after copying.
    var copiedLabel: String {
        switch self {
        case .en: "Copied"
        case .ja: "コピーしました"
        case .vi: "Đã sao chép"
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

    var retryLabel: String {
        switch self {
        case .en: "Retry"
        case .ja: "再試行"
        case .vi: "Thử lại"
        }
    }

    var dismissErrorLabel: String {
        switch self {
        case .en: "Hide error notification"
        case .ja: "エラー通知を閉じる"
        case .vi: "Ẩn thông báo lỗi"
        }
    }

    var chatErrorAnnouncementPrefix: String {
        switch self {
        case .en: "Error notification"
        case .ja: "エラー通知"
        case .vi: "Thông báo lỗi"
        }
    }

    var retryingCoachErrorTitle: String {
        switch self {
        case .en: "Retrying Coach."
        case .ja: "コーチに再接続中です。"
        case .vi: "Đang thử lại Coach."
        }
    }

    var retryingCoachErrorMessage: String {
        switch self {
        case .en: "Keeping your chat and draft intact."
        case .ja: "チャット履歴と入力中の内容はそのままです。"
        case .vi: "Giữ nguyên lịch sử chat và nội dung đang nhập."
        }
    }

    var interruptedFailureTitle: String {
        switch self {
        case .en: "Response interrupted"
        case .ja: "返信が中断されました"
        case .vi: "Phản hồi bị gián đoạn"
        }
    }

    var interruptedFailureMessage: String {
        switch self {
        case .en: "The connection to Coach was interrupted.\nYour message and attached data are still safe."
        case .ja: "Coach との接続が中断されました。\n送信済みのメッセージとデータは保持されています。"
        case .vi: "Kết nối với Coach đã bị ngắt.\nTin nhắn và dữ liệu đã gửi vẫn được giữ nguyên."
        }
    }

    var retryingInlineTitle: String {
        switch self {
        case .en: "Retrying..."
        case .ja: "再試行中…"
        case .vi: "Đang thử lại…"
        }
    }

    var retryingInlineMessage: String {
        switch self {
        case .en: "Coach is processing your request again."
        case .ja: "Coach がもう一度リクエストを処理しています。"
        case .vi: "Coach đang xử lý lại yêu cầu của anh."
        }
    }

    var dismissInlineErrorLabel: String {
        switch self {
        case .en: "Dismiss"
        case .ja: "閉じる"
        case .vi: "Bỏ qua"
        }
    }

    var cancelRetryLabel: String {
        switch self {
        case .en: "Cancel"
        case .ja: "キャンセル"
        case .vi: "Hủy"
        }
    }

    var incompleteResponseLabel: String {
        switch self {
        case .en: "Incomplete response"
        case .ja: "未完了の返信"
        case .vi: "Phản hồi chưa hoàn tất"
        }
    }

    var missingAttachmentFailureTitle: String {
        switch self {
        case .en: "Cannot retry with old data"
        case .ja: "古いデータでは再試行できません"
        case .vi: "Không thể thử lại với dữ liệu cũ"
        }
    }

    var missingAttachmentFailureMessage: String {
        switch self {
        case .en: "The attached health data is no longer available."
        case .ja: "添付されたヘルスデータはもう利用できません。"
        case .vi: "Dữ liệu sức khỏe đính kèm không còn khả dụng."
        }
    }

    var chooseDataAgainLabel: String {
        switch self {
        case .en: "Choose data again"
        case .ja: "データを選び直す"
        case .vi: "Chọn lại dữ liệu"
        }
    }

    var authenticationFailureMessage: String {
        switch self {
        case .en: "Coach needs permission again. Check Settings before retrying."
        case .ja: "Coach の権限を確認してください。設定を確認してから再試行してください。"
        case .vi: "Coach cần kiểm tra lại kết nối. Vào Cài đặt rồi thử lại."
        }
    }

    var checkConnectionLabel: String {
        switch self {
        case .en: "Check connection"
        case .ja: "接続を確認"
        case .vi: "Kiểm tra kết nối"
        }
    }

    var mutationReconciliationTitle: String {
        switch self {
        case .en: "Update confirmation missing"
        case .ja: "更新確認を受信できませんでした"
        case .vi: "Chưa nhận được xác nhận cập nhật"
        }
    }

    var mutationReconciliationMessage: String {
        switch self {
        case .en: "Coach is checking whether the change was applied."
        case .ja: "変更が適用済みか Coach が確認しています。"
        case .vi: "Coach đang kiểm tra xem thay đổi đã được áp dụng hay chưa."
        }
    }

    var checkStatusLabel: String {
        switch self {
        case .en: "Check status"
        case .ja: "状態を確認"
        case .vi: "Kiểm tra trạng thái"
        }
    }

    var olderFailureRetryMessage: String {
        switch self {
        case .en: "This failed turn is no longer the latest message. Start a new branch from here to retry safely."
        case .ja: "この失敗した返信の後に新しいメッセージがあります。安全に再試行するにはここから新しい分岐を作ってください。"
        case .vi: "Lượt lỗi này không còn là tin nhắn mới nhất. Muốn thử lại an toàn thì tạo nhánh mới từ đây."
        }
    }

    func missingCoachKeyError(provider: String) -> String {
        switch self {
        case .en: "Add your \(provider) API key in Settings first."
        case .ja: "先に設定で\(provider) APIキーを追加してください。"
        case .vi: "Thêm API key \(provider) trong Cài đặt trước."
        }
    }

    func chatErrorCopy(for rawMessage: String) -> (title: String, message: String) {
        let lower = rawMessage.lowercased()
        if lower.contains("connection") || lower.contains("offline") || lower.contains("network") || lower.contains("internet") || lower.contains("mất kết nối") || lower.contains("gián đoạn") {
            switch self {
            case .en:
                return ("The connection to Coach was interrupted.", "Your chat history is safe.")
            case .ja:
                return ("コーチとの接続が中断されました。", "チャット履歴は安全です。")
            case .vi:
                return ("Kết nối với Coach bị gián đoạn.", "Lịch sử chat của bạn vẫn an toàn.")
            }
        }
        if lower.contains("rate limit") || lower.contains("rate limited") || lower.contains("too many") {
            switch self {
            case .en:
                return ("Coach is receiving too many requests right now.", "Wait a moment, then try again.")
            case .ja:
                return ("現在コーチへのリクエストが混み合っています。", "少し待ってからもう一度お試しください。")
            case .vi:
                return ("Coach đang nhận quá nhiều yêu cầu.", "Chờ một chút rồi thử lại.")
            }
        }
        if lower.contains("api key") || lower.contains("key") || lower.contains("rejected") {
            switch self {
            case .en:
                return ("Coach needs a valid API key.", "Check Settings, then try again.")
            case .ja:
                return ("有効なAPIキーが必要です。", "設定を確認してからもう一度お試しください。")
            case .vi:
                return ("Coach cần API key hợp lệ.", "Kiểm tra Cài đặt rồi thử lại.")
            }
        }
        switch self {
        case .en:
            return ("Coach could not finish that response.", "Your chat history is safe.")
        case .ja:
            return ("コーチの返信を完了できませんでした。", "チャット履歴は安全です。")
        case .vi:
            return ("Coach chưa hoàn tất được câu trả lời.", "Lịch sử chat của bạn vẫn an toàn.")
        }
    }

    // MARK: - Plan update card

    /// Eyebrow above the proposed change.
    var planUpdateTitle: String {
        switch self {
        case .en: "PLAN UPDATED"
        case .ja: "プラン更新"
        case .vi: "KẾ HOẠCH CẬP NHẬT"
        }
    }

    /// Badge on the workout that would take the day.
    var planUpdateNewBadge: String {
        switch self {
        case .en: "NEW"
        case .ja: "新規"
        case .vi: "MỚI"
        }
    }

    /// Primary action on the card.
    var applyChangesLabel: String {
        switch self {
        case .en: "Apply changes"
        case .ja: "変更を適用"
        case .vi: "Áp dụng thay đổi"
        }
    }

    /// Dismissing action, named after the workout the day already holds.
    func keepExistingLabel(_ kind: WorkoutKind) -> String {
        switch self {
        case .en: "Keep \(shortKindName(kind))"
        case .ja: "\(shortKindName(kind))のまま"
        case .vi: "Giữ \(shortKindName(kind))"
        }
    }

    /// Third action on the card; also the text prefilled into the composer.
    var whySwapPrompt: String {
        switch self {
        case .en: "Why the swap?"
        case .ja: "なぜ入れ替えるの？"
        case .vi: "Vì sao lại đổi?"
        }
    }

    /// One row of the card, e.g. "Tempo run · 8 km".
    func workoutRowText(_ workout: WorkoutReplacementSummary) -> String {
        "\(kindName(workout.kind)) · \(distanceText(workout.distanceKm))"
    }

    /// The real change to the week's target volume — never a projected ACWR,
    /// which the app does not compute for future plan changes.
    func weeklyVolumeDeltaText(_ deltaKm: Double) -> String {
        guard abs(deltaKm) >= 0.05 else {
            switch self {
            case .en: return "Weekly volume unchanged"
            case .ja: return "週間走行距離は変わりません"
            case .vi: return "Khối lượng tuần không đổi"
            }
        }
        let signed = "\(deltaKm > 0 ? "+" : "−")\(distanceText(abs(deltaKm)))"
        switch self {
        case .en: return "Projected weekly volume \(signed)"
        case .ja: return "週間走行距離の見込み \(signed)"
        case .vi: return "Khối lượng tuần dự kiến \(signed)"
        }
    }

    /// Bare kind word, for reading inside a sentence ("Keep tempo").
    private func shortKindName(_ kind: WorkoutKind) -> String {
        switch (self, kind) {
        case (.en, .easy): "easy"
        case (.en, .long): "the long run"
        case (.en, .tempo): "tempo"
        case (.en, .threshold): "threshold"
        case (.en, .intervals): "intervals"
        case (.en, .race): "the race"
        case (.ja, _): kindName(kind)
        case (.vi, _): kindName(kind).lowercased()
        }
    }

    private func kindName(_ kind: WorkoutKind) -> String {
        switch (self, kind) {
        case (.en, .easy): "Easy run"
        case (.en, .long): "Long run"
        case (.en, .tempo): "Tempo run"
        case (.en, .threshold): "Threshold run"
        case (.en, .intervals): "Intervals"
        case (.en, .race): "Race"
        case (.ja, .easy): "イージーラン"
        case (.ja, .long): "ロングラン"
        case (.ja, .tempo): "テンポ走"
        case (.ja, .threshold): "閾値走"
        case (.ja, .intervals): "インターバル"
        case (.ja, .race): "レース"
        case (.vi, .easy): "Chạy dễ"
        case (.vi, .long): "Chạy dài"
        case (.vi, .tempo): "Bài tempo"
        case (.vi, .threshold): "Bài threshold"
        case (.vi, .intervals): "Bài interval"
        case (.vi, .race): "Cuộc đua"
        }
    }

    /// Drops a trailing ".0" so a whole number reads "8 km", not "8.0 km".
    private func distanceText(_ km: Double) -> String {
        let rounded = (km * 10).rounded() / 10
        let value = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return "\(value) km"
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
        case (.en, .threshold): kind = "threshold workout"
        case (.en, .intervals): kind = "interval workout"
        case (.en, .race): kind = "race"
        case (.ja, .easy): kind = "イージーラン"
        case (.ja, .long): kind = "ロングラン"
        case (.ja, .tempo): kind = "テンポ走"
        case (.ja, .threshold): kind = "閾値走"
        case (.ja, .intervals): kind = "インターバル"
        case (.ja, .race): kind = "レース"
        case (.vi, .easy): kind = "chạy dễ"
        case (.vi, .long): kind = "chạy dài"
        case (.vi, .tempo): kind = "bài tempo"
        case (.vi, .threshold): kind = "bài threshold"
        case (.vi, .intervals): kind = "bài interval"
        case (.vi, .race): kind = "cuộc đua"
        }
        return "\(distance) \(kind)"
    }
}
