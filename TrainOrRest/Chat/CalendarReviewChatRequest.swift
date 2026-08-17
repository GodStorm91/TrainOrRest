import Foundation

struct CalendarReviewChatRequest: Identifiable, Equatable {
    let id = UUID()
    let activityUUID: UUID
    let prompt: String

    init(activityUUID: UUID, prompt: String = "Review cuộc chạy này giúp tôi: điểm nào ổn, điểm nào nên chỉnh, và buổi sau nên chạy thế nào?") {
        self.activityUUID = activityUUID
        self.prompt = prompt
    }
}
