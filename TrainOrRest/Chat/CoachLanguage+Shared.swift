import Foundation

/// Vocabulary shared by every screen (Today, Plan, History, Settings, …):
/// workout kinds, plan phases, verdicts, weekdays, statuses, and the few
/// generic labels that recur across tabs. Screen-specific copy lives in the
/// screen's own `CoachLanguage+<Screen>.swift` extension.
///
/// The English `displayName`/`torWord`/`cardTitle` properties on the model
/// enums stay untouched: they feed the coach prompt and existing tests. Views
/// must call these language-aware accessors instead.
extension CoachLanguage {
    // MARK: - Workout kinds

    func name(_ kind: WorkoutKind) -> String {
        switch (self, kind) {
        case (.en, .easy): "Easy"
        case (.en, .long): "Long Run"
        case (.en, .tempo): "Tempo"
        case (.en, .threshold): "Threshold"
        case (.en, .intervals): "Intervals"
        case (.en, .race): "Race"
        case (.ja, .easy): "イージー"
        case (.ja, .long): "ロング走"
        case (.ja, .tempo): "テンポ走"
        case (.ja, .threshold): "閾値走"
        case (.ja, .intervals): "インターバル"
        case (.ja, .race): "レース"
        case (.vi, .easy): "Chạy nhẹ"
        case (.vi, .long): "Chạy dài"
        case (.vi, .tempo): "Tempo"
        case (.vi, .threshold): "Ngưỡng"
        case (.vi, .intervals): "Biến tốc"
        case (.vi, .race): "Thi đấu"
        }
    }

    /// Fallback noun when a planned workout has no recognised kind.
    var genericRunLabel: String {
        switch self {
        case .en: "Run"
        case .ja: "ラン"
        case .vi: "Buổi chạy"
        }
    }

    var restDayLabel: String {
        switch self {
        case .en: "Rest day"
        case .ja: "休養日"
        case .vi: "Ngày nghỉ"
        }
    }

    var recoveryLabel: String {
        switch self {
        case .en: "Recovery"
        case .ja: "リカバリー"
        case .vi: "Hồi phục"
        }
    }

    // MARK: - Plan phases

    func name(_ phase: TrainingPhase) -> String {
        switch (self, phase) {
        case (.en, .base): "Base"
        case (.en, .build): "Build"
        case (.en, .peak): "Peak"
        case (.en, .taper): "Taper"
        case (.ja, .base): "基礎期"
        case (.ja, .build): "強化期"
        case (.ja, .peak): "ピーク期"
        case (.ja, .taper): "調整期"
        case (.vi, .base): "Nền tảng"
        case (.vi, .build): "Xây dựng"
        case (.vi, .peak): "Đỉnh cao"
        case (.vi, .taper): "Giảm tải"
        }
    }

    // MARK: - Workout status chips

    func name(_ status: WorkoutStatus) -> String {
        switch (self, status) {
        case (.en, .planned): "Planned"
        case (.en, .done): "Done"
        case (.en, .skipped): "Skipped"
        case (.ja, .planned): "予定"
        case (.ja, .done): "完了"
        case (.ja, .skipped): "スキップ"
        case (.vi, .planned): "Dự kiến"
        case (.vi, .done): "Hoàn thành"
        case (.vi, .skipped): "Bỏ qua"
        }
    }

    // MARK: - Completed-run effort

    func name(_ effort: RunEffort) -> String {
        switch (self, effort) {
        case (.en, .easy): "Easy"
        case (.en, .tempo): "Tempo"
        case (.en, .long): "Long run"
        case (.en, .intervals): "Intervals"
        case (.ja, .easy): "イージー"
        case (.ja, .tempo): "テンポ"
        case (.ja, .long): "ロング走"
        case (.ja, .intervals): "インターバル"
        case (.vi, .easy): "Nhẹ"
        case (.vi, .tempo): "Tempo"
        case (.vi, .long): "Chạy dài"
        case (.vi, .intervals): "Biến tốc"
        }
    }

    // MARK: - Race distances

    func name(_ distance: RaceDistance) -> String {
        switch (self, distance) {
        case (_, .fiveK): "5K"
        case (_, .tenK): "10K"
        case (.en, .halfMarathon): "Half Marathon"
        case (.en, .marathon): "Marathon"
        case (.ja, .halfMarathon): "ハーフマラソン"
        case (.ja, .marathon): "フルマラソン"
        case (.vi, .halfMarathon): "Bán marathon"
        case (.vi, .marathon): "Marathon"
        }
    }

    // MARK: - Readiness verdict

    /// Short verdict word for the banner, engine header, chips, and widget (title case per DESIGN.md).
    func verdictWord(_ verdict: ReadinessVerdict) -> String {
        switch (self, verdict) {
        case (.en, .train): "Train"
        case (.en, .goEasy): "Go easy"
        case (.en, .rest): "Rest"
        case (.en, .insufficientData): "Baseline"
        case (.ja, .train): "トレーニング"
        case (.ja, .goEasy): "軽めに"
        case (.ja, .rest): "休養"
        case (.ja, .insufficientData): "ベースライン"
        case (.vi, .train): "Tập"
        case (.vi, .goEasy): "Nhẹ"
        case (.vi, .rest): "Nghỉ"
        case (.vi, .insufficientData): "Cơ sở"
        }
    }

    /// Title-case verdict for cards and headers.
    func verdictTitle(_ verdict: ReadinessVerdict) -> String {
        switch (self, verdict) {
        case (.en, .train): "Train"
        case (.en, .goEasy): "Go Easy"
        case (.en, .rest): "Rest"
        case (.en, .insufficientData): "Building Your Baseline"
        case (.ja, .train): "トレーニング"
        case (.ja, .goEasy): "軽めに"
        case (.ja, .rest): "休養"
        case (.ja, .insufficientData): "ベースラインを作成中"
        case (.vi, .train): "Tập luyện"
        case (.vi, .goEasy): "Tập nhẹ"
        case (.vi, .rest): "Nghỉ ngơi"
        case (.vi, .insufficientData): "Đang xây dựng mức cơ sở"
        }
    }

    func verdictSubtitle(_ verdict: ReadinessVerdict) -> String {
        switch (self, verdict) {
        case (.en, .train): "Primed for a quality session"
        case (.en, .goEasy): "Keep it light — active recovery"
        case (.en, .rest): "Recovery comes first today"
        case (.en, .insufficientData): "Collecting your baseline"
        case (.ja, .train): "質の高いセッションに最適"
        case (.ja, .goEasy): "軽めに — アクティブリカバリー"
        case (.ja, .rest): "今日は回復を優先"
        case (.ja, .insufficientData): "ベースラインを収集中"
        case (.vi, .train): "Sẵn sàng cho buổi tập chất lượng"
        case (.vi, .goEasy): "Giữ nhẹ — hồi phục tích cực"
        case (.vi, .rest): "Hôm nay ưu tiên hồi phục"
        case (.vi, .insufficientData): "Đang thu thập mức cơ sở"
        }
    }

    // MARK: - Check-in signals

    func name(_ signal: CheckInSignal) -> String {
        switch (self, signal) {
        case (.en, .sore): "Sore"
        case (.en, .ill): "Ill"
        case (.en, .poorSleep): "Poor sleep"
        case (.en, .travel): "Travel"
        case (.en, .alcohol): "Alcohol"
        case (.en, .stress): "Stress"
        case (.en, .heat): "Heat"
        case (.ja, .sore): "筋肉痛"
        case (.ja, .ill): "体調不良"
        case (.ja, .poorSleep): "睡眠不足"
        case (.ja, .travel): "移動"
        case (.ja, .alcohol): "飲酒"
        case (.ja, .stress): "ストレス"
        case (.ja, .heat): "暑さ"
        case (.vi, .sore): "Đau nhức"
        case (.vi, .ill): "Ốm"
        case (.vi, .poorSleep): "Ngủ kém"
        case (.vi, .travel): "Di chuyển"
        case (.vi, .alcohol): "Rượu bia"
        case (.vi, .stress): "Căng thẳng"
        case (.vi, .heat): "Nóng"
        }
    }

    // MARK: - Weekdays

    /// Abbreviated weekday for calendar headers and day pickers.
    func shortName(_ weekday: Weekday) -> String {
        switch (self, weekday) {
        case (.en, _): weekday.shortName
        case (.ja, .sunday): "日"
        case (.ja, .monday): "月"
        case (.ja, .tuesday): "火"
        case (.ja, .wednesday): "水"
        case (.ja, .thursday): "木"
        case (.ja, .friday): "金"
        case (.ja, .saturday): "土"
        case (.vi, .sunday): "CN"
        case (.vi, .monday): "T2"
        case (.vi, .tuesday): "T3"
        case (.vi, .wednesday): "T4"
        case (.vi, .thursday): "T5"
        case (.vi, .friday): "T6"
        case (.vi, .saturday): "T7"
        }
    }

    // MARK: - Generic labels shared across tabs

    var todayLabel: String {
        switch self {
        case .en: "Today"
        case .ja: "今日"
        case .vi: "Hôm nay"
        }
    }

    var tomorrowLabel: String {
        switch self {
        case .en: "Tomorrow"
        case .ja: "明日"
        case .vi: "Ngày mai"
        }
    }

    var detailsLabel: String {
        switch self {
        case .en: "Details"
        case .ja: "詳細"
        case .vi: "Chi tiết"
        }
    }




    var deleteLabel: String {
        switch self {
        case .en: "Delete"
        case .ja: "削除"
        case .vi: "Xóa"
        }
    }

    var editLabel: String {
        switch self {
        case .en: "Edit"
        case .ja: "編集"
        case .vi: "Sửa"
        }
    }


    var continueLabel: String {
        switch self {
        case .en: "Continue"
        case .ja: "続ける"
        case .vi: "Tiếp tục"
        }
    }

    var backLabel: String {
        switch self {
        case .en: "Back"
        case .ja: "戻る"
        case .vi: "Quay lại"
        }
    }




    var heartRateLabel: String {
        switch self {
        case .en: "Heart rate"
        case .ja: "心拍数"
        case .vi: "Nhịp tim"
        }
    }

    var sleepLabel: String {
        switch self {
        case .en: "Sleep"
        case .ja: "睡眠"
        case .vi: "Giấc ngủ"
        }
    }

    var readinessLabel: String {
        switch self {
        case .en: "Readiness"
        case .ja: "コンディション"
        case .vi: "Thể trạng"
        }
    }

    var trainingLoadLabel: String {
        switch self {
        case .en: "Training load"
        case .ja: "トレーニング負荷"
        case .vi: "Khối lượng tập"
        }
    }

    var weekLabel: String {
        switch self {
        case .en: "Week"
        case .ja: "週"
        case .vi: "Tuần"
        }
    }

    /// "Week of <date>" header prefix; callers append the localized date.
    func weekOf(_ dateText: String) -> String {
        switch self {
        case .en: "Week of \(dateText)"
        case .ja: "\(dateText)の週"
        case .vi: "Tuần từ \(dateText)"
        }
    }

    /// Ordinal plan week, e.g. "Week 3".
    func weekNumber(_ index: Int) -> String {
        switch self {
        case .en: "Week \(index)"
        case .ja: "第\(index)週"
        case .vi: "Tuần \(index)"
        }
    }

    // MARK: - Locale-aware date helpers

    /// Full weekday + month + day, e.g. "Monday, March 3".
    func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(uiLocale))
    }

    /// Abbreviated month + day, e.g. "Mar 3".
    func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(uiLocale))
    }

    /// Abbreviated weekday + abbreviated month + day, e.g. "Mon, Mar 3".
    func shortWeekdayDate(_ date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = uiLocale
        return date.formatted(style)
    }

    /// Month + year for calendar navigation, e.g. "March 2026".
    func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(uiLocale))
    }

    /// Hour + minute in the language's conventional clock format.
    func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(uiLocale))
    }
}
