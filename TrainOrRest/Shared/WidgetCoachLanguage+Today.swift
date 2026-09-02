import Foundation

enum WidgetCoachLanguage: String {
    case en
    case ja
    case vi

    var uiLocale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .ja: Locale(identifier: "ja_JP")
        case .vi: Locale(identifier: "vi_VN")
        }
    }

    var today: WidgetTodayCopy { WidgetTodayCopy(language: self) }
}

struct WidgetTodayCopy {
    let language: WidgetCoachLanguage

    var readinessLabel: String {
        switch language {
        case .en: "READINESS"
        case .ja: "コンディション"
        case .vi: "THỂ TRẠNG"
        }
    }

    /// Mirrors `CoachLanguage.verdictWord` for the widget target, which cannot import the app model.
    func verdictWord(rawValue: String) -> String {
        switch (language, rawValue) {
        case (.en, "train"): "Train"
        case (.en, "goEasy"): "Go easy"
        case (.en, "rest"): "Rest"
        case (.en, _): "Baseline"
        case (.ja, "train"): "トレーニング"
        case (.ja, "goEasy"): "軽めに"
        case (.ja, "rest"): "休養"
        case (.ja, _): "ベースライン"
        case (.vi, "train"): "Tập"
        case (.vi, "goEasy"): "Nhẹ"
        case (.vi, "rest"): "Nghỉ"
        case (.vi, _): "Cơ sở"
        }
    }

    func widgetReason(rawVerdict: String) -> String {
        switch (language, rawVerdict) {
        case (.en, "train"): "Ready for the planned session"
        case (.en, "goEasy"): "Keep the effort controlled today"
        case (.en, "rest"): "Recovery comes first today"
        case (.en, _): "Collecting your baseline"
        case (.ja, "train"): "予定のセッションに向けて準備完了"
        case (.ja, "goEasy"): "今日は強度を抑えましょう"
        case (.ja, "rest"): "今日は回復を最優先に"
        case (.ja, _): "ベースラインを収集中"
        case (.vi, "train"): "Sẵn sàng cho buổi tập theo kế hoạch"
        case (.vi, "goEasy"): "Hôm nay hãy kiểm soát cường độ"
        case (.vi, "rest"): "Hôm nay ưu tiên hồi phục"
        case (.vi, _): "Đang thu thập mức cơ sở"
        }
    }

    func updated(_ relativeDate: String) -> String {
        switch language {
        case .en: "Updated \(relativeDate)"
        case .ja: "更新：\(relativeDate)"
        case .vi: "Cập nhật \(relativeDate)"
        }
    }

    var noFreshData: String {
        switch language {
        case .en: "No fresh data"
        case .ja: "新しいデータはありません"
        case .vi: "Không có dữ liệu mới"
        }
    }

    var configurationDisplayName: String {
        switch language {
        case .en: "TrainOrRest Readiness"
        case .ja: "TrainOrRest コンディション"
        case .vi: "Thể trạng TrainOrRest"
        }
    }

    var configurationDescription: String {
        switch language {
        case .en: "Shows today's readiness score and verdict."
        case .ja: "今日のコンディションスコアと判定を表示します。"
        case .vi: "Hiển thị điểm thể trạng và kết luận hôm nay."
        }
    }
}
