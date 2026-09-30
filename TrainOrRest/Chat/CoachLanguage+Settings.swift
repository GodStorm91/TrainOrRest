import Foundation

extension CoachLanguage {
    var settings: SettingsCopy { SettingsCopy(language: self) }
}

struct SettingsCopy {
    let language: CoachLanguage

    // MARK: - Root settings

    var settingsTitle: String {
        switch language {
        case .en: "Settings"
        case .ja: "設定"
        case .vi: "Cài đặt"
        }
    }

    var accountSection: String {
        switch language {
        case .en: "Account"
        case .ja: "アカウント"
        case .vi: "Tài khoản"
        }
    }

    var personalInformation: String {
        switch language {
        case .en: "Personal information"
        case .ja: "個人情報"
        case .vi: "Thông tin cá nhân"
        }
    }

    var languageTitle: String {
        switch language {
        case .en: "Language"
        case .ja: "言語"
        case .vi: "Ngôn ngữ"
        }
    }

    var appearanceTitle: String {
        switch language {
        case .en: "Appearance"
        case .ja: "外観"
        case .vi: "Giao diện"
        }
    }

    var changeAppearanceAccessibilityLabel: String {
        switch language {
        case .en: "Change appearance"
        case .ja: "外観を変更"
        case .vi: "Thay đổi giao diện"
        }
    }

    var connectedServicesSection: String {
        switch language {
        case .en: "Connected Services"
        case .ja: "連携サービス"
        case .vi: "Dịch vụ đã kết nối"
        }
    }

    var appleHealth: String { "Apple Health" }
    var garmin: String { "Garmin" }
    var googleCalendar: String { "Google Calendar" }
    var intervalsICU: String { "intervals.icu" }

    var connected: String {
        switch language {
        case .en: "Connected"
        case .ja: "接続済み"
        case .vi: "Đã kết nối"
        }
    }

    var notConnected: String {
        switch language {
        case .en: "Not connected"
        case .ja: "未接続"
        case .vi: "Chưa kết nối"
        }
    }

    var viaAppleHealth: String {
        switch language {
        case .en: "via Apple Health"
        case .ja: "Apple Health 経由"
        case .vi: "qua Apple Health"
        }
    }

    var calendarsTitle: String {
        switch language {
        case .en: "Calendars"
        case .ja: "カレンダー"
        case .vi: "Lịch"
        }
    }

    var manageCalendarConnectionsAccessibilityLabel: String {
        switch language {
        case .en: "Manage calendar connections"
        case .ja: "カレンダー連携を管理"
        case .vi: "Quản lý kết nối lịch"
        }
    }

    var manageIntervalsConnectionAccessibilityLabel: String {
        switch language {
        case .en: "Manage intervals.icu connection"
        case .ja: "intervals.icu の接続を管理"
        case .vi: "Quản lý kết nối intervals.icu"
        }
    }

    var watchDeliverySection: String {
        switch language {
        case .en: "Watch Delivery"
        case .ja: "ウォッチへの配信"
        case .vi: "Gửi đến đồng hồ"
        }
    }

    var watchPush: String {
        switch language {
        case .en: "Watch Push"
        case .ja: "ウォッチ送信"
        case .vi: "Gửi đến đồng hồ"
        }
    }

    var coachPersonalizationSection: String {
        switch language {
        case .en: "Coach & Personalization"
        case .ja: "Coach とパーソナライズ"
        case .vi: "Coach & cá nhân hóa"
        }
    }

    var coachMemoryTitle: String {
        switch language {
        case .en: "Coach Memory"
        case .ja: "Coach メモリー"
        case .vi: "Bộ nhớ Coach"
        }
    }

    var coachProviderTitle: String {
        switch language {
        case .en: "Coach provider"
        case .ja: "Coach プロバイダー"
        case .vi: "Nhà cung cấp Coach"
        }
    }

    var modelAndAPI: String {
        switch language {
        case .en: "Model & API"
        case .ja: "モデルと API"
        case .vi: "Mô hình & API"
        }
    }

    var dataPrivacySection: String {
        switch language {
        case .en: "Data & Privacy"
        case .ja: "データとプライバシー"
        case .vi: "Dữ liệu & quyền riêng tư"
        }
    }

    var healthDataPermissions: String {
        switch language {
        case .en: "Health-data permissions"
        case .ja: "ヘルスケアデータの権限"
        case .vi: "Quyền dữ liệu Sức khỏe"
        }
    }

    var iOSSettings: String {
        switch language {
        case .en: "iOS Settings"
        case .ja: "iOS の設定"
        case .vi: "Cài đặt iOS"
        }
    }

    var dataStorage: String {
        switch language {
        case .en: "Data storage"
        case .ja: "データ保存先"
        case .vi: "Lưu trữ dữ liệu"
        }
    }

    var onThisDevice: String {
        switch language {
        case .en: "On this device"
        case .ja: "このデバイス上"
        case .vi: "Trên thiết bị này"
        }
    }

    var supportSection: String {
        switch language {
        case .en: "Support"
        case .ja: "サポート"
        case .vi: "Hỗ trợ"
        }
    }

    var aboutTrainOrRest: String {
        switch language {
        case .en: "About TrainOrRest"
        case .ja: "TrainOrRest について"
        case .vi: "Giới thiệu TrainOrRest"
        }
    }

    var notComplete: String {
        switch language {
        case .en: "Not complete"
        case .ja: "未入力"
        case .vi: "Chưa hoàn tất"
        }
    }

    func weightSummary(_ weight: String) -> String { "\(weight) kg" }

    var on: String {
        switch language {
        case .en: "On"
        case .ja: "オン"
        case .vi: "Bật"
        }
    }

    var off: String {
        switch language {
        case .en: "Off"
        case .ja: "オフ"
        case .vi: "Tắt"
        }
    }

    var googleConnected: String {
        switch language {
        case .en: "Google connected"
        case .ja: "Google に接続済み"
        case .vi: "Đã kết nối Google"
        }
    }

    var syncing: String {
        switch language {
        case .en: "Syncing"
        case .ja: "同期中"
        case .vi: "Đang đồng bộ"
        }
    }

    var needsAttention: String {
        switch language {
        case .en: "Needs attention"
        case .ja: "要確認"
        case .vi: "Cần chú ý"
        }
    }

    var queued: String {
        switch language {
        case .en: "Queued"
        case .ja: "待機中"
        case .vi: "Đang xếp hàng"
        }
    }

    var empty: String {
        switch language {
        case .en: "Empty"
        case .ja: "空"
        case .vi: "Trống"
        }
    }

    func memoryCount(_ count: Int) -> String {
        switch language {
        case .en: count == 1 ? "1 memory" : "\(count) memories"
        case .ja: "\(count)件のメモリー"
        case .vi: "\(count) ghi nhớ"
        }
    }

    func shortDateTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(language.uiLocale))
    }

    // MARK: - Calendars, appearance, and language

    var calendarsFooter: String {
        switch language {
        case .en: "Calendar integrations mirror TrainOrRest workouts outward. TrainOrRest stays the source of truth."
        case .ja: "カレンダー連携では TrainOrRest のワークアウトを外部へ反映します。データの正本は TrainOrRest です。"
        case .vi: "Tích hợp lịch sẽ phản chiếu buổi tập từ TrainOrRest ra ngoài. TrainOrRest vẫn là nguồn dữ liệu chính."
        }
    }

    var appearanceFooter: String {
        switch language {
        case .en: "Use System follows this iPhone. Light and Dark override it immediately without restarting or resetting where you are."
        case .ja: "「システムに合わせる」はこの iPhone の設定に従います。ライトとダークは、再起動や現在位置のリセットなしで直ちに切り替わります。"
        case .vi: "Dùng hệ thống sẽ theo iPhone này. Sáng và Tối áp dụng ngay mà không cần khởi động lại hay mất vị trí hiện tại."
        }
    }

    var languageFooter: String {
        switch language {
        case .en: "Coach chat and suggestions use this language."
        case .ja: "Coach とのチャットと提案にはこの言語を使用します。"
        case .vi: "Chat và gợi ý của Coach sử dụng ngôn ngữ này."
        }
    }

    // MARK: - intervals.icu and watch delivery

    var athleteID: String {
        switch language {
        case .en: "Athlete ID"
        case .ja: "アスリート ID"
        case .vi: "ID vận động viên"
        }
    }

    var apiKey: String {
        switch language {
        case .en: "API key"
        case .ja: "API キー"
        case .vi: "Khóa API"
        }
    }

    var hide: String {
        switch language {
        case .en: "Hide"
        case .ja: "非表示"
        case .vi: "Ẩn"
        }
    }

    var reveal: String {
        switch language {
        case .en: "Reveal"
        case .ja: "表示"
        case .vi: "Hiện"
        }
    }

    var saveConnection: String {
        switch language {
        case .en: "Save connection"
        case .ja: "接続を保存"
        case .vi: "Lưu kết nối"
        }
    }

    var saveIntervalsConnectionAccessibilityLabel: String {
        switch language {
        case .en: "Save intervals.icu connection"
        case .ja: "intervals.icu の接続を保存"
        case .vi: "Lưu kết nối intervals.icu"
        }
    }

    var manageConnection: String {
        switch language {
        case .en: "Manage connection"
        case .ja: "接続を管理"
        case .vi: "Quản lý kết nối"
        }
    }

    var intervalsConnectionFooter: String {
        switch language {
        case .en: "On the web: intervals.icu Settings, Developer Settings. Generate an API key and copy the Athlete ID from that page. Then Settings, Connections, Garmin, Upload planned workouts. Without that tick the watch stays empty."
        case .ja: "ウェブ版 intervals.icu の「設定」>「開発者設定」で API キーを作成し、このページからアスリート ID をコピーします。次に「設定」>「接続」>「Garmin」>「予定ワークアウトをアップロード」を有効にしてください。有効にしないとウォッチには何も届きません。"
        case .vi: "Trên web: vào Cài đặt intervals.icu, Cài đặt nhà phát triển. Tạo khóa API và sao chép ID vận động viên từ đó. Sau đó vào Cài đặt, Kết nối, Garmin, Tải lên buổi tập đã lên kế hoạch. Nếu không bật mục này, đồng hồ sẽ không có buổi tập."
        }
    }

    var watchPushManagedFooter: String {
        switch language {
        case .en: "Watch Push delivery is managed in Watch Delivery."
        case .ja: "ウォッチ送信は「ウォッチへの配信」で管理します。"
        case .vi: "Việc gửi đến đồng hồ được quản lý trong mục Gửi đến đồng hồ."
        }
    }

    var connectIntervals: String {
        switch language {
        case .en: "Connect intervals.icu"
        case .ja: "intervals.icu に接続"
        case .vi: "Kết nối intervals.icu"
        }
    }

    var intervalsSyncDescription: String {
        switch language {
        case .en: "Sync your training plan and deliver workouts to supported devices."
        case .ja: "トレーニングプランを同期し、対応デバイスへワークアウトを配信します。"
        case .vi: "Đồng bộ kế hoạch tập và gửi buổi tập đến các thiết bị được hỗ trợ."
        }
    }

    var syncNow: String {
        switch language {
        case .en: "Sync now"
        case .ja: "今すぐ同期"
        case .vi: "Đồng bộ ngay"
        }
    }

    var lastSyncFailed: String {
        switch language {
        case .en: "Last sync failed"
        case .ja: "前回の同期に失敗しました"
        case .vi: "Lần đồng bộ gần nhất thất bại"
        }
    }

    func lastSync(_ date: Date) -> String {
        let timestamp = shortDateTime(date)
        return switch language {
        case .en: "Last sync \(timestamp)"
        case .ja: "前回の同期: \(timestamp)"
        case .vi: "Đồng bộ gần nhất: \(timestamp)"
        }
    }

    var readyToSync: String {
        switch language {
        case .en: "Ready to sync"
        case .ja: "同期の準備完了"
        case .vi: "Sẵn sàng đồng bộ"
        }
    }

    var connectionSaved: String {
        switch language {
        case .en: "Connection saved"
        case .ja: "接続を保存しました"
        case .vi: "Đã lưu kết nối"
        }
    }

    var credentialsStored: String {
        switch language {
        case .en: "Your intervals.icu credentials are stored on this device."
        case .ja: "intervals.icu の認証情報はこのデバイスに保存されています。"
        case .vi: "Thông tin đăng nhập intervals.icu được lưu trên thiết bị này."
        }
    }

    var deliverPlanPrompt: String {
        switch language {
        case .en: "Tap Sync now to deliver your plan."
        case .ja: "「今すぐ同期」をタップしてプランを配信します。"
        case .vi: "Chạm Đồng bộ ngay để gửi kế hoạch của bạn."
        }
    }

    var enableWatchPushPrompt: String {
        switch language {
        case .en: "Turn on Watch Push in Watch Delivery to send workouts."
        case .ja: "ワークアウトを送信するには「ウォッチへの配信」でウォッチ送信をオンにしてください。"
        case .vi: "Bật Gửi đến đồng hồ trong mục Gửi đến đồng hồ để gửi buổi tập."
        }
    }

    var couldNotSaveKey: String {
        switch language {
        case .en: "Could not save key"
        case .ja: "キーを保存できませんでした"
        case .vi: "Không thể lưu khóa"
        }
    }

    var intervalsKeyWriteFailed: String {
        switch language {
        case .en: "The intervals.icu key could not be written to the keychain."
        case .ja: "intervals.icu のキーをキーチェーンに書き込めませんでした。"
        case .vi: "Không thể ghi khóa intervals.icu vào chuỗi khóa."
        }
    }

    var checkDeviceAccess: String {
        switch language {
        case .en: "Check device access and try again."
        case .ja: "デバイスのアクセス許可を確認して、もう一度お試しください。"
        case .vi: "Kiểm tra quyền truy cập thiết bị rồi thử lại."
        }
    }

    var syncSkipped: String {
        switch language {
        case .en: "Sync skipped"
        case .ja: "同期をスキップしました"
        case .vi: "Đã bỏ qua đồng bộ"
        }
    }

    var couldNotSync: String {
        switch language {
        case .en: "Could not sync"
        case .ja: "同期できませんでした"
        case .vi: "Không thể đồng bộ"
        }
    }

    var checkConnectionAndTryAgain: String {
        switch language {
        case .en: "Check your connection and try again."
        case .ja: "接続を確認して、もう一度お試しください。"
        case .vi: "Kiểm tra kết nối rồi thử lại."
        }
    }

    var syncComplete: String {
        switch language {
        case .en: "Sync complete"
        case .ja: "同期が完了しました"
        case .vi: "Đồng bộ hoàn tất"
        }
    }

    var garminWorkoutsRecreated: String {
        switch language {
        case .en: "Existing Garmin workouts were recreated on your watch."
        case .ja: "既存の Garmin ワークアウトをウォッチ上で再作成しました。"
        case .vi: "Các buổi tập Garmin hiện có đã được tạo lại trên đồng hồ của bạn."
        }
    }

    var watchDeliveryFooter: String {
        switch language {
        case .en: "Watch Push sends planned workouts to your watch through intervals.icu, then Garmin Connect. Manage the intervals.icu connection under Connected Services."
        case .ja: "ウォッチ送信は、予定ワークアウトを intervals.icu 経由で Garmin Connect に送信し、ウォッチへ配信します。intervals.icu の接続は「連携サービス」で管理できます。"
        case .vi: "Gửi đến đồng hồ chuyển các buổi tập đã lên kế hoạch qua intervals.icu, rồi đến Garmin Connect. Quản lý kết nối intervals.icu trong Dịch vụ đã kết nối."
        }
    }

    var garminDeliveryDebug: String {
        switch language {
        case .en: "Garmin delivery debug"
        case .ja: "Garmin 配信デバッグ"
        case .vi: "Gỡ lỗi gửi Garmin"
        }
    }

    var garminDeliveryDebugFooter: String {
        switch language {
        case .en: "This is the exact intervals.icu push path. If the DSL contains pace but Garmin shows distance only, the failure is in the intervals.icu to Garmin export."
        case .ja: "これは intervals.icu の正確な送信経路です。DSL にペースがあるのに Garmin で距離のみ表示される場合、問題は intervals.icu から Garmin へのエクスポートにあります。"
        case .vi: "Đây là đường gửi chính xác của intervals.icu. Nếu DSL có pace nhưng Garmin chỉ hiện quãng đường, lỗi nằm ở bước xuất từ intervals.icu sang Garmin."
        }
    }

    var intervalsNotConnected: String {
        switch language {
        case .en: "intervals.icu not connected"
        case .ja: "intervals.icu は未接続です"
        case .vi: "intervals.icu chưa kết nối"
        }
    }

    var connectIntervalsToDeliver: String {
        switch language {
        case .en: "Connect intervals.icu to deliver planned workouts to your watch."
        case .ja: "予定ワークアウトをウォッチへ配信するには intervals.icu に接続してください。"
        case .vi: "Kết nối intervals.icu để gửi buổi tập đã lên kế hoạch đến đồng hồ."
        }
    }

    var watchPushIsOff: String {
        switch language {
        case .en: "Watch Push is off"
        case .ja: "ウォッチ送信はオフです"
        case .vi: "Gửi đến đồng hồ đang tắt"
        }
    }

    var turnOnWatchPush: String {
        switch language {
        case .en: "Turn on Watch Push to send planned workouts to your watch."
        case .ja: "予定ワークアウトをウォッチに送信するにはウォッチ送信をオンにしてください。"
        case .vi: "Bật Gửi đến đồng hồ để gửi buổi tập đã lên kế hoạch đến đồng hồ."
        }
    }

    var lastDeliveryFailed: String {
        switch language {
        case .en: "Last delivery failed"
        case .ja: "前回の配信に失敗しました"
        case .vi: "Lần gửi gần nhất thất bại"
        }
    }

    var retrySyncPrompt: String {
        switch language {
        case .en: "Tap Sync now to retry."
        case .ja: "再試行するには「今すぐ同期」をタップしてください。"
        case .vi: "Chạm Đồng bộ ngay để thử lại."
        }
    }

    var deliveryPaused: String {
        switch language {
        case .en: "Delivery paused"
        case .ja: "配信を一時停止しました"
        case .vi: "Đã tạm dừng gửi"
        }
    }

    var workoutsDelivered: String {
        switch language {
        case .en: "Workouts delivered"
        case .ja: "ワークアウトを配信しました"
        case .vi: "Đã gửi buổi tập"
        }
    }

    func lastSyncSentence(_ date: Date) -> String {
        switch language {
        case .en: "\(lastSync(date))."
        case .ja: "\(lastSync(date))。"
        case .vi: "\(lastSync(date))."
        }
    }

    var readyToDeliver: String {
        switch language {
        case .en: "Ready to deliver"
        case .ja: "配信の準備完了"
        case .vi: "Sẵn sàng gửi"
        }
    }

    var sendPlanToWatch: String {
        switch language {
        case .en: "Tap Sync now to send your plan to your watch."
        case .ja: "「今すぐ同期」をタップしてプランをウォッチに送信します。"
        case .vi: "Chạm Đồng bộ ngay để gửi kế hoạch đến đồng hồ."
        }
    }

    // MARK: - Coach provider

    var testingConnection: String {
        switch language {
        case .en: "Testing connection…"
        case .ja: "接続をテスト中…"
        case .vi: "Đang kiểm tra kết nối…"
        }
    }

    var coachConnected: String {
        switch language {
        case .en: "Coach connected"
        case .ja: "Coach に接続済み"
        case .vi: "Đã kết nối Coach"
        }
    }

    func modelReady(_ model: String) -> String {
        switch language {
        case .en: "\(model) is ready."
        case .ja: "\(model) の準備ができました。"
        case .vi: "\(model) đã sẵn sàng."
        }
    }

    var connectionFailed: String {
        switch language {
        case .en: "Connection failed"
        case .ja: "接続に失敗しました"
        case .vi: "Kết nối thất bại"
        }
    }

    var checkKeyAndConnectAgain: String {
        switch language {
        case .en: "Check the key and connect again."
        case .ja: "キーを確認して、もう一度接続してください。"
        case .vi: "Kiểm tra khóa rồi kết nối lại."
        }
    }

    func modelSelected(_ model: String) -> String {
        switch language {
        case .en: "\(model) is selected. Connect to confirm it works."
        case .ja: "\(model) が選択されています。接続して動作を確認してください。"
        case .vi: "Đã chọn \(model). Hãy kết nối để xác nhận hoạt động."
        }
    }

    var connectCoachTitle: String {
        switch language {
        case .en: "Connect your coach"
        case .ja: "Coach に接続"
        case .vi: "Kết nối Coach"
        }
    }

    var connectCoachPrompt: String {
        switch language {
        case .en: "Use your ChatGPT plan, sign in with Grok, or add a Claude key."
        case .ja: "ChatGPT プラン、Grok、または Claude のキーを使えます。"
        case .vi: "Dùng gói ChatGPT, đăng nhập Grok, hoặc thêm khóa Claude."
        }
    }

    func usingChatGPTPlan(email: String?, model: String?) -> String {
        let lead: String
        switch language {
        case .en: lead = "Using your ChatGPT plan"
        case .ja: lead = "ChatGPT プランを使用中"
        case .vi: lead = "Đang dùng gói ChatGPT của bạn"
        }
        return ([lead] + [email, model].compactMap { $0?.isEmpty == false ? $0 : nil }).joined(separator: " · ")
    }
    func usingGrok(email: String?, model: String?) -> String {
        let lead: String
        switch language {
        case .en: lead = "Using Grok"
        case .ja: lead = "Grok を使用中"
        case .vi: lead = "Đang dùng Grok"
        }
        return ([lead] + [email, model].compactMap { $0?.isEmpty == false ? $0 : nil }).joined(separator: " · ")
    }

    var chatGPTPlanUseOffTitle: String {
        switch language {
        case .en: "ChatGPT plan use is off"
        case .ja: "ChatGPT プランの利用がオフです"
        case .vi: "Chưa bật dùng gói ChatGPT"
        }
    }

    var chatGPTPlanUseOffMessage: String {
        switch language {
        case .en: "TrainOrRest needs permission to use your plan."
        case .ja: "TrainOrRest がプランを使うには許可が必要です。"
        case .vi: "TrainOrRest cần được cho phép dùng gói của bạn."
        }
    }

    var allowPlanUse: String {
        switch language {
        case .en: "Allow plan use"
        case .ja: "プランの利用を許可"
        case .vi: "Cho phép dùng gói"
        }
    }

    var chatGPTLimitTitle: String {
        switch language {
        case .en: "ChatGPT usage limit reached"
        case .ja: "ChatGPT の利用上限に達しました"
        case .vi: "Đã chạm giới hạn dùng ChatGPT"
        }
    }

    var chatGPTLimitMessage: String {
        switch language {
        case .en: "The limit may be on your ChatGPT plan or on TrainOrRest's own limit. Check usage, or use a Claude key."
        case .ja: "上限はプラン全体、または TrainOrRest 個別の場合があります。利用状況を確認するか、Claude のキーを使ってください。"
        case .vi: "Giới hạn có thể thuộc gói ChatGPT của bạn hoặc riêng TrainOrRest. Kiểm tra mức dùng hoặc dùng khóa Claude."
        }
    }

    var manageUsage: String {
        switch language {
        case .en: "Manage usage"
        case .ja: "利用状況を管理"
        case .vi: "Quản lý mức dùng"
        }
    }

    var chatGPTDiagnosticsHeader: String {
        switch language {
        case .en: "ChatGPT diagnostics"
        case .ja: "ChatGPT 診断"
        case .vi: "Chẩn đoán ChatGPT"
        }
    }

    var runChatGPTDiagnostics: String {
        switch language {
        case .en: "Run ChatGPT check"
        case .ja: "ChatGPT をチェック"
        case .vi: "Kiểm tra ChatGPT"
        }
    }

    var copyDiagnosticsReport: String {
        switch language {
        case .en: "Copy report"
        case .ja: "レポートをコピー"
        case .vi: "Sao chép báo cáo"
        }
    }

    var clearDiagnosticsLog: String {
        switch language {
        case .en: "Clear log"
        case .ja: "ログを消去"
        case .vi: "Xóa nhật ký"
        }
    }

    var chatGPTDiagnosticsFooter: String {
        switch language {
        case .en: "TestFlight only. Lists recent ChatGPT request statuses, error codes, and request IDs. No sign-in tokens, messages, or health data. The check sends a few tiny requests."
        case .ja: "TestFlight 版のみ。最近の ChatGPT リクエストの状態、エラーコード、リクエスト ID を表示します。サインイントークン、メッセージ、ヘルスデータは含みません。チェックでは小さなリクエストをいくつか送信します。"
        case .vi: "Chỉ có trong bản TestFlight. Liệt kê trạng thái, mã lỗi và request ID của các yêu cầu ChatGPT gần đây. Không chứa token đăng nhập, tin nhắn hay dữ liệu sức khỏe. Lần kiểm tra sẽ gửi vài yêu cầu rất nhỏ."
        }
    }

    var tryAgain: String {
        switch language {
        case .en: "Try again"
        case .ja: "もう一度試す"
        case .vi: "Thử lại"
        }
    }

    var chatGPTNotEligibleTitle: String {
        switch language {
        case .en: "ChatGPT plan not available"
        case .ja: "ChatGPT プランを利用できません"
        case .vi: "Không dùng được gói ChatGPT"
        }
    }

    var chatGPTNotEligibleMessage: String {
        switch language {
        case .en: "Plan use needs ChatGPT Plus or Pro. Add a Claude or OpenAI key instead."
        case .ja: "プランの利用には ChatGPT Plus または Pro が必要です。代わりに Claude か OpenAI のキーを追加してください。"
        case .vi: "Cần ChatGPT Plus hoặc Pro để dùng gói. Hãy thêm khóa Claude hoặc OpenAI."
        }
    }

    var reconnectChatGPTTitle: String {
        switch language {
        case .en: "Reconnect ChatGPT"
        case .ja: "ChatGPT に再接続"
        case .vi: "Kết nối lại ChatGPT"
        }
    }

    var reconnectChatGPTMessage: String {
        switch language {
        case .en: "Your ChatGPT session ended. Your chats are safe."
        case .ja: "ChatGPT のセッションが終了しました。チャットは安全です。"
        case .vi: "Phiên ChatGPT đã kết thúc. Các cuộc chat của bạn vẫn an toàn."
        }
    }

    var reconnect: String {
        switch language {
        case .en: "Reconnect"
        case .ja: "再接続"
        case .vi: "Kết nối lại"
        }
    }

    var continueWithChatGPT: String {
        switch language {
        case .en: "Continue with ChatGPT"
        case .ja: "ChatGPT で続ける"
        case .vi: "Tiếp tục với ChatGPT"
        }
    }
    var signInWithGrok: String {
        switch language {
        case .en: "Sign in with Grok"
        case .ja: "Grok でサインイン"
        case .vi: "Đăng nhập bằng Grok"
        }
    }

    var grokHeader: String {
        switch language {
        case .en: "Use Grok"
        case .ja: "Grok を使う"
        case .vi: "Dùng Grok"
        }
    }

    var grokPrivacyFooter: String {
        switch language {
        case .en: "Signs in with the same device code as omp's Grok login. Tokens stay in this iPhone's Keychain. Health context goes from this iPhone directly to xAI."
        case .ja: "omp の Grok ログインと同じデバイスコードでサインインします。トークンはこの iPhone のキーチェーンに保存されます。健康データはこの iPhone から xAI に直接送られます。"
        case .vi: "Đăng nhập bằng mã thiết bị giống đăng nhập Grok của omp. Token nằm trong Keychain của iPhone này. Dữ liệu sức khỏe đi thẳng từ iPhone này đến xAI."
        }
    }

    var grokEnterCode: String {
        switch language {
        case .en: "Enter this code at xAI, then return here."
        case .ja: "このコードを xAI で入力して、ここに戻ってください。"
        case .vi: "Nhập mã này trên xAI, rồi quay lại đây."
        }
    }

    var copyCode: String {
        switch language {
        case .en: "Copy code"
        case .ja: "コードをコピー"
        case .vi: "Sao chép mã"
        }
    }

    var openGrokVerification: String {
        switch language {
        case .en: "Open xAI sign-in"
        case .ja: "xAI のサインインを開く"
        case .vi: "Mở trang đăng nhập xAI"
        }
    }

    var cancelGrokSignIn: String {
        switch language {
        case .en: "Cancel sign-in"
        case .ja: "サインインを中止"
        case .vi: "Hủy đăng nhập"
        }
    }

    var disconnectGrok: String {
        switch language {
        case .en: "Disconnect Grok"
        case .ja: "Grok の接続を解除"
        case .vi: "Ngắt kết nối Grok"
        }
    }

    var grokSignInFailed: String {
        switch language {
        case .en: "Grok sign-in failed"
        case .ja: "Grok にサインインできませんでした"
        case .vi: "Đăng nhập Grok thất bại"
        }
    }

    var reconnectGrokTitle: String {
        switch language {
        case .en: "Reconnect Grok"
        case .ja: "Grok に再接続"
        case .vi: "Kết nối lại Grok"
        }
    }

    var reconnectGrokMessage: String {
        switch language {
        case .en: "Your Grok session ended. Your chats are safe."
        case .ja: "Grok のセッションが終了しました。チャットは安全です。"
        case .vi: "Phiên Grok đã kết thúc. Các cuộc chat của bạn vẫn an toàn."
        }
    }

    var useChatGPTPlanHeader: String {
        switch language {
        case .en: "Use your ChatGPT plan"
        case .ja: "ChatGPT プランを使う"
        case .vi: "Dùng gói ChatGPT của bạn"
        }
    }

    var chatGPTPrivacyFooter: String {
        switch language {
        case .en: "Uses your ChatGPT Plus or Pro plan, separate from any TrainOrRest charges. Health context goes from this iPhone directly to OpenAI."
        case .ja: "ChatGPT Plus または Pro プランを使います（TrainOrRest の料金とは別です）。健康データはこの iPhone から OpenAI に直接送られます。"
        case .vi: "Dùng gói ChatGPT Plus hoặc Pro của bạn, tách biệt với mọi khoản phí của TrainOrRest. Dữ liệu sức khỏe đi thẳng từ iPhone này đến OpenAI."
        }
    }

    var disconnectChatGPT: String {
        switch language {
        case .en: "Disconnect ChatGPT"
        case .ja: "ChatGPT の接続を解除"
        case .vi: "Ngắt kết nối ChatGPT"
        }
    }

    var chatGPTSignInFailed: String {
        switch language {
        case .en: "ChatGPT sign-in failed"
        case .ja: "ChatGPT にサインインできませんでした"
        case .vi: "Đăng nhập ChatGPT thất bại"
        }
    }

    var chatGPTPlanNoticeTitle: String {
        switch language {
        case .en: "You're using your ChatGPT plan"
        case .ja: "ChatGPT プランを使用しています"
        case .vi: "Bạn đang dùng gói ChatGPT"
        }
    }

    var chatGPTPlanNoticeBody: String {
        switch language {
        case .en: "Coach replies in TrainOrRest use your ChatGPT plan's limits. On Plus, those limits are shared with your other ChatGPT use. You can manage usage in ChatGPT settings."
        case .ja: "TrainOrRest の Coach の返信は ChatGPT プランの上限を使います。Plus では、ほかの ChatGPT の利用と上限を共有します。利用状況は ChatGPT の設定で管理できます。"
        case .vi: "Câu trả lời của Coach trong TrainOrRest dùng giới hạn của gói ChatGPT. Với Plus, giới hạn này được chia sẻ với các lần dùng ChatGPT khác. Bạn có thể quản lý mức dùng trong cài đặt ChatGPT."
        }
    }

    var gotIt: String {
        switch language {
        case .en: "Got it"
        case .ja: "OK"
        case .vi: "Đã hiểu"
        }
    }

    var otherCoachOptions: String {
        switch language {
        case .en: "Other options"
        case .ja: "ほかの方法"
        case .vi: "Tùy chọn khác"
        }
    }

    var coachConnectionPicker: String {
        switch language {
        case .en: "Coach uses"
        case .ja: "使用する Coach"
        case .vi: "Coach dùng"
        }
    }

    var openAIKeyConnection: String {
        switch language {
        case .en: "OpenAI key"
        case .ja: "OpenAI キー"
        case .vi: "Khóa OpenAI"
        }
    }

    var claudeModel: String {
        switch language {
        case .en: "Claude model"
        case .ja: "Claude のモデル"
        case .vi: "Mô hình Claude"
        }
    }

    var openAIModel: String {
        switch language {
        case .en: "OpenAI model"
        case .ja: "OpenAI のモデル"
        case .vi: "Mô hình OpenAI"
        }
    }

    // MARK: - Claude key onboarding

    var useClaudeKeyHeader: String {
        switch language {
        case .en: "Use a Claude API key"
        case .ja: "Claude API キーを使う"
        case .vi: "Dùng khóa API Claude"
        }
    }

    var getClaudeKey: String {
        switch language {
        case .en: "Get a key"
        case .ja: "キーを取得"
        case .vi: "Lấy khóa"
        }
    }

    var getClaudeKeySteps: String {
        switch language {
        case .en: "Sign in, tap Create Key, copy it, and come back."
        case .ja: "サインインして Create Key をタップし、キーをコピーして戻ってきてください。"
        case .vi: "Đăng nhập, chạm Create Key, sao chép khóa rồi quay lại."
        }
    }

    var pasteKey: String {
        switch language {
        case .en: "Paste key"
        case .ja: "キーを貼り付け"
        case .vi: "Dán khóa"
        }
    }

    var notAClaudeKey: String {
        switch language {
        case .en: "That doesn't look like a Claude key (it should start with sk-ant-)."
        case .ja: "Claude のキーではないようです（sk-ant- で始まります）。"
        case .vi: "Đây không giống khóa Claude (khóa bắt đầu bằng sk-ant-)."
        }
    }

    var claudeKeyRejected: String {
        switch language {
        case .en: "Claude rejected this key. Create a new one."
        case .ja: "Claude がこのキーを拒否しました。新しいキーを作成してください。"
        case .vi: "Claude đã từ chối khóa này. Hãy tạo khóa mới."
        }
    }

    var claudeNeedsCredits: String {
        switch language {
        case .en: "Add credits to your Claude account first."
        case .ja: "先に Claude アカウントにクレジットを追加してください。"
        case .vi: "Hãy nạp credit vào tài khoản Claude trước."
        }
    }

    var addCredits: String {
        switch language {
        case .en: "Add credits"
        case .ja: "クレジットを追加"
        case .vi: "Nạp credit"
        }
    }

    var claudeBillingFooter: String {
        switch language {
        case .en: "Claude keys are billed per use by Anthropic. Prepaid credits are required. Your key stays in this device's keychain."
        case .ja: "Claude のキーは Anthropic によって従量課金されます。前払いのクレジットが必要です。キーはこのデバイスのキーチェーンに保管されます。"
        case .vi: "Khóa Claude được Anthropic tính phí theo mức dùng. Cần nạp credit trả trước. Khóa của bạn được giữ trong chuỗi khóa của thiết bị này."
        }
    }

    var coachRateLimited: String {
        switch language {
        case .en: "Too many requests right now. Wait a moment, then connect again."
        case .ja: "現在リクエストが多すぎます。少し待ってから再接続してください。"
        case .vi: "Hiện có quá nhiều yêu cầu. Chờ một chút rồi kết nối lại."
        }
    }

    var coachOffline: String {
        switch language {
        case .en: "You're offline. Connect to the internet, then try again."
        case .ja: "オフラインです。インターネットに接続してから、もう一度お試しください。"
        case .vi: "Bạn đang ngoại tuyến. Hãy kết nối internet rồi thử lại."
        }
    }

    var anthropicAPIKey: String {
        switch language {
        case .en: "Anthropic API key"
        case .ja: "Anthropic API キー"
        case .vi: "Khóa API Anthropic"
        }
    }

    var connectCoach: String {
        switch language {
        case .en: "Connect coach"
        case .ja: "Coach に接続"
        case .vi: "Kết nối Coach"
        }
    }

    var advancedOpenAIFooter: String {
        switch language {
        case .en: "Use your own OpenAI API key, billed per use by OpenAI, or pick a specific model. Most runners never need this."
        case .ja: "自分の OpenAI API キー（OpenAI による従量課金）を使うか、特定のモデルを選びます。ほとんどのランナーには不要です。"
        case .vi: "Dùng khóa API OpenAI của riêng bạn (OpenAI tính phí theo mức dùng) hoặc chọn mô hình cụ thể. Hầu hết người chạy không cần mục này."
        }
    }

    var advancedProviderSetup: String {
        switch language {
        case .en: "Advanced provider setup"
        case .ja: "詳細なプロバイダー設定"
        case .vi: "Thiết lập nhà cung cấp nâng cao"
        }
    }

    var model: String {
        switch language {
        case .en: "Model"
        case .ja: "モデル"
        case .vi: "Mô hình"
        }
    }

    var claude: String { "Claude" }
    var openAI: String { "OpenAI" }

    var openAIAPIKey: String {
        switch language {
        case .en: "OpenAI API key"
        case .ja: "OpenAI API キー"
        case .vi: "Khóa API OpenAI"
        }
    }

    var saveOpenAIAndTest: String {
        switch language {
        case .en: "Save OpenAI and test"
        case .ja: "OpenAI を保存してテスト"
        case .vi: "Lưu OpenAI và kiểm tra"
        }
    }

    var coachProviderNavigationTitle: String {
        switch language {
        case .en: "Coach Provider"
        case .ja: "Coach プロバイダー"
        case .vi: "Nhà cung cấp Coach"
        }
    }

    var couldNotSaveOpenAIAPIKey: String {
        switch language {
        case .en: "Could not save OpenAI API key."
        case .ja: "OpenAI API キーを保存できませんでした。"
        case .vi: "Không thể lưu khóa API OpenAI."
        }
    }

    var couldNotSaveAnthropicAPIKey: String {
        switch language {
        case .en: "Could not save Anthropic API key."
        case .ja: "Anthropic API キーを保存できませんでした。"
        case .vi: "Không thể lưu khóa API Anthropic."
        }
    }

    func modelLabel(_ id: String) -> String {
        switch id {
        case CoachChatConfig.defaultOpenAIModel:
            switch language {
            case .en: "Budget coach (GPT-5 Nano)"
            case .ja: "低コスト Coach（GPT-5 Nano）"
            case .vi: "Coach tiết kiệm (GPT-5 Nano)"
            }
        case "gpt-4o-mini":
            switch language {
            case .en: "Cheap balanced coach (GPT-4o mini)"
            case .ja: "低コストでバランスのよい Coach（GPT-4o mini）"
            case .vi: "Coach cân bằng, chi phí thấp (GPT-4o mini)"
            }
        case "gpt-4.1-mini":
            switch language {
            case .en: "Better OpenAI coach (GPT-4.1 mini)"
            case .ja: "高性能な OpenAI Coach（GPT-4.1 mini）"
            case .vi: "Coach OpenAI tốt hơn (GPT-4.1 mini)"
            }
        case CoachChatConfig.defaultModel:
            switch language {
            case .en: "Balanced Claude coach"
            case .ja: "バランス型 Claude Coach"
            case .vi: "Coach Claude cân bằng"
            }
        case "claude-haiku-4-5":
            switch language {
            case .en: "Fast Claude coach"
            case .ja: "高速 Claude Coach"
            case .vi: "Coach Claude nhanh"
            }
        case "claude-opus-4-8":
            switch language {
            case .en: "Deep Claude review"
            case .ja: "詳細な Claude レビュー"
            case .vi: "Đánh giá sâu của Claude"
            }
        default:
            id
        }
    }

    // MARK: - Coach memory

    var rememberedAthleteContextTitle: String {
        switch language {
        case .en: "Remembered athlete context"
        case .ja: "記憶したアスリート情報"
        case .vi: "Thông tin vận động viên đã ghi nhớ"
        }
    }

    var coachMemoryIntro: String {
        switch language {
        case .en: "TrainOrRest remembers useful facts from your chats. You can also add, edit, or remove memories manually."
        case .ja: "TrainOrRest はチャットから役立つ情報を記憶します。手動で追加、編集、削除もできます。"
        case .vi: "TrainOrRest ghi nhớ các thông tin hữu ích từ cuộc trò chuyện. Bạn cũng có thể tự thêm, sửa hoặc xóa ghi nhớ."
        }
    }

    var coachMemoryFooter: String {
        switch language {
        case .en: "Coach uses these facts to personalize future advice. You can edit or remove any item."
        case .ja: "Coach はこれらの情報を使って今後の助言を調整します。各項目は編集または削除できます。"
        case .vi: "Coach dùng các thông tin này để cá nhân hóa lời khuyên sau này. Bạn có thể sửa hoặc xóa từng mục."
        }
    }

    var addMemoryTitle: String {
        switch language {
        case .en: "Add memory"
        case .ja: "メモリーを追加"
        case .vi: "Thêm ghi nhớ"
        }
    }

    var editMemoryTitle: String {
        switch language {
        case .en: "Edit Memory"
        case .ja: "メモリーを編集"
        case .vi: "Chỉnh sửa ghi nhớ"
        }
    }

    var clearAllCoachMemoryTitle: String {
        switch language {
        case .en: "Clear all coach memory"
        case .ja: "すべての Coach メモリーを消去"
        case .vi: "Xóa toàn bộ bộ nhớ Coach"
        }
    }

    var suggestedExamplesTitle: String {
        switch language {
        case .en: "Suggested examples"
        case .ja: "例"
        case .vi: "Gợi ý"
        }
    }

    var noCoachMemoriesTitle: String {
        switch language {
        case .en: "No Coach memories yet"
        case .ja: "Coach のメモリーはまだありません"
        case .vi: "Coach chưa ghi nhớ thông tin nào"
        }
    }

    var noCoachMemoriesMessage: String {
        switch language {
        case .en: "Add useful facts such as your training schedule, injuries, preferences, or race goals. Memory is optional and under your control."
        case .ja: "練習スケジュール、怪我、好み、レース目標など、役立つ安定情報を追加できます。メモリーは任意で、いつでも管理できます。"
        case .vi: "Thêm thông tin hữu ích như lịch tập, chấn thương, sở thích hoặc mục tiêu race. Bộ nhớ là tùy chọn và bạn kiểm soát được."
        }
    }

    var memoryEditorIntro: String {
        switch language {
        case .en: "Add a stable fact about your training, body, preferences, schedule, or constraints."
        case .ja: "練習、身体、好み、予定、制約に関する安定した情報を追加します。"
        case .vi: "Thêm một thông tin ổn định về tập luyện, cơ thể, sở thích, lịch trình hoặc ràng buộc của bạn."
        }
    }

    var memoryEditorPlaceholder: String {
        switch language {
        case .en: "Write something Coach should remember..."
        case .ja: "Coach に覚えてほしいことを書く..."
        case .vi: "Viết điều Coach nên ghi nhớ..."
        }
    }

    var coachMemorySuggestedExamples: [String] {
        switch language {
        case .en:
            [
                "I can train 8-10 hours per week.",
                "I prefer running in the morning.",
                "My shin hurts when mileage increases quickly.",
                "I am training for a marathon on Oct 25, 2026.",
                "I travel frequently on weekends."
            ]
        case .ja:
            [
                "週に8-10時間トレーニングできます。",
                "朝に走るのが好きです。",
                "走行距離を急に増やすとすねが痛みます。",
                "2026年10月25日のマラソンに向けて練習しています。",
                "週末に移動が多いです。"
            ]
        case .vi:
            [
                "Tôi có thể tập 8-10 giờ mỗi tuần.",
                "Tôi thích chạy vào buổi sáng.",
                "Ống chân của tôi đau khi tăng số km quá nhanh.",
                "Tôi đang tập cho marathon ngày 25/10/2026.",
                "Tôi thường xuyên đi xa vào cuối tuần."
            ]
        }
    }

    var deleteMemoryConfirmationTitle: String {
        switch language {
        case .en: "Delete this memory?"
        case .ja: "このメモリーを削除しますか？"
        case .vi: "Xóa ghi nhớ này?"
        }
    }

    var deleteMemoryConfirmationMessage: String {
        switch language {
        case .en: "Coach will no longer use this fact in future advice."
        case .ja: "Coach は今後の助言でこの情報を使わなくなります。"
        case .vi: "Coach sẽ không dùng thông tin này cho lời khuyên sau này nữa."
        }
    }

    var clearAllConfirmationTitle: String {
        switch language {
        case .en: "Clear all Coach Memory?"
        case .ja: "すべての Coach メモリーを消去しますか？"
        case .vi: "Xóa toàn bộ bộ nhớ Coach?"
        }
    }

    var clearAllConfirmationMessage: String {
        switch language {
        case .en: "Coach will forget all manually added and chat-learned athlete context. This cannot be undone."
        case .ja: "手動追加およびチャットから学習したアスリート情報をすべて忘れます。元に戻せません。"
        case .vi: "Coach sẽ quên toàn bộ thông tin vận động viên do bạn thêm và học từ chat. Không thể hoàn tác."
        }
    }

    var clearAllConfirmationAction: String {
        switch language {
        case .en: "Clear all"
        case .ja: "すべて消去"
        case .vi: "Xóa tất cả"
        }
    }

    var discardChangesTitle: String {
        switch language {
        case .en: "Discard changes?"
        case .ja: "変更を破棄しますか？"
        case .vi: "Bỏ thay đổi?"
        }
    }

    var keepEditingTitle: String {
        switch language {
        case .en: "Keep editing"
        case .ja: "編集を続ける"
        case .vi: "Sửa tiếp"
        }
    }

    var discardTitle: String {
        switch language {
        case .en: "Discard"
        case .ja: "破棄"
        case .vi: "Bỏ"
        }
    }

    var replaceMemoryDraftTitle: String {
        switch language {
        case .en: "Replace current text?"
        case .ja: "現在の文章を置き換えますか？"
        case .vi: "Thay nội dung đang nhập?"
        }
    }

    var replaceMemoryDraftMessage: String {
        switch language {
        case .en: "This example will replace the text already in the editor."
        case .ja: "この例はエディタ内の文章を置き換えます。"
        case .vi: "Gợi ý này sẽ thay phần đang nhập trong ô soạn."
        }
    }

    var replaceTitle: String {
        switch language {
        case .en: "Replace"
        case .ja: "置き換え"
        case .vi: "Thay"
        }
    }

    var learnedFromChatLabel: String {
        switch language {
        case .en: "Learned from chat"
        case .ja: "チャットから学習"
        case .vi: "Học từ chat"
        }
    }

    var saveMemoryErrorTitle: String {
        switch language {
        case .en: "Could not save this memory"
        case .ja: "このメモリーを保存できませんでした"
        case .vi: "Không thể lưu ghi nhớ này"
        }
    }

    var memoryTextNotLostMessage: String {
        switch language {
        case .en: "Your text has not been lost."
        case .ja: "入力した文章は失われていません。"
        case .vi: "Nội dung bạn nhập chưa bị mất."
        }
    }

    var deleteMemoryErrorMessage: String {
        switch language {
        case .en: "Could not delete this memory. The memory is still available."
        case .ja: "このメモリーを削除できませんでした。メモリーはまだ残っています。"
        case .vi: "Không thể xóa ghi nhớ này. Ghi nhớ vẫn còn."
        }
    }

    var loadMemoryErrorTitle: String {
        switch language {
        case .en: "Could not load Coach Memory"
        case .ja: "Coach メモリーを読み込めませんでした"
        case .vi: "Không thể tải bộ nhớ Coach"
        }
    }

    var tryAgainTitle: String {
        switch language {
        case .en: "Try again"
        case .ja: "再試行"
        case .vi: "Thử lại"
        }
    }

    var addCoachMemoryAccessibilityLabel: String {
        switch language {
        case .en: "Add Coach memory"
        case .ja: "Coach メモリーを追加"
        case .vi: "Thêm ghi nhớ Coach"
        }
    }

    var moreActionsForMemoryAccessibilityLabel: String {
        switch language {
        case .en: "More actions for memory"
        case .ja: "メモリーのその他の操作"
        case .vi: "Thêm thao tác cho ghi nhớ"
        }
    }

    var clearAllCoachMemoryAccessibilityLabel: String {
        switch language {
        case .en: "Clear all Coach Memory"
        case .ja: "すべての Coach メモリーを消去"
        case .vi: "Xóa toàn bộ bộ nhớ Coach"
        }
    }

    var saveMemoryAccessibilityLabel: String {
        switch language {
        case .en: "Save memory"
        case .ja: "メモリーを保存"
        case .vi: "Lưu ghi nhớ"
        }
    }

    var memoryTextFieldAccessibilityLabel: String {
        switch language {
        case .en: "Memory text field"
        case .ja: "メモリー入力欄"
        case .vi: "Ô nhập nội dung ghi nhớ"
        }
    }

    func memoryDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(language.uiLocale))
    }

    func memoryCardAccessibilityLabel(text: String, dateText: String) -> String {
        switch language {
        case .en: "\(text), \(dateText)"
        case .ja: "\(text)、\(dateText)"
        case .vi: "\(text), \(dateText)"
        }
    }

    // MARK: - Profile

    var profileTitle: String {
        switch language {
        case .en: "Profile"
        case .ja: "プロフィール"
        case .vi: "Hồ sơ"
        }
    }

    var openSettingsAccessibilityLabel: String {
        switch language {
        case .en: "Open Settings"
        case .ja: "設定を開く"
        case .vi: "Mở cài đặt"
        }
    }

    var athleteEyebrow: String {
        switch language {
        case .en: "ATHLETE"
        case .ja: "アスリート"
        case .vi: "VẬN ĐỘNG VIÊN"
        }
    }

    var completeAthleteProfile: String {
        switch language {
        case .en: "Complete athlete profile"
        case .ja: "アスリートプロフィールを完成"
        case .vi: "Hoàn tất hồ sơ vận động viên"
        }
    }

    var editAthleteProfile: String {
        switch language {
        case .en: "Edit athlete profile"
        case .ja: "アスリートプロフィールを編集"
        case .vi: "Chỉnh sửa hồ sơ vận động viên"
        }
    }

    var openActivePlanDetailsAccessibilityLabel: String {
        switch language {
        case .en: "Open active training plan details"
        case .ja: "進行中のトレーニングプランの詳細を開く"
        case .vi: "Mở chi tiết kế hoạch tập hiện tại"
        }
    }

    var setRaceEnteredAccessibilityLabel: String {
        switch language {
        case .en: "Set the race you entered"
        case .ja: "参加するレースを設定"
        case .vi: "Đặt race bạn đã đăng ký"
        }
    }

    func weekProgress(current: Int, total: Int) -> String {
        switch language {
        case .en: "Week \(current) of \(total)"
        case .ja: "全\(total)週中 \(current)週目"
        case .vi: "Tuần \(current) / \(total)"
        }
    }

    var timeline: String {
        switch language {
        case .en: "Timeline"
        case .ja: "進行状況"
        case .vi: "Tiến độ"
        }
    }

    var currentPhase: String {
        switch language {
        case .en: "Current phase"
        case .ja: "現在のフェーズ"
        case .vi: "Giai đoạn hiện tại"
        }
    }

    var thisWeek: String {
        switch language {
        case .en: "This week"
        case .ja: "今週"
        case .vi: "Tuần này"
        }
    }

    var nextWorkout: String {
        switch language {
        case .en: "Next workout"
        case .ja: "次のワークアウト"
        case .vi: "Buổi tập tiếp theo"
        }
    }

    var planEyebrow: String {
        switch language {
        case .en: "PLAN"
        case .ja: "プラン"
        case .vi: "KẾ HOẠCH"
        }
    }

    var emptyPlanDescription: String {
        switch language {
        case .en: "Distance, date, and target time become the plan."
        case .ja: "距離、日付、目標タイムからプランを作成します。"
        case .vi: "Cự ly, ngày và thời gian mục tiêu sẽ tạo thành kế hoạch."
        }
    }

    var setRaceEntered: String {
        switch language {
        case .en: "Set the race you entered"
        case .ja: "参加するレースを設定"
        case .vi: "Đặt race bạn đã đăng ký"
        }
    }

    var personalHistoryEyebrow: String {
        switch language {
        case .en: "PERSONAL HISTORY"
        case .ja: "個人履歴"
        case .vi: "LỊCH SỬ CÁ NHÂN"
        }
    }

    var runHistory: String {
        switch language {
        case .en: "Run history"
        case .ja: "ラン履歴"
        case .vi: "Lịch sử chạy"
        }
    }

    var runHistorySubtitle: String {
        switch language {
        case .en: "Completed runs and trends"
        case .ja: "完了したランと傾向"
        case .vi: "Các buổi chạy hoàn thành và xu hướng"
        }
    }

    var runningShoes: String {
        switch language {
        case .en: "Running shoes"
        case .ja: "ランニングシューズ"
        case .vi: "Giày chạy"
        }
    }

    var runningShoesSubtitle: String {
        switch language {
        case .en: "Rotation and mileage"
        case .ja: "ローテーションと走行距離"
        case .vi: "Luân phiên và số km"
        }
    }

    func openAccessibilityLabel(_ label: String) -> String {
        switch language {
        case .en: "Open \(label.lowercased())"
        case .ja: "\(label)を開く"
        case .vi: "Mở \(label.lowercased())"
        }
    }

    var athleteName: String { "Khanh Nguyen" }

    var trainingPlan: String {
        switch language {
        case .en: "Training Plan"
        case .ja: "トレーニングプラン"
        case .vi: "Kế hoạch tập luyện"
        }
    }

    var marathonRunner: String {
        switch language {
        case .en: "Marathon runner"
        case .ja: "マラソンランナー"
        case .vi: "Người chạy marathon"
        }
    }

    func distanceRunner(_ distance: RaceDistance) -> String {
        switch language {
        case .en: "\(language.name(distance)) runner"
        case .ja: "\(language.name(distance))ランナー"
        case .vi: "Người chạy \(language.name(distance))"
        }
    }

    var runner: String {
        switch language {
        case .en: "Runner"
        case .ja: "ランナー"
        case .vi: "Người chạy"
        }
    }

    var athleteDetailsMissing: String {
        switch language {
        case .en: "Add age, height, and weight so Coach can personalize targets."
        case .ja: "Coach が目標を個別化できるよう、年齢、身長、体重を追加してください。"
        case .vi: "Thêm tuổi, chiều cao và cân nặng để Coach cá nhân hóa mục tiêu."
        }
    }

    func athleteDetailsPartial(_ count: Int) -> String {
        switch language {
        case .en: "\(count) of 3 details set · complete for sharper targets."
        case .ja: "3項目中\(count)項目を設定済み · より的確な目標のために入力を完了してください。"
        case .vi: "Đã đặt \(count)/3 thông tin · hãy hoàn tất để có mục tiêu chính xác hơn."
        }
    }

    var athleteDetailsComplete: String {
        switch language {
        case .en: "Age, height, and weight on file."
        case .ja: "年齢、身長、体重を登録済みです。"
        case .vi: "Đã lưu tuổi, chiều cao và cân nặng."
        }
    }

    var thresholdPace: String {
        switch language {
        case .en: "Threshold pace"
        case .ja: "閾値ペース"
        case .vi: "Pace ngưỡng"
        }
    }

    var restingHeartRate: String {
        switch language {
        case .en: "Resting HR"
        case .ja: "安静時心拍数"
        case .vi: "Nhịp tim nghỉ"
        }
    }

    var weight: String {
        switch language {
        case .en: "Weight"
        case .ja: "体重"
        case .vi: "Cân nặng"
        }
    }

    var vo2Max: String { "VO₂ max" }

    func paceValue(_ secondsPerKilometer: Double) -> String {
        let total = Int(secondsPerKilometer.rounded())
        let minutes = String(format: "%d", locale: language.uiLocale, total / 60)
        let seconds = String(format: "%02d", locale: language.uiLocale, total % 60)
        return "\(minutes):\(seconds)\(paceUnit)"
    }

    func heartRateValue(_ beatsPerMinute: Double) -> String {
        let value = String(format: "%d", locale: language.uiLocale, Int(beatsPerMinute.rounded()))
        return switch language {
        case .en: "\(value) bpm"
        case .ja: "\(value) bpm"
        case .vi: "\(value) bpm"
        }
    }

    func weightValue(_ value: Double) -> String {
        "\(String(format: "%.1f", locale: language.uiLocale, value)) kg"
    }

    func longDateWithYear(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day().locale(language.uiLocale))
    }

    func raceDay(_ date: Date) -> String {
        switch language {
        case .en: "\(longDateWithYear(date)) · Race day"
        case .ja: "\(longDateWithYear(date))・レース当日"
        case .vi: "\(longDateWithYear(date)) · Ngày race"
        }
    }

    func raceCompleted(_ date: Date) -> String {
        switch language {
        case .en: "\(longDateWithYear(date)) · Completed"
        case .ja: "\(longDateWithYear(date))・完了"
        case .vi: "\(longDateWithYear(date)) · Đã hoàn thành"
        }
    }

    func raceDaysLeft(date: Date, days: Int) -> String {
        switch language {
        case .en: "\(longDateWithYear(date)) · \(days) days left"
        case .ja: "\(longDateWithYear(date))・あと\(days)日"
        case .vi: "\(longDateWithYear(date)) · còn \(days) ngày"
        }
    }

    func thisWeekProgress(completed: Int, planned: Int, completedDistance: String, plannedDistance: String) -> String {
        switch language {
        case .en: "\(completed) of \(planned) runs · \(completedDistance) of \(plannedDistance)"
        case .ja: "\(planned)回中\(completed)回完了・\(completedDistance) / \(plannedDistance)"
        case .vi: "\(completed)/\(planned) buổi chạy · \(completedDistance)/\(plannedDistance)"
        }
    }

    var planCompleted: String {
        switch language {
        case .en: "Plan completed"
        case .ja: "プラン完了"
        case .vi: "Đã hoàn thành kế hoạch"
        }
    }

    var planPaused: String {
        switch language {
        case .en: "Plan is paused"
        case .ja: "プランは一時停止中"
        case .vi: "Kế hoạch đang tạm dừng"
        }
    }

    var noUpcomingWorkout: String {
        switch language {
        case .en: "No upcoming workout"
        case .ja: "予定のワークアウトはありません"
        case .vi: "Không có buổi tập sắp tới"
        }
    }

    func workoutSummary(name: String, distance: String, day: String) -> String {
        switch language {
        case .en: "\(name) \(distance) · \(day)"
        case .ja: "\(day)・\(name) \(distance)"
        case .vi: "\(name) \(distance) · \(day)"
        }
    }

    func distanceText(_ kilometers: Double) -> String {
        "\(String(format: "%.1f", locale: language.uiLocale, kilometers)) km"
    }

    func workoutName(kind: WorkoutKind?, raw: String) -> String {
        if let kind { return language.name(kind) }
        if let kind = WorkoutKind(rawValue: raw) { return language.name(kind) }
        return raw
    }

    func planStatusEyebrow(_ status: ActivePlanStatus) -> String {
        switch (language, status) {
        case (.en, .active): "PLAN ACTIVE"
        case (.en, .onTrack): "PLAN ON TRACK"
        case (.en, .needsAttention): "PLAN NEEDS ADJUSTMENT"
        case (.en, .paused): "PLAN PAUSED"
        case (.en, .completed): "PLAN COMPLETED"
        case (.ja, .active): "プラン進行中"
        case (.ja, .onTrack): "プラン順調"
        case (.ja, .needsAttention): "プラン要調整"
        case (.ja, .paused): "プラン一時停止"
        case (.ja, .completed): "プラン完了"
        case (.vi, .active): "KẾ HOẠCH ĐANG DIỄN RA"
        case (.vi, .onTrack): "KẾ HOẠCH ĐÚNG TIẾN ĐỘ"
        case (.vi, .needsAttention): "KẾ HOẠCH CẦN ĐIỀU CHỈNH"
        case (.vi, .paused): "KẾ HOẠCH TẠM DỪNG"
        case (.vi, .completed): "KẾ HOẠCH HOÀN TẤT"
        }
    }

    func planTitle(distance: RaceDistance, targetTime: Double) -> String {
        let time = Formatters.duration(targetTime)
        if distance == .marathon, targetTime <= 4 * 3600 {
            switch language {
            case .en: return "Sub-4:00 Marathon"
            case .ja: return "4時間切りマラソン"
            case .vi: return "Marathon dưới 4:00"
            }
        }
        switch language {
        case .en: return "\(language.name(distance)) in \(time)"
        case .ja: return "\(language.name(distance)) \(time)目標"
        case .vi: return "\(language.name(distance)) trong \(time)"
        }
    }

    func missedKeySessions(_ count: Int) -> String {
        switch language {
        case .en: "Missed \(count) key session\(count == 1 ? "" : "s"). Nothing is broken — reschedule in the plan or ask Coach to rebalance the week."
        case .ja: "重要セッションを\(count)回逃しました。問題ではありません。プランで予定を組み直すか、Coach に週の調整を依頼してください。"
        case .vi: "Đã bỏ lỡ \(count) buổi tập chính. Không có gì hỏng cả — hãy lên lịch lại trong kế hoạch hoặc nhờ Coach cân bằng lại tuần này."
        }
    }

    var weeklyVolumeBehind: String {
        switch language {
        case .en: "Behind this week's mileage. Review the remaining runs or ease back to target — the plan adapts."
        case .ja: "今週の走行距離が目標に届いていません。残りのランを確認するか、目標を少し下げてください。プランは調整されます。"
        case .vi: "Số km tuần này đang chậm tiến độ. Xem lại các buổi chạy còn lại hoặc giảm mục tiêu — kế hoạch sẽ điều chỉnh."
        }
    }

    func missedRecentRuns(_ count: Int) -> String {
        switch language {
        case .en: "Missed \(count) run\(count == 1 ? "" : "s") recently. Pick the next one back up when you are ready."
        case .ja: "最近\(count)回のランを逃しました。準備ができたら次のランから再開しましょう。"
        case .vi: "Gần đây đã bỏ lỡ \(count) buổi chạy. Hãy bắt đầu lại từ buổi tiếp theo khi bạn sẵn sàng."
        }
    }

    var insufficientPlanHealthData: String {
        switch language {
        case .en: "Not enough recent runs to read plan health yet. Sync or log your latest runs."
        case .ja: "プランの状態を確認するための最近のランがまだ十分ではありません。最新のランを同期または記録してください。"
        case .vi: "Chưa đủ buổi chạy gần đây để đánh giá trạng thái kế hoạch. Hãy đồng bộ hoặc ghi lại các buổi chạy mới nhất."
        }
    }

    var planSessionsSlipped: String {
        switch language {
        case .en: "A few sessions slipped. Open the plan to get back on track."
        case .ja: "いくつかのセッションがずれました。プランを開いて軌道に戻しましょう。"
        case .vi: "Một vài buổi tập đã lỡ. Mở kế hoạch để trở lại đúng tiến độ."
        }
    }

    var logRunsForPlanHealth: String {
        switch language {
        case .en: "Log or sync a few runs so Coach can track how the plan is going."
        case .ja: "Coach がプランの進行を追えるよう、いくつかのランを記録または同期してください。"
        case .vi: "Ghi lại hoặc đồng bộ vài buổi chạy để Coach theo dõi tiến độ kế hoạch."
        }
    }

    // MARK: - Athlete profile editor

    var athleteProfileTitle: String {
        switch language {
        case .en: "Athlete Profile"
        case .ja: "アスリートプロフィール"
        case .vi: "Hồ sơ vận động viên"
        }
    }

    var athleteSection: String {
        switch language {
        case .en: "Athlete"
        case .ja: "アスリート"
        case .vi: "Vận động viên"
        }
    }

    var age: String {
        switch language {
        case .en: "Age"
        case .ja: "年齢"
        case .vi: "Tuổi"
        }
    }

    var years: String {
        switch language {
        case .en: "years"
        case .ja: "歳"
        case .vi: "tuổi"
        }
    }

    var height: String {
        switch language {
        case .en: "Height"
        case .ja: "身長"
        case .vi: "Chiều cao"
        }
    }

    var centimeters: String { "cm" }
    var kilograms: String { "kg" }

    // MARK: - Goal entry

    var raceGoalTitle: String {
        switch language {
        case .en: "Race Goal"
        case .ja: "レース目標"
        case .vi: "Mục tiêu race"
        }
    }

    var overwriteCurrentPlan: String {
        switch language {
        case .en: "Overwrite current plan?"
        case .ja: "現在のプランを上書きしますか？"
        case .vi: "Ghi đè kế hoạch hiện tại?"
        }
    }

    var overwritePlan: String {
        switch language {
        case .en: "Overwrite Plan"
        case .ja: "プランを上書き"
        case .vi: "Ghi đè kế hoạch"
        }
    }

    var overwritePlanMessage: String {
        switch language {
        case .en: "This deletes the affected old plan and writes the new one. Completed runs stay in your history."
        case .ja: "対象の古いプランを削除し、新しいプランを作成します。完了したランは履歴に残ります。"
        case .vi: "Việc này xóa kế hoạch cũ bị ảnh hưởng và tạo kế hoạch mới. Các buổi chạy đã hoàn thành vẫn ở trong lịch sử."
        }
    }

    var raceSection: String {
        switch language {
        case .en: "Race"
        case .ja: "レース"
        case .vi: "Race"
        }
    }

    var distance: String {
        switch language {
        case .en: "Distance"
        case .ja: "距離"
        case .vi: "Cự ly"
        }
    }

    var targetTime: String {
        switch language {
        case .en: "Target time"
        case .ja: "目標タイム"
        case .vi: "Thời gian mục tiêu"
        }
    }

    var hours: String {
        switch language {
        case .en: "Hours"
        case .ja: "時間"
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

    func hourPickerValue(_ value: Int) -> String {
        switch language {
        case .en: "\(value) h"
        case .ja: "\(value)時間"
        case .vi: "\(value) giờ"
        }
    }

    func minutePickerValue(_ value: Int) -> String {
        switch language {
        case .en: "\(String(format: "%02d", locale: language.uiLocale, value)) m"
        case .ja: "\(value)分"
        case .vi: "\(String(format: "%02d", locale: language.uiLocale, value)) phút"
        }
    }

    var raceDate: String {
        switch language {
        case .en: "Race date"
        case .ja: "レース日"
        case .vi: "Ngày race"
        }
    }

    func runningDays(_ count: Int) -> String {
        switch language {
        case .en: "Running Days (\(count)/week)"
        case .ja: "走る曜日（週\(count)日）"
        case .vi: "Ngày chạy (\(count)/tuần)"
        }
    }

    var longRunDay: String {
        switch language {
        case .en: "Long run day"
        case .ja: "ロング走の日"
        case .vi: "Ngày chạy dài"
        }
    }

    var minimumRunningDays: String {
        switch language {
        case .en: "Pick at least 3 running days."
        case .ja: "走る曜日を少なくとも3日選んでください。"
        case .vi: "Chọn ít nhất 3 ngày chạy."
        }
    }

    var comfortablePace: String {
        switch language {
        case .en: "Comfortable pace"
        case .ja: "快適なペース"
        case .vi: "Pace thoải mái"
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

    var paceUnit: String { "/km" }
    var timeSeparator: String { ":" }


    func weeklyVolume(_ kilometers: Int) -> String {
        switch language {
        case .en: "Weekly volume: \(kilometers) km"
        case .ja: "週間走行距離: \(kilometers) km"
        case .vi: "Khối lượng tuần: \(kilometers) km"
        }
    }

    var currentFitness: String {
        switch language {
        case .en: "Current Fitness"
        case .ja: "現在の走力"
        case .vi: "Thể lực hiện tại"
        }
    }

    var coldStartFitnessFooter: String {
        switch language {
        case .en: "Not enough recent running history to estimate fitness — tell us how you run today."
        case .ja: "走力を推定するための最近のラン履歴が十分ではありません。今日の走りについて教えてください。"
        case .vi: "Chưa đủ lịch sử chạy gần đây để ước tính thể lực — hãy cho chúng tôi biết bạn chạy thế nào hôm nay."
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
        case (.en, .ok): "Realistic goal"
        case (.en, .stretch): "Stretch goal"
        case (.en, .unrealistic): "Very ambitious goal"
        case (.ja, .ok): "現実的な目標"
        case (.ja, .stretch): "挑戦的な目標"
        case (.ja, .unrealistic): "とても意欲的な目標"
        case (.vi, .ok): "Mục tiêu thực tế"
        case (.vi, .stretch): "Mục tiêu thử thách"
        case (.vi, .unrealistic): "Mục tiêu rất tham vọng"
        }
    }

    func goalFitness(goal: Int, projected: Int) -> String {
        switch language {
        case .en: "Goal fitness \(goal) vs projected \(projected) VDOT"
        case .ja: "目標走力 \(goal) と予測 \(projected) VDOT"
        case .vi: "Thể lực mục tiêu \(goal) so với dự báo \(projected) VDOT"
        }
    }

    var enterGoalDetails: String {
        switch language {
        case .en: "Enter goal details to see feasibility."
        case .ja: "実現可能性を確認するには目標の詳細を入力してください。"
        case .vi: "Nhập chi tiết mục tiêu để xem tính khả thi."
        }
    }

    func couldNotSaveGoal(_ error: String) -> String {
        switch language {
        case .en: "Could not save goal: \(error)"
        case .ja: "目標を保存できませんでした: \(error)"
        case .vi: "Không thể lưu mục tiêu: \(error)"
        }
    }
}
