import Foundation
import SwiftData
import UserNotifications

/// Posts the once-daily morning verdict notification after a background
/// refresh. Best-effort by design — the dashboard is the source of truth.
@MainActor
enum VerdictNotifier {
    /// Safe to call on every launch; the system prompt shows only once.
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Delivers the verdict notification unless one was already sent today
    /// or there is no real verdict to report.
    static func notifyIfNeeded(for readiness: DailyReadiness, in context: ModelContext) async {
        guard readiness.verdict != .insufficientData, readiness.notifiedAt == nil else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = readiness.verdict.notificationTitle
        content.body = readiness.reasons.first ?? "All recovery signals look good."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "verdict-\(readiness.date.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            readiness.notifiedAt = .now
            try? context.save()
        } catch {
            // Best-effort: leave notifiedAt nil so a later refresh can retry.
        }
    }
}

extension ReadinessVerdict {
    var notificationTitle: String {
        switch self {
        case .train: "Train today"
        case .goEasy: "Go easy today"
        case .rest: "Rest today"
        case .insufficientData: "TrainOrRest"
        }
    }
}
