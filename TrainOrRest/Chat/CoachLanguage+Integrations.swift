import Foundation

extension CoachLanguage {
    var integrations: IntegrationsCopy { IntegrationsCopy(language: self) }
}

struct IntegrationsCopy {
    let language: CoachLanguage

    // MARK: - Google Calendar

    var googleCalendarTitle: String { "Google Calendar" }

    var connectGoogleCalendar: String {
        switch language {
        case .en: "Connect Google Calendar"
        case .ja: "Google Calendarに接続"
        case .vi: "Kết nối Google Calendar"
        }
    }

    var disconnectGoogleCalendar: String {
        switch language {
        case .en: "Disconnect Google Calendar"
        case .ja: "Google Calendarの接続を解除"
        case .vi: "Ngắt kết nối Google Calendar"
        }
    }

    var connectCalendarSubtitle: String {
        switch language {
        case .en: "View TrainOrRest workouts alongside your work and personal schedule."
        case .ja: "仕事や個人の予定と並べてTrainOrRestのワークアウトを確認できます。"
        case .vi: "Xem các buổi tập TrainOrRest cùng lịch công việc và cá nhân của bạn."
        }
    }

    var separateCalendarFooter: String {
        switch language {
        case .en: "TrainOrRest creates a separate training calendar and does not read personal events."
        case .ja: "TrainOrRestはトレーニング用のカレンダーを別に作成し、個人の予定は読み取りません。"
        case .vi: "TrainOrRest tạo một lịch tập riêng và không đọc các sự kiện cá nhân."
        }
    }

    var trainingCalendarName: String { "TrainOrRest Training" }

    var disconnectGoogleCalendarQuestion: String {
        switch language {
        case .en: "Disconnect Google Calendar?"
        case .ja: "Google Calendarの接続を解除しますか？"
        case .vi: "Ngắt kết nối Google Calendar?"
        }
    }

    var keepCalendarAndEvents: String {
        switch language {
        case .en: "Keep calendar and events"
        case .ja: "カレンダーと予定を残す"
        case .vi: "Giữ lịch và sự kiện"
        }
    }

    var deleteTrainingCalendar: String {
        switch language {
        case .en: "Delete TrainOrRest Training calendar"
        case .ja: "TrainOrRest Trainingカレンダーを削除"
        case .vi: "Xóa lịch TrainOrRest Training"
        }
    }

    var disconnectMessage: String {
        switch language {
        case .en: "TrainOrRest will stop updating your Google Calendar."
        case .ja: "TrainOrRestはGoogle Calendarの更新を停止します。"
        case .vi: "TrainOrRest sẽ ngừng cập nhật Google Calendar của bạn."
        }
    }

    var deleteTrainingCalendarQuestion: String {
        switch language {
        case .en: "Delete TrainOrRest Training calendar?"
        case .ja: "TrainOrRest Trainingカレンダーを削除しますか？"
        case .vi: "Xóa lịch TrainOrRest Training?"
        }
    }

    var deleteCalendar: String {
        switch language {
        case .en: "Delete calendar"
        case .ja: "カレンダーを削除"
        case .vi: "Xóa lịch"
        }
    }

    var deleteTrainingCalendarMessage: String {
        switch language {
        case .en: "Only the TrainOrRest-created secondary calendar is removed. Your workouts and personal calendars stay untouched."
        case .ja: "TrainOrRestが作成したサブカレンダーのみが削除されます。ワークアウトと個人のカレンダーは変更されません。"
        case .vi: "Chỉ lịch phụ do TrainOrRest tạo sẽ bị xóa. Các buổi tập và lịch cá nhân của bạn không bị thay đổi."
        }
    }

    var schedulingFromGoogleQuestion: String {
        switch language {
        case .en: "Allow scheduling from Google Calendar?"
        case .ja: "Google Calendarからのスケジュール変更を許可しますか？"
        case .vi: "Cho phép lên lịch từ Google Calendar?"
        }
    }

    var enable: String {
        switch language {
        case .en: "Enable"
        case .ja: "有効にする"
        case .vi: "Bật"
        }
    }

    var schedulingFromGoogleMessage: String {
        switch language {
        case .en: "You’ll be able to change when a TrainOrRest workout happens directly from Google Calendar.\n\nGoogle Calendar can change:\n✓ Workout date\n✓ Start time\n\nGoogle Calendar cannot change:\n✕ Workout type\n✕ Distance\n✕ Pace or intensity\n✕ Workout structure\n✕ Your training goal\n\nMoves that could disrupt your training plan will require review in TrainOrRest."
        case .ja: "Google Calendarから、TrainOrRestのワークアウト日時を直接変更できるようになります。\n\nGoogle Calendarで変更できるもの：\n✓ ワークアウト日\n✓ 開始時刻\n\nGoogle Calendarで変更できないもの：\n✕ ワークアウト種別\n✕ 距離\n✕ ペースまたは強度\n✕ ワークアウトの構成\n✕ トレーニング目標\n\nトレーニングプランに影響する変更は、TrainOrRestで確認が必要です。"
        case .vi: "Bạn sẽ có thể thay đổi thời điểm diễn ra buổi tập TrainOrRest ngay trong Google Calendar.\n\nGoogle Calendar có thể thay đổi:\n✓ Ngày tập\n✓ Giờ bắt đầu\n\nGoogle Calendar không thể thay đổi:\n✕ Loại buổi tập\n✕ Cự ly\n✕ Pace hoặc cường độ\n✕ Cấu trúc buổi tập\n✕ Mục tiêu tập luyện\n\nNhững thay đổi có thể ảnh hưởng đến kế hoạch tập sẽ cần được xem xét trong TrainOrRest."
        }
    }

    var smartSchedulingQuestion: String {
        switch language {
        case .en: "Use Google Calendar availability?"
        case .ja: "Google Calendarの空き時間を使用しますか？"
        case .vi: "Dùng thời gian rảnh trên Google Calendar?"
        }
    }

    var continueWithGoogle: String {
        switch language {
        case .en: "Continue with Google"
        case .ja: "Googleで続ける"
        case .vi: "Tiếp tục với Google"
        }
    }

    var smartSchedulingMessage: String {
        switch language {
        case .en: "TrainOrRest can use your busy and available time to suggest better workout times.\n\nTrainOrRest will be able to see:\n✓ When you are busy\n✓ When you are available\n\nTrainOrRest will not read:\n✕ Event names\n✕ Event descriptions\n✕ Attendees\n✕ Meeting links\n✕ Event notes\n\nYour training plan and workout details remain managed by TrainOrRest."
        case .ja: "TrainOrRestは予定のある時間と空き時間を使って、より良いワークアウト時間を提案できます。\n\nTrainOrRestが確認できるもの：\n✓ 予定がある時間\n✓ 空いている時間\n\nTrainOrRestが読み取らないもの：\n✕ 予定名\n✕ 予定の説明\n✕ 参加者\n✕ 会議リンク\n✕ 予定メモ\n\nトレーニングプランとワークアウトの詳細は、引き続きTrainOrRestで管理されます。"
        case .vi: "TrainOrRest có thể dùng thời gian bận và rảnh của bạn để gợi ý giờ tập phù hợp hơn.\n\nTrainOrRest có thể xem:\n✓ Khi nào bạn bận\n✓ Khi nào bạn rảnh\n\nTrainOrRest sẽ không đọc:\n✕ Tên sự kiện\n✕ Mô tả sự kiện\n✕ Người tham dự\n✕ Liên kết cuộc họp\n✕ Ghi chú sự kiện\n\nKế hoạch tập và chi tiết buổi tập vẫn do TrainOrRest quản lý."
        }
    }

    var workoutDate: String {
        switch language {
        case .en: "Workout date"
        case .ja: "ワークアウト日時"
        case .vi: "Ngày tập"
        }
    }

    var dateValidationFooter: String {
        switch language {
        case .en: "TrainOrRest will validate the chosen date before applying it."
        case .ja: "TrainOrRestは適用前に選択した日時を確認します。"
        case .vi: "TrainOrRest sẽ xác thực ngày đã chọn trước khi áp dụng."
        }
    }

    var chooseAnotherDay: String {
        switch language {
        case .en: "Choose another day"
        case .ja: "別の日を選ぶ"
        case .vi: "Chọn ngày khác"
        }
    }

    var apply: String {
        switch language {
        case .en: "Apply"
        case .ja: "適用"
        case .vi: "Áp dụng"
        }
    }

    var lastSuccessfulSync: String {
        switch language {
        case .en: "Last successful sync"
        case .ja: "最終同期成功"
        case .vi: "Lần đồng bộ thành công gần nhất"
        }
    }

    var notYet: String {
        switch language {
        case .en: "Not yet"
        case .ja: "まだありません"
        case .vi: "Chưa có"
        }
    }

    var googleCalendarDate: String {
        switch language {
        case .en: "the Google Calendar date"
        case .ja: "Google Calendarの日付"
        case .vi: "ngày trên Google Calendar"
        }
    }

    var calendar: String {
        switch language {
        case .en: "Calendar"
        case .ja: "カレンダー"
        case .vi: "Lịch"
        }
    }

    var syncNow: String {
        switch language {
        case .en: "Sync now"
        case .ja: "今すぐ同期"
        case .vi: "Đồng bộ ngay"
        }
    }

    var syncGoogleCalendarNow: String {
        switch language {
        case .en: "Sync Google Calendar now"
        case .ja: "Google Calendarを今すぐ同期"
        case .vi: "Đồng bộ Google Calendar ngay"
        }
    }

    var upcomingPlanWorkouts: String {
        switch language {
        case .en: "Upcoming plan workouts"
        case .ja: "今後のプラン済みワークアウト"
        case .vi: "Buổi tập sắp tới trong kế hoạch"
        }
    }

    var completedActivities: String {
        switch language {
        case .en: "Completed activities"
        case .ja: "完了したアクティビティ"
        case .vi: "Hoạt động đã hoàn thành"
        }
    }

    func completedActivityMode(_ mode: GoogleCalendarCompletedActivityMode) -> String {
        switch (language, mode) {
        case (.en, .none): "None"
        case (.en, .plannedOnly): "Plan workouts only"
        case (.en, .allActivities): "All activities"
        case (.ja, .none): "なし"
        case (.ja, .plannedOnly): "プランのワークアウトのみ"
        case (.ja, .allActivities): "すべてのアクティビティ"
        case (.vi, .none): "Không có"
        case (.vi, .plannedOnly): "Chỉ buổi tập trong kế hoạch"
        case (.vi, .allActivities): "Tất cả hoạt động"
        }
    }

    var workoutsWithoutStartTime: String {
        switch language {
        case .en: "Workouts without a start time"
        case .ja: "開始時刻のないワークアウト"
        case .vi: "Buổi tập không có giờ bắt đầu"
        }
    }

    var allDayEvent: String {
        switch language {
        case .en: "All-day event"
        case .ja: "終日予定"
        case .vi: "Sự kiện cả ngày"
        }
    }

    var googleCalendarReminders: String {
        switch language {
        case .en: "Google Calendar reminders"
        case .ja: "Google Calendarのリマインダー"
        case .vi: "Nhắc nhở Google Calendar"
        }
    }

    var off: String {
        switch language {
        case .en: "Off"
        case .ja: "オフ"
        case .vi: "Tắt"
        }
    }

    var whatSyncs: String {
        switch language {
        case .en: "What syncs"
        case .ja: "同期する内容"
        case .vi: "Nội dung đồng bộ"
        }
    }

    var schedulingEnabledSyncFooter: String {
        switch language {
        case .en: "Google Calendar can schedule the workout. TrainOrRest defines the workout."
        case .ja: "Google Calendarでワークアウトの日時を設定できます。ワークアウト内容はTrainOrRestが決めます。"
        case .vi: "Google Calendar có thể lên lịch buổi tập. TrainOrRest xác định nội dung buổi tập."
        }
    }

    var schedulingDisabledSyncFooter: String {
        switch language {
        case .en: "TrainOrRest is the source of truth. Changes made in Google Calendar do not update your training plan and may be overwritten during sync."
        case .ja: "TrainOrRestが正しい情報源です。Google Calendarでの変更はトレーニングプランに反映されず、同期時に上書きされることがあります。"
        case .vi: "TrainOrRest là nguồn dữ liệu chính. Các thay đổi trên Google Calendar không cập nhật kế hoạch tập và có thể bị ghi đè khi đồng bộ."
        }
    }

    var allowSchedulingFromGoogle: String {
        switch language {
        case .en: "Allow scheduling from Google Calendar"
        case .ja: "Google Calendarからのスケジュール変更を許可"
        case .vi: "Cho phép lên lịch từ Google Calendar"
        }
    }

    var lastChecked: String {
        switch language {
        case .en: "Last checked"
        case .ja: "最終確認"
        case .vi: "Lần kiểm tra gần nhất"
        }
    }

    var schedulingFromGoogle: String {
        switch language {
        case .en: "Scheduling from Google"
        case .ja: "Googleからのスケジュール変更"
        case .vi: "Lên lịch từ Google"
        }
    }

    var schedulingFromGoogleFooter: String {
        switch language {
        case .en: "When enabled, changing the date or start time of a TrainOrRest workout in Google Calendar can update your training schedule.\n\nWorkout type, distance, pace, and structure remain managed by TrainOrRest."
        case .ja: "有効にすると、Google CalendarでTrainOrRestワークアウトの日付や開始時刻を変更した場合、トレーニングスケジュールを更新できます。\n\nワークアウト種別、距離、ペース、構成は引き続きTrainOrRestで管理されます。"
        case .vi: "Khi bật, việc thay đổi ngày hoặc giờ bắt đầu của buổi tập TrainOrRest trên Google Calendar có thể cập nhật lịch tập của bạn.\n\nLoại buổi tập, cự ly, pace và cấu trúc vẫn do TrainOrRest quản lý."
        }
    }

    var calendarChangeReview: String {
        switch language {
        case .en: "Calendar change review"
        case .ja: "カレンダー変更の確認"
        case .vi: "Xem xét thay đổi lịch"
        }
    }

    var disconnect: String {
        switch language {
        case .en: "Disconnect"
        case .ja: "接続を解除"
        case .vi: "Ngắt kết nối"
        }
    }

    var googleCalendarNeedsAttention: String {
        switch language {
        case .en: "Google Calendar needs attention"
        case .ja: "Google Calendarの確認が必要です"
        case .vi: "Google Calendar cần được chú ý"
        }
    }

    var reconnectSubtitle: String {
        switch language {
        case .en: "TrainOrRest no longer has permission to update your training calendar."
        case .ja: "TrainOrRestにはトレーニングカレンダーを更新する権限がなくなりました。"
        case .vi: "TrainOrRest không còn quyền cập nhật lịch tập của bạn."
        }
    }

    var reconnect: String {
        switch language {
        case .en: "Reconnect"
        case .ja: "再接続"
        case .vi: "Kết nối lại"
        }
    }

    var trainingCalendarRemoved: String {
        switch language {
        case .en: "Training calendar was removed"
        case .ja: "トレーニングカレンダーが削除されました"
        case .vi: "Lịch tập đã bị xóa"
        }
    }

    var trainingCalendarRemovedSubtitle: String {
        switch language {
        case .en: "The TrainOrRest Training calendar can no longer be found in Google Calendar."
        case .ja: "Google CalendarでTrainOrRest Trainingカレンダーが見つからなくなりました。"
        case .vi: "Không thể tìm thấy lịch TrainOrRest Training trong Google Calendar."
        }
    }

    var createAgain: String {
        switch language {
        case .en: "Create again"
        case .ja: "もう一度作成"
        case .vi: "Tạo lại"
        }
    }

    var useCalendarAvailability: String {
        switch language {
        case .en: "Use calendar availability"
        case .ja: "カレンダーの空き時間を使用"
        case .vi: "Dùng thời gian rảnh trên lịch"
        }
    }

    var useGoogleCalendarAvailability: String {
        switch language {
        case .en: "Use Google Calendar availability"
        case .ja: "Google Calendarの空き時間を使用"
        case .vi: "Dùng thời gian rảnh trên Google Calendar"
        }
    }

    var availabilityCoachExplanation: String {
        switch language {
        case .en: "Let Coach use busy and available time blocks to suggest better workout times. TrainOrRest does not read event names or details."
        case .ja: "予定のある時間と空き時間を使って、Coachがより良いワークアウト時間を提案します。TrainOrRestは予定名や詳細を読み取りません。"
        case .vi: "Cho Coach dùng các khoảng thời gian bận và rảnh để gợi ý giờ tập phù hợp hơn. TrainOrRest không đọc tên hoặc chi tiết sự kiện."
        }
    }

    var smartScheduling: String {
        switch language {
        case .en: "Smart Scheduling"
        case .ja: "スマートスケジューリング"
        case .vi: "Lên lịch thông minh"
        }
    }

    var needsPermission: String {
        switch language {
        case .en: "Needs permission"
        case .ja: "権限が必要"
        case .vi: "Cần quyền truy cập"
        }
    }

    var reconnectSmartScheduling: String {
        switch language {
        case .en: "Reconnect Smart Scheduling"
        case .ja: "スマートスケジューリングを再接続"
        case .vi: "Kết nối lại Lên lịch thông minh"
        }
    }

    var availabilityCalendars: String {
        switch language {
        case .en: "Availability calendars"
        case .ja: "空き時間を確認するカレンダー"
        case .vi: "Lịch dùng để xem thời gian rảnh"
        }
    }

    var schedulingPreferences: String {
        switch language {
        case .en: "Scheduling preferences"
        case .ja: "スケジュール設定"
        case .vi: "Tùy chọn lên lịch"
        }
    }

    var lastAvailabilityRefresh: String {
        switch language {
        case .en: "Last availability refresh"
        case .ja: "空き時間の最終更新"
        case .vi: "Lần làm mới thời gian rảnh gần nhất"
        }
    }

    var refreshAvailability: String {
        switch language {
        case .en: "Refresh availability"
        case .ja: "空き時間を更新"
        case .vi: "Làm mới thời gian rảnh"
        }
    }

    var refreshCalendarAvailability: String {
        switch language {
        case .en: "Refresh calendar availability"
        case .ja: "カレンダーの空き時間を更新"
        case .vi: "Làm mới thời gian rảnh trên lịch"
        }
    }

    var smartSchedulingFooter: String {
        switch language {
        case .en: "TrainOrRest only uses busy/free time to help schedule workouts. Event names and details are not used."
        case .ja: "TrainOrRestはワークアウトのスケジュール提案のために予定あり／空き時間のみを使用します。予定名と詳細は使用しません。"
        case .vi: "TrainOrRest chỉ dùng thời gian bận/rảnh để hỗ trợ lên lịch buổi tập. Tên và chi tiết sự kiện không được sử dụng."
        }
    }

    func connectionStatusTitle(_ status: GoogleCalendarConnectionStatus) -> String {
        switch (language, status) {
        case (.en, .initialSync): "Initial sync"
        case (.en, .syncing): "Syncing"
        case (.en, .partialFailure): "Calendar sync incomplete"
        case (.en, .offlineQueued): "Waiting for connection"
        case (.en, _): "Google Calendar Connected"
        case (.ja, .initialSync): "初回同期"
        case (.ja, .syncing): "同期中"
        case (.ja, .partialFailure): "カレンダーの同期が未完了"
        case (.ja, .offlineQueued): "接続待機中"
        case (.ja, _): "Google Calendarに接続済み"
        case (.vi, .initialSync): "Đồng bộ lần đầu"
        case (.vi, .syncing): "Đang đồng bộ"
        case (.vi, .partialFailure): "Đồng bộ lịch chưa hoàn tất"
        case (.vi, .offlineQueued): "Đang chờ kết nối"
        case (.vi, _): "Đã kết nối Google Calendar"
        }
    }

    var otherOptions: String {
        switch language {
        case .en: "Other options"
        case .ja: "その他の選択肢"
        case .vi: "Tùy chọn khác"
        }
    }

    func recommendationRationale(for reason: GoogleCalendarInboundChangeReason) -> String {
        switch (language, reason) {
        case (.en, .eventDeleted): "You deleted this workout in Google Calendar. Recommended: add it back so your plan stays intact."
        case (.en, .targetDayConflict): "That day already has a workout. Recommended: swap the two so both still fit your week."
        case (.en, .outsidePlannedWeek): "This moves the workout outside its planned week. Recommended: review with Coach before changing plan structure."
        case (.en, .planValidationFailed): "This move breaks a plan rule. Recommended: review with Coach to find a safe fit."
        case (.en, _): "This change needs review. Recommended: review with Coach before applying it."
        case (.ja, .eventDeleted): "Google Calendarでこのワークアウトを削除しました。プランを維持するため、戻すことをおすすめします。"
        case (.ja, .targetDayConflict): "その日にはすでにワークアウトがあります。どちらもその週に収まるよう、入れ替えることをおすすめします。"
        case (.ja, .outsidePlannedWeek): "この変更によりワークアウトが予定週の外に移動します。プラン構成を変える前にCoachと確認することをおすすめします。"
        case (.ja, .planValidationFailed): "この変更はプランのルールに反します。安全な調整を見つけるため、Coachと確認することをおすすめします。"
        case (.ja, _): "この変更は確認が必要です。適用前にCoachと確認することをおすすめします。"
        case (.vi, .eventDeleted): "Bạn đã xóa buổi tập này trong Google Calendar. Khuyến nghị: thêm lại để giữ nguyên kế hoạch."
        case (.vi, .targetDayConflict): "Ngày đó đã có buổi tập. Khuyến nghị: đổi chỗ hai buổi để cả hai vẫn phù hợp trong tuần."
        case (.vi, .outsidePlannedWeek): "Thay đổi này đưa buổi tập ra ngoài tuần đã lên kế hoạch. Khuyến nghị: xem lại với Coach trước khi đổi cấu trúc kế hoạch."
        case (.vi, .planValidationFailed): "Thay đổi này vi phạm một quy tắc của kế hoạch. Khuyến nghị: xem lại với Coach để tìm phương án an toàn."
        case (.vi, _): "Thay đổi này cần được xem xét. Khuyến nghị: xem lại với Coach trước khi áp dụng."
        }
    }

    var addBackToGoogleCalendar: String {
        switch language {
        case .en: "Add back to Google Calendar"
        case .ja: "Google Calendarに戻す"
        case .vi: "Thêm lại vào Google Calendar"
        }
    }

    var addWorkoutBackToGoogleCalendar: String {
        switch language {
        case .en: "Add workout back to Google Calendar"
        case .ja: "ワークアウトをGoogle Calendarに戻す"
        case .vi: "Thêm lại buổi tập vào Google Calendar"
        }
    }

    var swapWorkouts: String {
        switch language {
        case .en: "Swap workouts"
        case .ja: "ワークアウトを入れ替える"
        case .vi: "Đổi chỗ buổi tập"
        }
    }

    var reviewWithCoach: String {
        switch language {
        case .en: "Review with Coach"
        case .ja: "Coachと確認"
        case .vi: "Xem lại với Coach"
        }
    }

    var reviewGoogleCalendarChangeWithCoach: String {
        switch language {
        case .en: "Review Google Calendar change with Coach"
        case .ja: "Google Calendarの変更をCoachと確認"
        case .vi: "Xem lại thay đổi Google Calendar với Coach"
        }
    }

    var smartSchedulingFound: String {
        switch language {
        case .en: "Smart Scheduling found"
        case .ja: "スマートスケジューリングの候補"
        case .vi: "Lên lịch thông minh đã tìm thấy"
        }
    }

    func timeRange(_ start: String, _ end: String) -> String { "\(start)-\(end)" }

    var acceptSmartSchedulingAlternative: String {
        switch language {
        case .en: "Accept Smart Scheduling alternative"
        case .ja: "スマートスケジューリングの候補を採用"
        case .vi: "Chấp nhận lựa chọn Lên lịch thông minh"
        }
    }

    var restoreOriginalDate: String {
        switch language {
        case .en: "Restore original date"
        case .ja: "元の日付に戻す"
        case .vi: "Khôi phục ngày ban đầu"
        }
    }

    var keepOriginalSchedule: String {
        switch language {
        case .en: "Keep original schedule"
        case .ja: "元の予定を維持"
        case .vi: "Giữ lịch ban đầu"
        }
    }

    var restoreOriginalWorkoutDate: String {
        switch language {
        case .en: "Restore original workout date"
        case .ja: "元のワークアウト日を復元"
        case .vi: "Khôi phục ngày tập ban đầu"
        }
    }

    func changeStatusTitle(_ status: GoogleCalendarInboundChangeStatus) -> String {
        switch (language, status) {
        case (.en, .pendingReview): "Needs review"
        case (.en, .applied): "Applied"
        case (.en, .rejected): "Rejected"
        case (.en, .restored): "Restored"
        case (.ja, .pendingReview): "確認が必要"
        case (.ja, .applied): "適用済み"
        case (.ja, .rejected): "却下済み"
        case (.ja, .restored): "復元済み"
        case (.vi, .pendingReview): "Cần xem xét"
        case (.vi, .applied): "Đã áp dụng"
        case (.vi, .rejected): "Đã từ chối"
        case (.vi, .restored): "Đã khôi phục"
        }
    }

    func coachPrompt(original: String, proposed: String) -> String {
        switch language {
        case .en: "Review this Google Calendar schedule change before changing the training plan. Original workout date: \(original). Requested Google Calendar date: \(proposed). Consider the current plan week, target week, nearby workouts, phase, load, recovery, and whether to accept, swap, adjust the week, or keep the original schedule."
        case .ja: "トレーニングプランを変更する前に、このGoogle Calendarのスケジュール変更を確認してください。元のワークアウト日時：\(original)。希望するGoogle Calendar日時：\(proposed)。現在のプラン週、目標週、近くのワークアウト、フェーズ、負荷、回復を考慮し、承認、入れ替え、週の調整、または元の予定を維持するか判断してください。"
        case .vi: "Hãy xem xét thay đổi lịch Google Calendar này trước khi thay đổi kế hoạch tập. Ngày tập ban đầu: \(original). Ngày Google Calendar được yêu cầu: \(proposed). Hãy cân nhắc tuần kế hoạch hiện tại, tuần mục tiêu, các buổi tập gần đó, giai đoạn, khối lượng, hồi phục và việc chấp nhận, đổi chỗ, điều chỉnh tuần hoặc giữ lịch ban đầu."
        }
    }

    var createSeparateTrainingCalendar: String {
        switch language {
        case .en: "Create a separate calendar named “TrainOrRest Training”"
        case .ja: "「TrainOrRest Training」という別のカレンダーを作成"
        case .vi: "Tạo một lịch riêng tên “TrainOrRest Training”"
        }
    }

    var addAndUpdateWorkouts: String {
        switch language {
        case .en: "Add and update workouts in that calendar"
        case .ja: "そのカレンダーにワークアウトを追加・更新"
        case .vi: "Thêm và cập nhật buổi tập trong lịch đó"
        }
    }

    var keepWorkoutsSynchronized: String {
        switch language {
        case .en: "Keep those workouts synchronized when your plan changes"
        case .ja: "プランの変更に合わせてワークアウトを同期"
        case .vi: "Đồng bộ các buổi tập đó khi kế hoạch thay đổi"
        }
    }

    var doNotReadPersonalEvents: String {
        switch language {
        case .en: "Read events from your personal calendars"
        case .ja: "個人のカレンダーから予定を読み取る"
        case .vi: "Đọc sự kiện từ lịch cá nhân của bạn"
        }
    }

    var doNotChangeOtherCalendars: String {
        switch language {
        case .en: "Change your other calendars"
        case .ja: "ほかのカレンダーを変更する"
        case .vi: "Thay đổi các lịch khác của bạn"
        }
    }

    var doNotReschedulePlan: String {
        switch language {
        case .en: "Reschedule your TrainOrRest plan from Google Calendar"
        case .ja: "Google CalendarからTrainOrRestプランを再調整する"
        case .vi: "Đổi lịch kế hoạch TrainOrRest từ Google Calendar"
        }
    }

    var notNow: String {
        switch language {
        case .en: "Not now"
        case .ja: "今はしない"
        case .vi: "Không phải bây giờ"
        }
    }

    var status: String { language.statusLabel }

    func changesNeedReview(_ count: Int) -> String {
        switch language {
        case .en: "\(count) changes need review"
        case .ja: "\(count)件の変更を確認"
        case .vi: "\(count) thay đổi cần xem xét"
        }
    }

    var reviewChanges: String {
        switch language {
        case .en: "Review changes"
        case .ja: "変更を確認"
        case .vi: "Xem xét thay đổi"
        }
    }

    var reviewGoogleCalendarChanges: String {
        switch language {
        case .en: "Review Google Calendar changes"
        case .ja: "Google Calendarの変更を確認"
        case .vi: "Xem xét thay đổi Google Calendar"
        }
    }

    var manageSync: String {
        switch language {
        case .en: "Manage sync"
        case .ja: "同期を管理"
        case .vi: "Quản lý đồng bộ"
        }
    }

    func statusSheetSubtitle(_ status: GoogleCalendarConnectionStatus, lastSynced: String? = nil) -> String {
        switch status {
        case .disconnected: return localized(disconnected: "Not connected", ja: "未接続", vi: "Chưa kết nối")
        case .syncing, .initialSync: return localized(disconnected: "Syncing", ja: "同期中", vi: "Đang đồng bộ")
        case .needsReconnect: return localized(disconnected: "Reconnect required", ja: "再接続が必要", vi: "Cần kết nối lại")
        case .offlineQueued: return localized(disconnected: "Waiting for connection", ja: "接続待機中", vi: "Đang chờ kết nối")
        case .partialFailure: return localized(disconnected: "Needs attention", ja: "確認が必要", vi: "Cần được chú ý")
        default:
            if let lastSynced {
                return localized(disconnected: "Last synced \(lastSynced)", ja: "最終同期：\(lastSynced)", vi: "Đồng bộ gần nhất: \(lastSynced)")
            }
            return localized(disconnected: "Connected", ja: "接続済み", vi: "Đã kết nối")
        }
    }

    func statusValue(_ status: GoogleCalendarConnectionStatus) -> String {
        switch (language, status) {
        case (.en, .connected): "Up to date"
        case (.en, .syncing), (.en, .initialSync): "Syncing"
        case (.en, .needsReconnect): "Reconnect required"
        case (.en, .offlineQueued): "Waiting for connection"
        case (.en, .partialFailure), (.en, .calendarMissing): "Sync incomplete"
        case (.en, .disconnected), (.en, .connecting): "Not connected"
        case (.ja, .connected): "最新です"
        case (.ja, .syncing), (.ja, .initialSync): "同期中"
        case (.ja, .needsReconnect): "再接続が必要"
        case (.ja, .offlineQueued): "接続待機中"
        case (.ja, .partialFailure), (.ja, .calendarMissing): "同期未完了"
        case (.ja, .disconnected), (.ja, .connecting): "未接続"
        case (.vi, .connected): "Đã cập nhật"
        case (.vi, .syncing), (.vi, .initialSync): "Đang đồng bộ"
        case (.vi, .needsReconnect): "Cần kết nối lại"
        case (.vi, .offlineQueued): "Đang chờ kết nối"
        case (.vi, .partialFailure), (.vi, .calendarMissing): "Đồng bộ chưa hoàn tất"
        case (.vi, .disconnected), (.vi, .connecting): "Chưa kết nối"
        }
    }

    var preferredTrainingTime: String {
        switch language {
        case .en: "Preferred training time"
        case .ja: "希望するトレーニング時間"
        case .vi: "Thời gian tập ưu tiên"
        }
    }

    func preferredTrainingTimeOption(_ time: PreferredTrainingTime) -> String {
        switch (language, time) {
        case (.en, .none): "No preference"
        case (.en, .earlyMorning): "Early morning"
        case (.en, .morning): "Morning"
        case (.en, .lunch): "Lunch"
        case (.en, .afternoon): "Afternoon"
        case (.en, .evening): "Evening"
        case (.en, .custom): "Custom"
        case (.ja, .none): "希望なし"
        case (.ja, .earlyMorning): "早朝"
        case (.ja, .morning): "午前"
        case (.ja, .lunch): "昼"
        case (.ja, .afternoon): "午後"
        case (.ja, .evening): "夕方"
        case (.ja, .custom): "カスタム"
        case (.vi, .none): "Không ưu tiên"
        case (.vi, .earlyMorning): "Sáng sớm"
        case (.vi, .morning): "Buổi sáng"
        case (.vi, .lunch): "Buổi trưa"
        case (.vi, .afternoon): "Buổi chiều"
        case (.vi, .evening): "Buổi tối"
        case (.vi, .custom): "Tùy chỉnh"
        }
    }

    func earliestStart(_ time: String) -> String {
        switch language {
        case .en: "Earliest start \(time)"
        case .ja: "最も早い開始時刻：\(time)"
        case .vi: "Bắt đầu sớm nhất: \(time)"
        }
    }

    func latestFinish(_ time: String) -> String {
        switch language {
        case .en: "Latest finish \(time)"
        case .ja: "最も遅い終了時刻：\(time)"
        case .vi: "Kết thúc muộn nhất: \(time)"
        }
    }

    func bufferBefore(_ minutes: Int) -> String {
        switch language {
        case .en: "Buffer before \(minutes) min"
        case .ja: "前の余裕時間：\(minutes)分"
        case .vi: "Khoảng đệm trước: \(minutes) phút"
        }
    }

    func bufferAfter(_ minutes: Int) -> String {
        switch language {
        case .en: "Buffer after \(minutes) min"
        case .ja: "後の余裕時間：\(minutes)分"
        case .vi: "Khoảng đệm sau: \(minutes) phút"
        }
    }

    var schedulingPreferencesFooter: String {
        switch language {
        case .en: "These preferences rank valid slots. They never override recovery or plan-safety validation."
        case .ja: "これらの設定は有効な候補の優先順位を決めます。回復やプラン安全性の確認より優先されることはありません。"
        case .vi: "Các tùy chọn này xếp hạng các khung giờ hợp lệ. Chúng không bao giờ ghi đè xác thực hồi phục hoặc an toàn kế hoạch."
        }
    }

    // MARK: - Running shoes

    var runningShoes: String {
        switch language {
        case .en: "Running Shoes"
        case .ja: "ランニングシューズ"
        case .vi: "Giày chạy"
        }
    }

    var active: String {
        switch language {
        case .en: "Active"
        case .ja: "使用中"
        case .vi: "Đang dùng"
        }
    }

    func retiredShoes(_ count: Int) -> String {
        switch language {
        case .en: "Retired · \(count) shoes"
        case .ja: "引退済み・\(count)足"
        case .vi: "Đã ngừng dùng · \(count) đôi"
        }
    }

    var addYourFirstShoe: String {
        switch language {
        case .en: "Add your first shoe"
        case .ja: "最初のシューズを追加"
        case .vi: "Thêm đôi giày đầu tiên"
        }
    }

    var addShoe: String {
        switch language {
        case .en: "Add shoe"
        case .ja: "シューズを追加"
        case .vi: "Thêm giày"
        }
    }

    var shoeAssignmentSettings: String {
        switch language {
        case .en: "Shoe assignment settings"
        case .ja: "シューズ割り当て設定"
        case .vi: "Cài đặt gán giày"
        }
    }

    var shoeMileageEmptyState: String {
        switch language {
        case .en: "Track shoe mileage and let TrainOrRest pick the right pair for each workout."
        case .ja: "シューズの走行距離を記録し、各ワークアウトに合う一足をTrainOrRestに選ばせましょう。"
        case .vi: "Theo dõi quãng đường của giày và để TrainOrRest chọn đôi phù hợp cho mỗi buổi tập."
        }
    }

    var noActiveShoes: String {
        switch language {
        case .en: "No active shoes."
        case .ja: "使用中のシューズはありません。"
        case .vi: "Không có giày đang dùng."
        }
    }

    func shoeTypes(_ types: [ShoeWorkoutType]) -> String {
        guard !types.isEmpty else { return anyRun }
        return types.map(shoeWorkoutType).joined(separator: " · ")
    }

    var anyRun: String {
        switch language {
        case .en: "Any run"
        case .ja: "すべてのラン"
        case .vi: "Mọi buổi chạy"
        }
    }

    func shoeWorkoutType(_ type: ShoeWorkoutType) -> String {
        switch (language, type) {
        case (.en, .recovery): "Recovery"
        case (.en, .easy): "Easy"
        case (.en, .longRun): "Long Run"
        case (.en, .steady): "Steady"
        case (.en, .tempo): "Tempo"
        case (.en, .threshold): "Threshold"
        case (.en, .intervals): "Intervals"
        case (.en, .race): "Race"
        case (.en, .other): "Other"
        case (.ja, .recovery): "リカバリー"
        case (.ja, .easy): "イージー"
        case (.ja, .longRun): "ロング走"
        case (.ja, .steady): "ステディ"
        case (.ja, .tempo): "テンポ"
        case (.ja, .threshold): "閾値走"
        case (.ja, .intervals): "インターバル"
        case (.ja, .race): "レース"
        case (.ja, .other): "その他"
        case (.vi, .recovery): "Hồi phục"
        case (.vi, .easy): "Nhẹ"
        case (.vi, .longRun): "Chạy dài"
        case (.vi, .steady): "Ổn định"
        case (.vi, .tempo): "Tempo"
        case (.vi, .threshold): "Ngưỡng"
        case (.vi, .intervals): "Biến tốc"
        case (.vi, .race): "Thi đấu"
        case (.vi, .other): "Khác"
        }
    }

    func mileageProgress(current: String, expected: String) -> String { "\(current) / ~\(expected)" }

    var checkSoon: String {
        switch language {
        case .en: "Check soon"
        case .ja: "まもなく確認"
        case .vi: "Sớm kiểm tra"
        }
    }

    var pastTypicalRange: String {
        switch language {
        case .en: "Past typical range"
        case .ja: "標準範囲を超過"
        case .vi: "Đã vượt phạm vi thông thường"
        }
    }

    func kilometersLogged(_ distance: String) -> String {
        switch language {
        case .en: "\(distance) logged"
        case .ja: "走行距離：\(distance)"
        case .vi: "Đã ghi \(distance)"
        }
    }

    func kilometersUntilRecommendedRange(_ distance: String) -> String {
        switch language {
        case .en: "~\(distance) until recommended range"
        case .ja: "推奨範囲まで約\(distance)"
        case .vi: "Còn ~\(distance) đến phạm vi khuyến nghị"
        }
    }

    var runningShoe: String {
        switch language {
        case .en: "Running Shoe"
        case .ja: "ランニングシューズ"
        case .vi: "Giày chạy"
        }
    }

    func shoeStatus(_ status: RunningShoeStatus) -> String {
        switch (language, status) {
        case (.en, .active): "Active"
        case (.en, .retired): "Retired"
        case (.ja, .active): "使用中"
        case (.ja, .retired): "引退済み"
        case (.vi, .active): "Đang dùng"
        case (.vi, .retired): "Đã ngừng dùng"
        }
    }

    var mileage: String {
        switch language {
        case .en: "Mileage"
        case .ja: "走行距離"
        case .vi: "Quãng đường"
        }
    }

    var usage: String {
        switch language {
        case .en: "Usage"
        case .ja: "使用状況"
        case .vi: "Sử dụng"
        }
    }

    var runs: String {
        switch language {
        case .en: "Runs"
        case .ja: "ラン回数"
        case .vi: "Lần chạy"
        }
    }

    var distance: String { language.distanceLabel }

    var lastRun: String {
        switch language {
        case .en: "Last run"
        case .ja: "前回のラン"
        case .vi: "Lần chạy gần nhất"
        }
    }

    var preferences: String {
        switch language {
        case .en: "Preferences"
        case .ja: "設定"
        case .vi: "Tùy chọn"
        }
    }

    var preferredFor: String {
        switch language {
        case .en: "Preferred for"
        case .ja: "おすすめの用途"
        case .vi: "Phù hợp cho"
        }
    }

    var primary: String {
        switch language {
        case .en: "Primary"
        case .ja: "主な用途"
        case .vi: "Chính"
        }
    }

    var purchase: String {
        switch language {
        case .en: "Purchase"
        case .ja: "購入"
        case .vi: "Mua sắm"
        }
    }

    var purchased: String {
        switch language {
        case .en: "Purchased"
        case .ja: "購入日"
        case .vi: "Ngày mua"
        }
    }

    var notSet: String {
        switch language {
        case .en: "Not set"
        case .ja: "未設定"
        case .vi: "Chưa đặt"
        }
    }

    var startingMileage: String {
        switch language {
        case .en: "Starting mileage"
        case .ja: "開始時の走行距離"
        case .vi: "Quãng đường ban đầu"
        }
    }

    var retireShoe: String {
        switch language {
        case .en: "Retire shoe"
        case .ja: "シューズを引退"
        case .vi: "Ngừng dùng giày"
        }
    }

    var reactivateShoe: String {
        switch language {
        case .en: "Reactivate shoe"
        case .ja: "シューズを再び使用"
        case .vi: "Dùng lại giày"
        }
    }
    var retireShoeQuestion: String {
        switch language {
        case .en: "Retire this shoe?"
        case .ja: "このシューズを引退しますか？"
        case .vi: "Ngừng dùng đôi giày này?"
        }
    }

    func retireShoeMessage(_ name: String) -> String {
        switch language {
        case .en: "\(name) leaves automatic assignment. Mileage stays in the ledger. You can reactivate it later."
        case .ja: "\(name)は自動割り当てから外れます。走行距離は残ります。後から再使用できます。"
        case .vi: "\(name) sẽ không còn được gán tự động. Quãng đường vẫn giữ. Bạn có thể dùng lại sau."
        }
    }

    func shoeFormTitle(_ base: String, step: Int, of total: Int) -> String {
        switch language {
        case .en: "\(base) · \(step) of \(total)"
        case .ja: "\(base) · \(step)/\(total)"
        case .vi: "\(base) · \(step)/\(total)"
        }
    }

    var approachingShort: String {
        switch language {
        case .en: "Approaching"
        case .ja: "接近"
        case .vi: "Sắp đến hạn"
        }
    }


    var approachingRecommendedMileage: String {
        switch language {
        case .en: "Approaching recommended mileage"
        case .ja: "推奨走行距離に近づいています"
        case .vi: "Sắp đến quãng đường khuyến nghị"
        }
    }

    var noActionNeededYet: String {
        switch language {
        case .en: "No action needed yet."
        case .ja: "まだ対応は不要です。"
        case .vi: "Chưa cần làm gì."
        }
    }

    func checkShoe(_ shoeName: String) -> String {
        switch language {
        case .en: "Check your \(shoeName)"
        case .ja: "\(shoeName)を確認"
        case .vi: "Kiểm tra \(shoeName)"
        }
    }

    var inspectShoeMessage: String {
        switch language {
        case .en: "Consider cushioning feel, outsole wear, uneven wear, and new discomfort."
        case .ja: "クッションの感触、アウトソールの摩耗、偏った摩耗、新しい痛みを確認してください。"
        case .vi: "Hãy kiểm tra cảm giác đệm, độ mòn đế ngoài, mòn không đều và cảm giác khó chịu mới."
        }
    }

    var pastRangeMessage: String {
        switch language {
        case .en: "You can keep using it if it still feels good, or retire it from automatic assignment."
        case .ja: "まだ快適なら使い続けられますが、自動割り当てから引退させることもできます。"
        case .vi: "Bạn có thể tiếp tục dùng nếu vẫn thấy ổn, hoặc ngừng gán tự động cho đôi này."
        }
    }

    var basicInformation: String {
        switch language {
        case .en: "Basic information"
        case .ja: "基本情報"
        case .vi: "Thông tin cơ bản"
        }
    }

    var brand: String {
        switch language {
        case .en: "Brand"
        case .ja: "ブランド"
        case .vi: "Thương hiệu"
        }
    }

    var model: String {
        switch language {
        case .en: "Model"
        case .ja: "モデル"
        case .vi: "Mẫu"
        }
    }

    var nickname: String {
        switch language {
        case .en: "Nickname"
        case .ja: "呼び名"
        case .vi: "Biệt danh"
        }
    }

    var setPurchaseDate: String {
        switch language {
        case .en: "Set purchase date"
        case .ja: "購入日を設定"
        case .vi: "Đặt ngày mua"
        }
    }

    var purchaseDate: String {
        switch language {
        case .en: "Purchase date"
        case .ja: "購入日"
        case .vi: "Ngày mua"
        }
    }

    func startingMileageValue(_ distance: String) -> String {
        switch language {
        case .en: "Starting mileage: \(distance)"
        case .ja: "開始時の走行距離：\(distance)"
        case .vi: "Quãng đường ban đầu: \(distance)"
        }
    }

    var shoeUsageQuestion: String {
        switch language {
        case .en: "What do you use this shoe for?"
        case .ja: "このシューズは何に使いますか？"
        case .vi: "Bạn dùng đôi giày này cho việc gì?"
        }
    }

    var primaryUse: String {
        switch language {
        case .en: "Primary use"
        case .ja: "主な用途"
        case .vi: "Mục đích chính"
        }
    }

    var expectedLifespan: String {
        switch language {
        case .en: "Expected lifespan"
        case .ja: "想定寿命"
        case .vi: "Tuổi thọ dự kiến"
        }
    }

    func expectedLifespanValue(_ distance: String) -> String {
        switch language {
        case .en: "Expected lifespan: ~\(distance)"
        case .ja: "想定寿命：約\(distance)"
        case .vi: "Tuổi thọ dự kiến: ~\(distance)"
        }
    }

    var adjustAnytime: String {
        switch language {
        case .en: "You can adjust this anytime."
        case .ja: "これはいつでも変更できます。"
        case .vi: "Bạn có thể điều chỉnh bất cứ lúc nào."
        }
    }

    var next: String {
        switch language {
        case .en: "Next"
        case .ja: "次へ"
        case .vi: "Tiếp"
        }
    }

    var shoeAssignment: String {
        switch language {
        case .en: "Shoe Assignment"
        case .ja: "シューズの割り当て"
        case .vi: "Gán giày"
        }
    }

    var automaticShoeAssignment: String {
        switch language {
        case .en: "Automatic shoe assignment"
        case .ja: "シューズの自動割り当て"
        case .vi: "Gán giày tự động"
        }
    }

    var autoPickShoe: String {
        switch language {
        case .en: "Auto-pick a shoe"
        case .ja: "シューズを自動選択"
        case .vi: "Tự chọn giày"
        }
    }

    var autoPickShoeExplanation: String {
        switch language {
        case .en: "When a workout does not already have a shoe, TrainOrRest can choose one based on workout type and your shoe preferences."
        case .ja: "ワークアウトにシューズがまだない場合、TrainOrRestはワークアウト種別とシューズ設定に基づいて選択できます。"
        case .vi: "Khi một buổi tập chưa có giày, TrainOrRest có thể chọn dựa trên loại buổi tập và tùy chọn giày của bạn."
        }
    }

    var selectionStrategy: String {
        switch language {
        case .en: "Selection strategy"
        case .ja: "選択方法"
        case .vi: "Chiến lược chọn"
        }
    }

    var strategy: String {
        switch language {
        case .en: "Strategy"
        case .ja: "方法"
        case .vi: "Chiến lược"
        }
    }

    func shoeAssignmentStrategy(_ strategy: ShoeAutoAssignmentStrategy) -> String {
        switch (language, strategy) {
        case (.en, .bestMatch): "Best match"
        case (.en, .newestMatched): "Newest matched shoe"
        case (.en, .rotateMatched): "Rotate matched shoes"
        case (.ja, .bestMatch): "最適な一致"
        case (.ja, .newestMatched): "最も新しい一致シューズ"
        case (.ja, .rotateMatched): "一致シューズをローテーション"
        case (.vi, .bestMatch): "Phù hợp nhất"
        case (.vi, .newestMatched): "Đôi phù hợp mới nhất"
        case (.vi, .rotateMatched): "Luân phiên các đôi phù hợp"
        }
    }

    func shoeAssignmentStrategyDescription(_ strategy: ShoeAutoAssignmentStrategy) -> String {
        switch (language, strategy) {
        case (.en, .bestMatch): "Prefer the shoe best suited to the workout."
        case (.en, .newestMatched): "Prefer the newest eligible shoe for that workout type."
        case (.en, .rotateMatched): "Prefer the least recently used matching shoe."
        case (.ja, .bestMatch): "ワークアウトに最も適したシューズを優先します。"
        case (.ja, .newestMatched): "そのワークアウト種別に使える最も新しいシューズを優先します。"
        case (.ja, .rotateMatched): "条件に合うシューズのうち、最も最近使われていないものを優先します。"
        case (.vi, .bestMatch): "Ưu tiên đôi giày phù hợp nhất với buổi tập."
        case (.vi, .newestMatched): "Ưu tiên đôi giày mới nhất đủ điều kiện cho loại buổi tập đó."
        case (.vi, .rotateMatched): "Ưu tiên đôi giày phù hợp được dùng ít gần đây nhất."
        }
    }

    var mileageRange: String {
        switch language {
        case .en: "Mileage range"
        case .ja: "走行距離の範囲"
        case .vi: "Phạm vi quãng đường"
        }
    }

    var avoidShoesNearMileageLimit: String {
        switch language {
        case .en: "Avoid shoes near mileage limit"
        case .ja: "走行距離の上限に近いシューズを避ける"
        case .vi: "Tránh giày gần giới hạn quãng đường"
        }
    }

    func avoidAfter(_ percentage: Int) -> String {
        switch language {
        case .en: "Avoid after \(percentage)%"
        case .ja: "\(percentage)%を超えたら避ける"
        case .vi: "Tránh sau \(percentage)%"
        }
    }

    var chooseShoe: String {
        switch language {
        case .en: "Choose shoe"
        case .ja: "シューズを選ぶ"
        case .vi: "Chọn giày"
        }
    }

    var automatic: String {
        switch language {
        case .en: "Auto"
        case .ja: "自動"
        case .vi: "Tự động"
        }
    }

    var nearRecommendedMileageRange: String {
        switch language {
        case .en: "Near recommended mileage range"
        case .ja: "推奨走行距離に近づいています"
        case .vi: "Gần phạm vi quãng đường khuyến nghị"
        }
    }

    var automaticallySelected: String {
        switch language {
        case .en: "Automatically selected"
        case .ja: "自動選択"
        case .vi: "Được chọn tự động"
        }
    }

    var recommended: String {
        switch language {
        case .en: "Recommended"
        case .ja: "おすすめ"
        case .vi: "Đề xuất"
        }
    }

    var otherMatches: String {
        switch language {
        case .en: "Other matches"
        case .ja: "ほかの候補"
        case .vi: "Lựa chọn phù hợp khác"
        }
    }

    var otherShoes: String {
        switch language {
        case .en: "Other shoes"
        case .ja: "ほかのシューズ"
        case .vi: "Giày khác"
        }
    }

    var useAutomaticSelection: String {
        switch language {
        case .en: "Use automatic selection"
        case .ja: "自動選択を使う"
        case .vi: "Dùng lựa chọn tự động"
        }
    }

    var noShoe: String {
        switch language {
        case .en: "No shoe"
        case .ja: "シューズなし"
        case .vi: "Không chọn giày"
        }
    }

    var chooseAShoe: String {
        switch language {
        case .en: "Choose a shoe"
        case .ja: "シューズを選ぶ"
        case .vi: "Chọn một đôi giày"
        }
    }

    private func localized(disconnected: String, ja: String, vi: String) -> String {
        switch language {
        case .en: disconnected
        case .ja: ja
        case .vi: vi
        }
    }
}
