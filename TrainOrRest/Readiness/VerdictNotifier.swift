import Foundation
import SwiftData
import UserNotifications

/// Posts the once-daily morning verdict notification after a background
/// refresh. Best-effort by design — the dashboard is the source of truth.
@MainActor
enum VerdictNotifier {
    /// Safe to call on every launch; the system prompt shows only once.
    static func requestPermission() async {
        if ProcessInfo.processInfo.environment["TOR_DEV_SEED"] == "1" { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Delivers the verdict notification unless one was already sent today
    /// or there is no real verdict to report.
    static func notifyIfNeeded(for readiness: DailyReadiness, in context: ModelContext) async {
        guard readiness.verdict != .insufficientData, readiness.notifiedAt == nil else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let language = CoachLanguage.current
        let content = UNMutableNotificationContent()
        content.title = language.today.notificationTitle(readiness.verdict)
        content.body = readiness.reasonCodes.first.map(language.today.reason)
            ?? readiness.reasons.first
            ?? language.today.notificationDefaultBody
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
