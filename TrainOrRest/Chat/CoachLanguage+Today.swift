import Foundation

extension CoachLanguage {
    var today: TodayCopy { TodayCopy(language: self) }
}

struct TodayCopy {
    let language: CoachLanguage

    func greeting(hour: Int) -> String {
        switch (language, hour) {
        case (.en, 5..<12): "Good morning"
        case (.en, 12..<18): "Good afternoon"
        case (.en, _): "Good evening"
        case (.ja, 5..<12): "おはようございます"
        case (.ja, 12..<18): "こんにちは"
        case (.ja, _): "こんばんは"
        case (.vi, 5..<12): "Chào buổi sáng"
        case (.vi, 12..<18): "Chào buổi chiều"
        case (.vi, _): "Chào buổi tối"
        }
    }

    var settingsAccessibilityLabel: String {
        switch language {
        case .en: "Settings"
        case .ja: "設定"
        case .vi: "Cài đặt"
        }
    }

    var suggestedSession: String {
        switch language {
        case .en: "Suggested session"
        case .ja: "おすすめのセッション"
        case .vi: "Buổi tập gợi ý"
        }
    }

    var setRaceGoal: String {
        switch language {
        case .en: "Set a race goal"
        case .ja: "レース目標を設定"
        case .vi: "Đặt mục tiêu giải đua"
        }
    }

    var generateTrainingPlan: String {
        switch language {
        case .en: "Generate your training plan"
        case .ja: "トレーニングプランを作成"
        case .vi: "Tạo kế hoạch tập luyện"
        }
    }

    var askCoach: String {
        switch language {
        case .en: "Ask your coach"
        case .ja: "Coachに聞く"
        case .vi: "Hỏi Coach"
        }
    }

    var driversHeading: String {
        switch language {
        case .en: "What's driving this"
        case .ja: "判断の根拠"
        case .vi: "Yếu tố quyết định"
        }
    }

    var restingHeartRate: String {
        switch language {
        case .en: "Resting HR"
        case .ja: "安静時心拍"
        case .vi: "Nhịp tim nghỉ"
        }
    }

    var vo2Max: String { "VO₂max" }

    var trainingLoadACWR: String {
        switch language {
        case .en: "Load · ACWR"
        case .ja: "負荷 · ACWR"
        case .vi: "Khối lượng tập · ACWR"
        }
    }

    func versusBaseline(_ value: Int, unit: String) -> String {
        switch language {
        case .en: "vs \(value) \(unit) baseline"
        case .ja: "ベースライン \(value) \(unit) 比"
        case .vi: "so với mức cơ sở \(value) \(unit)"
        }
    }

    var baselineBuilding: String {
        switch language {
        case .en: "baseline building"
        case .ja: "ベースラインを作成中"
        case .vi: "đang xây dựng mức cơ sở"
        }
    }

    var lastNight: String {
        switch language {
        case .en: "last night"
        case .ja: "昨夜"
        case .vi: "đêm qua"
        }
    }

    var optimal: String {
        switch language {
        case .en: "OPTIMAL"
        case .ja: "最適"
        case .vi: "TỐI ƯU"
        }
    }

    var watch: String {
        switch language {
        case .en: "WATCH"
        case .ja: "要注意"
        case .vi: "THEO DÕI"
        }
    }

    var buildingHistory: String {
        switch language {
        case .en: "building history"
        case .ja: "履歴を作成中"
        case .vi: "đang xây dựng lịch sử"
        }
    }

    var rampingFast: String {
        switch language {
        case .en: "ramping fast"
        case .ja: "急増中"
        case .vi: "tăng nhanh"
        }
    }

    var detraining: String {
        switch language {
        case .en: "detraining"
        case .ja: "負荷不足"
        case .vi: "thiếu tải"
        }
    }

    var balancedTraining: String {
        switch language {
        case .en: "balanced training"
        case .ja: "バランス良好"
        case .vi: "tập luyện cân bằng"
        }
    }

    var flat: String {
        switch language {
        case .en: "flat"
        case .ja: "横ばい"
        case .vi: "ổn định"
        }
    }

    func sourceCount(_ count: Int) -> String {
        switch language {
        case .en: "\(count) sources"
        case .ja: "\(count)件のソース"
        case .vi: "\(count) nguồn"
        }
    }

    var showHRVSources: String {
        switch language {
        case .en: "Show HRV sources"
        case .ja: "HRVのソースを表示"
        case .vi: "Xem nguồn HRV"
        }
    }

    var hrvSourcesTitle: String {
        switch language {
        case .en: "HRV sources"
        case .ja: "HRVのソース"
        case .vi: "Nguồn HRV"
        }
    }

    func primaryHRVSource(_ source: String) -> String {
        switch language {
        case .en: "\(source) is primary for HRV — change in Settings."
        case .ja: "HRVには\(source)を優先使用しています。設定で変更できます。"
        case .vi: "\(source) là nguồn chính cho HRV — thay đổi trong Cài đặt."
        }
    }

    func usedHRVValue(_ value: Double) -> String {
        switch language {
        case .en: String(format: "%.0f ms (used)", locale: language.uiLocale, value)
        case .ja: String(format: "%.0f ms（使用中）", locale: language.uiLocale, value)
        case .vi: String(format: "%.0f ms (đang dùng)", locale: language.uiLocale, value)
        }
    }

    func hrvValue(_ value: Double) -> String {
        String(format: "%.0f ms", locale: language.uiLocale, value)
    }

    var checkInTitle: String {
        switch language {
        case .en: "Anything to note?"
        case .ja: "気になることはありますか？"
        case .vi: "Có điều gì cần lưu ý?"
        }
    }

    var checkInSaveFailed: String {
        switch language {
        case .en: "Could not save check-in."
        case .ja: "チェックインを保存できませんでした。"
        case .vi: "Không thể lưu check-in."
        }
    }

    func checkInAccessibility(_ signal: CheckInSignal) -> String {
        switch language {
        case .en: "\(language.name(signal)) check-in"
        case .ja: "\(language.name(signal))のチェックイン"
        case .vi: "Check-in \(language.name(signal))"
        }
    }

    var selected: String {
        switch language {
        case .en: "Selected"
        case .ja: "選択済み"
        case .vi: "Đã chọn"
        }
    }

    var notSelected: String {
        switch language {
        case .en: "Not selected"
        case .ja: "未選択"
        case .vi: "Chưa chọn"
        }
    }

    func reason(_ code: ReadinessReason) -> String {
        switch (language, code) {
        case (.en, _): code.englishText
        case (.ja, .illness): "体調不良の報告"
        case (.vi, .illness): "Đã báo ốm"
        case (.ja, .hrvDisputed): "HRVのソース間に差異があるため、カウントしません"
        case (.vi, .hrvDisputed): "HRV có khác biệt giữa các nguồn — không tính"
        case let (.ja, .hrvBelowBaseline(ms, band)):
            String(format: "HRV %.0f ms はベースライン帯 %.0f ms を下回っています", locale: language.uiLocale, ms, band)
        case let (.vi, .hrvBelowBaseline(ms, band)):
            String(format: "HRV %.0f ms thấp hơn dải mức cơ sở %.0f ms", locale: language.uiLocale, ms, band)
        case let (.ja, .restingHRAbove(bpm)):
            "安静時心拍がベースラインより \(bpm) bpm 高い"
        case let (.vi, .restingHRAbove(bpm)):
            "Nhịp tim nghỉ cao hơn mức cơ sở \(bpm) bpm"
        case let (.ja, .sleptHours(h)):
            String(format: "昨夜の睡眠は %.1f 時間", locale: language.uiLocale, h)
        case let (.vi, .sleptHours(h)):
            String(format: "Đã ngủ %.1f giờ đêm qua", locale: language.uiLocale, h)
        case let (.ja, .loadRamping(acwr)):
            String(format: "トレーニング負荷が急増しています（通常の %.2f×）", locale: language.uiLocale, acwr)
        case let (.vi, .loadRamping(acwr)):
            String(format: "Khối lượng tập tăng nhanh (%.2f× mức thường lệ)", locale: language.uiLocale, acwr)
        case (.ja, .sorenessTwoDays): "筋肉痛の報告が2日連続"
        case (.vi, .sorenessTwoDays): "Đã báo đau nhức trong 2 ngày liên tiếp"
        case (.ja, .sorenessWatching): "筋肉痛の報告あり。2日目を確認中"
        case (.vi, .sorenessWatching): "Đã báo đau nhức; đang theo dõi ngày thứ hai"
        case let (.ja, .corroboratingSignal(signal)):
            "\(language.name(signal))の報告（回復シグナルを裏付け）"
        case let (.vi, .corroboratingSignal(signal)):
            "Đã báo \(language.name(signal).lowercased()) (xác nhận tín hiệu hồi phục)"
        }
    }

    var why: String {
        switch language {
        case .en: "Why?"
        case .ja: "理由"
        case .vi: "Vì sao?"
        }
    }

    var showReadinessDrivers: String {
        switch language {
        case .en: "Show readiness drivers"
        case .ja: "コンディションの要因を表示"
        case .vi: "Hiện yếu tố thể trạng"
        }
    }

    var hideReadinessDrivers: String {
        switch language {
        case .en: "Hide readiness drivers"
        case .ja: "コンディションの要因を非表示"
        case .vi: "Ẩn yếu tố thể trạng"
        }
    }

    var keepPlannedSession: String {
        switch language {
        case .en: "Keep planned session"
        case .ja: "予定どおりに実施"
        case .vi: "Giữ buổi tập theo kế hoạch"
        }
    }

    func likely(_ verdict: ReadinessVerdict) -> String {
        let word = language.verdictWord(verdict)
        return switch language {
        case .en: "Likely \(word.lowercased())"
        case .ja: "おそらく\(word)"
        case .vi: "Có thể \(word.lowercased())"
        }
    }

    func planCallsFor(_ session: String, but reason: String) -> String {
        switch language {
        case .en: "Plan calls for \(session), but \(reason)."
        case .ja: "プランは\(session)ですが、\(reason)です。"
        case .vi: "Kế hoạch yêu cầu \(session), nhưng \(reason)."
        }
    }

    var recoverySignalsMixed: String {
        switch language {
        case .en: "recovery signals are mixed"
        case .ja: "回復シグナルがまちまち"
        case .vi: "các tín hiệu hồi phục chưa đồng nhất"
        }
    }

    func collectingBaseline(day: Int, total: Int) -> String {
        switch language {
        case .en: "Collecting baseline, day \(day) of \(total)."
        case .ja: "ベースラインを収集中：\(total)日中\(day)日目。"
        case .vi: "Đang thu thập mức cơ sở, ngày \(day)/\(total)."
        }
    }

    var normalDrivers: String {
        switch language {
        case .en: "HRV normal · sleep steady · load balanced"
        case .ja: "HRVは通常 · 睡眠は安定 · 負荷はバランス良好"
        case .vi: "HRV bình thường · giấc ngủ ổn định · khối lượng tập cân bằng"
        }
    }

    var adjustedByRule: String {
        switch language {
        case .en: "Adjusted by rule"
        case .ja: "ルールにより調整"
        case .vi: "Đã điều chỉnh theo quy tắc"
        }
    }

    var deterministicRuleSubtitle: String {
        switch language {
        case .en: "Deterministic training rule — no AI involved."
        case .ja: "決定的なトレーニングルールによる調整です。AIは使用していません。"
        case .vi: "Quy tắc tập luyện xác định — không dùng AI."
        }
    }

    func plannedSession(_ session: String) -> String {
        switch language {
        case .en: "Planned: \(session)"
        case .ja: "予定：\(session)"
        case .vi: "Dự kiến: \(session)"
        }
    }

    var showRuleAdjustmentReceipt: String {
        switch language {
        case .en: "Show rule adjustment receipt"
        case .ja: "ルール調整の詳細を表示"
        case .vi: "Xem chi tiết điều chỉnh theo quy tắc"
        }
    }

    func ruleLabel(_ rule: ReadinessRuleID) -> String {
        switch language {
        case .en: "Rule \(rule.code) · \(rule.title)"
        case .ja: "ルール \(rule.code) · \(ruleTitle(rule))"
        case .vi: "Quy tắc \(rule.code) · \(ruleTitle(rule))"
        }
    }

    func ruleTitle(_ rule: ReadinessRuleID) -> String {
        switch (language, rule) {
        case (.en, _): rule.title
        case (.ja, .rhrElevated): "安静時心拍の上昇"
        case (.ja, .shortSleep): "睡眠不足"
        case (.ja, .loadRamp): "トレーニング負荷の急増"
        case (.ja, .hrvLow): "HRVがベースライン未満"
        case (.ja, .overreaching): "HRVと負荷の両方に負担"
        case (.ja, .soreness): "筋肉痛が継続"
        case (.ja, .illness): "体調不良の報告"
        case (.ja, .persistenceHold): "継続性ゲートで保留"
        case (.ja, .sourceDispute): "ソース間の不一致を抑制"
        case (.ja, .overrideWidened): "上書きでしきい値を拡大"
        case (.vi, .rhrElevated): "Nhịp tim nghỉ tăng"
        case (.vi, .shortSleep): "Thiếu ngủ"
        case (.vi, .loadRamp): "Khối lượng tập tăng nhanh"
        case (.vi, .hrvLow): "HRV thấp hơn mức cơ sở"
        case (.vi, .overreaching): "HRV và khối lượng tập cùng quá tải"
        case (.vi, .soreness): "Đau nhức lặp lại"
        case (.vi, .illness): "Đã báo ốm"
        case (.vi, .persistenceHold): "Tạm giữ theo cổng duy trì"
        case (.vi, .sourceDispute): "Bỏ qua vì nguồn không thống nhất"
        case (.vi, .overrideWidened): "Đã nới ngưỡng theo ghi đè"
        }
    }

    func ruleDetail(_ rule: ReadinessRuleID) -> String {
        switch (language, rule) {
        case (.en, _): rule.detail
        case (.ja, .rhrElevated): "直近の安静時心拍が個人のベースライン帯を上回ると、回復負荷として検出します。"
        case (.ja, .shortSleep): "昨夜の睡眠が短い、または直近の基準を大きく下回ると、回復負荷として検出します。"
        case (.ja, .loadRamp): "直近のトレーニング負荷が長期負荷に比べて高い場合のリスクを検出します。"
        case (.ja, .hrvLow): "直近のHRVが個人のベースライン帯を下回ると、回復負荷として検出します。"
        case (.ja, .overreaching): "低いHRVと急なトレーニング負荷の増加が重なった場合、より多くの回復を勧めます。"
        case (.ja, .soreness): "筋肉痛が2日連続で報告された場合にのみ、強度を制限します。"
        case (.ja, .illness): "センサーの確認なしでも、体調不良の報告があれば休養を勧めます。"
        case (.ja, .persistenceHold): "シグナルが3日中2日継続するまで、1日の急変でボリュームを減らさないようにします。"
        case (.ja, .sourceDispute): "信頼できるソースの差異が大きく不確かな場合、その指標のフラグを抑制します。"
        case (.ja, .overrideWidened): "最近の予定維持の上書きにより、今回のルールのしきい値を広げます。"
        case (.vi, .rhrElevated): "Gắn cờ áp lực hồi phục khi nhịp tim nghỉ gần đây cao hơn dải mức cơ sở cá nhân."
        case (.vi, .shortSleep): "Gắn cờ áp lực hồi phục khi giấc ngủ đêm qua ngắn hoặc giảm mạnh so với mức gần đây."
        case (.vi, .loadRamp): "Gắn cờ rủi ro khi khối lượng tập gần đây cao so với tải dài hạn."
        case (.vi, .hrvLow): "Gắn cờ áp lực hồi phục khi HRV gần đây thấp hơn dải mức cơ sở cá nhân."
        case (.vi, .overreaching): "Khuyến nghị hồi phục nhiều hơn khi HRV thấp xuất hiện cùng với khối lượng tập tăng nhanh."
        case (.vi, .soreness): "Chỉ giới hạn cường độ sau khi đau nhức được báo trong 2 ngày liên tiếp."
        case (.vi, .illness): "Khuyến nghị nghỉ khi bạn báo ốm, không cần xác nhận từ cảm biến."
        case (.vi, .persistenceHold): "Không giảm khối lượng chỉ vì một ngày tăng đột biến cho tới khi tín hiệu xuất hiện 2 trong 3 ngày."
        case (.vi, .sourceDispute): "Bỏ qua cờ chỉ số khi các nguồn đáng tin cậy chênh lệch đủ lớn để chỉ số không chắc chắn."
        case (.vi, .overrideWidened): "Áp dụng các ghi đè giữ buổi tập gần đây bằng cách nới ngưỡng quy tắc cho lần chạy này."
        }
    }

    var hrvBand: String {
        switch language {
        case .en: "HRV band"
        case .ja: "HRV帯"
        case .vi: "Dải HRV"
        }
    }

    var load: String {
        switch language {
        case .en: "Load"
        case .ja: "負荷"
        case .vi: "Khối lượng tập"
        }
    }

    var adjustment: String {
        switch language {
        case .en: "Adjustment"
        case .ja: "調整"
        case .vi: "Điều chỉnh"
        }
    }

    var source: String {
        switch language {
        case .en: "Source"
        case .ja: "ソース"
        case .vi: "Nguồn"
        }
    }

    var localRuleSource: String {
        switch language {
        case .en: "Adjusted by a deterministic local training rule."
        case .ja: "決定的なローカルトレーニングルールにより調整されました。"
        case .vi: "Đã điều chỉnh theo quy tắc tập luyện cục bộ xác định."
        }
    }

    func adjustedRuleTag(_ code: String?) -> String {
        guard let code else {
            switch language {
            case .en: return "Adjusted · rule"
            case .ja: return "調整済み · ルール"
            case .vi: return "Đã điều chỉnh · quy tắc"
            }
        }
        switch language {
        case .en: return "Adjusted · rule \(code)"
        case .ja: return "調整済み · ルール \(code)"
        case .vi: return "Đã điều chỉnh · quy tắc \(code)"
        }
    }

    func hrvDriver(value: Double, percent: Int?) -> String {
        let roundedValue = Int(value.rounded())
        guard let percent else {
            switch language {
            case .en: return "HRV: \(roundedValue) ms"
            case .ja: return "HRV：\(roundedValue) ms"
            case .vi: return "HRV: \(roundedValue) ms"
            }
        }
        let band: String
        switch language {
        case .en:
            band = percent >= 0 ? "\(percent)% above baseline" : "\(abs(percent))% below baseline"
            return "HRV: \(roundedValue) ms, \(band)"
        case .ja:
            band = percent >= 0 ? "ベースラインより\(percent)%上" : "ベースラインより\(abs(percent))%下"
            return "HRV：\(roundedValue) ms、\(band)"
        case .vi:
            band = percent >= 0 ? "cao hơn mức cơ sở \(percent)%" : "thấp hơn mức cơ sở \(abs(percent))%"
            return "HRV: \(roundedValue) ms, \(band)"
        }
    }

    var hrvBaselineBuilding: String {
        switch language {
        case .en: "HRV: baseline building"
        case .ja: "HRV：ベースラインを作成中"
        case .vi: "HRV: đang xây dựng mức cơ sở"
        }
    }

    var sleepNoSample: String {
        switch language {
        case .en: "Sleep: no sleep sample last night"
        case .ja: "睡眠：昨夜の睡眠データなし"
        case .vi: "Giấc ngủ: không có dữ liệu đêm qua"
        }
    }

    func sleepDuration(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let hour = totalMinutes / 60
        let minute = totalMinutes % 60
        switch language {
        case .en: return String(format: "%dh %02dm", hour, minute)
        case .ja: return "\(hour)時間\(minute)分"
        case .vi: return "\(hour) giờ \(minute) phút"
        }
    }

    func sleepDriver(_ sleep: String) -> String {
        switch language {
        case .en: "Sleep: \(sleep) last night"
        case .ja: "睡眠：昨夜 \(sleep)"
        case .vi: "Giấc ngủ: \(sleep) đêm qua"
        }
    }

    var loadBuildingHistory: String {
        switch language {
        case .en: "Load: building training history"
        case .ja: "負荷：トレーニング履歴を作成中"
        case .vi: "Khối lượng tập: đang xây dựng lịch sử tập luyện"
        }
    }

    func loadDriver(acwr: Double, status: String) -> String {
        switch language {
        case .en: String(format: "Load: %.2f ACWR, %@", locale: language.uiLocale, acwr, status)
        case .ja: String(format: "負荷：%.2f ACWR、%@", locale: language.uiLocale, acwr, status)
        case .vi: String(format: "Khối lượng tập: %.2f ACWR, %@", locale: language.uiLocale, acwr, status)
        }
    }

    func readinessScore(_ score: Int?) -> String {
        guard let score else {
            switch language {
            case .en: return "readiness --"
            case .ja: return "コンディション --"
            case .vi: return "thể trạng --"
            }
        }
        switch language {
        case .en: return "readiness \(score)"
        case .ja: return "コンディション \(score)"
        case .vi: return "thể trạng \(score)"
        }
    }

    func readinessAccessibility(score: Int?, verdict: String) -> String {
        guard let score else {
            switch language {
            case .en: return "Readiness not yet available, \(verdict)"
            case .ja: return "コンディションはまだ利用できません。\(verdict)"
            case .vi: return "Thể trạng chưa khả dụng, \(verdict)"
            }
        }
        switch language {
        case .en: return "Readiness \(score) out of 100, \(verdict)"
        case .ja: return "コンディション \(score)/100、\(verdict)"
        case .vi: return "Thể trạng \(score) trên 100, \(verdict)"
        }
    }

    var neverSynced: String {
        switch language {
        case .en: "never synced"
        case .ja: "未同期"
        case .vi: "chưa đồng bộ"
        }
    }

    func syncAgo(hours: Int) -> String {
        switch language {
        case .en: "sync \(hours)h ago"
        case .ja: "\(hours)時間前に同期"
        case .vi: "đồng bộ \(hours) giờ trước"
        }
    }

    func sessionText(fallbackKind: WorkoutKind?, details: String, durationMinutes: Int?) -> String {
        let sessionName = fallbackKind.map { language.name($0) } ?? language.genericRunLabel
        var parts = [details.isEmpty ? sessionName : details.replacingOccurrences(of: " at ", with: " @ ")]
        if let durationMinutes {
            switch language {
            case .en: parts.append("\(durationMinutes) min")
            case .ja: parts.append("\(durationMinutes)分")
            case .vi: parts.append("\(durationMinutes) phút")
            }
        }
        return parts.joined(separator: " · ")
    }

    func adjustedSession(kind: WorkoutKind?) -> String {
        switch (language, kind) {
        case (.en, .intervals): "shorter reps or easy 40 min"
        case (.en, .tempo): "easy 40 min"
        case (.en, _): "easy 30 min"
        case (.ja, .intervals): "短いレペティション、またはイージー40分"
        case (.ja, .tempo): "イージー40分"
        case (.ja, _): "イージー30分"
        case (.vi, .intervals): "lặp ngắn hơn hoặc chạy nhẹ 40 phút"
        case (.vi, .tempo): "chạy nhẹ 40 phút"
        case (.vi, _): "chạy nhẹ 30 phút"
        }
    }

    var engine: String {
        switch language {
        case .en: "Engine"
        case .ja: "エンジン"
        case .vi: "Máy đánh giá"
        }
    }

    var noVerdictYet: String {
        switch language {
        case .en: "No verdict yet"
        case .ja: "判定はまだありません"
        case .vi: "Chưa có kết luận"
        }
    }

    func engineText(verdict: ReadinessVerdict, ruleCodes: [String]) -> String {
        ([language.verdictWord(verdict)] + ruleCodes).reduce(engine) { partial, item in "\(partial) · \(item)" }
    }

    func engineCompactText(verdict: ReadinessVerdict, ruleCodes: [String]) -> String {
        ([language.verdictWord(verdict)] + ruleCodes).joined(separator: " · ")
    }

    func engineAccessibility(verdict: ReadinessVerdict?, ruleCodes: [String]) -> String {
        guard let verdict else {
            switch language {
            case .en: return "Engine readiness. No verdict yet."
            case .ja: return "コンディションエンジン。判定はまだありません。"
            case .vi: return "Máy đánh giá thể trạng. Chưa có kết luận."
            }
        }
        let codes = ruleCodes.joined(separator: ", ")
        guard !codes.isEmpty else {
            switch language {
            case .en: return "Engine readiness. \(language.verdictWord(verdict))."
            case .ja: return "コンディションエンジン。\(language.verdictWord(verdict))。"
            case .vi: return "Máy đánh giá thể trạng. \(language.verdictWord(verdict))."
            }
        }
        switch language {
        case .en: return "Engine readiness. \(language.verdictWord(verdict)). Fired rules \(codes)."
        case .ja: return "コンディションエンジン。\(language.verdictWord(verdict))。適用ルール：\(codes)。"
        case .vi: return "Máy đánh giá thể trạng. \(language.verdictWord(verdict)). Quy tắc đã áp dụng: \(codes)."
        }
    }

    var noReadinessOutput: String {
        switch language {
        case .en: "The readiness engine has not produced a verdict for today."
        case .ja: "コンディションエンジンは、今日の判定をまだ作成していません。"
        case .vi: "Máy đánh giá thể trạng chưa đưa ra kết luận cho hôm nay."
        }
    }

    var noTimestampAvailable: String {
        switch language {
        case .en: "No timestamp is available until today's readiness is computed."
        case .ja: "今日のコンディションが計算されるまで、時刻は表示されません。"
        case .vi: "Chưa có thời điểm cho tới khi thể trạng hôm nay được tính."
        }
    }

    func computedAt(_ date: Date) -> String {
        let dateText = date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().locale(language.uiLocale))
        switch language {
        case .en: return "Computed \(dateText)."
        case .ja: return "計算日時：\(dateText)。"
        case .vi: return "Đã tính lúc \(dateText)."
        }
    }

    var noRulesFired: String {
        switch language {
        case .en: "No deterministic readiness rules fired today."
        case .ja: "今日は決定的なコンディションルールは適用されませんでした。"
        case .vi: "Hôm nay không có quy tắc thể trạng xác định nào được áp dụng."
        }
    }

    var rules: String {
        switch language {
        case .en: "Rules"
        case .ja: "ルール"
        case .vi: "Quy tắc"
        }
    }

    var closePostRunReview: String {
        switch language {
        case .en: "Close post-run review"
        case .ja: "ラン後レビューを閉じる"
        case .vi: "Đóng đánh giá sau chạy"
        }
    }

    func postRunDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute().locale(language.uiLocale))
    }

    var running: String {
        switch language {
        case .en: "Running"
        case .ja: "ランニング"
        case .vi: "Chạy bộ"
        }
    }

    func postRunDistance(_ meters: Double?) -> String {
        guard let meters else { return language.genericRunLabel }
        let value = meters / 1_000
        switch language {
        case .en: return String(format: meters >= 9_950 ? "%.0fkm" : "%.1fkm", locale: language.uiLocale, value)
        case .ja: return String(format: meters >= 9_950 ? "%.0f km" : "%.1f km", locale: language.uiLocale, value)
        case .vi: return String(format: meters >= 9_950 ? "%.0f km" : "%.1f km", locale: language.uiLocale, value)
        }
    }

    func postRunHeadline(distance: String, minutes: Int) -> String {
        switch language {
        case .en: "\(distance) in \(minutes)min 🏃"
        case .ja: "\(distance)・\(minutes)分 🏃"
        case .vi: "\(distance) trong \(minutes) phút 🏃"
        }
    }

    var editAndShare: String {
        switch language {
        case .en: "Edit & Share"
        case .ja: "編集して共有"
        case .vi: "Sửa và chia sẻ"
        }
    }

    var new: String {
        switch language {
        case .en: "NEW"
        case .ja: "新着"
        case .vi: "MỚI"
        }
    }

    var hideReview: String {
        switch language {
        case .en: "Hide Review"
        case .ja: "レビューを隠す"
        case .vi: "Ẩn đánh giá"
        }
    }

    var review: String {
        switch language {
        case .en: "Review"
        case .ja: "レビュー"
        case .vi: "Đánh giá"
        }
    }

    var addNote: String {
        switch language {
        case .en: "Add Note"
        case .ja: "メモを追加"
        case .vi: "Thêm ghi chú"
        }
    }

    var reviewNotePlaceholder: String {
        switch language {
        case .en: "How did it feel? Share what the data can't, like motivation, fueling, or how hard it felt."
        case .ja: "どう感じましたか？ モチベーション、補給、きつさなど、データでは分からないことを記録しましょう。"
        case .vi: "Cảm giác thế nào? Hãy chia sẻ điều dữ liệu không nói lên được, như động lực, dinh dưỡng hoặc mức độ khó."
        }
    }

    func notificationTitle(_ verdict: ReadinessVerdict) -> String {
        switch (language, verdict) {
        case (.en, .train): "Train today"
        case (.en, .goEasy): "Go easy today"
        case (.en, .rest): "Rest today"
        case (.en, .insufficientData): "TrainOrRest"
        case (.ja, .train): "今日はトレーニング"
        case (.ja, .goEasy): "今日は軽めに"
        case (.ja, .rest): "今日は休養"
        case (.ja, .insufficientData): "TrainOrRest"
        case (.vi, .train): "Tập luyện hôm nay"
        case (.vi, .goEasy): "Tập nhẹ hôm nay"
        case (.vi, .rest): "Nghỉ ngơi hôm nay"
        case (.vi, .insufficientData): "TrainOrRest"
        }
    }

    var notificationDefaultBody: String {
        switch language {
        case .en: "All recovery signals look good."
        case .ja: "回復シグナルはすべて良好です。"
        case .vi: "Mọi tín hiệu hồi phục đều tốt."
        }
    }

    func widgetReason(_ verdict: ReadinessVerdict) -> String {
        switch (language, verdict) {
        case (.en, .train): "Ready for the planned session"
        case (.en, .goEasy): "Keep the effort controlled today"
        case (.en, .rest): "Recovery comes first today"
        case (.en, .insufficientData): "Collecting your baseline"
        case (.ja, .train): "予定のセッションに向けて準備完了"
        case (.ja, .goEasy): "今日は強度を抑えましょう"
        case (.ja, .rest): "今日は回復を最優先に"
        case (.ja, .insufficientData): "ベースラインを収集中"
        case (.vi, .train): "Sẵn sàng cho buổi tập theo kế hoạch"
        case (.vi, .goEasy): "Hôm nay hãy kiểm soát cường độ"
        case (.vi, .rest): "Hôm nay ưu tiên hồi phục"
        case (.vi, .insufficientData): "Đang thu thập mức cơ sở"
        }
    }
}
