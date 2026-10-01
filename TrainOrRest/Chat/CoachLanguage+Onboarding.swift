import Foundation

extension CoachLanguage {
    var onboarding: OnboardingCopy { OnboardingCopy(language: self) }
}

struct OnboardingCopy {
    let language: CoachLanguage

    func tabTitle(_ tab: RootTabView.Tab) -> String {
        switch (language, tab) {
        case (.en, .calendar): "Calendar"
        case (.en, .chat): "Chat"
        case (.en, .profile): "Profile"
        case (.ja, .calendar): "カレンダー"
        case (.ja, .chat): "チャット"
        case (.ja, .profile): "プロフィール"
        case (.vi, .calendar): "Lịch"
        case (.vi, .chat): "Trò chuyện"
        case (.vi, .profile): "Hồ sơ"
        }
    }

    func progressStep(_ current: Int, of total: Int) -> String {
        switch language {
        case .en: "Step \(current) of \(total)"
        case .ja: "全\(total)ステップ中\(current)"
        case .vi: "Bước \(current) trên \(total)"
        }
    }

    var languageChoiceTitle: String {
        switch language {
        case .en: "Choose your language"
        case .ja: "言語を選択"
        case .vi: "Chọn ngôn ngữ"
        }
    }

    var languageChoiceSubtitle: String {
        switch language {
        case .en: "Set the language Coach uses for guidance and suggestions. You can change it anytime in Settings."
        case .ja: "Coachのガイダンスと提案に使う言語を設定します。設定からいつでも変更できます。"
        case .vi: "Đặt ngôn ngữ Coach dùng cho hướng dẫn và đề xuất. Bạn có thể đổi bất cứ lúc nào trong Cài đặt."
        }
    }

    var startSetupLabel: String {
        switch language {
        case .en: "Start setup"
        case .ja: "セットアップを始める"
        case .vi: "Bắt đầu thiết lập"
        }
    }

    var welcomeHeadline: String {
        switch language {
        case .en: "What should I do in the next 12 hours?"
        case .ja: "次の12時間、何をすればいい？"
        case .vi: "Trong 12 giờ tới, tôi nên làm gì?"
        }
    }

    var welcomeDescription: String {
        switch language {
        case .en: "Enter the race you signed up for. Get a plan, then a daily call to train, go easy, or rest. Health data stays on this iPhone."
        case .ja: "参加するレースを入力してください。プランを作成し、毎日「トレーニング・軽め・休養」の判断をお届けします。ヘルスケアデータはこのiPhone内に保存されます。"
        case .vi: "Nhập giải đua bạn đã đăng ký. Nhận kế hoạch, rồi quyết định mỗi ngày: tập, tập nhẹ hay nghỉ. Dữ liệu sức khỏe luôn ở trên iPhone này."
        }
    }

    var welcomeDuration: String {
        switch language {
        case .en: "About 3 minutes to a plan. Watch, calendar, and Coach can wait."
        case .ja: "プラン作成まで約3分。Watch、カレンダー、Coachは後から設定できます。"
        case .vi: "Kế hoạch mất khoảng 3 phút. Watch, lịch và Coach có thể thiết lập sau."
        }
    }

    var connectAppleHealth: String {
        switch language {
        case .en: "Connect Apple Health"
        case .ja: "Apple Healthに接続"
        case .vi: "Kết nối Apple Health"
        }
    }


    var healthDescription: String {
        switch language {
        case .en: "TrainOrRest reads running workouts, heart rate, HRV, resting heart rate, VO₂ max, walking and running distance, and sleep from Apple Health to calculate readiness and build or adapt your training plan. TrainOrRest does not write data to Apple Health."
        case .ja: "TrainOrRestはApple Healthからランニングワークアウト、心拍数、HRV、安静時心拍数、VO₂ max、歩行・走行距離、睡眠を読み取り、コンディションの算出とトレーニングプランの作成・調整に使用します。Apple Healthへの書き込みは行いません。"
        case .vi: "TrainOrRest đọc các buổi chạy, nhịp tim, HRV, nhịp tim nghỉ, VO₂ max, quãng đường đi bộ và chạy, cùng dữ liệu giấc ngủ từ Apple Health để tính mức sẵn sàng và tạo hoặc điều chỉnh kế hoạch tập luyện. TrainOrRest không ghi dữ liệu vào Apple Health."
        }
    }

    var healthReadPermission: String {
        switch language {
        case .en: "Running workouts, heart rate, HRV, resting heart rate, VO₂ max, distance, and sleep"
        case .ja: "ランニングワークアウト、心拍数、HRV、安静時心拍数、VO₂ max、距離、睡眠"
        case .vi: "Buổi chạy, nhịp tim, HRV, nhịp tim nghỉ, VO₂ max, quãng đường và giấc ngủ"
        }
    }

    var healthNoWritePermission: String {
        switch language {
        case .en: "Writes no data to Apple Health or Garmin"
        case .ja: "Apple HealthやGarminへデータを書き込みません"
        case .vi: "Không ghi dữ liệu vào Apple Health hoặc Garmin"
        }
    }

    var healthNoAccountPermission: String {
        switch language {
        case .en: "No account or external connection required"
        case .ja: "アカウントや外部サービス連携は不要です"
        case .vi: "Không cần tài khoản hay kết nối dịch vụ ngoài"
        }
    }




    var healthAccessDeniedTitle: String {
        switch language {
        case .en: "Health access is off"
        case .ja: "Healthへのアクセスがオフです"
        case .vi: "Quyền truy cập Health đang tắt"
        }
    }

    var healthAccessDeniedDescription: String {
        switch language {
        case .en: "TrainOrRest will not ask again. Open Settings to enable the Apple Health categories you want to share, or continue with plan, calendar, and Coach features."
        case .ja: "TrainOrRestから再度リクエストすることはありません。設定で共有するApple Healthの項目を有効にするか、プラン、カレンダー、Coachの機能を続けて利用できます。"
        case .vi: "TrainOrRest sẽ không yêu cầu lại. Mở Cài đặt để bật các danh mục Apple Health bạn muốn chia sẻ, hoặc tiếp tục dùng kế hoạch, lịch và Coach."
        }
    }

    var healthAccessRestrictedTitle: String {
        switch language {
        case .en: "Health access is restricted"
        case .ja: "Healthへのアクセスが制限されています"
        case .vi: "Quyền truy cập Health bị hạn chế"
        }
    }

    var healthAccessRestrictedDescription: String {
        switch language {
        case .en: "This device does not allow TrainOrRest to request Apple Health data. You can continue using plan, calendar, and Coach features; readiness and imported runs will remain unavailable."
        case .ja: "このデバイスではTrainOrRestがApple Healthデータをリクエストできません。プラン、カレンダー、Coachは利用できますが、コンディションとランの読み込みは利用できません。"
        case .vi: "Thiết bị này không cho phép TrainOrRest yêu cầu dữ liệu Apple Health. Bạn vẫn có thể dùng kế hoạch, lịch và Coach; mức sẵn sàng và các buổi chạy nhập sẽ không khả dụng."
        }
    }

    var healthAccessNotDeterminedTitle: String {
        switch language {
        case .en: "Health access needs a decision"
        case .ja: "Healthへのアクセスを選択してください"
        case .vi: "Cần quyết định quyền truy cập Health"
        }
    }

    var healthAccessNotDeterminedDescription: String {
        switch language {
        case .en: "Apple Health has not completed the permission decision. Continue to open the native permission request."
        case .ja: "Apple Healthの権限選択が完了していません。「続ける」を押すと標準の権限リクエストが開きます。"
        case .vi: "Apple Health chưa hoàn tất quyết định quyền. Chọn Tiếp tục để mở yêu cầu quyền của hệ thống."
        }
    }

    var healthAccessErrorTitle: String {
        switch language {
        case .en: "Health access could not be requested"
        case .ja: "Healthへのアクセスをリクエストできませんでした"
        case .vi: "Không thể yêu cầu quyền truy cập Health"
        }
    }

    func healthAccessErrorDescription(_ detail: String) -> String {
        switch language {
        case .en: "Apple Health returned an error: \(detail). Retry the native request, or continue with features that do not use Health data."
        case .ja: "Apple Healthでエラーが発生しました：\(detail)。標準の権限リクエストを再試行するか、Healthデータを使用しない機能を続けて利用できます。"
        case .vi: "Apple Health trả về lỗi: \(detail). Hãy thử lại yêu cầu quyền của hệ thống, hoặc tiếp tục với các tính năng không dùng dữ liệu Health."
        }
    }

    var healthAccessDecidedTitle: String {
        switch language {
        case .en: "Apple Health access recorded"
        case .ja: "Apple Healthのアクセス設定を保存しました"
        case .vi: "Đã ghi nhận quyền truy cập Apple Health"
        }
    }

    var healthAccessDecidedDescription: String {
        switch language {
        case .en: "Apple controls each Health category separately. If you declined any requested data, enable it in Settings. TrainOrRest will not repeatedly show the permission request."
        case .ja: "AppleはHealthの各項目を個別に管理します。リクエストしたデータを許可しなかった場合は、設定から有効にできます。TrainOrRestが権限リクエストを繰り返し表示することはありません。"
        case .vi: "Apple quản lý riêng từng danh mục Health. Nếu bạn đã từ chối dữ liệu được yêu cầu, hãy bật lại trong Cài đặt. TrainOrRest sẽ không liên tục hiển thị yêu cầu quyền."
        }
    }

    var openHealthSettings: String {
        switch language {
        case .en: "Open Settings"
        case .ja: "設定を開く"
        case .vi: "Mở Cài đặt"
        }
    }

    var hubTitle: String {
        switch language {
        case .en: "Connect what you use"
        case .ja: "使うものを接続"
        case .vi: "Kết nối những gì bạn dùng"
        }
    }

    var hubDescription: String {
        switch language {
        case .en: "Watch, Google Calendar, and Coach are optional. Open a card or go to Calendar."
        case .ja: "Watch、Google Calendar、Coachは任意です。カードを開くか、カレンダーへ進んでください。"
        case .vi: "Watch, Google Calendar và Coach là tùy chọn. Mở thẻ hoặc vào Lịch."
        }
    }

    var watchWorkoutsTitle: String {
        switch language {
        case .en: "Watch workouts"
        case .ja: "Watchのワークアウト"
        case .vi: "Buổi tập Watch"
        }
    }

    var watchWorkoutsSubtitle: String {
        switch language {
        case .en: "Send sessions to Garmin through intervals.icu"
        case .ja: "intervals.icu経由でセッションをGarminへ送信"
        case .vi: "Gửi buổi tập đến Garmin qua intervals.icu"
        }
    }

    var googleCalendarSubtitle: String {
        switch language {
        case .en: "See workouts next to work and life"
        case .ja: "仕事や生活の予定と一緒にワークアウトを確認"
        case .vi: "Xem buổi tập cùng công việc và cuộc sống"
        }
    }

    var coachSetupTitle: String {
        switch language {
        case .en: "Coach"
        case .ja: "コーチ"
        case .vi: "Coach"
        }
    }

    var coachSetupSubtitle: String {
        switch language {
        case .en: "Explains today and proposes edits you approve."
        case .ja: "今日の判断を説明し、承認してから変更を提案します。"
        case .vi: "Giải thích hôm nay và đề xuất thay đổi khi bạn phê duyệt."
        }
    }

    var openCalendar: String {
        switch language {
        case .en: "Open Calendar"
        case .ja: "カレンダーを開く"
        case .vi: "Mở Lịch"
        }
    }

    var raceSetupTitle: String {
        switch language {
        case .en: "Set the race you entered"
        case .ja: "参加するレースを設定"
        case .vi: "Thiết lập giải đua"
        }
    }

    var raceSetupDescription: String {
        switch language {
        case .en: "Your plan is built backward from race day: distance, date, and target time."
        case .ja: "距離、日付、目標タイムからレース当日から逆算してプランを作成します。"
        case .vi: "Kế hoạch được xây ngược từ ngày đua: cự ly, ngày và thời gian mục tiêu."
        }
    }

    var distance: String {
        switch language {
        case .en: "Distance"
        case .ja: "距離"
        case .vi: "Cự ly"
        }
    }

    var raceDate: String {
        switch language {
        case .en: "Race date"
        case .ja: "レース日"
        case .vi: "Ngày đua"
        }
    }

    var targetTime: String {
        switch language {
        case .en: "Target time (h:mm)"
        case .ja: "目標タイム（時:分）"
        case .vi: "Thời gian mục tiêu (giờ:phút)"
        }
    }

    var hours: String {
        switch language {
        case .en: "Hours"
        case .ja: "時"
        case .vi: "Giờ"
        }
    }

    var minutes: String {
        switch language {
        case .en: "Minutes"
        case .ja: "分"
        case .vi: "Phút"
        }
    }

    func targetHour(_ hour: Int) -> String {
        let value = hour.formatted(.number.locale(language.uiLocale))
        return switch language {
        case .en: "\(value) h"
        case .ja: "\(value)時間"
        case .vi: "\(value) giờ"
        }
    }

    func targetMinute(_ minute: Int) -> String {
        let value = minute.formatted(.number.precision(.integerLength(2)).locale(language.uiLocale))
        return switch language {
        case .en: "\(value) m"
        case .ja: "\(value)分"
        case .vi: "\(value) phút"
        }
    }

    var runningDays: String {
        switch language {
        case .en: "Running days"
        case .ja: "ランニング日"
        case .vi: "Ngày chạy"
        }
    }

    var runningDaysHint: String {
        switch language {
        case .en: "Hard sessions are spaced across these days."
        case .ja: "高強度セッションはこれらの日に分けて配置されます。"
        case .vi: "Các buổi nặng được bố trí cách nhau theo những ngày này."
        }
    }

    var longRunDay: String {
        switch language {
        case .en: "Long run day"
        case .ja: "ロング走の日"
        case .vi: "Ngày chạy dài"
        }
    }

    var comfortablePace: String {
        switch language {
        case .en: "Comfortable pace /km"
        case .ja: "楽なペース /km"
        case .vi: "Pace thoải mái /km"
        }
    }

    var minutesAbbreviation: String {
        switch language {
        case .en: "Min"
        case .ja: "分"
        case .vi: "Phút"
        }
    }

    var secondsAbbreviation: String {
        switch language {
        case .en: "Sec"
        case .ja: "秒"
        case .vi: "Giây"
        }
    }

    func weeklyVolume(_ kilometers: Double) -> String {
        let value = Int(kilometers).formatted(.number.locale(language.uiLocale))
        return switch language {
        case .en: "Weekly volume: \(value) km"
        case .ja: "週間走行距離: \(value) km"
        case .vi: "Khối lượng tuần: \(value) km"
        }
    }

    var checkRace: String {
        switch language {
        case .en: "Check this race"
        case .ja: "このレースを確認"
        case .vi: "Kiểm tra giải đua này"
        }
    }

    var later: String {
        switch language {
        case .en: "Later"
        case .ja: "あとで"
        case .vi: "Để sau"
        }
    }

    var tightDateTitle: String {
        switch language {
        case .en: "This date is tight"
        case .ja: "この日程は厳しめです"
        case .vi: "Thời gian này khá gấp"
        }
    }

    var realisticRaceTitle: String {
        switch language {
        case .en: "This race looks realistic"
        case .ja: "このレースは現実的です"
        case .vi: "Giải đua này có vẻ khả thi"
        }
    }

    var feasibility: String {
        switch language {
        case .en: "Feasibility"
        case .ja: "実現可能性"
        case .vi: "Tính khả thi"
        }
    }

    func feasibilityVerdict(_ verdict: FeasibilityVerdict) -> String {
        switch (language, verdict) {
        case (.en, .ok): "On track"
        case (.en, .stretch): "Stretch"
        case (.en, .unrealistic): "Too soon"
        case (.ja, .ok): "順調"
        case (.ja, .stretch): "挑戦的"
        case (.ja, .unrealistic): "期間が短すぎます"
        case (.vi, .ok): "Đúng tiến độ"
        case (.vi, .stretch): "Thách thức"
        case (.vi, .unrealistic): "Quá sớm"
        }
    }

    func feasibilityHint(_ verdict: FeasibilityVerdict, goal: Int, projected: Int) -> String {
        switch (language, verdict) {
        case (.en, .ok): "Target needs about VDOT \(goal). You project \(projected). The plan keeps hard sessions to two a week."
        case (.en, .stretch): "Target needs about VDOT \(goal). You project \(projected). The plan can try, with more easy volume and fewer quality days."
        case (.en, .unrealistic): "This date is too close for that time. Edit the race or pick a later event."
        case (.ja, .ok): "目標にはVDOT約\(goal)が必要です。現在の予測は\(projected)です。プランでは高強度セッションを週2回までにします。"
        case (.ja, .stretch): "目標にはVDOT約\(goal)が必要です。現在の予測は\(projected)です。イージーの距離を増やし、質の高い日を減らして挑戦できます。"
        case (.ja, .unrealistic): "この日程ではそのタイムに近すぎます。レースを編集するか、より後のイベントを選んでください。"
        case (.vi, .ok): "Mục tiêu cần khoảng VDOT \(goal). Dự báo của bạn là \(projected). Kế hoạch giới hạn buổi nặng ở hai lần mỗi tuần."
        case (.vi, .stretch): "Mục tiêu cần khoảng VDOT \(goal). Dự báo của bạn là \(projected). Kế hoạch vẫn có thể thử với nhiều chạy nhẹ hơn và ít ngày chất lượng hơn."
        case (.vi, .unrealistic): "Ngày này quá gần cho thời gian đó. Hãy sửa giải đua hoặc chọn sự kiện muộn hơn."
        }
    }

    var editRace: String {
        switch language {
        case .en: "Edit race"
        case .ja: "レースを編集"
        case .vi: "Sửa giải đua"
        }
    }

    var createPlan: String {
        switch language {
        case .en: "Create plan"
        case .ja: "プランを作成"
        case .vi: "Tạo kế hoạch"
        }
    }

    var createPlanAnyway: String {
        switch language {
        case .en: "Create plan anyway"
        case .ja: "このままプランを作成"
        case .vi: "Vẫn tạo kế hoạch"
        }
    }

    func raceSummary(distance: String, date: String, targetTime: String, runningDays: Int, longRunDay: String) -> String {
        switch language {
        case .en: "\(distance) on \(date) at \(targetTime). \(runningDays) run days. Long run \(longRunDay)."
        case .ja: "\(date)の\(distance)、目標\(targetTime)。ランニングは週\(runningDays)日。ロング走は\(longRunDay)。"
        case .vi: "\(distance) vào \(date), mục tiêu \(targetTime). \(runningDays) ngày chạy. Chạy dài vào \(longRunDay)."
        }
    }

    var goalSaveError: String {
        switch language {
        case .en: "Could not save goal. Try again."
        case .ja: "目標を保存できませんでした。もう一度お試しください。"
        case .vi: "Không thể lưu mục tiêu. Hãy thử lại."
        }
    }

    var healthDataUnavailableTitle: String {
        switch language {
        case .en: "Health Data Unavailable"
        case .ja: "ヘルスケアデータを利用できません"
        case .vi: "Dữ liệu sức khỏe không khả dụng"
        }
    }

    var healthDataUnavailableDescription: String {
        switch language {
        case .en: "This device does not provide Apple Health data."
        case .ja: "このデバイスではApple Healthデータを利用できません。"
        case .vi: "Thiết bị này không cung cấp dữ liệu Apple Health."
        }
    }

    var appearanceEyebrow: String {
        switch language {
        case .en: "Appearance"
        case .ja: "表示"
        case .vi: "Giao diện"
        }
    }

    var adaptiveThemeTitle: String {
        switch language {
        case .en: "Adaptive theme"
        case .ja: "自動テーマ"
        case .vi: "Giao diện thích ứng"
        }
    }

    var appearanceDescription: String {
        switch language {
        case .en: "Use System follows your device appearance."
        case .ja: "システムに合わせると、デバイスの表示設定に従います。"
        case .vi: "Dùng hệ thống sẽ theo giao diện thiết bị của bạn."
        }
    }

    var appearanceChangeHint: String {
        switch language {
        case .en: "Choose Light or Dark anytime."
        case .ja: "ライトまたはダークはいつでも選べます。"
        case .vi: "Bạn có thể chọn Sáng hoặc Tối bất cứ lúc nào."
        }
    }

    func appearanceTitle(_ appearance: AppAppearance) -> String {
        switch (language, appearance) {
        case (.en, .system): "Use System"
        case (.en, .light): "Light"
        case (.en, .dark): "Dark"
        case (.ja, .system): "システムに合わせる"
        case (.ja, .light): "ライト"
        case (.ja, .dark): "ダーク"
        case (.vi, .system): "Dùng hệ thống"
        case (.vi, .light): "Sáng"
        case (.vi, .dark): "Tối"
        }
    }

    func appearanceSubtitle(_ appearance: AppAppearance) -> String {
        switch (language, appearance) {
        case (.en, .system): "Follows your device appearance."
        case (.en, .light): "Always uses the bright TrainOrRest interface."
        case (.en, .dark): "Always uses the low-glare TrainOrRest interface."
        case (.ja, .system): "デバイスの表示設定に従います。"
        case (.ja, .light): "明るいTrainOrRestの表示を常に使います。"
        case (.ja, .dark): "低照度のTrainOrRest表示を常に使います。"
        case (.vi, .system): "Theo giao diện thiết bị của bạn."
        case (.vi, .light): "Luôn dùng giao diện TrainOrRest sáng."
        case (.vi, .dark): "Luôn dùng giao diện TrainOrRest giảm chói."
        }
    }

    var selected: String {
        switch language {
        case .en: "Selected"
        case .ja: "選択中"
        case .vi: "Đã chọn"
        }
    }
}
