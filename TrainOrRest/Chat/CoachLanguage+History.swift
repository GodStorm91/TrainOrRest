import Foundation

extension CoachLanguage {
    var history: HistoryCopy { HistoryCopy(language: self) }
}

struct HistoryCopy {
    let language: CoachLanguage

    var runHistory: String { switch language { case .en: "Run History"; case .ja: "ラン履歴"; case .vi: "Lịch sử chạy" } }
    var activities: String { switch language { case .en: "Activities"; case .ja: "アクティビティ"; case .vi: "Hoạt động" } }
    var rollingThirtyDays: String { switch language { case .en: "30d"; case .ja: "30日"; case .vi: "30 ngày" } }
    var month: String { switch language { case .en: "Month"; case .ja: "月"; case .vi: "Tháng" } }
    var year: String { switch language { case .en: "Year"; case .ja: "年"; case .vi: "Năm" } }
    var selectMonth: String { switch language { case .en: "Select Month"; case .ja: "月を選択"; case .vi: "Chọn tháng" } }
    var selectMonthAndYear: String { switch language { case .en: "Select month and year"; case .ja: "月と年を選択"; case .vi: "Chọn tháng và năm" } }
    var goToCurrentMonth: String { switch language { case .en: "Go to current month"; case .ja: "今月へ移動"; case .vi: "Đến tháng hiện tại" } }
    var loadingSelectedRunHistory: String { switch language { case .en: "Loading selected run history period"; case .ja: "選択したラン履歴を読み込み中"; case .vi: "Đang tải khoảng thời gian lịch sử chạy đã chọn" } }

    func selectMonthAndYearAccessibility(_ current: String) -> String {
        switch language {
        case .en: "Select month and year. Current selection \(current)"
        case .ja: "月と年を選択。現在の選択は\(current)"
        case .vi: "Chọn tháng và năm. Lựa chọn hiện tại là \(current)"
        }
    }

    func previousMonth(_ month: String) -> String {
        switch language { case .en: "Previous month, \(month)"; case .ja: "前月、\(month)"; case .vi: "Tháng trước, \(month)" }
    }

    func nextMonth(_ month: String) -> String {
        switch language { case .en: "Next month, \(month)"; case .ja: "翌月、\(month)"; case .vi: "Tháng sau, \(month)" }
    }

    func previousYear(_ year: Int) -> String {
        switch language { case .en: "Previous year, \(year)"; case .ja: "前年、\(year)年"; case .vi: "Năm trước, \(year)" }
    }

    func nextYear(_ year: Int) -> String {
        switch language { case .en: "Next year, \(year)"; case .ja: "翌年、\(year)年"; case .vi: "Năm sau, \(year)" }
    }

    var previousPeriod: String { switch language { case .en: "Previous period"; case .ja: "前の期間"; case .vi: "Khoảng thời gian trước" } }
    var nextPeriod: String { switch language { case .en: "Next period"; case .ja: "次の期間"; case .vi: "Khoảng thời gian tiếp theo" } }
    var nextMonthUnavailable: String { switch language { case .en: "Next month unavailable"; case .ja: "翌月は選択できません"; case .vi: "Không thể chọn tháng sau" } }
    var nextYearUnavailable: String { switch language { case .en: "Next year unavailable"; case .ja: "翌年は選択できません"; case .vi: "Không thể chọn năm sau" } }

    func noRunsInLastThirtyDays() -> String {
        switch language { case .en: "No runs in the last 30 days"; case .ja: "過去30日間にランはありません"; case .vi: "Không có buổi chạy nào trong 30 ngày qua" }
    }

    func noRuns(in period: String) -> String {
        switch language { case .en: "No runs in \(period)"; case .ja: "\(period)にランはありません"; case .vi: "Không có buổi chạy nào trong \(period)" }
    }

    func completedRunsWillAppear(for period: HistoryPeriodDescription) -> String {
        switch (language, period) {
        case (.en, .lastThirtyDays): "Your completed runs for this period will appear here."
        case (.ja, .lastThirtyDays): "この期間に完了したランがここに表示されます。"
        case (.vi, .lastThirtyDays): "Các buổi chạy đã hoàn thành trong khoảng thời gian này sẽ hiện ở đây."
        case (.en, .month): "Your completed runs for this month will appear here."
        case (.ja, .month): "今月完了したランがここに表示されます。"
        case (.vi, .month): "Các buổi chạy đã hoàn thành trong tháng này sẽ hiện ở đây."
        case (.en, .year): "Your completed runs for this year will appear here."
        case (.ja, .year): "今年完了したランがここに表示されます。"
        case (.vi, .year): "Các buổi chạy đã hoàn thành trong năm này sẽ hiện ở đây."
        }
    }

    func totalDistance(runCount: Int) -> String {
        switch language {
        case .en: "total distance · \(runCount) \(runCount == 1 ? "run" : "runs")"
        case .ja: "合計距離 · \(runCount)回のラン"
        case .vi: "Tổng quãng đường · \(runCount) buổi chạy"
        }
    }

    var averagePace: String { switch language { case .en: "AVG PACE"; case .ja: "平均ペース"; case .vi: "NHỊP ĐỘ TB" } }
    var totalTime: String { switch language { case .en: "TOTAL TIME"; case .ja: "合計時間"; case .vi: "TỔNG THỜI GIAN" } }
    var longestDistance: String { switch language { case .en: "LONGEST km"; case .ja: "最長 km"; case .vi: "DÀI NHẤT km" } }
    var pace: String { switch language { case .en: "Pace"; case .ja: "ペース"; case .vi: "Nhịp độ" } }

    var date: String { switch language { case .en: "Date"; case .ja: "日付"; case .vi: "Ngày" } }
    var distance: String { switch language { case .en: "Distance"; case .ja: "距離"; case .vi: "Quãng đường" } }
    var duration: String { switch language { case .en: "Duration"; case .ja: "時間"; case .vi: "Thời lượng" } }
    var matchedPlan: String { switch language { case .en: "Matched plan"; case .ja: "一致したプラン"; case .vi: "Kế hoạch khớp" } }
    var plannedDistance: String { switch language { case .en: "Planned distance"; case .ja: "予定距離"; case .vi: "Quãng đường dự kiến" } }
    var analysisSource: String { switch language { case .en: "Analysis source"; case .ja: "分析元"; case .vi: "Nguồn phân tích" } }
    var maximumHeartRate: String { switch language { case .en: "Maximum HR"; case .ja: "最大心拍数"; case .vi: "Nhịp tim tối đa" } }
    var averagingLogic: String { switch language { case .en: "Averaging logic"; case .ja: "平均の算出方法"; case .vi: "Cách tính trung bình" } }
    var cadence: String { switch language { case .en: "Cadence"; case .ja: "ケイデンス"; case .vi: "Nhịp bước" } }
    var strideLength: String { switch language { case .en: "Stride length"; case .ja: "歩幅"; case .vi: "Sải chân" } }
    var groundContact: String { switch language { case .en: "Ground contact"; case .ja: "接地時間"; case .vi: "Thời gian tiếp đất" } }
    var gain: String { switch language { case .en: "Gain"; case .ja: "獲得標高"; case .vi: "Độ cao tăng" } }
    var loss: String { switch language { case .en: "Loss"; case .ja: "下降標高"; case .vi: "Độ cao giảm" } }
    var temperature: String { switch language { case .en: "Temperature"; case .ja: "気温"; case .vi: "Nhiệt độ" } }
    var humidity: String { switch language { case .en: "Humidity"; case .ja: "湿度"; case .vi: "Độ ẩm" } }
    var shoeTotal: String { switch language { case .en: "Shoe total"; case .ja: "シューズ合計"; case .vi: "Tổng quãng đường giày" } }
    var recordedBy: String { switch language { case .en: "Recorded by"; case .ja: "記録元"; case .vi: "Được ghi bởi" } }
    var device: String { switch language { case .en: "Device"; case .ja: "デバイス"; case .vi: "Thiết bị" } }
    var notAvailable: String { switch language { case .en: "Not available"; case .ja: "利用できません"; case .vi: "Chưa có dữ liệu" } }
    var cadenceUnavailable: String { switch language { case .en: "Cadence and stride data not synced"; case .ja: "ケイデンスと歩幅のデータは未同期です"; case .vi: "Dữ liệu nhịp bước và sải chân chưa được đồng bộ" } }
    var noElevationSeries: String { switch language { case .en: "No elevation series"; case .ja: "標高データはありません"; case .vi: "Không có dữ liệu độ cao" } }
    var noWeatherAttached: String { switch language { case .en: "No weather attached"; case .ja: "天気情報はありません"; case .vi: "Không có thông tin thời tiết" } }
    var recordedAverageHeartRate: String { switch language { case .en: "Recorded average HR"; case .ja: "記録された平均心拍数"; case .vi: "Nhịp tim trung bình ghi nhận" } }
    var intervalsAverageHeartRate: String { switch language { case .en: "Intervals average HR"; case .ja: "Intervalsの平均心拍数"; case .vi: "Nhịp tim trung bình từ Intervals" } }
    var healthSamplesAcrossWorkout: String { switch language { case .en: "Health samples across the workout interval"; case .ja: "ワークアウト時間内のHealthサンプル"; case .vi: "Mẫu Health trong khoảng thời gian buổi tập" } }
    var intervalsGarminActivitySummary: String { switch language { case .en: "intervals.icu Garmin activity summary"; case .ja: "intervals.icu のGarminアクティビティ概要"; case .vi: "Tóm tắt hoạt động Garmin từ intervals.icu" } }
    var appleHealthImport: String { switch language { case .en: "Apple Health import"; case .ja: "Apple Healthからの読み込み"; case .vi: "Nhập từ Apple Health" } }
    var intervalsGarminImport: String { switch language { case .en: "intervals.icu Garmin import"; case .ja: "intervals.icu からのGarmin読み込み"; case .vi: "Nhập Garmin từ intervals.icu" } }

    func intervalsActivity(_ id: String) -> String { "intervals.icu · \(id)" }
    var loadingIntervalsAnalysis: String { switch language { case .en: "Loading intervals.icu analysis"; case .ja: "intervals.icuの分析を読み込み中"; case .vi: "Đang tải phân tích intervals.icu" } }
    var healthKitSummaryFallback: String { switch language { case .en: "HealthKit summary fallback"; case .ja: "HealthKitの要約にフォールバック"; case .vi: "Dùng bản tóm tắt HealthKit thay thế" } }
    var healthKitNoIntervalsMatch: String { switch language { case .en: "HealthKit fallback · no intervals activity match"; case .ja: "HealthKitにフォールバック · intervalsのアクティビティ一致なし"; case .vi: "Dùng HealthKit thay thế · không khớp hoạt động intervals" } }
    var healthKitIntervalsUnavailable: String { switch language { case .en: "HealthKit fallback · intervals unavailable"; case .ja: "HealthKitにフォールバック · intervalsは利用できません"; case .vi: "Dùng HealthKit thay thế · intervals không khả dụng" } }

    var viewFullAnalysis: String { switch language { case .en: "View full analysis"; case .ja: "分析の詳細を見る"; case .vi: "Xem phân tích đầy đủ" } }
    var run: String { switch language { case .en: "Run"; case .ja: "ラン"; case .vi: "Buổi chạy" } }
    var paceVsPlan: String { switch language { case .en: "Pace vs plan"; case .ja: "ペースとプラン"; case .vi: "Nhịp độ so với kế hoạch" } }
    var pacePattern: String { switch language { case .en: "Pace pattern"; case .ja: "ペースの推移"; case .vi: "Diễn biến nhịp độ" } }
    var actual: String { switch language { case .en: "actual"; case .ja: "実績"; case .vi: "thực tế" } }
    var planned: String { switch language { case .en: "planned"; case .ja: "予定"; case .vi: "dự kiến" } }
    var fast: String { switch language { case .en: "fast"; case .ja: "速い"; case .vi: "nhanh" } }
    var recordedAverage: String { switch language { case .en: "recorded avg"; case .ja: "記録平均"; case .vi: "TB ghi nhận" } }
    var maximum: String { switch language { case .en: "max"; case .ja: "最大"; case .vi: "tối đa" } }
    var splits: String { switch language { case .en: "Splits"; case .ja: "ラップ"; case .vi: "Các km" } }
    var nextSession: String { switch language { case .en: "Next session"; case .ja: "次のセッション"; case .vi: "Buổi tập tiếp theo" } }
    var target: String { switch language { case .en: "Target"; case .ja: "目標"; case .vi: "Mục tiêu" } }
    var mainDeviation: String { switch language { case .en: "Main deviation · 18-24 min"; case .ja: "主な差異 · 18〜24分"; case .vi: "Sai lệch chính · 18–24 phút" } }

    func splitAccessibility(kilometer: Int, pace: String, plannedPace: String) -> String {
        switch language {
        case .en: "Kilometer \(kilometer), \(pace), planned \(plannedPace)"
        case .ja: "\(kilometer)キロ、\(pace)、予定\(plannedPace)"
        case .vi: "Kilômét \(kilometer), \(pace), dự kiến \(plannedPace)"
        }
    }

    func analysisTabTitle(_ tab: ActivityAnalysisTab) -> String {
        switch (language, tab) {
        case (.en, .pace): "Pace"
        case (.en, .heartRate): "Heart rate"
        case (.en, .splits): "Splits"
        case (.ja, .pace): "ペース"
        case (.ja, .heartRate): "心拍数"
        case (.ja, .splits): "ラップ"
        case (.vi, .pace): "Nhịp độ"
        case (.vi, .heartRate): "Nhịp tim"
        case (.vi, .splits): "Các km"
        }
    }

    func technicalSectionTitle(_ section: ActivityTechnicalSection) -> String {
        switch (language, section) {
        case (.en, .activityDetails): "Activity details"
        case (.en, .heartRateDetails): "Heart rate details"
        case (.en, .runningDynamics): "Running dynamics"
        case (.en, .elevation): "Elevation"
        case (.en, .weather): "Weather"
        case (.en, .gear): "Gear"
        case (.ja, .activityDetails): "アクティビティの詳細"
        case (.ja, .heartRateDetails): "心拍数の詳細"
        case (.ja, .runningDynamics): "ランニングダイナミクス"
        case (.ja, .elevation): "標高"
        case (.ja, .weather): "天気"
        case (.ja, .gear): "ギア"
        case (.vi, .activityDetails): "Chi tiết hoạt động"
        case (.vi, .heartRateDetails): "Chi tiết nhịp tim"
        case (.vi, .runningDynamics): "Chỉ số chạy"
        case (.vi, .elevation): "Độ cao"
        case (.vi, .weather): "Thời tiết"
        case (.vi, .gear): "Trang bị"
        }
    }

    func reviewEyebrow(hasPlan: Bool) -> String {
        switch (language, hasPlan) {
        case (.en, true): "Post-run review"
        case (.en, false): "Run review"
        case (.ja, true): "ラン後レビュー"
        case (.ja, false): "ランレビュー"
        case (.vi, true): "Đánh giá sau chạy"
        case (.vi, false): "Đánh giá buổi chạy"
        }
    }

    func reviewHeadline(_ verdict: RunReview.Verdict, hasPlan: Bool) -> String {
        guard hasPlan else { return runLogged }
        return switch (language, verdict) {
        case (.en, .onPlan): "Nice execution"
        case (.en, .overcooked): "You went hotter than planned"
        case (.en, .undercooked): "You kept it lighter than planned"
        case (.en, .unmatched): "Run logged"
        case (.ja, .onPlan): "見事な実行でした"
        case (.ja, .overcooked): "予定より強度が高めでした"
        case (.ja, .undercooked): "予定より軽めでした"
        case (.ja, .unmatched): "ランを記録しました"
        case (.vi, .onPlan): "Thực hiện rất tốt"
        case (.vi, .overcooked): "Bạn chạy nặng hơn dự kiến"
        case (.vi, .undercooked): "Bạn chạy nhẹ hơn dự kiến"
        case (.vi, .unmatched): "Đã ghi nhận buổi chạy"
        }
    }

    var runLogged: String { switch language { case .en: "Run logged"; case .ja: "ランを記録しました"; case .vi: "Đã ghi nhận buổi chạy" } }
    var plannedRun: String { switch language { case .en: "planned run"; case .ja: "予定のラン"; case .vi: "buổi chạy dự kiến" } }

    func supportingSentence(kind: String, distanceMatched: Bool, paceDelta: Double?) -> String {
        let distance: String
        switch (language, distanceMatched) {
        case (.en, true): distance = "Your distance matched the \(kind)"
        case (.en, false): distance = "Your distance drifted from the \(kind)"
        case (.ja, true): distance = "距離は\(kind)の予定どおりでした"
        case (.ja, false): distance = "距離は\(kind)の予定からずれました"
        case (.vi, true): distance = "Quãng đường của bạn khớp với \(kind)"
        case (.vi, false): distance = "Quãng đường của bạn lệch so với \(kind)"
        }
        guard let paceDelta, abs(paceDelta) >= 10 else {
            switch language {
            case .en: return "\(distance), and your average pace stayed close to the planned range."
            case .ja: return "\(distance)。平均ペースも予定の範囲に近く収まりました。"
            case .vi: return "\(distance) và nhịp độ trung bình vẫn gần với phạm vi dự kiến."
            }
        }
        let seconds = Int(abs(paceDelta).rounded())
        switch (language, paceDelta < 0) {
        case (.en, true): return "\(distance), but your pace was \(seconds) sec/km faster than planned."
        case (.en, false): return "\(distance), but your pace was \(seconds) sec/km slower than planned."
        case (.ja, true): return "\(distance)。ただしペースは予定より\(seconds)秒/km速めでした。"
        case (.ja, false): return "\(distance)。ただしペースは予定より\(seconds)秒/km遅めでした。"
        case (.vi, true): return "\(distance), nhưng nhịp độ của bạn nhanh hơn dự kiến \(seconds) giây/km."
        case (.vi, false): return "\(distance), nhưng nhịp độ của bạn chậm hơn dự kiến \(seconds) giây/km."
        }
    }

    var unmatchedSupportingSentence: String {
        switch language {
        case .en: "No planned workout is matched yet, so TrainOrRest is showing the pacing pattern without judging execution."
        case .ja: "まだ予定のワークアウトに一致していないため、TrainOrRestは実行を評価せずペースの推移を表示しています。"
        case .vi: "Chưa có buổi tập dự kiến nào khớp, nên TrainOrRest chỉ hiển thị diễn biến nhịp độ mà không đánh giá mức thực hiện."
        }
    }

    var garminSynced: String { switch language { case .en: "Garmin synced"; case .ja: "Garminを同期済み"; case .vi: "Đã đồng bộ Garmin" } }
    var distanceOnPlan: String { switch language { case .en: "Distance on plan"; case .ja: "距離は予定どおり"; case .vi: "Quãng đường đúng kế hoạch" } }

    func distanceOff(_ kilometers: Double) -> String {
        switch language {
        case .en: String(format: "%.1f km off", locale: language.uiLocale, kilometers)
        case .ja: String(format: "%.1f km の差", locale: language.uiLocale, kilometers)
        case .vi: String(format: "Lệch %.1f km", locale: language.uiLocale, kilometers)
        }
    }

    func paceDelta(_ seconds: Double, faster: Bool) -> String {
        let rounded = Int(seconds.rounded())
        return switch (language, faster) {
        case (.en, true): "\(rounded) sec/km fast"
        case (.en, false): "\(rounded) sec/km slow"
        case (.ja, true): "\(rounded)秒/km 速い"
        case (.ja, false): "\(rounded)秒/km 遅い"
        case (.vi, true): "\(rounded) giây/km nhanh"
        case (.vi, false): "\(rounded) giây/km chậm"
        }
    }

    func durationDelta(_ minutes: Int, shorter: Bool) -> String {
        switch (language, shorter) {
        case (.en, true): "\(minutes) min shorter"
        case (.en, false): "\(minutes) min longer"
        case (.ja, true): "\(minutes)分短い"
        case (.ja, false): "\(minutes)分長い"
        case (.vi, true): "Ngắn hơn \(minutes) phút"
        case (.vi, false): "Dài hơn \(minutes) phút"
        }
    }

    func recommendation(verdict: RunReview.Verdict, averageHeartRate: Double?) -> String {
        switch (language, verdict) {
        case (.en, .onPlan): "Good match. Keep the next session as planned unless tomorrow's readiness says otherwise."
        case (.en, .overcooked): "Treat this as extra load. If tomorrow feels heavy, downgrade the next quality session."
        case (.en, .undercooked): "No drama. Bank the aerobic work and avoid cramming the missed load into tomorrow."
        case (.en, .unmatched) where (averageHeartRate ?? 0) >= 165: "This looks like a hard effort. Give recovery priority before stacking intensity."
        case (.en, .unmatched): "Synced from Garmin. Match it to a plan day for a tighter review."
        case (.ja, .onPlan): "よく一致しました。明日のコンディションに問題がなければ、次のセッションは予定どおり進めましょう。"
        case (.ja, .overcooked): "追加の負荷として扱いましょう。明日重く感じる場合は、次の高強度セッションを軽くしてください。"
        case (.ja, .undercooked): "問題ありません。有酸素の積み上げとして受け止め、明日に不足分を詰め込まないでください。"
        case (.ja, .unmatched) where (averageHeartRate ?? 0) >= 165: "高強度のようです。強度を重ねる前に回復を優先してください。"
        case (.ja, .unmatched): "Garminから同期しました。より正確に振り返るため、プランの日に紐付けてください。"
        case (.vi, .onPlan): "Buổi chạy khớp tốt. Giữ buổi tập tiếp theo theo kế hoạch, trừ khi thể trạng ngày mai cho thấy điều khác."
        case (.vi, .overcooked): "Hãy xem đây là tải bổ sung. Nếu ngày mai thấy nặng, hãy giảm độ khó của buổi chất lượng tiếp theo."
        case (.vi, .undercooked): "Không sao. Ghi nhận khối lượng aerobic và đừng cố bù phần còn thiếu vào ngày mai."
        case (.vi, .unmatched) where (averageHeartRate ?? 0) >= 165: "Đây có vẻ là nỗ lực nặng. Hãy ưu tiên hồi phục trước khi xếp thêm bài cường độ."
        case (.vi, .unmatched): "Đã đồng bộ từ Garmin. Hãy ghép với một ngày trong kế hoạch để đánh giá chính xác hơn."
        }
    }

    func miniChartInterpretation(hasPlan: Bool) -> String {
        switch (language, hasPlan) {
        case (.en, true): "Most of the extra effort came from the middle of the run."
        case (.en, false): "The pace pattern is shown without a plan target."
        case (.ja, true): "追加の負荷の大半はランの中盤に生じました。"
        case (.ja, false): "プランの目標なしでペースの推移を表示しています。"
        case (.vi, true): "Phần lớn nỗ lực tăng thêm xuất hiện ở giữa buổi chạy."
        case (.vi, false): "Diễn biến nhịp độ được hiển thị mà không có mục tiêu từ kế hoạch."
        }
    }

    var paceOnRange: String { switch language { case .en: "on range"; case .ja: "範囲内"; case .vi: "trong phạm vi" } }

    func paceInsight(hasPlan: Bool, easyLabel: String) -> String {
        switch (language, hasPlan) {
        case (.en, true): "You were closest to the \(easyLabel) target during the final third, but the middle section was substantially faster."
        case (.en, false): "Without a matched plan, this is a pacing shape only. Match the run to a planned workout for execution feedback."
        case (.ja, true): "最後の3分の1は\(easyLabel)の目標に最も近く、中盤はかなり速めでした。"
        case (.ja, false): "一致するプランがないため、これはペースの形状のみです。実行フィードバックにはランを予定のワークアウトに紐付けてください。"
        case (.vi, true): "Bạn gần mục tiêu \(easyLabel) nhất ở một phần ba cuối, nhưng đoạn giữa nhanh hơn đáng kể."
        case (.vi, false): "Không có kế hoạch khớp, đây chỉ là diễn biến nhịp độ. Hãy ghép buổi chạy với một buổi tập dự kiến để nhận phản hồi thực hiện."
        }
    }

    var heartRateInsight: String {
        switch language {
        case .en: "Heart rate continued rising even after pace settled, suggesting accumulating effort."
        case .ja: "ペースが安定した後も心拍数は上がり続け、負荷の蓄積が示唆されます。"
        case .vi: "Nhịp tim vẫn tăng ngay cả khi nhịp độ ổn định, cho thấy nỗ lực đang tích lũy."
        }
    }
    func paceDeltaValue(_ delta: Double?) -> String {
        guard let delta else { return paceOnRange }
        return "\(Int(abs(delta).rounded()))s/km"
    }

    func easyHeartRateTarget(_ bpm: Int) -> String {
        switch language {
        case .en: "easy \(bpm) bpm"
        case .ja: "イージー \(bpm) bpm"
        case .vi: "nhẹ \(bpm) bpm"
        }
    }

    func chartAccessibility(hasPlan: Bool) -> String {
        switch (language, hasPlan) {
        case (.en, true): "Actual pace line compared with planned target band. Faster than plan is highlighted in amber during the middle of the run."
        case (.en, false): "Actual pace line over the workout duration."
        case (.ja, true): "実際のペース線を予定の目標帯と比較しています。ランの中盤で予定より速い箇所はアンバーで強調されています。"
        case (.ja, false): "ワークアウト時間に対する実際のペース線です。"
        case (.vi, true): "Đường nhịp độ thực tế được so sánh với dải mục tiêu dự kiến. Đoạn nhanh hơn kế hoạch ở giữa buổi chạy được làm nổi bật bằng màu hổ phách."
        case (.vi, false): "Đường nhịp độ thực tế theo thời lượng buổi tập."
        }
    }

    func splitsSummary(fastCount: Int, total: Int) -> String {
        switch language {
        case .en: "\(fastCount) of \(total) kilometres were faster than the planned Easy range."
        case .ja: "\(total)キロ中\(fastCount)キロは、予定のイージー範囲より速めでした。"
        case .vi: "\(fastCount) trong \(total) kilômét nhanh hơn phạm vi chạy nhẹ dự kiến."
        }
    }

    var running: String { switch language { case .en: "Running"; case .ja: "ランニング"; case .vi: "Chạy" } }
    var reviewed: String { switch language { case .en: "REVIEWED"; case .ja: "確認済み"; case .vi: "ĐÃ ĐÁNH GIÁ" } }
    var review: String { switch language { case .en: "Review"; case .ja: "確認"; case .vi: "Đánh giá" } }
    var load: String { switch language { case .en: "Load"; case .ja: "負荷"; case .vi: "Tải" } }
    var reviewRun: String { switch language { case .en: "Review run"; case .ja: "ランを確認"; case .vi: "Đánh giá buổi chạy" } }
    var reviewRunWithCoach: String { switch language { case .en: "Review run with Coach"; case .ja: "コーチとランを確認"; case .vi: "Đánh giá buổi chạy với Coach" } }

    func viaGarmin(_ source: String) -> String {
        switch language { case .en: "\(source) via Garmin"; case .ja: "\(source)（Garmin経由）"; case .vi: "\(source) qua Garmin" }
    }

    var lastTwentyEightDays: String { switch language { case .en: "Last 28 days"; case .ja: "過去28日間"; case .vi: "28 ngày qua" } }
    var trends: String { switch language { case .en: "Trends"; case .ja: "トレンド"; case .vi: "Xu hướng" } }
    var trendsEmpty: String { switch language { case .en: "Trends appear once a few days of readiness are recorded."; case .ja: "数日分のコンディションが記録されると、トレンドが表示されます。"; case .vi: "Xu hướng sẽ hiển thị khi đã có vài ngày thể trạng được ghi nhận." } }
    var averageReadiness: String { switch language { case .en: "AVG READY"; case .ja: "平均コンディション"; case .vi: "THỂ TRẠNG TB" } }
    var trained: String { switch language { case .en: "TRAINED"; case .ja: "トレーニング"; case .vi: "ĐÃ TẬP" } }
    var rested: String { switch language { case .en: "RESTED"; case .ja: "休養"; case .vi: "ĐÃ NGHỈ" } }

    func streakDays(_ count: Int) -> String {
        switch language {
        case .en: count == 1 ? "STREAK DAY" : "STREAK DAYS"
        case .ja: "連続日数"
        case .vi: "NGÀY LIÊN TIẾP"
        }
    }

    var readinessThisWeek: String { switch language { case .en: "Readiness · this week"; case .ja: "コンディション · 今週"; case .vi: "Thể trạng · tuần này" } }
    var heartRateVariability: String { switch language { case .en: "Heart Rate Variability"; case .ja: "心拍変動"; case .vi: "Biến thiên nhịp tim" } }
    var restingHeartRate: String { switch language { case .en: "Resting Heart Rate"; case .ja: "安静時心拍数"; case .vi: "Nhịp tim nghỉ" } }
    var sleepSevenNights: String { switch language { case .en: "Sleep · 7 nights"; case .ja: "睡眠 · 7夜"; case .vi: "Giấc ngủ · 7 đêm" } }
    var dayAxis: String { switch language { case .en: "Day"; case .ja: "日"; case .vi: "Ngày" } }
    var nightAxis: String { switch language { case .en: "Night"; case .ja: "夜"; case .vi: "Đêm" } }
    var hoursAxis: String { switch language { case .en: "Hours"; case .ja: "時間"; case .vi: "Giờ" } }
    var deepSleep: String { switch language { case .en: "Deep"; case .ja: "深い睡眠"; case .vi: "Ngủ sâu" } }
    var remSleep: String { "REM" }
    var lightSleep: String { switch language { case .en: "Light"; case .ja: "浅い睡眠"; case .vi: "Ngủ nông" } }
    var sleepStage: String { switch language { case .en: "Stage"; case .ja: "ステージ"; case .vi: "Giai đoạn" } }
}

enum HistoryPeriodDescription {
    case lastThirtyDays
    case month
    case year
}
