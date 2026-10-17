import Foundation

extension CoachLanguage {
    var season: SeasonCopy { SeasonCopy(language: self) }
}

struct SeasonCopy {
    let language: CoachLanguage

    var seasonTitle: String { text(en: "Season", ja: "シーズン", vi: "Mùa giải") }
    func raceCount(_ count: Int) -> String { text(en: "Season · \(count) races", ja: "シーズン・\(count)レース", vi: "Mùa giải · \(count) race") }
    var addRace: String { text(en: "+ Add race", ja: "+ レースを追加", vi: "+ Thêm race") }
    var addRaceTitle: String { text(en: "Add race", ja: "レースを追加", vi: "Thêm race") }
    var raceName: String { text(en: "Race name", ja: "レース名", vi: "Tên race") }
    var raceDate: String { text(en: "Date", ja: "日付", vi: "Ngày") }
    var raceDistance: String { text(en: "Distance", ja: "距離", vi: "Cự li") }
    var raceTargetOptional: String { text(en: "Target (optional)", ja: "目標（任意）", vi: "Mục tiêu (tùy chọn)") }
    var raceTypeSection: String { text(en: "RACE TYPE", ja: "レースタイプ", vi: "LOẠI RACE") }
    var priorityATitle: String { text(en: "Main goal", ja: "メイン目標", vi: "Mục tiêu chính") }
    var priorityBTitle: String { text(en: "Test effort · mini-taper", ja: "テスト・ミニテーパー", vi: "Thử sức · mini-taper") }
    var priorityCTitle: String { text(en: "Run as a workout", ja: "練習として走る", vi: "Chạy như buổi tập") }
    var addToSeason: String { text(en: "Add to season", ja: "シーズンに追加", vi: "Thêm vào mùa giải") }
    var cancel: String { text(en: "Cancel", ja: "キャンセル", vi: "Hủy") }
    var custom: String { text(en: "Other", ja: "その他", vi: "Khác") }
    func daysLeft(_ days: Int) -> String { text(en: "\(days) days left", ja: "残り\(days)日", vi: "còn \(days) ngày") }
    var today: String { text(en: "Today", ja: "今日", vi: "Hôm nay") }
    var miniTaperTag: String { text(en: "mini-taper", ja: "ミニテーパー", vi: "mini-taper") }
    var runAsWorkoutTag: String { text(en: "run as a workout", ja: "練習として", vi: "chạy như buổi tập") }
    var taperTag: String { text(en: "Taper", ja: "テーパー", vi: "Giảm tải") }
    var recoveryTag: String { text(en: "Recovery", ja: "回復", vi: "Hồi phục") }
    var viewSuggestion: String { text(en: "View suggestion", ja: "提案を見る", vi: "Xem đề xuất") }
    var raceDetailTitle: String { text(en: "Race", ja: "レース", vi: "Race") }
    var deleteRace: String { text(en: "Delete race", ja: "レースを削除", vi: "Xóa race") }
    var deleteRaceConfirm: String { text(en: "Delete this race?", ja: "このレースを削除しますか？", vi: "Xóa race này?") }
    var save: String { text(en: "Save", ja: "保存", vi: "Lưu") }
    var recordResult: String { text(en: "Record result", ja: "結果を記録", vi: "Ghi kết quả") }
    var finishTime: String { text(en: "Finish time", ja: "ゴールタイム", vi: "Thời gian hoàn thành") }
    var demoteExistingATitle: String { text(en: "Replace your main goal?", ja: "メイン目標を置き換えますか？", vi: "Thay mục tiêu chính?") }
    var noRacesYet: String { text(en: "No races yet", ja: "レースがありません", vi: "Chưa có race nào") }
    var noRacesDescription: String { text(en: "Add the race you entered and Coach plans around it.", ja: "参加するレースを追加すると、コーチがそれに合わせて計画します。", vi: "Thêm race bạn đã đăng ký để Coach lên kế hoạch quanh nó.") }

    func demoteExistingA(_ name: String) -> String {
        text(en: "\(name) becomes a B race.", ja: "\(name)はBレースになります。", vi: "\(name) sẽ thành race B.")
    }

    func prioritySuggestion(_ priority: RacePriority, reason: RacePrioritySuggestion.Reason, weeks: Int?) -> String {
        switch reason {
        case .noARaceYet:
            text(en: "Suggested: A, your first race", ja: "提案: A、最初のレース", vi: "Gợi ý: A · race đầu tiên")
        case .farFromARace:
            text(en: "Suggested: B, \(weeks ?? 0) weeks from Race A", ja: "提案: B、Race Aまで\(weeks ?? 0)週", vi: "Gợi ý: B · cách Race A \(weeks ?? 0) tuần")
        case .insideARaceTaper:
            text(en: "Suggested: C, inside the Race A taper", ja: "提案: C、Race Aのテーパー期間内", vi: "Gợi ý: C · nằm trong giai đoạn giảm tải Race A")
        case .closeToARace:
            text(en: "Suggested: C, close to Race A", ja: "提案: C、Race Aに近い", vi: "Gợi ý: C · gần Race A")
        case .insideRecoveryWindow:
            text(en: "Suggested: C, inside a recovery window", ja: "提案: C、回復期間内", vi: "Gợi ý: C · nằm trong giai đoạn hồi phục")
        }
    }

    func warningText(_ warning: RaceWarning) -> String {
        switch warning.code {
        case .insideARaceTaper:
            text(en: "This race falls inside the Race A taper.", ja: "このレースはRace Aのテーパー期間内です。", vi: "Race này nằm trong giai đoạn giảm tải của Race A.")
        case .tooSoonAfterMarathon:
            text(en: "Half or longer \(warning.dayGap ?? 0) days after a marathon.", ja: "マラソンの\(warning.dayGap ?? 0)日後にハーフ以上です。", vi: "Half cách marathon \(warning.dayGap ?? 0) ngày.")
        case .racesTooClose:
            text(en: "Two races \(warning.dayGap ?? 0) days apart.", ja: "2レースが\(warning.dayGap ?? 0)日間隔です。", vi: "Hai race cách nhau \(warning.dayGap ?? 0) ngày.")
        case .insideRecoveryWindow:
            text(en: "This race falls inside a recovery window.", ja: "このレースは回復期間内です。", vi: "Race này nằm trong giai đoạn hồi phục.")
        }
    }

    func schedulePreview(miniTaperDays: Int, miniTaperRange: String, recoveryDays: Int) -> String {
        text(
            en: "Coach adds \(miniTaperDays) mini-taper days (\(miniTaperRange)) and \(recoveryDays) recovery days after the race.",
            ja: "コーチはミニテーパー\(miniTaperDays)日（\(miniTaperRange)）とレース後の回復\(recoveryDays)日を追加します。",
            vi: "Coach sẽ thêm \(miniTaperDays) ngày mini-taper (\(miniTaperRange)) và \(recoveryDays) ngày hồi phục sau race."
        )
    }

    private func text(en: String, ja: String, vi: String) -> String {
        switch language {
        case .en: en
        case .ja: ja
        case .vi: vi
        }
    }
}
