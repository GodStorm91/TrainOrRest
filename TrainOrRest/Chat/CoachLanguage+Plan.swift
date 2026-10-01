import Foundation

extension CoachLanguage {
    var plan: PlanCopy { PlanCopy(language: self) }
}

struct PlanCopy {
    let language: CoachLanguage

    // MARK: - Calendar

    var trainingPlanTitle: String { text(en: "Training Plan", ja: "トレーニングプラン", vi: "Kế hoạch tập luyện") }
    var monthMode: String { text(en: "Month", ja: "月", vi: "Tháng") }
    var weekMode: String { text(en: "Week", ja: "週", vi: "Tuần") }
    var weatherOnNoForecast: String { text(en: "Weather on · no forecast", ja: "天気オン・予報なし", vi: "Thời tiết bật · chưa có dự báo") }
    var updatingForecast: String { text(en: "Updating 10-day forecast…", ja: "10日予報を更新中…", vi: "Đang cập nhật dự báo 10 ngày…") }
    var addWeatherForRun: String { text(en: "Add weather for this run", ja: "このランの天気を追加", vi: "Thêm thời tiết cho buổi chạy") }
    var weatherUnavailable: String { text(en: "Forecast unavailable. Plan unchanged.", ja: "予報を利用できません。プランは変更されていません。", vi: "Không có dự báo. Kế hoạch không thay đổi.") }
    var weatherRetry: String { text(en: "Retry", ja: "再試行", vi: "Thử lại") }
    var appleWeatherMark: String { " Weather" }
    var weatherLegalSource: String { text(en: "Other data sources", ja: "その他のデータソース", vi: "Nguồn dữ liệu khác") }
    var weatherAttributionAccessibility: String { "\(appleWeatherMark), \(weatherLegalSource)" }
    var weatherMissingLocation: String { text(en: "Set a run location to load weather.", ja: "天気を読み込むにはラン地点を設定します。", vi: "Đặt vị trí chạy để tải thời tiết.") }
    var search: String { text(en: "Search", ja: "検索", vi: "Tìm") }
    var findTimeWithCalendar: String { text(en: "Find a better time with Calendar", ja: "カレンダーでより良い時間を探す", vi: "Tìm giờ tốt hơn với Lịch") }
    var syncIntervals: String { text(en: "Sync intervals.icu", ja: "intervals.icuと同期", vi: "Đồng bộ intervals.icu") }
    var noPlanYet: String { text(en: "No plan yet", ja: "プランはまだありません", vi: "Chưa có kế hoạch") }
    var noPlanDescription: String { text(en: "Set a race goal and TrainOrRest builds your day-by-day training plan.", ja: "レース目標を設定すると、TrainOrRestが日ごとのトレーニングプランを作成します。", vi: "Đặt mục tiêu cuộc đua để TrainOrRest xây dựng kế hoạch tập luyện theo từng ngày.") }
    var setRaceGoal: String { text(en: "Set race goal", ja: "レース目標を設定", vi: "Đặt mục tiêu cuộc đua") }
    var setEnteredRace: String { text(en: "Set the race you entered", ja: "参加するレースを設定", vi: "Đặt cuộc đua bạn đã đăng ký") }
    var changeGoal: String { text(en: "Change goal", ja: "目標を変更", vi: "Đổi mục tiêu") }
    var connectGoogleCalendar: String { text(en: "Connect Google Calendar", ja: "Google カレンダーに接続", vi: "Kết nối Google Calendar") }
    func googleChangesNeedReview(_ count: Int) -> String { text(en: "Google Calendar · \(count) changes need review", ja: "Google カレンダー・\(count)件の変更を確認", vi: "Google Calendar · \(count) thay đổi cần xem lại") }
    var googleUpToDate: String { text(en: "Google Calendar · Up to date", ja: "Google カレンダー・最新", vi: "Google Calendar · Đã cập nhật") }
    var googleSyncing: String { text(en: "Google Calendar · Syncing", ja: "Google カレンダー・同期中", vi: "Google Calendar · Đang đồng bộ") }
    var googleReconnectRequired: String { text(en: "Google Calendar · Reconnect required", ja: "Google カレンダー・再接続が必要", vi: "Google Calendar · Cần kết nối lại") }
    var googleWaitingForConnection: String { text(en: "Google Calendar · Waiting for connection", ja: "Google カレンダー・接続待ち", vi: "Google Calendar · Đang chờ kết nối") }
    var googleNeedsAttention: String { text(en: "Google Calendar · Needs attention", ja: "Google カレンダー・要確認", vi: "Google Calendar · Cần chú ý") }
    var googleChangesNeedReviewAccessibility: String { text(en: "Google Calendar changes need review", ja: "Google カレンダーの変更を確認", vi: "Các thay đổi Google Calendar cần xem lại") }
    var googleConnectedAccessibility: String { text(en: "Google Calendar connected", ja: "Google カレンダーに接続済み", vi: "Đã kết nối Google Calendar") }
    var googleSyncingAccessibility: String { text(en: "Google Calendar syncing", ja: "Google カレンダーを同期中", vi: "Đang đồng bộ Google Calendar") }
    var googleReconnectAccessibility: String { text(en: "Google Calendar needs reconnect", ja: "Google カレンダーの再接続が必要", vi: "Google Calendar cần kết nối lại") }
    var manageGoogleSyncAccessibility: String { text(en: "Manage Google Calendar sync", ja: "Google カレンダーの同期を管理", vi: "Quản lý đồng bộ Google Calendar") }
    var dismissGoogleCalendarStatusAccessibility: String { text(en: "Dismiss Google Calendar status", ja: "Google カレンダーのステータスを閉じる", vi: "Đóng trạng thái Google Calendar") }
    var noWorkoutsToSync: String { text(en: "Nothing to sync right now.", ja: "現在同期するワークアウトはありません。", vi: "Hiện không có buổi tập nào để đồng bộ.") }
    var retry: String { text(en: "Retry", ja: "再試行", vi: "Thử lại") }
    var retryIntervalsAccessibility: String { text(en: "Retry intervals.icu sync", ja: "intervals.icuの同期を再試行", vi: "Thử lại đồng bộ intervals.icu") }
    var syncingIntervals: String { text(en: "Syncing planned workouts to intervals.icu…", ja: "予定ワークアウトをintervals.icuと同期中…", vi: "Đang đồng bộ buổi tập dự kiến với intervals.icu…") }
    func syncedIntervals(_ date: Date) -> String { text(en: "Synced to intervals.icu · \(language.shortDate(date)) \(language.time(date))", ja: "intervals.icuと同期済み・\(language.shortDate(date)) \(language.time(date))", vi: "Đã đồng bộ với intervals.icu · \(language.shortDate(date)) \(language.time(date))") }
    func syncSkipped(_ reason: String) -> String { text(en: "Sync skipped · \(reason)", ja: "同期をスキップ・\(reason)", vi: "Bỏ qua đồng bộ · \(reason)") }
    func syncFailed(_ reason: String) -> String { text(en: "Could not sync to intervals.icu · \(reason)", ja: "intervals.icuと同期できませんでした・\(reason)", vi: "Không thể đồng bộ với intervals.icu · \(reason)") }
    func moreRecentChanges(_ count: Int) -> String { text(en: "+\(count) more recent change\(count == 1 ? "" : "s")", ja: "ほかに\(count)件の最近の変更", vi: "+\(count) thay đổi gần đây khác") }
    func coachUpdatedWorkout(_ summary: String) -> String { text(en: "Coach updated 1 workout · \(summary)", ja: "Coachが1件のワークアウトを更新・\(summary)", vi: "Coach đã cập nhật 1 buổi tập · \(summary)") }
    var undo: String { text(en: "Undo", ja: "元に戻す", vi: "Hoàn tác") }
    var undoCoachWorkoutChangeAccessibility: String { text(en: "Undo Coach workout change", ja: "Coachによるワークアウト変更を元に戻す", vi: "Hoàn tác thay đổi buổi tập của Coach") }
    var dismissRecentCoachChangesAccessibility: String { text(en: "Dismiss recent Coach changes", ja: "最近のCoachによる変更を閉じる", vi: "Đóng các thay đổi gần đây của Coach") }
    func workoutChangeSummary(beforeKind: String, beforeDistance: String, afterKind: String, afterDistance: String) -> String { "\(beforeKind) \(beforeDistance) km → \(afterKind) \(afterDistance) km" }

    var reviewNextSevenDays: String { text(en: "Review next 7 days", ja: "次の7日間を確認", vi: "Xem lại 7 ngày tới") }
    var nextWeekReviewQueued: String { text(en: "Run synced. A next-week review starts when sync finishes.", ja: "ランを同期しました。同期完了後に次週レビューを開始します。", vi: "Đã đồng bộ buổi chạy. Đánh giá tuần tới sẽ bắt đầu khi đồng bộ hoàn tất.") }
    var nextWeekReviewNeedsKey: String { text(en: "Add a Coach provider key to review the next 7 days.", ja: "次の7日間を確認するにはCoachプロバイダーキーを追加してください。", vi: "Thêm khóa nhà cung cấp Coach để xem lại 7 ngày tới.") }
    var nextWeekReviewPreparing: String { text(en: "Preparing a next-week review. No plan changes have been made.", ja: "次週レビューを準備中です。プランは変更されていません。", vi: "Đang chuẩn bị đánh giá tuần tới. Kế hoạch chưa thay đổi.") }
    var nextWeekReviewReady: String { text(en: "Review ready. No changes have been made.", ja: "レビューの準備ができました。変更はまだありません。", vi: "Đánh giá đã sẵn sàng. Chưa có thay đổi nào.") }
    func nextWeekReviewScope(_ dateRange: String) -> String {
        text(
            en: "Next 7 days · \(dateRange). Keep closes this review.",
            ja: "次の7日間 · \(dateRange)。保持するとこのレビューを閉じます。",
            vi: "7 ngày tới · \(dateRange). Giữ nguyên sẽ đóng bản đánh giá này."
        )
    }
    var nextWeekReviewNoChange: String { text(en: "No changes needed for the next 7 days.", ja: "次の7日間に変更は必要ありません。", vi: "Không cần thay đổi cho 7 ngày tới.") }
    var nextWeekReviewFailed: String { text(en: "Couldn't prepare a review. Retry manually.", ja: "レビューを準備できませんでした。手動で再試行してください。", vi: "Không thể chuẩn bị đánh giá. Hãy thử lại thủ công.") }
    var nextWeekReviewStale: String { text(en: "This review is out of date. Review the new diff before applying.", ja: "このレビューは古くなっています。適用前に新しい差分を確認してください。", vi: "Đánh giá này đã cũ. Xem lại khác biệt mới trước khi áp dụng.") }
    var nextWeekReviewApplied: String { text(en: "Applied. You can undo this in Recent Coach changes for 7 days.", ja: "適用しました。7日間は最近のCoach変更から元に戻せます。", vi: "Đã áp dụng. Bạn có thể hoàn tác trong Thay đổi Coach gần đây trong 7 ngày.") }
    var nextWeekReviewReverted: String { text(en: "Reverted.", ja: "元に戻しました。", vi: "Đã hoàn tác.") }
    var nextWeekReviewSuperseded: String { text(en: "A newer review replaced this one.", ja: "より新しいレビューに置き換えられました。", vi: "Một đánh giá mới hơn đã thay thế đánh giá này.") }
    var retryManually: String { text(en: "Retry manually", ja: "手動で再試行", vi: "Thử lại thủ công") }
    var connectCoach: String { text(en: "Connect your coach", ja: "Coach に接続", vi: "Kết nối Coach") }
    var nextWeekReviewSettingsTitle: String { text(en: "Next-week review", ja: "次週レビュー", vi: "Đánh giá tuần tới") }
    func automaticNextWeekReview(provider: String) -> String { text(en: "Automatically review next week with \(provider)", ja: "\(provider)で次週を自動レビュー", vi: "Tự động đánh giá tuần tới với \(provider)") }
    var connectCoachFirst: String { text(en: "Connect a coach above to turn this on.", ja: "オンにするには、上で Coach に接続してください。", vi: "Kết nối Coach ở trên để bật mục này.") }
    func nextWeekReviewDisclosure(provider: String) -> String {
        text(
            en: "When enabled, \(provider) receives distance, duration, pace, and average and maximum heart rate for the finished run and up to 7 runs from the last 7 days, plus your current readiness and the next 7 planned days.",
            ja: "有効にすると、\(provider)には完了したランと直近7日間の最大7件のランの距離、時間、ペース、平均・最大心拍数に加え、現在のレディネスと次の7日間の予定が送信されます。",
            vi: "Khi bật, \(provider) nhận quãng đường, thời lượng, pace, nhịp tim trung bình và tối đa của buổi chạy hoàn thành và tối đa 7 buổi chạy trong 7 ngày qua, cùng mức sẵn sàng hiện tại và 7 ngày kế hoạch tiếp theo."
        )
    }

    // MARK: - Month and week views

    var todayCall: String { text(en: "Today's call", ja: "今日のメニュー", vi: "Buổi tập hôm nay") }
    var completedRun: String { text(en: "Completed run", ja: "完了したラン", vi: "Buổi chạy đã hoàn thành") }
    var completedToday: String { text(en: "Completed today", ja: "今日の完了", vi: "Đã hoàn thành hôm nay") }
    var completedOnSelectedDay: String { text(en: "Completed on selected day", ja: "選択日の完了", vi: "Đã hoàn thành vào ngày đã chọn") }
    var recoveryAndAdaptation: String { text(en: "Recovery and adaptation", ja: "回復と適応", vi: "Hồi phục và thích nghi") }
    var sessionLabel: String { text(en: "Session", ja: "セッション", vi: "Buổi tập") }
    var autoLabel: String { text(en: "Auto", ja: "自動", vi: "Tự động") }
    var reviewWithCoach: String { text(en: "Review with Coach", ja: "Coachと振り返る", vi: "Xem lại với Coach") }

    var stillPlannedToday: String {
        text(en: "Still planned today", ja: "今日の予定のまま", vi: "Vẫn dự kiến hôm nay")
    }

    var stillPlannedOnSelectedDay: String {
        text(en: "Still planned on selected day", ja: "選択した日の予定のまま", vi: "Vẫn dự kiến vào ngày đã chọn")
    }

    func stillPlannedAccessibility(scope: String, workout: String, metrics: String) -> String {
        switch language {
        case .en: "\(scope): \(workout), \(metrics)"
        case .ja: "\(scope)、\(workout)、\(metrics)"
        case .vi: "\(scope): \(workout), \(metrics)"
        }
    }

    func linkedRunTitle(_ name: String) -> String { text(en: "Done: \(name)", ja: "完了: \(name)", vi: "Đã hoàn thành: \(name)") }
    func planComparison(_ planText: String) -> String { text(en: "Plan \(planText)", ja: "予定 \(planText)", vi: "Kế hoạch \(planText)") }
    func suggestRunLinkTitle(_ kilometers: String, name: String) -> String { text(en: "Link your \(kilometers) run to \(name)?", ja: "\(kilometers)のランを\(name)に紐づけますか？", vi: "Liên kết buổi chạy \(kilometers) với \(name)?") }
    var linkRunAction: String { text(en: "Link", ja: "紐づける", vi: "Liên kết") }
    var notThisRunAction: String { text(en: "Not this", ja: "違う", vi: "Không phải") }
    var unlinkRunAction: String { text(en: "Unlink", ja: "解除", vi: "Bỏ liên kết") }
    var unlinkRunRow: String { text(en: "Unlink run", ja: "ランの紐づけを解除", vi: "Bỏ liên kết buổi chạy") }
    var linkRunSection: String { text(en: "Link a run", ja: "ランを紐づける", vi: "Liên kết buổi chạy") }
    var linkRunFooter: String { text(en: "Runs recorded on this day.", ja: "この日に記録されたラン。", vi: "Các buổi chạy ghi nhận trong ngày này.") }
    func skippedRunTitle(_ name: String) -> String { text(en: "Skipped: \(name)", ja: "スキップ: \(name)", vi: "Đã bỏ qua: \(name)") }
    func unplannedRunTitle(_ detail: String) -> String { text(en: "Unplanned run: \(detail)", ja: "予定外のラン: \(detail)", vi: "Buổi chạy ngoài kế hoạch: \(detail)") }
    func linkRunAccessibility(_ name: String) -> String { text(en: "Link run to \(name)", ja: "ランを\(name)に紐づける", vi: "Liên kết buổi chạy với \(name)") }
    var linkUpdateFailed: String { text(en: "Couldn't update the run link. Try again.", ja: "ランの紐づけを更新できませんでした。もう一度お試しください。", vi: "Không cập nhật được liên kết buổi chạy. Hãy thử lại.") }
    var editWithCoach: String { text(en: "Edit with Coach", ja: "Coachと編集", vi: "Chỉnh sửa với Coach") }
    var askCoach: String { text(en: "Ask Coach", ja: "Coachに聞く", vi: "Hỏi Coach") }
    var reviewCompletedRunAccessibility: String { text(en: "Review completed run with Coach", ja: "完了したランをCoachと振り返る", vi: "Xem lại buổi chạy đã hoàn thành với Coach") }
    func openTodayWorkoutAccessibility(_ name: String) -> String { text(en: "Open today’s \(name)", ja: "今日の\(name)を開く", vi: "Mở \(name) hôm nay") }
    var openWorkoutDetailsAccessibility: String { text(en: "Open workout details", ja: "ワークアウトの詳細を開く", vi: "Mở chi tiết buổi tập") }
    func coachActionAccessibility(_ action: String, workout: String) -> String { "\(action) \(workout)" }
    func dayAccessibility(date: Date, kind: WorkoutKind?, isToday: Bool, weatherStance: String? = nil) -> String {
        let name = kind.map(language.name) ?? language.restDayLabel
        let base: String
        switch language {
        case .en: base = "\(language.shortDate(date))\(isToday ? ", today" : ""), \(name)"
        case .ja: base = "\(language.shortDate(date))\(isToday ? "、今日" : "")、\(name)"
        case .vi: base = "\(language.shortDate(date))\(isToday ? ", hôm nay" : ""), \(name)"
        }
        guard let weatherStance, !weatherStance.isEmpty else { return base }
        return "\(base), \(weatherStance)"
    }
    var weekVolumeHeader: String { text(en: "Week", ja: "週", vi: "Tuần") }
    func weekVolumeAccessibility(completed: Int, planned: Int) -> String {
        text(
            en: "\(completed) of \(planned) kilometers this week",
            ja: "今週 \(completed) / \(planned) km",
            vi: "Tuần này \(completed) / \(planned) km"
        )
    }
    func weekVolumePlannedAccessibility(_ kilometers: Int) -> String {
        text(
            en: "\(kilometers) kilometers planned this week",
            ja: "今週の予定 \(kilometers) km",
            vi: "Tuần này dự kiến \(kilometers) km"
        )
    }
    func planReceipt(phase: String, source: PlanReceiptSource) -> String {
        switch (language, source) {
        case (.en, .calendar): "\(phase) phase · synced from calendar"
        case (.ja, .calendar): "\(phase)期・カレンダーから同期"
        case (.vi, .calendar): "Giai đoạn \(phase) · đã đồng bộ từ lịch"
        case (.en, .moved): "\(phase) phase · moved to fit your week"
        case (.ja, .moved): "\(phase)期・今週に合わせて移動"
        case (.vi, .moved): "Giai đoạn \(phase) · đã dời để phù hợp tuần này"
        case (.en, .onPlan): "\(phase) phase · on plan"
        case (.ja, .onPlan): "\(phase)期・プランどおり"
        case (.vi, .onPlan): "Giai đoạn \(phase) · đúng theo kế hoạch"
        }
    }
    func workoutPurpose(_ kind: WorkoutKind) -> String {
        switch (language, kind) {
        case (.en, .easy): "Aerobic base at an easy, conversational effort."
        case (.ja, .easy): "会話できる楽な強度で有酸素の土台を作ります。"
        case (.vi, .easy): "Xây nền tảng aerobic ở cường độ nhẹ, có thể trò chuyện."
        case (.en, .long): "Extends endurance for race distance."
        case (.ja, .long): "レース距離に向けた持久力を伸ばします。"
        case (.vi, .long): "Phát triển sức bền cho cự ly đua."
        case (.en, .tempo): "Sustained, comfortably-hard race effort."
        case (.ja, .tempo): "心地よくきついレース強度を維持します。"
        case (.vi, .tempo): "Duy trì nỗ lực cường độ đua, khó nhưng kiểm soát được."
        case (.en, .threshold): "Raises your lactate threshold."
        case (.ja, .threshold): "乳酸性作業閾値を高めます。"
        case (.vi, .threshold): "Nâng ngưỡng lactate của bạn."
        case (.en, .intervals): "Short, fast reps that sharpen speed."
        case (.ja, .intervals): "短く速い反復でスピードを磨きます。"
        case (.vi, .intervals): "Các đoạn ngắn, nhanh để cải thiện tốc độ."
        case (.en, .race): "Your goal race. The plan builds to this."
        case (.ja, .race): "目標レースです。プランはここに向けて進みます。"
        case (.vi, .race): "Cuộc đua mục tiêu. Kế hoạch được xây dựng hướng đến đây."
        }
    }
    func weekRange(_ start: Date, _ end: Date) -> String {
        let startMonth = start.formatted(.dateTime.month(.abbreviated).locale(language.uiLocale))
        let endMonth = end.formatted(.dateTime.month(.abbreviated).locale(language.uiLocale))
        let startDay = Calendar.current.component(.day, from: start)
        let endDay = Calendar.current.component(.day, from: end)
        if startMonth == endMonth { return "\(startMonth) \(startDay) – \(endDay)" }
        return "\(startMonth) \(startDay) – \(endMonth) \(endDay)"
    }
    func weekSummary(completed: String?, planned: String, completedLoad: Int?, plannedLoad: Int) -> String {
        let load = language.trainingLoadLabel
        if let completed, let completedLoad { return "\(completed) / \(planned) · \(completedLoad) / \(plannedLoad) \(load)" }
        return "\(planned) · \(plannedLoad) \(load)"
    }

    // MARK: - Plan changes

    var noChanges: String { text(en: "No Changes", ja: "変更なし", vi: "Không có thay đổi") }
    var planMatchesYesterday: String { text(en: "Today's plan matches yesterday's schedule.", ja: "今日のプランは昨日のスケジュールと同じです。", vi: "Kế hoạch hôm nay khớp với lịch hôm qua.") }
    var changesLimitedNotice: String { text(en: "Changes are limited to the upcoming plan window and reviewed by local training rules.", ja: "変更は今後のプラン期間に限定され、ローカルのトレーニングルールで確認済みです。", vi: "Thay đổi chỉ áp dụng cho phần kế hoạch sắp tới và đã được kiểm tra theo quy tắc tập luyện cục bộ.") }
    var planChangesTitle: String { text(en: "Plan Changes", ja: "プランの変更", vi: "Thay đổi kế hoạch") }
    var beforeLabel: String { text(en: "Before", ja: "変更前", vi: "Trước") }
    var nowLabel: String { text(en: "Now", ja: "現在", vi: "Hiện tại") }
    var reviewedByRules: String { text(en: "Reviewed by local plan rules before it reached your calendar.", ja: "カレンダーに反映する前にローカルのプランルールで確認済みです。", vi: "Đã được kiểm tra theo quy tắc kế hoạch cục bộ trước khi đến lịch của bạn.") }
    var noWorkoutImpact: String { text(en: "No workout impact.", ja: "ワークアウトへの影響はありません。", vi: "Không ảnh hưởng đến buổi tập.") }
    func readinessReason(_ verdict: ReadinessVerdict) -> String { text(en: "Triggered by today's \(language.verdictTitle(verdict).lowercased()) readiness verdict", ja: "今日の\(language.verdictTitle(verdict))のコンディション判定で実行", vi: "Được kích hoạt bởi đánh giá thể trạng \(language.verdictTitle(verdict).lowercased()) hôm nay") }
    var volumeRefitReason: String { text(en: "Adjusted after recent completed training changed the volume fit", ja: "最近完了したトレーニングに合わせて走行量を調整", vi: "Đã điều chỉnh sau khi các buổi tập hoàn thành gần đây thay đổi mức tải phù hợp") }
    func intensityChanged(from: String, to: String) -> String { text(en: "Changed intensity from \(from.lowercased()) to \(to.lowercased()).", ja: "強度を\(from)から\(to)へ変更。", vi: "Đã thay đổi cường độ từ \(from.lowercased()) sang \(to.lowercased()).") }
    func distanceChanged(_ delta: Double) -> String { text(en: "Distance changed by \(String(format: "%.1f", delta)) km.", ja: "距離を\(String(format: "%.1f", delta)) km変更。", vi: "Đã thay đổi quãng đường \(String(format: "%.1f", delta)) km.") }
    var workoutUpdatedDetails: String { text(en: "Workout kept in place with updated training details.", ja: "ワークアウトはそのままでトレーニング詳細を更新しました。", vi: "Giữ nguyên buổi tập và cập nhật chi tiết tập luyện.") }
    var workoutRemovedRecovery: String { text(en: "Workout removed so the day becomes recovery.", ja: "ワークアウトを削除して回復日にしました。", vi: "Đã bỏ buổi tập để ngày này trở thành ngày hồi phục.") }
    func workoutAddedBalanced(_ kind: String) -> String { text(en: "Added \(kind.lowercased()) to keep the plan balanced.", ja: "プランのバランスを保つため\(kind)を追加。", vi: "Đã thêm \(kind.lowercased()) để giữ cân bằng kế hoạch.") }
    func createdWorkout(kind: String, on day: String) -> String {
        text(en: "Created \(kind) on \(day)", ja: "\(day)に\(kind)を作成しました", vi: "Đã tạo \(kind) vào \(day)")
    }
    func removedDuplicateWorkouts(_ count: Int, on day: String) -> String {
        text(
            en: "Removed \(count) duplicate workout\(count == 1 ? "" : "s") on \(day)",
            ja: "\(day)の重複したワークアウトを\(count)件削除しました",
            vi: "Đã xóa \(count) buổi tập trùng lặp vào \(day)"
        )
    }
    func restedWorkout(on day: String) -> String {
        text(en: "Rested \(day)", ja: "\(day)を休養日にしました", vi: "Đã chuyển \(day) thành ngày nghỉ")
    }
    func downgradedWorkout(on day: String, to kind: String) -> String {
        text(en: "Downgraded \(day) to \(kind)", ja: "\(day)を\(kind)に軽減しました", vi: "Đã giảm buổi tập \(day) xuống \(kind)")
    }
    func movedWorkout(from source: String, to target: String) -> String {
        text(en: "Moved \(source) to \(target)", ja: "\(source)を\(target)に移動しました", vi: "Đã chuyển \(source) sang \(target)")
    }
    func swappedWorkouts(_ first: String, with second: String) -> String {
        text(en: "Swapped \(first) with \(second)", ja: "\(first)と\(second)を入れ替えました", vi: "Đã đổi \(first) với \(second)")
    }
    func replacedWorkout(on day: String, with kind: String) -> String {
        text(en: "Replaced \(day) with \(kind)", ja: "\(day)を\(kind)に変更しました", vi: "Đã thay buổi tập vào \(day) bằng \(kind)")
    }

    // MARK: - Plan detail

    var couldNotLoadDetails: String { text(en: "Could not load plan details", ja: "プランの詳細を読み込めませんでした", vi: "Không thể tải chi tiết kế hoạch") }
    var loadDetailsRecovery: String { text(en: "Try again from Profile or create a training plan.", ja: "プロフィールから再試行するか、トレーニングプランを作成してください。", vi: "Hãy thử lại từ Hồ sơ hoặc tạo kế hoạch tập luyện.") }
    var pausePlanAccessibility: String { text(en: "Pause training plan", ja: "トレーニングプランを一時停止", vi: "Tạm dừng kế hoạch tập luyện") }
    var resumePlanAccessibility: String { text(en: "Resume training plan", ja: "トレーニングプランを再開", vi: "Tiếp tục kế hoạch tập luyện") }
    var adjustPlanAccessibility: String { text(en: "Adjust training plan", ja: "トレーニングプランを調整", vi: "Điều chỉnh kế hoạch tập luyện") }
    var planAdjustmentFailed: String { text(en: "Plan adjustment failed", ja: "プランの調整に失敗しました", vi: "Điều chỉnh kế hoạch thất bại") }
    var target: String { text(en: "Target", ja: "目標", vi: "Mục tiêu") }
    var runningDays: String { text(en: "Running days", ja: "ランニング日", vi: "Ngày chạy") }
    var timeRemaining: String { text(en: "Time remaining", ja: "残り時間", vi: "Thời gian còn lại") }
    var raceDay: String { text(en: "Race day", ja: "レース当日", vi: "Ngày đua") }
    func daysRemaining(_ days: Int) -> String { text(en: "\(days) days", ja: "あと\(days)日", vi: "\(days) ngày") }
    var ok: String { text(en: "OK", ja: "OK", vi: "OK") }
    func runningDaysPerWeek(_ days: Int) -> String { text(en: "\(days)/week", ja: "週\(days)日", vi: "\(days) ngày/tuần") }
    func weekOfTotal(_ week: Int, total: Int) -> String { text(en: "Week \(week) of \(total)", ja: "全\(total)週中 \(week)週目", vi: "Tuần \(week) / \(total)") }

    func activePlanStatus(_ status: ActivePlanStatus) -> String {
        switch (language, status) {
        case (.en, .active): "Active"
        case (.ja, .active): "進行中"
        case (.vi, .active): "Đang hoạt động"
        case (.en, .onTrack): "On track"
        case (.ja, .onTrack): "順調"
        case (.vi, .onTrack): "Đúng tiến độ"
        case (.en, .needsAttention): "Needs adjustment"
        case (.ja, .needsAttention): "要調整"
        case (.vi, .needsAttention): "Cần điều chỉnh"
        case (.en, .paused): "Paused"
        case (.ja, .paused): "一時停止中"
        case (.vi, .paused): "Đã tạm dừng"
        case (.en, .completed): "Completed"
        case (.ja, .completed): "完了"
        case (.vi, .completed): "Đã hoàn thành"
        }
    }

    func phaseSummary(_ phase: TrainingPhase) -> String {
        switch (language, phase) {
        case (.en, .base): "Build a durable aerobic foundation with comfortable running."
        case (.ja, .base): "無理のないランで持続的な有酸素の土台を作ります。"
        case (.vi, .base): "Xây nền tảng hiếu khí bền vững bằng các buổi chạy thoải mái."
        case (.en, .build): "Increase training volume and introduce focused quality sessions."
        case (.ja, .build): "走行量を高め、目的を絞った質の高いセッションを加えます。"
        case (.vi, .build): "Tăng khối lượng tập và thêm các buổi chất lượng có trọng tâm."
        case (.en, .peak): "Sharpen race-specific fitness while protecting recovery."
        case (.ja, .peak): "回復を守りながらレース特異的な力を磨きます。"
        case (.vi, .peak): "Nâng cao thể lực chuyên biệt cho cuộc đua đồng thời bảo vệ hồi phục."
        case (.en, .taper): "Reduce volume and arrive fresh for race day."
        case (.ja, .taper): "走行量を減らし、レース当日に向けてフレッシュな状態に整えます。"
        case (.vi, .taper): "Giảm khối lượng để đến ngày đua với thể trạng tươi mới."
        }
    }

    var noSuitableSlot: String { text(en: "No suitable slot", ja: "適切な時間枠がありません", vi: "Không có khung giờ phù hợp") }
    var noSafeSchedulingWindows: String { text(en: "Smart Scheduling could not find safe available windows for this week.", ja: "スマートスケジューリングでは今週の安全な空き時間を見つけられませんでした。", vi: "Xếp lịch thông minh không tìm được khung giờ trống an toàn trong tuần này.") }
    var suggestedScheduleAdjustment: String { text(en: "Suggested schedule adjustment", ja: "スケジュール調整の提案", vi: "Đề xuất điều chỉnh lịch") }
    var schedulingValidationNotice: String { text(en: "TrainOrRest validates recovery and plan rules before showing these options. No workout moves until you apply the changes.", ja: "TrainOrRestはこれらの候補を表示する前に回復とプランのルールを検証します。変更を適用するまでワークアウトは移動しません。", vi: "TrainOrRest kiểm tra quy tắc hồi phục và kế hoạch trước khi hiển thị các lựa chọn này. Buổi tập không bị dời cho đến khi bạn áp dụng thay đổi.") }
    func bestSchedulingOptionAccessibility(_ workout: String) -> String { text(en: "Best scheduling option for \(workout)", ja: "\(workout)の最適な予定候補", vi: "Lựa chọn xếp lịch tốt nhất cho \(workout)") }
    var applySmartSchedulingAccessibility: String { text(en: "Apply Smart Scheduling changes", ja: "スマートスケジューリングの変更を適用", vi: "Áp dụng thay đổi Xếp lịch thông minh") }

    func schedulingMessage(_ raw: String) -> String {
        guard language != .en else { return raw }
        let japanese: [String: String] = [
            "No calendar conflicts": "カレンダーの競合なし",
            "Required duration fits": "必要な時間に収まります",
            "Recovery spacing is safe": "回復間隔は安全です",
            "Keeps the workout inside its training week": "ワークアウトをトレーニング週内に維持",
            "Keeps the planned workout date": "予定したワークアウト日を維持",
            "Leaves extra buffer around the workout": "ワークアウト前後に余裕があります",
            "Respects hard-workout recovery spacing": "高強度ワークアウト後の回復間隔を守ります",
            "Required buffer does not fit": "必要な余裕時間に収まりません",
            "This workout is fixed.": "このワークアウトは固定されています。",
            "This time has already passed.": "この時刻はすでに過ぎています。",
            "Calendar availability needs to be refreshed.": "カレンダーの空き状況を更新する必要があります。",
            "This time is not safe for the current plan.": "この時刻は現在のプランにとって安全ではありません。",
            "This starts before your earliest allowed start.": "許可された最も早い開始時刻より前です。",
            "This finishes after your latest allowed finish.": "許可された最も遅い終了時刻を過ぎます。",
            "This option needs to be checked again.": "この候補は再確認が必要です。",
            "Google Calendar update queued": "Google カレンダーの更新をキューに追加しました",
            "Google Calendar was not changed": "Google カレンダーは変更されませんでした",
            "Google Calendar will update when online": "オンラインになるとGoogle カレンダーを更新します",
            "Workout no longer exists.": "ワークアウトは存在しなくなりました。",
            "Undo is no longer available.": "元に戻す操作は利用できなくなりました。",
            "This workout changed again, so undo is no longer safe.": "このワークアウトは再度変更されたため、安全に元に戻せません。"
        ]
        let vietnamese: [String: String] = [
            "No calendar conflicts": "Không có xung đột lịch",
            "Required duration fits": "Phù hợp với thời lượng cần thiết",
            "Recovery spacing is safe": "Khoảng hồi phục an toàn",
            "Keeps the workout inside its training week": "Giữ buổi tập trong tuần tập luyện",
            "Keeps the planned workout date": "Giữ ngày buổi tập đã lên kế hoạch",
            "Leaves extra buffer around the workout": "Có thời gian đệm thêm quanh buổi tập",
            "Respects hard-workout recovery spacing": "Tôn trọng khoảng hồi phục sau buổi nặng",
            "Required buffer does not fit": "Không đủ thời gian đệm cần thiết",
            "This workout is fixed.": "Buổi tập này đã cố định.",
            "This time has already passed.": "Thời điểm này đã qua.",
            "Calendar availability needs to be refreshed.": "Cần làm mới trạng thái rảnh của lịch.",
            "This time is not safe for the current plan.": "Thời điểm này không an toàn cho kế hoạch hiện tại.",
            "This starts before your earliest allowed start.": "Bắt đầu trước giờ sớm nhất được phép.",
            "This finishes after your latest allowed finish.": "Kết thúc sau giờ muộn nhất được phép.",
            "This option needs to be checked again.": "Lựa chọn này cần được kiểm tra lại.",
            "Google Calendar update queued": "Đã xếp hàng cập nhật Google Calendar",
            "Google Calendar was not changed": "Google Calendar không được thay đổi",
            "Google Calendar will update when online": "Google Calendar sẽ cập nhật khi trực tuyến",
            "Workout no longer exists.": "Buổi tập không còn tồn tại.",
            "Undo is no longer available.": "Không thể hoàn tác nữa.",
            "This workout changed again, so undo is no longer safe.": "Buổi tập này đã thay đổi lần nữa nên không còn an toàn để hoàn tác."
        ]
        let translations = language == .ja ? japanese : vietnamese
        if let translation = translations[raw] { return translation }
        if raw.hasPrefix("Matches your preferred ") {
            return text(en: raw, ja: "希望する時間帯に合います", vi: "Phù hợp với khung giờ bạn ưu tiên")
        }
        if raw.hasPrefix("Outside your preferred ") {
            return text(en: raw, ja: "希望する時間帯の外です。", vi: "Ngoài khung giờ bạn ưu tiên.")
        }
        if raw.hasPrefix("Your calendar is busy from ") {
            return text(en: raw, ja: "この時間帯はカレンダーが埋まっています。", vi: "Lịch của bạn đang bận trong khung giờ này.")
        }
        return text(en: raw, ja: "スケジュール情報", vi: "Thông tin xếp lịch")
    }
    var timeline: String { text(en: "Timeline", ja: "タイムライン", vi: "Tiến trình") }
    var currentPhase: String { text(en: "CURRENT PHASE", ja: "現在のフェーズ", vi: "GIAI ĐOẠN HIỆN TẠI") }
    func phaseDateRange(_ start: Date, _ end: Date) -> String { "\(language.shortDate(start)) – \(language.shortDate(end))" }
    var weeklyTarget: String { text(en: "Weekly target", ja: "週の目標", vi: "Mục tiêu tuần") }
    func phaseProgress(week: Int, total: Int) -> String { text(en: "Phase progress week \(week) of \(total)", ja: "フェーズの進捗 \(week)/\(total)週", vi: "Tiến độ giai đoạn tuần \(week)/\(total)") }
    var thisWeek: String { text(en: "THIS WEEK", ja: "今週", vi: "TUẦN NÀY") }
    func sessionsCompleted(_ completed: Int, of planned: Int) -> String { text(en: "\(completed) of \(planned) sessions completed", ja: "\(planned)回中\(completed)回のセッションを完了", vi: "Đã hoàn thành \(completed)/\(planned) buổi tập") }
    func weeklyDistanceAccessibility(completed: String, planned: String) -> String { text(en: "Weekly distance \(completed) of \(planned)", ja: "週の距離 \(completed) / \(planned)", vi: "Quãng đường tuần \(completed)/\(planned)") }
    var scheduleFit: String { text(en: "SCHEDULE FIT", ja: "スケジュールの適合", vi: "ĐỘ PHÙ HỢP LỊCH") }
    var reviewSchedule: String { text(en: "Review schedule", ja: "スケジュールを確認", vi: "Xem lại lịch") }
    var reviewWeeklyScheduleAccessibility: String { text(en: "Review weekly schedule", ja: "週のスケジュールを確認", vi: "Xem lại lịch tuần") }
    var upNext: String { text(en: "UP NEXT", ja: "次の予定", vi: "TIẾP THEO") }
    var planCompleted: String { text(en: "Plan completed", ja: "プラン完了", vi: "Đã hoàn thành kế hoạch") }
    var noUpcomingWorkout: String { text(en: "No upcoming workout", ja: "今後のワークアウトはありません", vi: "Không có buổi tập sắp tới") }
    var viewInCalendar: String { text(en: "View in Calendar", ja: "カレンダーで表示", vi: "Xem trong Lịch") }
    var viewPlanInCalendarAccessibility: String { text(en: "View training plan in Calendar", ja: "トレーニングプランをカレンダーで表示", vi: "Xem kế hoạch tập luyện trong Lịch") }
    var plannedVsCompleted: String { text(en: "PLANNED VS COMPLETED", ja: "予定と完了", vi: "DỰ KIẾN VÀ HOÀN THÀNH") }
    func completedDistanceSummary(percent: Int, weeks: Int) -> String { text(en: "You completed \(percent)% of planned distance over the last \(weeks) weeks.", ja: "直近\(weeks)週間で予定距離の\(percent)%を完了しました。", vi: "Bạn đã hoàn thành \(percent)% quãng đường dự kiến trong \(weeks) tuần gần đây.") }
    func plannedCompletedAccessibility(completed: String, planned: String) -> String { text(en: "Planned versus completed weekly distance. Completed \(completed) of \(planned).", ja: "週の予定距離と完了距離。\(planned)中\(completed)を完了。", vi: "Quãng đường tuần dự kiến và đã hoàn thành. Đã hoàn thành \(completed)/\(planned).") }
    var planPhases: String { text(en: "PLAN PHASES", ja: "プランのフェーズ", vi: "CÁC GIAI ĐOẠN KẾ HOẠCH") }
    func phaseWeeks(_ start: Int, _ end: Int) -> String { text(en: "Weeks \(start)-\(end)", ja: "第\(start)〜\(end)週", vi: "Tuần \(start)–\(end)") }
    var aboutThisPlan: String { text(en: "ABOUT THIS PLAN", ja: "このプランについて", vi: "VỀ KẾ HOẠCH NÀY") }
    var aboutPlanDescription: String { text(en: "This plan gradually builds weekly volume and race-specific endurance while adapting recommendations to your schedule and available training data.", ja: "このプランは週ごとの走行量とレースに必要な持久力を段階的に高め、スケジュールと利用可能なトレーニングデータに合わせて提案を調整します。", vi: "Kế hoạch này tăng dần khối lượng hàng tuần và sức bền theo cự ly đua, đồng thời điều chỉnh đề xuất theo lịch và dữ liệu tập luyện hiện có của bạn.") }
    func openNextWorkoutAccessibility(_ workout: String, day: String) -> String { text(en: "Open next workout: \(workout) \(day)", ja: "次のワークアウトを開く：\(workout) \(day)", vi: "Mở buổi tập tiếp theo: \(workout) \(day)") }
    func scheduleFits(_ count: Int) -> String { text(en: "This week fits your current availability", ja: "今週は現在の空き時間に収まります", vi: "Tuần này phù hợp với thời gian rảnh hiện tại") }
    func workoutsNeedScheduling(_ count: Int) -> String { text(en: "\(count) workouts need scheduling", ja: "\(count)件のワークアウトで予定設定が必要", vi: "\(count) buổi tập cần xếp lịch") }
    func workoutTimingConflicts(_ count: Int) -> String { text(en: "\(count) workout timing conflicts", ja: "\(count)件のワークアウトで時間が競合", vi: "\(count) buổi tập bị xung đột thời gian") }
    func workoutsScheduled(_ count: Int) -> String { text(en: "\(count) workouts are scheduled and no busy-time conflicts were found.", ja: "\(count)件のワークアウトは予定済みで、予定との競合はありません。", vi: "\(count) buổi tập đã được xếp lịch và không có xung đột lịch bận.") }
    func validSlots(_ count: Int) -> String { text(en: "\(count) valid Smart Scheduling slots are available this week.", ja: "今週はSmart Schedulingで\(count)件の有効な時間帯があります。", vi: "Tuần này có \(count) khung giờ Smart Scheduling hợp lệ.") }
    var scheduleConflictDetail: String { text(en: "At least one workout overlaps busy time. Review options before changing the plan.", ja: "少なくとも1件のワークアウトが予定と重なっています。プランを変更する前に候補を確認してください。", vi: "Ít nhất một buổi tập trùng lịch bận. Hãy xem các lựa chọn trước khi đổi kế hoạch.") }
    func relativeDay(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return language.todayLabel }
        if Calendar.current.isDateInTomorrow(date) { return language.tomorrowLabel }
        return language.shortWeekdayDate(date)
    }

    // MARK: - Workout detail and scheduling

    var date: String { text(en: "Date", ja: "日付", vi: "Ngày") }
    var workout: String { text(en: "Workout", ja: "ワークアウト", vi: "Buổi tập") }
    var distance: String { text(en: "Distance", ja: "距離", vi: "Quãng đường") }
    var pace: String { text(en: "Pace", ja: "ペース", vi: "Nhịp chạy") }
    var scheduleHistory: String { text(en: "Schedule history", ja: "予定履歴", vi: "Lịch sử xếp lịch") }
    var scheduledFrom: String { text(en: "Scheduled from", ja: "予定元", vi: "Được xếp từ") }
    var updated: String { text(en: "Updated", ja: "更新", vi: "Đã cập nhật") }
    var notShownInGoogleCalendar: String { text(en: "Not shown in Google Calendar", ja: "Google カレンダーに表示されていません", vi: "Không hiển thị trong Google Calendar") }
    var workoutStillInPlan: String { text(en: "This workout still exists in your TrainOrRest plan.", ja: "このワークアウトはTrainOrRestのプランに残っています。", vi: "Buổi tập này vẫn có trong kế hoạch TrainOrRest của bạn.") }
    var addBackToGoogleCalendar: String { text(en: "Add back to Google Calendar", ja: "Google カレンダーに戻す", vi: "Thêm lại vào Google Calendar") }
    var smartScheduling: String { text(en: "Smart Scheduling", ja: "スマートスケジューリング", vi: "Xếp lịch thông minh") }
    var runSchedule: String { text(en: "Run schedule", ja: "ラン予定", vi: "Lịch chạy") }
    var setupRunSchedule: String { addWeatherForRun }
    var runScheduleExplainTitle: String { text(en: "Weather for today's run", ja: "今日のランの天気", vi: "Thời tiết buổi chạy hôm nay") }
    var runScheduleExplainBody: String { text(en: "Set where you run. TrainOrRest loads a 10-day forecast of rain and wind so Today's Call can tell you if the slot is safe. Calendar is optional if you want a better time.", ja: "走る場所を設定します。TrainOrRestが今後10日の雨と風を読み込み、今日のメニューでその枠が走れるかを示します。より良い時間を探すならカレンダーは任意です。", vi: "Đặt nơi bạn chạy. TrainOrRest tải dự báo mưa và gió 10 ngày để Buổi tập hôm nay nói khung giờ có an toàn không. Lịch là tuỳ chọn nếu bạn muốn giờ tốt hơn.") }
    var setRunLocation: String { text(en: "Run location", ja: "ラン地点", vi: "Vị trí chạy") }
    var currentLocation: String { text(en: "Use current location", ja: "現在地を使う", vi: "Dùng vị trí hiện tại") }
    var searchCity: String { text(en: "Search city", ja: "都市を検索", vi: "Tìm thành phố") }
    var rainTolerance: String { text(en: "Rain", ja: "雨", vi: "Mưa") }
    func rainStanceLabel(_ rain: RainTolerance) -> String {
        switch rain {
        case .low: text(en: "Avoid rain", ja: "雨を避ける", vi: "Tránh mưa")
        case .medium: text(en: "Drizzle OK", ja: "小雨なら可", vi: "Mưa phùn được")
        case .high: text(en: "Heavy only", ja: "大雨のみ", vi: "Chỉ mưa to")
        }
    }
    func rainToleranceCaption(_ rain: RainTolerance) -> String {
        let percent = Int((rain.maxPrecipitationChance * 100).rounded())
        return text(en: "Skip slots above \(percent)% chance of rain.", ja: "降水確率\(percent)%を超える枠は外します。", vi: "Bỏ khung trên \(percent)% khả năng mưa.")
    }
    func weatherStance(_ glyph: WeatherGlyph) -> String {
        switch glyph {
        case .good: text(en: "Clear to run", ja: "走れる天気", vi: "Trời ổn để chạy")
        case .rainRisk: text(en: "Rain risk", ja: "雨の恐れ", vi: "Có nguy cơ mưa")
        case .strongWind: text(en: "Windy", ja: "風が強い", vi: "Gió mạnh")
        case .noSlot: text(en: "Move this run", ja: "この時間は避ける", vi: "Nên dời buổi chạy")
        case .noData: weatherOnNoForecast
        }
    }
    func slotWeatherSummary(_ weather: SlotWeather) -> String {
        let low = Int(weather.temperatureRangeC.lowerBound.rounded())
        let high = Int(weather.temperatureRangeC.upperBound.rounded())
        let rain = Int((weather.precipitationMax * 100).rounded())
        let wind = Int(weather.windMaxKmh.rounded())
        let numbers = text(
            en: "\(low)–\(high)°C · \(rain)% rain · \(wind) km/h",
            ja: "\(low)–\(high)°C · 降水 \(rain)% · 風 \(wind) km/h",
            vi: "\(low)–\(high)°C · \(rain)% mưa · gió \(wind) km/h"
        )
        return "\(weatherStance(weather.glyph)) · \(numbers)"
    }
    func weatherCopy(_ message: WeatherForecastingError) -> String {
        switch message {
        case .missingLocation: weatherMissingLocation
        case .unavailable: weatherUnavailable
        }
    }
    var findingTime: String { text(en: "Finding a time", ja: "時間を検索中", vi: "Đang tìm giờ") }
    var findTime: String { text(en: "Find a time", ja: "時間を探す", vi: "Tìm giờ") }
    var findTimeAccessibility: String { text(en: "Find a time", ja: "時間を探す", vi: "Tìm giờ") }
    var completedRunSection: String { text(en: "Completed Run", ja: "完了したラン", vi: "Buổi chạy đã hoàn thành") }
    var gear: String { text(en: "Gear", ja: "ギア", vi: "Trang bị") }
    var retiredShoeNotice: String { text(en: "This workout uses a retired shoe.", ja: "このワークアウトには引退済みのシューズを使っています。", vi: "Buổi tập này dùng một đôi giày đã ngừng sử dụng.") }
    var status: String { text(en: "Status", ja: "ステータス", vi: "Trạng thái") }
    var bestAvailableSlot: String { text(en: "Best available slot", ja: "最適な空き時間", vi: "Khung giờ trống tốt nhất") }
    var chooseAnotherTime: String { text(en: "Choose another time", ja: "別の時間を選ぶ", vi: "Chọn giờ khác") }
    func useTime(_ time: String) -> String { text(en: "Use \(time)", ja: "\(time)を使う", vi: "Dùng \(time)") }
    var scheduled: String { text(en: "Scheduled", ja: "予定済み", vi: "Đã xếp lịch") }
    var syncedWhenAvailable: String { text(en: "Synced with Google Calendar when connection is available", ja: "接続可能になるとGoogle カレンダーと同期されます", vi: "Sẽ đồng bộ với Google Calendar khi có kết nối") }
    var changeTime: String { text(en: "Change time", ja: "時間を変更", vi: "Đổi giờ") }
    func noSuitableTime(_ date: Date) -> String { text(en: "No suitable time found on \(language.shortWeekdayDate(date)).", ja: "\(language.shortWeekdayDate(date))に適切な時間が見つかりませんでした。", vi: "Không tìm thấy giờ phù hợp vào \(language.shortWeekdayDate(date)).") }
    func workoutScheduledFor(_ time: String) -> String { text(en: "Workout scheduled for \(time).", ja: "ワークアウトを\(time)に予定しました。", vi: "Đã xếp buổi tập lúc \(time).") }
    var workoutScheduledPendingSync: String { text(en: "Workout scheduled. Google Calendar will update when online.", ja: "ワークアウトを予定しました。オンラインになるとGoogle カレンダーを更新します。", vi: "Đã xếp buổi tập. Google Calendar sẽ cập nhật khi trực tuyến.") }
    var noCalendarConflicts: String { text(en: "No calendar conflicts", ja: "カレンダーの競合なし", vi: "Không có xung đột lịch") }
    func statusHelp(_ status: WorkoutStatus) -> String {
        switch (language, status) {
        case (.en, .done): "Done is a manual completion and stays linked to this workout."
        case (.ja, .done): "完了は手動で記録され、このワークアウトとの紐付けを維持します。"
        case (.vi, .done): "Hoàn thành là ghi nhận thủ công và vẫn liên kết với buổi tập này."
        case (.en, .skipped): "Skipped is a manual decision; the planner will not auto-match this workout."
        case (.ja, .skipped): "スキップは手動の決定です。プランナーはこのワークアウトを自動照合しません。"
        case (.vi, .skipped): "Bỏ qua là quyết định thủ công; trình lập kế hoạch sẽ không tự ghép buổi tập này."
        case (.en, .planned): "Planned clears the manual decision so future sync matching can apply again."
        case (.ja, .planned): "予定に戻すと手動の決定が解除され、今後の同期で再び自動照合できます。"
        case (.vi, .planned): "Dự kiến sẽ xoá quyết định thủ công để lần đồng bộ sau có thể tự ghép lại."
        }
    }
    var chooseCustomTime: String { text(en: "Choose a custom time", ja: "時刻を指定", vi: "Chọn giờ tùy chỉnh") }
    var chooseStartTime: String { text(en: "Choose start time", ja: "開始時刻を選択", vi: "Chọn giờ bắt đầu") }
    var workoutScheduledTitle: String { text(en: "Workout scheduled", ja: "ワークアウトを予定しました", vi: "Đã xếp buổi tập") }
    func estimatedDuration(_ minutes: Int) -> String { text(en: "Estimated duration: \(minutes) min", ja: "推定時間：\(minutes)分", vi: "Thời lượng ước tính: \(minutes) phút") }
    var availableTimes: String { text(en: "Available times", ja: "空き時間", vi: "Khung giờ trống") }
    var noSuitableTimeFound: String { text(en: "No suitable time found", ja: "適切な時間が見つかりません", vi: "Không tìm thấy giờ phù hợp") }
    var needsClearWindow: String { text(en: "This workout needs a clear window plus buffers.", ja: "このワークアウトには余裕を含む空き時間が必要です。", vi: "Buổi tập này cần một khung giờ trống kèm thời gian đệm.") }
    var chooseAnotherDay: String { text(en: "Choose another day", ja: "別の日を選ぶ", vi: "Chọn ngày khác") }
    var selected: String { text(en: "Selected", ja: "選択中", vi: "Đã chọn") }
    var recommended: String { text(en: "Recommended", ja: "おすすめ", vi: "Đề xuất") }
    var customStartTime: String { text(en: "Custom start time", ja: "開始時刻を指定", vi: "Giờ bắt đầu tùy chỉnh") }
    var startTime: String { text(en: "Start time", ja: "開始時刻", vi: "Giờ bắt đầu") }
    var estimatedEnd: String { text(en: "Estimated end", ja: "終了予定", vi: "Giờ kết thúc dự kiến") }
    func requiredWindow(_ minutes: Int) -> String { text(en: "Required window: \(minutes) min workout + buffers", ja: "必要な時間枠：\(minutes)分のワークアウト＋余裕時間", vi: "Khung giờ cần thiết: buổi tập \(minutes) phút + thời gian đệm") }
    func timeAvailability(_ time: String, available: Bool) -> String {
        switch language {
        case .en: return "\(time) is \(available ? "available" : "not available")"
        case .ja: return "\(time)は\(available ? "利用可能" : "利用不可")"
        case .vi: return "\(time) \(available ? "còn trống" : "không còn trống")"
        }
    }
    func workoutTimeRange(_ range: String) -> String { text(en: "Workout \(range)", ja: "ワークアウト \(range)", vi: "Buổi tập \(range)") }
    var nearestAvailableOptions: String { text(en: "Nearest available options", ja: "近い空き時間", vi: "Các lựa chọn trống gần nhất") }
    var keepTimeFixed: String { text(en: "Keep this time fixed", ja: "この時間を固定", vi: "Giữ cố định giờ này") }
    var keepTimeFixedAccessibility: String { text(en: "Keep this scheduled time fixed", ja: "この予定時刻を固定", vi: "Giữ cố định giờ đã xếp") }
    var keepTimeFixedDescription: String { text(en: "Smart Scheduling will not suggest moving this workout during future schedule optimization.", ja: "今後のスケジュール最適化では、このワークアウトの移動を提案しません。", vi: "Xếp lịch thông minh sẽ không đề xuất dời buổi tập này trong các lần tối ưu lịch sau.") }
    var schedulingWorkout: String { text(en: "Scheduling workout", ja: "ワークアウトを予定中", vi: "Đang xếp lịch buổi tập") }
    func checkTime(_ time: String) -> String { text(en: "Check \(time)", ja: "\(time)を確認", vi: "Kiểm tra \(time)") }
    func scheduleAt(_ time: String) -> String { text(en: "Schedule at \(time)", ja: "\(time)に予定", vi: "Xếp lúc \(time)") }
    var schedule: String { text(en: "Schedule", ja: "予定", vi: "Xếp lịch") }
    var refreshOptions: String { text(en: "Refresh options", ja: "候補を更新", vi: "Làm mới lựa chọn") }
    var couldNotScheduleWorkout: String { text(en: "Could not schedule the workout", ja: "ワークアウトを予定できませんでした", vi: "Không thể xếp lịch buổi tập") }
    var keepCurrent: String { text(en: "Keep current", ja: "現在のまま", vi: "Giữ nguyên") }

    var cancel: String { text(en: "Cancel", ja: "キャンセル", vi: "Hủy") }
    var done: String { text(en: "Done", ja: "完了", vi: "Xong") }
    func candidateAccessibility(range: String, recommended: Bool, selected: Bool) -> String {
        let states: [String?] = [
            range,
            text(en: "available", ja: "利用可能", vi: "còn trống"),
            recommended ? self.recommended.lowercased() : nil,
            selected ? self.selected.lowercased() : nil
        ]
        return states.compactMap { $0 }.joined(separator: ", ")
    }

    private func text(en: String, ja: String, vi: String) -> String {
        switch language {
        case .en: en
        case .ja: ja
        case .vi: vi
        }
    }
}

enum PlanReceiptSource {
    case calendar
    case moved
    case onPlan
}
