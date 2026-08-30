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

    var nextSuggestionsLabel: String {
        switch self {
        case .en: "NEXT SUGGESTIONS"
        case .ja: "次の提案"
        case .vi: "GỢI Ý TIẾP THEO"
        }
    }

    var choiceDefaultTitle: String {
        switch self {
        case .en: "Choose next step"
        case .ja: "次のステップを選択"
        case .vi: "Chọn bước tiếp theo"
        }
    }

    var choiceOtherLabel: String {
        switch self {
        case .en: "Other request..."
        case .ja: "別のリクエスト…"
        case .vi: "Yêu cầu khác…"
        }
    }

    var choiceOtherPlaceholder: String {
        switch self {
        case .en: "How would you like Coach to adjust?"
        case .ja: "Coach にどう調整してほしいですか？"
        case .vi: "Bạn muốn Coach điều chỉnh như thế nào?"
        }
    }

    func choiceResolvedSelectedLabel(option: String) -> String {
        switch self {
        case .en: "Selected: \(option)"
        case .ja: "選択済み: \(option)"
        case .vi: "Đã chọn: \(option)"
        }
    }

    var choiceResolvedOtherLabel: String {
        switch self {
        case .en: "Answered with another request"
        case .ja: "別のリクエストで回答済み"
        case .vi: "Đã trả lời bằng yêu cầu khác"
        }
    }

    var choiceDisabledAccessibilitySuffix: String {
        switch self {
        case .en: "Disabled"
        case .ja: "無効"
        case .vi: "Đã tắt"
        }
    }

    var choiceSelectedAccessibilitySuffix: String {
        switch self {
        case .en: "Selected"
        case .ja: "選択済み"
        case .vi: "Đã chọn"
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

    var genericProcessingLabel: String {
        switch self {
        case .en: "Coach is analyzing..."
        case .ja: "Coach が分析中…"
        case .vi: "Coach đang phân tích…"
        }
    }

    var stillProcessingLabel: String {
        switch self {
        case .en: "Still processing data..."
        case .ja: "まだデータを処理中…"
        case .vi: "Vẫn đang xử lý dữ liệu…"
        }
    }

    var continueAnswerLabel: String {
        switch self {
        case .en: "Continue answer"
        case .ja: "回答の続きを見る"
        case .vi: "Tiếp tục câu trả lời"
        }
    }

    var expandDetailsLabel: String {
        switch self {
        case .en: "View detailed analysis"
        case .ja: "詳しい分析を見る"
        case .vi: "Xem phân tích chi tiết"
        }
    }

    var collapseDetailsLabel: String {
        switch self {
        case .en: "Collapse"
        case .ja: "閉じる"
        case .vi: "Thu gọn"
        }
    }

    var responseStartedAnnouncement: String {
        switch self {
        case .en: "Coach started responding."
        case .ja: "Coach の返信が始まりました。"
        case .vi: "Coach bắt đầu trả lời."
        }
    }

    var responseCompleteAnnouncement: String {
        switch self {
        case .en: "Coach response complete."
        case .ja: "Coach の返信が完了しました。"
        case .vi: "Coach đã trả lời xong."
        }
    }

    var cancelledLabel: String {
        switch self {
        case .en: "Stopped"
        case .ja: "停止しました"
        case .vi: "Đã dừng"
        }
    }

    func processingLabel(for stage: CoachProcessingStage?) -> String {
        guard let stage else { return genericProcessingLabel }
        switch (self, stage) {
        case (.en, .preparingContext): return "Preparing data..."
        case (.ja, .preparingContext): return "データを準備中…"
        case (.vi, .preparingContext): return "Đang chuẩn bị dữ liệu…"
        case (.en, .readingTrainingPlan): return "Reading the current plan..."
        case (.ja, .readingTrainingPlan): return "現在の計画を確認中…"
        case (.vi, .readingTrainingPlan): return "Đang đọc kế hoạch hiện tại…"
        case (.en, .comparingWithGoal): return "Comparing with the race goal..."
        case (.ja, .comparingWithGoal): return "レース目標と比較中…"
        case (.vi, .comparingWithGoal): return "Đang so sánh với mục tiêu cuộc đua…"
        case (.en, .checkingTrainingLoad): return "Checking training load..."
        case (.ja, .checkingTrainingLoad): return "トレーニング負荷を確認中…"
        case (.vi, .checkingTrainingLoad): return "Đang kiểm tra tải tập…"
        case (.en, .checkingRecovery): return "Checking recovery..."
        case (.ja, .checkingRecovery): return "回復状態を確認中…"
        case (.vi, .checkingRecovery): return "Đang kiểm tra mức hồi phục…"
        case (.en, .reviewingUpcomingWorkouts): return "Reviewing upcoming workouts..."
        case (.ja, .reviewingUpcomingWorkouts): return "今後の練習を確認中…"
        case (.vi, .reviewingUpcomingWorkouts): return "Đang xem các buổi tập sắp tới…"
        case (.en, .buildingRecommendation): return "Building the recommendation..."
        case (.ja, .buildingRecommendation): return "提案を作成中…"
        case (.vi, .buildingRecommendation): return "Đang chuẩn bị đề xuất điều chỉnh…"
        case (.en, .finalizing): return "Finalizing the response..."
        case (.ja, .finalizing): return "回答を仕上げ中…"
        case (.vi, .finalizing): return "Đang hoàn thiện câu trả lời…"
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

    func goalAssessmentText(_ key: GoalAssessmentLabelKey, value: Int? = nil) -> String {
        switch (self, key) {
        case (_, .raceGoal): return self == .vi ? "MỤC TIÊU CUỘC ĐUA" : self == .ja ? "レース目標" : "RACE GOAL"
        case (_, .goalConfidence): return self == .vi ? "Khả năng đạt mục tiêu" : self == .ja ? "目標達成見込み" : "Goal confidence"
        case (_, .goalAlignment): return self == .vi ? "Mức độ bám mục tiêu" : self == .ja ? "目標との整合度" : "Goal alignment"
        case (_, .targetTime): return self == .vi ? "Thời gian mục tiêu" : self == .ja ? "目標タイム" : "Target time"
        case (_, .currentPrediction): return self == .vi ? "Dự đoán hiện tại" : self == .ja ? "現在の予測" : "Current prediction"
        case (_, .targetGap): return self == .vi ? "Cách mục tiêu" : self == .ja ? "目標との差" : "Gap to target"
        case (_, .goalStatus): return self == .vi ? "Trạng thái" : self == .ja ? "状態" : "Status"
        case (_, .planAndActual): return self == .vi ? "Kế hoạch và thực tế" : self == .ja ? "計画と実績" : "Plan vs actual"
        case (_, .planned): return self == .vi ? "Kế hoạch" : self == .ja ? "計画" : "Planned"
        case (_, .actual): return self == .vi ? "Thực tế" : self == .ja ? "実績" : "Actual"
        case (_, .currentWeek): return self == .vi ? "Tuần hiện tại" : self == .ja ? "今週" : "Current week"
        case (_, .completedVolume): return self == .vi ? "Khối lượng hoàn thành" : self == .ja ? "完了量" : "Completed volume"
        case (_, .latestLongRun): return self == .vi ? "Long run gần nhất" : self == .ja ? "直近ロングラン" : "Latest long run"
        case (_, .adjustPlan): return self == .vi ? "Điều chỉnh kế hoạch" : self == .ja ? "計画を調整" : "Adjust plan"
        case (_, .assessmentMethod): return self == .vi ? "Xem cách đánh giá" : self == .ja ? "評価方法を見る" : "View assessment method"
        case (_, .planAdjustmentProposal): return self == .vi ? "Đề xuất điều chỉnh kế hoạch" : self == .ja ? "計画調整案" : "Plan adjustment proposal"
        case (_, .applyChanges): return self == .vi ? "Áp dụng \(value ?? 0) thay đổi" : self == .ja ? "\(value ?? 0)件の変更を適用" : "Apply \(value ?? 0) changes"
        case (_, .keepCurrentPlan): return self == .vi ? "Giữ kế hoạch hiện tại" : self == .ja ? "現在の計画を維持" : "Keep current plan"
        case (_, .insufficientPrediction): return self == .vi ? "Chưa đủ dữ liệu để dự đoán" : self == .ja ? "予測にはデータが不足しています" : "Not enough data to predict"
        case (_, .onTrack): return self == .vi ? "Đúng tiến độ" : self == .ja ? "順調" : "On track"
        case (_, .adjustmentRecommended): return self == .vi ? "Có thể đạt, nhưng cần điều chỉnh" : self == .ja ? "達成可能、ただし調整が必要" : "Reachable, but adjust now"
        case (_, .atRisk): return self == .vi ? "Có nguy cơ không đạt" : self == .ja ? "達成リスクあり" : "At risk"
        case (_, .insufficientData): return self == .vi ? "Chưa đủ dữ liệu" : self == .ja ? "データ不足" : "Insufficient data"
        case (_, .onTrackSummary): return self == .vi ? "Các buổi tập chính và tải tập hiện tại đang phù hợp với mục tiêu của bạn." : self == .ja ? "主要な練習と現在の負荷は目標に合っています。" : "Key workouts and current training load are aligned with your goal."
        case (_, .adjustmentSummary): return self == .vi ? "Đánh giá giảm chủ yếu do một yếu tố tập luyện chưa theo kịp kế hoạch." : self == .ja ? "主な要因の遅れにより評価が下がっています。" : "The assessment is down mainly because one training factor is behind plan."
        case (_, .atRiskSummary): return self == .vi ? "Một tín hiệu quan trọng đang kéo mục tiêu ra xa hơn. Nên xem lại kế hoạch trước buổi tập kế tiếp." : self == .ja ? "重要なシグナルが目標達成を難しくしています。次の練習前に見直しましょう。" : "A key signal is pulling the goal further away. Review the plan before the next workout."
        case (_, .insufficientDataSummary): return self == .vi ? "Hoàn thành thêm 2-3 buổi chạy có nhịp tim để RestOrTrain đánh giá chính xác hơn." : self == .ja ? "心拍付きのランをあと2-3回完了すると、より正確に評価できます。" : "Complete 2-3 more runs with heart-rate data so RestOrTrain can assess this more accurately."
        case (_, .planAdherence): return self == .vi ? "Mức độ bám kế hoạch" : self == .ja ? "計画遵守" : "Plan adherence"
        case (_, .keyWorkout): return self == .vi ? "Buổi tập trọng điểm" : self == .ja ? "重要練習" : "Key workout"
        case (_, .longRunProgression): return self == .vi ? "Sức bền đường dài" : self == .ja ? "ロングラン進捗" : "Long-run progression"
        case (_, .trainingLoad): return self == .vi ? "Tải tập luyện" : self == .ja ? "トレーニング負荷" : "Training load"
        case (_, .recovery): return self == .vi ? "Hồi phục" : self == .ja ? "回復" : "Recovery"
        case (_, .trainingConsistency): return self == .vi ? "Tính ổn định tập luyện" : self == .ja ? "練習の一貫性" : "Training consistency"
        case (_, .timeRemaining): return self == .vi ? "Thời gian còn lại" : self == .ja ? "残り時間" : "Time remaining"
        case (_, .dataQuality): return self == .vi ? "Chất lượng dữ liệu" : self == .ja ? "データ品質" : "Data quality"
        case (_, .good): return self == .vi ? "Tốt" : self == .ja ? "良好" : "Good"
        case (_, .stable): return self == .vi ? "Ổn định" : self == .ja ? "安定" : "Stable"
        case (_, .needsAdjustment): return self == .vi ? "Cần điều chỉnh" : self == .ja ? "調整が必要" : "Needs adjustment"
        case (_, .highRisk): return self == .vi ? "Rủi ro cao" : self == .ja ? "高リスク" : "High risk"
        case (_, .unknown): return self == .vi ? "Chưa rõ" : self == .ja ? "不明" : "Unknown"
        case (_, .mostImportantAdjustment): return self == .vi ? "Điểm cần điều chỉnh quan trọng nhất" : self == .ja ? "最も重要な調整点" : "Most important adjustment"
        case (_, .evidence): return self == .vi ? "Bằng chứng" : self == .ja ? "根拠" : "Evidence"
        case (_, .impact): return self == .vi ? "Tác động" : self == .ja ? "影響" : "Impact"
        case (_, .action): return self == .vi ? "Hành động tiếp theo" : self == .ja ? "次の行動" : "Next action"
        case (_, .why): return self == .vi ? "Vì sao?" : self == .ja ? "理由" : "Why?"
        case (_, .whyMetric): return self == .vi ? "Vì sao \(value ?? 0)%?" : self == .ja ? "\(value ?? 0)% の理由" : "Why \(value ?? 0)%?"
        case (_, .metricMeaning): return self == .vi ? "Ý nghĩa của chỉ số" : self == .ja ? "指標の意味" : "What this metric means"
        case (_, .metricDataUsed): return self == .vi ? "Dữ liệu đã dùng" : self == .ja ? "使用データ" : "Data used"
        case (_, .metricCalculatedAt): return self == .vi ? "Lần tính gần nhất" : self == .ja ? "最終計算" : "Last calculated"
        case (_, .metricFactors): return self == .vi ? "Yếu tố làm tăng hoặc giảm điểm" : self == .ja ? "増減要因" : "Factors that moved it"
        case (_, .metricEstimateCaveat): return self == .vi ? "Đây là ước tính từ dữ liệu tập luyện, không phải kết quả cuộc đua được đảm bảo." : self == .ja ? "これは練習データからの推定であり、レース結果を保証しません。" : "This is an estimate from training data, not a guaranteed race result."
        case (_, .metricAlignmentExplanation): return self == .vi ? "Điểm heuristic 0-100 cho biết kế hoạch, khối lượng, buổi trọng điểm và dữ liệu thể lực hiện tại đang bám mục tiêu đến đâu." : self == .ja ? "計画、負荷、重要練習、現在のフィットネスデータが目標にどれだけ合っているかを示す0-100のヒューリスティックです。" : "A 0-100 heuristic score showing how plan adherence, volume, key sessions, and current fitness data align with the goal."
        case (_, .metricProbabilityExplanation): return self == .vi ? "Xác suất đã hiệu chuẩn từ mô hình dự đoán mục tiêu." : self == .ja ? "校正済みモデルによる目標達成確率です。" : "A calibrated probability from a validated goal-prediction model."
        case (_, .viewRecommendation): return self == .vi ? "Xem đề xuất điều chỉnh" : self == .ja ? "調整案を見る" : "View recommendation"
        case (_, .viewMoreItems): return self == .vi ? "Xem thêm \(value ?? 0) điểm" : self == .ja ? "他 \(value ?? 0) 件を見る" : "View \(value ?? 0) more"
        case (_, .remainingPlan): return self == .vi ? "8 tuần còn lại" : self == .ja ? "残り8週間" : "Remaining plan"
        case (_, .currentTrainingPlan): return self == .vi ? "Kế hoạch hiện tại" : self == .ja ? "現在の計画" : "Current training plan"
        case (_, .healthData): return self == .vi ? "Dữ liệu sức khỏe" : self == .ja ? "健康データ" : "Health data"
        case (_, .weeklyVolumeBehindTitle): return self == .vi ? "Tải tập tuần này chưa theo kịp kế hoạch" : self == .ja ? "今週の負荷が計画より遅れています" : "This week's training load is behind plan"
        case (_, .missedKeyWorkoutTitle): return self == .vi ? "Buổi tập trọng điểm chưa hoàn thành" : self == .ja ? "重要練習が未完了です" : "Key workout not completed"
        case (_, .missedSessionsTitle): return self == .vi ? "Tính ổn định tập luyện đang giảm" : self == .ja ? "練習の一貫性が下がっています" : "Training consistency is slipping"
        case (_, .longRunBehindTitle): return self == .vi ? "Sức bền đường dài chưa theo kịp kế hoạch" : self == .ja ? "ロングラン耐久力が計画より遅れています" : "Long-run endurance is behind plan"
        case (_, .dataMissingTitle): return self == .vi ? "Thiếu dữ liệu để đánh giá chính xác" : self == .ja ? "正確な評価にはデータが不足しています" : "More data needed for a reliable assessment"
        case (_, .volumeBehindImpact): return self == .vi ? "Tải tập thấp hơn kế hoạch làm giảm độ tin cậy của tiến trình hiện tại." : self == .ja ? "計画より低い負荷が現在の進捗評価を下げています。" : "Lower-than-planned load reduces confidence in the current progression."
        case (_, .missedKeyImpact): return self == .vi ? "Buổi tập trọng điểm là tín hiệu race-specific quan trọng nhất trong tuần." : self == .ja ? "重要練習は今週のレース特化シグナルです。" : "Key workouts are the most important race-specific signal this week."
        case (_, .missedSessionsImpact): return self == .vi ? "Bỏ lỡ nhiều buổi khiến kế hoạch mất nhịp và làm giảm mức độ bám mục tiêu." : self == .ja ? "複数の未完了練習が計画のリズムを崩し、目標整合度を下げます。" : "Missed sessions disrupt the plan rhythm and lower goal alignment."
        case (_, .longRunBehindImpact): return self == .vi ? "Đây là yếu tố ảnh hưởng lớn nhất đến đánh giá hiện tại." : self == .ja ? "これは現在の評価に最も大きく影響している要因です。" : "This is the largest factor in the current assessment."
        case (_, .dataMissingImpact): return self == .vi ? "RestOrTrain chưa có đủ lịch sử chạy để tách tín hiệu thật khỏi nhiễu dữ liệu." : self == .ja ? "実際のシグナルとデータノイズを分けるには履歴が不足しています。" : "RestOrTrain does not yet have enough run history to separate real signal from noise."
        case (_, .qualitativeLargestImpact): return self == .vi ? "Đây là yếu tố ảnh hưởng lớn nhất đến đánh giá hiện tại." : self == .ja ? "これは現在の評価に最も影響しています。" : "This is the largest factor in the current assessment."
        case (_, .completedRunsSource): return self == .vi ? "Buổi chạy đã hoàn thành" : self == .ja ? "完了したラン" : "Completed runs"
        case (_, .plannedWorkoutsSource): return self == .vi ? "Buổi tập trong kế hoạch" : self == .ja ? "計画済み練習" : "Planned workouts"
        case (_, .fitnessEstimateSource): return self == .vi ? "Ước tính thể lực" : self == .ja ? "フィットネス推定" : "Fitness estimate"
        case (_, .noAttention): return self == .vi ? "Không có điểm cần xử lý ngay." : self == .ja ? "今すぐ対応が必要な項目はありません。" : "Nothing needs action right now."
        }
    }

    // MARK: - Chat screen chrome

    var backToCalendarLabel: String { self == .vi ? "Quay lại Lịch" : self == .ja ? "カレンダーに戻る" : "Back to Calendar" }
    var openMenuLabel: String { self == .vi ? "Mở menu" : self == .ja ? "メニューを開く" : "Open menu" }
    var coachOptionsLabel: String { self == .vi ? "Tùy chọn Coach" : self == .ja ? "Coach のオプション" : "Coach options" }
    var newConversationLabel: String { self == .vi ? "Cuộc trò chuyện mới" : self == .ja ? "新しい会話" : "New conversation" }
    var chatHistoryLabel: String { self == .vi ? "Lịch sử trò chuyện" : self == .ja ? "会話履歴" : "Chat history" }
    var settingsLabel: String { self == .vi ? "Cài đặt" : self == .ja ? "設定" : "Settings" }

    var editingWorkoutStatus: String { self == .vi ? "Đang chỉnh buổi tập" : self == .ja ? "ワークアウトを編集中" : "Editing workout" }
    var reviewWithCoachStatus: String { self == .vi ? "Xem lại cùng Coach" : self == .ja ? "Coach と振り返り" : "Reviewing with Coach" }
    func dataUpdatedAt(_ time: String) -> String { self == .vi ? "Dữ liệu cập nhật lúc \(time)" : self == .ja ? "データ更新 \(time)" : "Data updated at \(time)" }

    var viewWorkoutDetailsLabel: String { self == .vi ? "Xem chi tiết buổi tập" : self == .ja ? "ワークアウトの詳細を見る" : "View workout details" }
    var openWorkoutDetailsLabel: String { self == .vi ? "Mở chi tiết buổi tập" : self == .ja ? "ワークアウトの詳細を開く" : "Open workout details" }

    var viewTodayPlanLabel: String { self == .vi ? "Xem kế hoạch hôm nay" : self == .ja ? "今日のプランを見る" : "View today's plan" }

    func todayReadinessTitle(_ verdict: ReadinessVerdict?) -> String {
        switch verdict {
        case .train: return self == .vi ? "Hôm nay: Sẵn sàng tập luyện" : self == .ja ? "今日: トレーニング可能" : "Today: Ready to train"
        case .goEasy: return self == .vi ? "Hôm nay: Nên tập nhẹ" : self == .ja ? "今日: 軽めに" : "Today: Take it easy"
        case .rest: return self == .vi ? "Hôm nay: Ưu tiên phục hồi" : self == .ja ? "今日: 回復を優先" : "Today: Prioritize recovery"
        case .insufficientData: return self == .vi ? "Hôm nay: Đang xây baseline" : self == .ja ? "今日: ベースライン構築中" : "Today: Building baseline"
        case .none: return self == .vi ? "Hôm nay: Đang cập nhật" : self == .ja ? "今日: 更新中" : "Today: Updating"
        }
    }
    var noReadinessSubtitle: String { self == .vi ? "Chưa có verdict mới nhất từ dữ liệu sức khỏe." : self == .ja ? "健康データからの最新判定はまだありません。" : "No latest verdict from health data yet." }
    var goodRecoverySubtitle: String { self == .vi ? "Phục hồi tốt · Chưa có dấu hiệu quá tải" : self == .ja ? "回復良好 · 過負荷の兆候なし" : "Good recovery · No overload signs" }
    var noPlannedWorkoutTodayText: String { self == .vi ? "Không có bài dự kiến hôm nay" : self == .ja ? "今日の予定練習はありません" : "No planned workout today" }
    var plannedWorkoutPrefix: String { self == .vi ? "Bài dự kiến: " : self == .ja ? "予定: " : "Planned: " }

    var healthDataChipLabel: String { self == .vi ? "Dữ liệu sức khỏe" : self == .ja ? "ヘルスデータ" : "Health data" }
    var latestWorkoutChipLabel: String { self == .vi ? "Buổi tập gần nhất" : self == .ja ? "最新のワークアウト" : "Latest workout" }
    var imageChipLabel: String { self == .vi ? "Ảnh" : self == .ja ? "画像" : "Image" }
    func removeAttachmentLabel(_ title: String) -> String { self == .vi ? "Xóa \(title)" : self == .ja ? "\(title)を削除" : "Remove \(title)" }
    var attachImageLabel: String { self == .vi ? "Đính kèm hình ảnh" : self == .ja ? "画像を添付" : "Attach image" }
    var workoutMenuLabel: String { self == .vi ? "Buổi tập" : self == .ja ? "ワークアウト" : "Workout" }
    var savedQuestionsLabel: String { self == .vi ? "Câu hỏi đã lưu" : self == .ja ? "保存した質問" : "Saved questions" }
    var openSavedQuestionsLabel: String { self == .vi ? "Mở câu hỏi đã lưu" : self == .ja ? "保存した質問を開く" : "Open saved questions" }
    var removeImageLabel: String { self == .vi ? "Xóa ảnh" : self == .ja ? "画像を削除" : "Remove image" }
    var addContentLabel: String { self == .vi ? "Thêm nội dung" : self == .ja ? "コンテンツを追加" : "Add content" }
    var attachEvidenceLabel: String { self == .vi ? "Đính kèm dữ liệu" : self == .ja ? "根拠を添付" : "Attach evidence" }
    var hideKeyboardLabel: String { self == .vi ? "Ẩn bàn phím" : self == .ja ? "キーボードを閉じる" : "Hide keyboard" }
    var sendMessageLabel: String { self == .vi ? "Gửi tin nhắn" : self == .ja ? "メッセージを送信" : "Send message" }

    var apiKeyNeededTitle: String { self == .vi ? "Cần API key" : self == .ja ? "APIキーが必要です" : "API key needed" }
    func apiKeyNeededMessage(provider: String) -> String { self == .vi ? "Thêm API key \(provider) trước khi trò chuyện." : self == .ja ? "チャットの前に\(provider) APIキーを追加してください。" : "Add a \(provider) API key before chatting." }
    var addApiKeyLabel: String { self == .vi ? "Thêm API key" : self == .ja ? "APIキーを追加" : "Add API key" }

    var openingPrompts: [String] {
        switch self {
        case .en: return ["Why train or rest today?", "Review my latest workout", "Adjust this week's plan"]
        case .ja: return ["今日は練習すべき？休むべき？", "最近のワークアウトを振り返って", "今週の計画を調整したい"]
        case .vi: return ["Hôm nay nên tập hay nghỉ?", "Xem lại buổi tập gần nhất", "Điều chỉnh kế hoạch tuần này"]
        }
    }
    var savedPrompts: [String] {
        switch self {
        case .en: return ["What should I train today?", "How is my training load this week?", "How can I recover faster?", "Should I add intensity next session?"]
        case .ja: return ["今日は何を練習すべき？", "今週のトレーニング負荷はどう？", "もっと早く回復するには？", "次回は強度を上げるべき？"]
        case .vi: return ["Hôm nay tôi nên tập gì?", "Tải tập tuần này của tôi thế nào?", "Làm sao để phục hồi nhanh hơn?", "Buổi sau có nên tăng cường độ không?"]
        }
    }
    var chooseRecentWorkoutPrompt: String { self == .vi ? "Chọn buổi tập gần nhất để Coach phân tích" : self == .ja ? "Coach に分析してもらう最近のワークアウトを選ぶ" : "Choose a recent workout for Coach to analyze" }

    var matchedWorkoutLabel: String { self == .vi ? "BÀI TẬP KHỚP" : self == .ja ? "一致するワークアウト" : "MATCHED WORKOUT" }
    var noTomorrowWorkoutSuggestion: String { self == .vi ? "Ngày mai chưa có bài trong lịch. Tạo một buổi tập mới cho ngày mai?" : self == .ja ? "明日の予定はまだありません。明日のワークアウトを作成しますか？" : "Nothing scheduled for tomorrow yet. Create a new workout for tomorrow?" }
    func changeTomorrowDistanceSuggestion(workout: String, distance: String) -> String { self == .vi ? "Đổi buổi training ngày mai (\(workout)) thành \(distance), giữ cùng loại bài nếu an toàn." : self == .ja ? "明日のワークアウト（\(workout)）を\(distance)に変更し、安全なら同じ種類を維持して。" : "Change tomorrow's workout (\(workout)) to \(distance), keeping the same type if safe." }
    func findTimeTomorrowSuggestion(workout: String) -> String { self == .vi ? "Tìm giờ tốt cho buổi training ngày mai (\(workout))." : self == .ja ? "明日のワークアウト（\(workout)）に良い時間を見つけて。" : "Find a good time for tomorrow's workout (\(workout))." }
    func moveTomorrowSuggestion(workout: String) -> String { self == .vi ? "Cập nhật lịch cho buổi training ngày mai (\(workout))." : self == .ja ? "明日のワークアウト（\(workout)）の予定を更新して。" : "Update the schedule for tomorrow's workout (\(workout))." }
    func updateTomorrowSuggestion(workout: String) -> String { self == .vi ? "Ngày mai có \(workout). Anh muốn cập nhật buổi này thế nào?" : self == .ja ? "明日は\(workout)です。どのように更新しますか？" : "Tomorrow has \(workout). How would you like to update it?" }

    func workoutContextLabel(title: String, date: String) -> String { self == .vi ? "Bối cảnh buổi tập: \(title), \(date)" : self == .ja ? "ワークアウトの文脈: \(title)、\(date)" : "Workout context: \(title), \(date)" }
    func fixedWorkoutContextLabel(title: String) -> String { self == .vi ? "Bối cảnh buổi tập cố định: \(title)" : self == .ja ? "固定のワークアウト文脈: \(title)" : "Fixed workout context: \(title)" }

    func contextSourceCountLabel(count: Int) -> String {
        self == .vi ? "\(count) nguồn" : self == .ja ? "\(count) 件のデータ" : count == 1 ? "1 source" : "\(count) sources"
    }
    var contextSourcesSheetTitle: String {
        self == .vi ? "Nguồn dữ liệu" : self == .ja ? "データソース" : "Data sources"
    }

    var dataSourcesUsedTitle: String { self == .vi ? "Nguồn dữ liệu đã sử dụng" : self == .ja ? "使用したデータソース" : "Data sources used" }
    var additionalRecommendationsTitle: String { self == .vi ? "Khuyến nghị bổ sung" : self == .ja ? "追加の推奨事項" : "Additional recommendations" }
    var verifiedPlanUpdateLabel: String { self == .vi ? "Đã kiểm tra và cập nhật kế hoạch" : self == .ja ? "計画を確認して更新しました" : "Plan checked and updated" }
    var viewSourcesLabel: String { self == .vi ? "Xem nguồn dữ liệu" : self == .ja ? "データソースを見る" : "View data sources" }
    func sourceLineWithTime(_ time: String) -> String { self == .vi ? "Dựa trên dữ liệu lúc \(time) · Xem nguồn" : self == .ja ? "\(time) のデータに基づく · ソースを見る" : "Based on data from \(time) · View sources" }
    func sourceLineWithCount(_ count: Int) -> String { self == .vi ? "Dựa trên \(count) nguồn dữ liệu · Xem nguồn" : self == .ja ? "\(count) 件のデータソースに基づく · ソースを見る" : "Based on \(count) data sources · View sources" }
    var coachDetailSheetTitle: String { self == .vi ? "Phân tích chi tiết" : self == .ja ? "詳細分析" : "Detailed analysis" }
    var coachViewDetailLabel: String { self == .vi ? "Xem phân tích chi tiết" : self == .ja ? "詳細分析を見る" : "View detailed analysis" }
    var coachDetailDoneLabel: String { self == .vi ? "Xong" : self == .ja ? "完了" : "Done" }
    var coachSafetyLabel: String { self == .vi ? "Lưu ý an toàn" : self == .ja ? "安全の注意" : "Safety note" }

    func coachStatusLabel(for status: CoachResponseStatus) -> String {
        switch status {
        case .ready: self == .vi ? "SẴN SÀNG TẬP LUYỆN" : self == .ja ? "トレーニング可能" : "READY TO TRAIN"
        case .recoveryRecommended: self == .vi ? "NÊN ƯU TIÊN HỒI PHỤC" : self == .ja ? "回復を優先" : "PRIORITIZE RECOVERY"
        case .adjustmentRecommended: self == .vi ? "NÊN ĐIỀU CHỈNH KẾ HOẠCH" : self == .ja ? "計画の調整を推奨" : "ADJUST THE PLAN"
        case .attention: self == .vi ? "CẦN CHÚ Ý" : self == .ja ? "要注意" : "NEEDS ATTENTION"
        case .insufficientData: self == .vi ? "CHƯA ĐỦ DỮ LIỆU" : self == .ja ? "データ不足" : "NOT ENOUGH DATA"
        }
    }

    func coachBasedOnSourcesLabel(count: Int) -> String {
        self == .vi ? "Dựa trên \(count) nguồn" : self == .ja ? "\(count) 件のデータに基づく" : "Based on \(count) sources"
    }
    func coachUpdatedAtLabel(_ time: String) -> String {
        self == .vi ? "Cập nhật \(time)" : self == .ja ? "\(time) 更新" : "Updated \(time)"
    }
    var coachViewSourcesHint: String {
        self == .vi ? "Xem chi tiết nguồn dữ liệu" : self == .ja ? "データソースの詳細を見る" : "View data source details"
    }
    var checkedDataRowTitle: String { self == .vi ? "Đã kiểm tra dữ liệu" : self == .ja ? "確認済みデータ" : "Checked data" }
    var noAdditionalSourceDetail: String { self == .vi ? "Không có chi tiết nguồn bổ sung." : self == .ja ? "追加のソース詳細はありません。" : "No additional source details." }
    var readinessSourceTitle: String { self == .vi ? "Thể trạng hiện tại" : self == .ja ? "現在のコンディション" : "Current readiness" }
    var planSourceTitle: String { self == .vi ? "Kế hoạch tuần này" : self == .ja ? "今週の計画" : "This week's plan" }
    var photoSourceTitle: String { self == .vi ? "Ảnh đính kèm" : self == .ja ? "添付写真" : "Attached photo" }
    var genericSourceTitle: String { self == .vi ? "Nguồn dữ liệu" : self == .ja ? "データソース" : "Data source" }
    var coachResponseInterruptedLabel: String { self == .vi ? "Phản hồi của Coach bị gián đoạn" : self == .ja ? "Coach の返信が中断されました" : "Coach's response was interrupted" }
    var cancelRetryAccessibilityLabel: String { self == .vi ? "Hủy thử lại" : self == .ja ? "再試行をキャンセル" : "Cancel retry" }
    var checkUpdateStatusAccessibilityLabel: String { self == .vi ? "Kiểm tra trạng thái cập nhật" : self == .ja ? "更新状態を確認" : "Check update status" }
    var dismissResponseErrorAccessibilityLabel: String { self == .vi ? "Bỏ qua lỗi phản hồi" : self == .ja ? "応答エラーを閉じる" : "Dismiss response error" }
    var retryResponseAccessibilityLabel: String { self == .vi ? "Thử lại phản hồi" : self == .ja ? "応答を再試行" : "Retry response" }

    // MARK: - Chat contextual session, sheets, plan transactions

    var composerTypingPlaceholder: String { self == .vi ? "Nội dung đang nhập…" : self == .ja ? "入力中…" : "Typing…" }
    var askCoachChangeWorkoutPlaceholder: String { self == .vi ? "Nhờ Coach chỉnh buổi tập này…" : self == .ja ? "この練習の変更を Coach に頼む…" : "Ask Coach to change this workout…" }
    var askCoachAnythingPlaceholder: String { self == .vi ? "Hỏi Coach bất cứ điều gì…" : self == .ja ? "Coach に何でも質問…" : "Ask Coach anything…" }

    var reviewWorkoutStripLabel: String { self == .vi ? "XEM LẠI BÀI TẬP" : self == .ja ? "練習を振り返る" : "REVIEW WORKOUT" }
    var editWorkoutStripLabel: String { self == .vi ? "CHỈNH BÀI TẬP" : self == .ja ? "練習を編集" : "EDIT WORKOUT" }

    var reviewRunAgainstTargetPrompt: String { self == .vi ? "Xem lại buổi chạy này so với mục tiêu đã lên kế hoạch." : self == .ja ? "このランを計画目標と比較して振り返って。" : "Review this run against the planned target." }
    var adjustNextAfterRunPrompt: String { self == .vi ? "Sau buổi chạy này tôi nên điều chỉnh gì tiếp theo?" : self == .ja ? "このラン後、次に何を調整すべき？" : "What should I adjust next after this run?" }
    var reviewCompletedWorkoutPrompt: String { self == .vi ? "Xem lại buổi tập đã hoàn thành này." : self == .ja ? "この完了した練習を振り返って。" : "Review this completed workout." }
    var reviewWhyFixedPrompt: String { self == .vi ? "Xem vì sao buổi tập này bị cố định." : self == .ja ? "この練習が固定されている理由を見る。" : "Review why this workout is fixed." }
    var askSafeAlternativesPrompt: String { self == .vi ? "Hỏi Coach về các lựa chọn an toàn." : self == .ja ? "安全な代替案を Coach に聞く。" : "Ask Coach for safe alternatives." }
    var changeDistanceOrDurationPrompt: String { self == .vi ? "Đổi cự ly hoặc thời lượng" : self == .ja ? "距離または時間を変更" : "Change distance or duration" }
    var moveThisWorkoutPrompt: String { self == .vi ? "Dời buổi tập này" : self == .ja ? "この練習を移動" : "Move this workout" }

    var completedRunTitle: String { self == .vi ? "Buổi chạy đã hoàn thành" : self == .ja ? "完了したラン" : "Completed run" }
    var workoutUnavailableTitle: String { self == .vi ? "Không có buổi tập" : self == .ja ? "ワークアウトを表示できません" : "Workout unavailable" }
    var distanceLabel: String { self == .vi ? "Cự ly" : self == .ja ? "距離" : "Distance" }
    var durationLabel: String { self == .vi ? "Thời lượng" : self == .ja ? "時間" : "Duration" }
    var paceLabel: String { self == .vi ? "Pace" : self == .ja ? "ペース" : "Pace" }
    var statusLabel: String { self == .vi ? "Trạng thái" : self == .ja ? "状態" : "Status" }
    var unavailableLabel: String { self == .vi ? "Không có" : self == .ja ? "利用不可" : "Unavailable" }

    var updatingPlanTitle: String { self == .vi ? "Đang cập nhật kế hoạch…" : self == .ja ? "計画を更新中…" : "Updating plan…" }
    var planErrorMissingTargets: String { self == .vi ? "Kế hoạch còn thiếu thời lượng hoặc pace mục tiêu. Anh có thể để Coach tự đề xuất hoặc nhập thủ công." : self == .ja ? "計画に時間または目標ペースがありません。Coach に提案させるか手動で入力してください。" : "The plan is missing a duration or target pace. Let Coach suggest one, or enter it manually." }
    var planErrorLoadTooHigh: String { self == .vi ? "Buổi tập mới có thể khiến tải tập tuần này tăng quá nhanh." : self == .ja ? "新しい練習は今週の負荷を急に増やす可能性があります。" : "The new workout could ramp this week's training load too fast." }
    var planUnchangedMessage: String { self == .vi ? "Kế hoạch hiện tại chưa bị thay đổi." : self == .ja ? "現在の計画は変更されていません。" : "Your current plan is unchanged." }
    var reviewRunNotFoundError: String { self == .vi ? "Không tìm thấy buổi chạy để review. Thử đồng bộ lại Health rồi mở lại Calendar." : self == .ja ? "レビュー対象のランが見つかりません。Health を再同期してからカレンダーを開き直してください。" : "Couldn't find the run to review. Re-sync Health, then reopen Calendar." }

    var savedPromptsSubtitle: String { self == .vi ? "Chọn một câu, rồi sửa trước khi gửi." : self == .ja ? "1つ選んで、送信前に編集できます。" : "Pick one, then edit before sending." }
    var closeLabel: String { self == .vi ? "Đóng" : self == .ja ? "閉じる" : "Close" }
    func insertSavedPromptLabel(_ prompt: String) -> String { self == .vi ? "Chèn câu hỏi đã lưu: \(prompt)" : self == .ja ? "保存した質問を挿入: \(prompt)" : "Insert saved question: \(prompt)" }
    var noChatsTitle: String { self == .vi ? "Chưa có chat" : self == .ja ? "まだチャットがありません" : "No chats yet" }
    var noChatsDescription: String { self == .vi ? "Các cuộc trò chuyện với Coach sẽ hiện ở đây." : self == .ja ? "Coach との会話がここに表示されます。" : "Your conversations with Coach will appear here." }
    var archiveLabel: String { self == .vi ? "Lưu trữ" : self == .ja ? "アーカイブ" : "Archive" }
    var pinChatLabel: String { self == .vi ? "Ghim chat" : self == .ja ? "チャットをピン留め" : "Pin chat" }
    var unpinChatLabel: String { self == .vi ? "Bỏ ghim" : self == .ja ? "ピン留めを解除" : "Unpin" }
    var renameLabel: String { self == .vi ? "Đổi tên" : self == .ja ? "名前を変更" : "Rename" }
    var pinnedLabel: String { self == .vi ? "Đã ghim" : self == .ja ? "ピン留め済み" : "Pinned" }
    var chatOptionsLabel: String { self == .vi ? "Tùy chọn chat" : self == .ja ? "チャットのオプション" : "Chat options" }
    var chatsNavTitle: String { self == .vi ? "Chat" : self == .ja ? "チャット" : "Chats" }
    var doneLabel: String { self == .vi ? "Xong" : self == .ja ? "完了" : "Done" }
    var renameChatTitle: String { self == .vi ? "Đổi tên chat" : self == .ja ? "チャットの名前を変更" : "Rename chat" }
    var chatNamePlaceholder: String { self == .vi ? "Tên chat" : self == .ja ? "チャット名" : "Chat name" }
    var cancelLabel: String { self == .vi ? "Hủy" : self == .ja ? "キャンセル" : "Cancel" }
    var saveLabel: String { self == .vi ? "Lưu" : self == .ja ? "保存" : "Save" }
    var renameChatMessage: String { self == .vi ? "Đặt tên để nhận ra cuộc trò chuyện này sau." : self == .ja ? "後で見分けられるように名前を付けます。" : "Name it so you can recognize this conversation later." }
    var newChatFallbackTitle: String { self == .vi ? "Chat mới" : self == .ja ? "新しいチャット" : "New chat" }

    var uiLocale: Locale { locale }

    // MARK: - Plan transaction card, review sheet, thread titles

    var planCardUpdatedTitle: String { self == .vi ? "Đã cập nhật kế hoạch" : self == .ja ? "計画を更新しました" : "Plan updated" }
    var viewInCalendarLabel: String { self == .vi ? "Xem trong lịch" : self == .ja ? "カレンダーで見る" : "View in calendar" }
    var undoLabel: String { self == .vi ? "Hoàn tác" : self == .ja ? "元に戻す" : "Undo" }
    var keepOldPlanLabel: String { self == .vi ? "Giữ kế hoạch cũ" : self == .ja ? "元の計画を保持" : "Keep old plan" }
    var viewTechnicalDetailsLabel: String { self == .vi ? "Xem chi tiết kỹ thuật" : self == .ja ? "技術的な詳細を見る" : "View technical details" }
    var planFailureCantCreate: String { self == .vi ? "Chưa thể tạo buổi chạy" : self == .ja ? "ランを作成できませんでした" : "Couldn't create the run" }
    var planFailureNotSuitable: String { self == .vi ? "Thay đổi này chưa phù hợp với kế hoạch hiện tại" : self == .ja ? "この変更は現在の計画にまだ合いません" : "This change doesn't fit the current plan yet" }
    var planFailureGeneric: String { self == .vi ? "Chưa thể cập nhật kế hoạch lúc này" : self == .ja ? "今は計画を更新できませんでした" : "Couldn't update the plan right now" }

    var useEvidenceAndSendLabel: String { self == .vi ? "Dùng nguồn dữ liệu và gửi" : self == .ja ? "このデータを使って送信" : "Use this data and send" }

    var workoutNoLongerAvailableError: String { self == .vi ? "Buổi tập này không còn khả dụng." : self == .ja ? "このワークアウトは利用できなくなりました。" : "This workout is no longer available." }
    var reviewTitlePrefix: String { self == .vi ? "Xem lại" : self == .ja ? "振り返り" : "Review" }
    var editTitlePrefix: String { self == .vi ? "Chỉnh" : self == .ja ? "編集" : "Edit" }
    func reviewRunThreadTitle(distance: String, date: String) -> String { self == .vi ? "Xem lại buổi chạy \(distance) · \(date)" : self == .ja ? "\(distance) のランを振り返る · \(date)" : "Review \(distance) run · \(date)" }
    var previousChatTitle: String { self == .vi ? "Cuộc trò chuyện trước" : self == .ja ? "以前のチャット" : "Previous chat" }

    // MARK: - Plan proposal cards (shared trust ledger)

    var planProposalEyebrow: String { self == .vi ? "ĐỀ XUẤT CẬP NHẬT KẾ HOẠCH" : self == .ja ? "計画更新の提案" : "PROPOSED PLAN UPDATE" }
    var ledgerProposedLabel: String { self == .vi ? "Đề xuất" : self == .ja ? "提案" : "Proposed" }
    var ledgerValidatedLabel: String { self == .vi ? "Đã kiểm tra" : self == .ja ? "検証済み" : "Validated" }
    var ledgerAwaitsLabel: String { self == .vi ? "Chờ xác nhận" : self == .ja ? "確認待ち" : "Awaits you" }
    var showValidationReceiptLabel: String { self == .vi ? "Xem biên nhận kiểm tra" : self == .ja ? "検証レシートを表示" : "Show validation receipt" }
    var validationReceiptTitle: String { self == .vi ? "Đã kiểm tra kế hoạch" : self == .ja ? "計画チェック合格" : "Plan checks passed" }
    var validationReceiptSubtitle: String { self == .vi ? "Đã kiểm tra bằng quy tắc tập luyện trên máy trước khi thay đổi kế hoạch." : self == .ja ? "変更前にデバイス内のトレーニングルールで検証済みです。" : "Checked against on-device training rules before any change." }
    func applyToWeekLabel(_ week: Int) -> String { self == .vi ? "Áp dụng cho tuần \(week)" : self == .ja ? "第\(week)週に適用" : "Apply to week \(week)" }
    var planChangedBannerText: String { self == .vi ? "Kế hoạch đã thay đổi sau đề xuất này, anh xem lại thay đổi mới nhé." : self == .ja ? "この提案の後に計画が変わりました。最新の変更を確認してください。" : "The plan changed after this was proposed — review the latest change." }
    var proposalNoChangeYetText: String { self == .vi ? "Chưa thay đổi kế hoạch. TrainOrRest chỉ cập nhật sau khi anh xác nhận." : self == .ja ? "計画はまだ変わりません。確認後にのみ更新されます。" : "Nothing changes yet. TrainOrRest updates only after you confirm." }
    func planChangeActionLabel(_ action: PlanAdjustmentProposal.Change.Action) -> String {
        switch action {
        case .swap: return self == .vi ? "Đổi" : self == .ja ? "入替" : "Swap"
        case .downgrade: return self == .vi ? "Giảm" : self == .ja ? "軽減" : "Ease"
        case .rest: return self == .vi ? "Nghỉ" : self == .ja ? "休養" : "Rest"
        case .move: return self == .vi ? "Dời" : self == .ja ? "移動" : "Move"
        case .create: return self == .vi ? "Thêm" : self == .ja ? "追加" : "Add"
        case .replace: return self == .vi ? "Thay" : self == .ja ? "置換" : "Replace"
        }
    }
    var planValidationChecks: [(title: String, detail: String)] {
        switch self {
        case .en: return [
            ("Workout uses available days", "No workout on an unavailable day."),
            ("Long-run length within limit", "Long runs stay within absolute and weekly-share caps."),
            ("Ramp rate safe", "Weekly volume does not grow faster than the plan allows."),
            ("Taper stays monotonic", "Taper volume does not climb toward race day."),
            ("Quality sessions spaced", "Hard sessions keep the required recovery gap."),
            ("Race day present", "The plan still includes exactly one race workout."),
            ("Weekly volume within cap", "Week volume remains under the athlete's peak cap."),
            ("No duplicate workout day", "Each date has at most one workout."),
            ("Workout stays inside plan week", "The workout date matches its plan week."),
            ("Distances valid", "Workout distances are finite and above zero."),
            ("Structure matches distance", "Structured steps add up to the workout distance.")
        ]
        case .ja: return [
            ("利用可能日を使用", "利用不可の日に練習を入れません。"),
            ("ロング走が上限内", "ロング走は絶対値と週比率の上限内に収まります。"),
            ("増加率が安全", "週間距離は計画の許容を超えて増えません。"),
            ("テーパーは単調", "テーパー量はレース日に向けて増えません。"),
            ("質練習の間隔", "高強度練習は必要な回復間隔を保ちます。"),
            ("レース日あり", "計画にレース練習がちょうど1つ残ります。"),
            ("週間距離が上限内", "週間距離は選手のピーク上限内に収まります。"),
            ("練習日の重複なし", "各日付の練習は最大1つです。"),
            ("計画週の内側", "練習の日付は計画週と一致します。"),
            ("距離が有効", "練習距離は有限かつ0より大きい値です。"),
            ("構成が距離と一致", "構成ステップの合計が練習距離と一致します。")
        ]
        case .vi: return [
            ("Dùng ngày khả dụng", "Không đặt bài vào ngày không khả dụng."),
            ("Long run trong giới hạn", "Long run nằm trong mức tuyệt đối và tỷ lệ tuần."),
            ("Tốc độ tăng an toàn", "Khối lượng tuần không tăng nhanh hơn kế hoạch cho phép."),
            ("Taper giảm đều", "Khối lượng taper không tăng dần về ngày đua."),
            ("Buổi chất lượng cách nhau", "Buổi nặng giữ đủ khoảng hồi phục."),
            ("Còn ngày đua", "Kế hoạch vẫn có đúng một buổi đua."),
            ("Khối lượng tuần trong mức", "Khối lượng tuần dưới mức đỉnh của vận động viên."),
            ("Không trùng ngày tập", "Mỗi ngày có tối đa một buổi tập."),
            ("Bài nằm trong tuần kế hoạch", "Ngày của buổi tập khớp với tuần kế hoạch."),
            ("Cự ly hợp lệ", "Cự ly buổi tập hữu hạn và lớn hơn 0."),
            ("Cấu trúc khớp cự ly", "Các bước cấu trúc cộng lại đúng bằng cự ly buổi tập.")
        ]
        }
    }

    var coachRoleLine: String { self == .vi ? "Giải thích & đề xuất · không tự sửa kế hoạch của bạn." : self == .ja ? "説明と提案のみ · あなたの計画は編集しません。" : "Explains & proposes · never edits your plan." }
    var responseTruncatedTitle: String { self == .vi ? "Phản hồi bị cắt ngắn" : self == .ja ? "返信が途中で切れました" : "Reply was cut off" }
    var responseTruncatedMessage: String { self == .vi ? "Phản hồi của Coach bị cắt ngắn. Nhấn thử lại, hoặc yêu cầu từng thay đổi một." : self == .ja ? "Coach の返信が途中で切れました。再試行するか、変更を1つずつ依頼してください。" : "The coach's reply was cut off. Tap retry, or ask for one change at a time." }

    var metricReadinessLabel: String { self == .vi ? "Mức sẵn sàng tập luyện" : self == .ja ? "トレーニング準備度" : "Training readiness" }
    var metricSleepLabel: String { self == .vi ? "Giấc ngủ" : self == .ja ? "睡眠" : "Sleep" }
    var metricRestingHRLabel: String { self == .vi ? "Nhịp tim nghỉ (RHR)" : self == .ja ? "安静時心拍数 (RHR)" : "Resting heart rate (RHR)" }
    var metricHRVLabel: String { self == .vi ? "Biến thiên nhịp tim (HRV)" : self == .ja ? "心拍変動 (HRV)" : "Heart-rate variability (HRV)" }
    var metricLoadLabel: String { self == .vi ? "Tỷ lệ tải cấp tính/mạn tính (ACWR)" : self == .ja ? "急性:慢性負荷比 (ACWR)" : "Acute:chronic load (ACWR)" }
    var metricStableNote: String { self == .vi ? "Ổn định" : self == .ja ? "安定" : "Stable" }
    var metricAttentionNote: String { self == .vi ? "Cần chú ý" : self == .ja ? "要注意" : "Needs attention" }
    var metricGoodNote: String { self == .vi ? "Tốt" : self == .ja ? "良好" : "Good" }
    var sourceHealthDataLabel: String { self == .vi ? "Dữ liệu sức khỏe" : self == .ja ? "健康データ" : "Health data" }
    var sourceCompletedWorkoutLabel: String { self == .vi ? "Buổi tập gần nhất" : self == .ja ? "直近のワークアウト" : "Latest workout" }
    var sourceTrainingPlanLabel: String { self == .vi ? "Kế hoạch hiện tại" : self == .ja ? "現在の計画" : "Current plan" }
    var sourceUpcomingWorkoutsLabel: String { self == .vi ? "Buổi tập sắp tới" : self == .ja ? "今後のワークアウト" : "Upcoming workouts" }
    var sourceRaceGoalLabel: String { self == .vi ? "Mục tiêu cuộc đua" : self == .ja ? "レース目標" : "Race goal" }

    func sleepHours(_ hours: Double) -> String {
        let compact = (hours * 10).rounded() / 10
        let number = compact.rounded() == compact ? String(Int(compact)) : String(format: "%.1f", compact)
        return self == .vi ? "\(number) giờ" : self == .ja ? "\(number)時間" : "\(number)h"
    }
}
