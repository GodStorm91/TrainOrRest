import Foundation
import SwiftData

struct CoachImageAttachment: Equatable {
    var data: Data
    var mediaType: String
    var filename: String

    var base64String: String { data.base64EncodedString() }
}

enum CoachContextAttachment: Equatable, Identifiable {
    case health
    case plannedWorkout(UUID)
    case completedActivity(UUID)
    case image(CoachImageAttachment)

    var id: String {
        switch self {
        case .health: "health"
        case .plannedWorkout(let uuid): "planned-\(uuid.uuidString)"
        case .completedActivity(let uuid): "completed-\(uuid.uuidString)"
        case .image(let attachment): "image-\(attachment.filename)-\(attachment.data.count)"
        }
    }
}

@MainActor
enum CoachAttachmentContextBuilder {
    static func content(
        text: String,
        attachments: [CoachContextAttachment],
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) -> [ClaudeContentBlock] {
        var blocks: [ClaudeContentBlock] = [
            .text(messageText(text, attachments: attachments, in: context, today: today, calendar: calendar))
        ]
        blocks += attachments.compactMap { attachment in
            guard case .image(let image) = attachment else { return nil }
            return .image(mediaType: image.mediaType, data: image.base64String)
        }
        return blocks
    }

    static func displayText(
        text: String,
        attachments: [CoachContextAttachment],
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) -> String {
        let labels = attachments.map { label(for: $0, in: context, today: today, calendar: calendar) }
        guard !labels.isEmpty else { return text }
        return text + "\n\nAttached: " + labels.joined(separator: ", ")
    }

    private static func messageText(
        _ text: String,
        attachments: [CoachContextAttachment],
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) -> String {
        let contextText = attachments.compactMap {
            detail(for: $0, in: context, today: today, calendar: calendar)
        }
        guard !contextText.isEmpty else { return text }
        return ([text, "Attached context:"] + contextText).joined(separator: "\n\n")
    }

    private static func detail(
        for attachment: CoachContextAttachment,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) -> String? {
        switch attachment {
        case .health:
            return healthDetail(in: context, today: today, calendar: calendar)
        case .plannedWorkout(let uuid):
            guard let workout = plannedWorkout(uuid, in: context) else { return nil }
            return [
                "Selected workout context. This is the workout the user opened from Calendar; do not ask which workout they mean unless this row becomes unavailable:",
                "- Workout ID: \(workout.uuid.uuidString)",
                "- Date: \(CoachContextBuilder.day(workout.date, calendar: calendar))",
                "- Kind: \(workout.kind?.displayName ?? workout.kindRaw)",
                "- Distance: \(String(format: "%.1f", workout.distanceKm)) km",
                "- Estimated duration: \(workout.expectedDurationSeconds.map(Formatters.duration) ?? "unknown")",
                "- Pace band: \(workout.paceBand.map(Formatters.paceBand) ?? "none")",
                "- Details: \(workout.details)",
                "- Status: \(workout.status.rawValue)",
                "- Schedule locked: \(workout.isScheduleLocked ? "yes" : "no")",
                "- Plan week: \(workout.weekIndex + 1)",
                "If the user asks to change this workout, use \(CoachTools.toolName) with this absolute date. The app will validate and ask for confirmation before applying."
            ].joined(separator: "\n")
        case .completedActivity(let uuid):
            guard let activity = completedActivity(uuid, in: context) else { return nil }
            return [
                "Selected completed run context. This is for review, not direct workout-plan mutation:",
                "- Date: \(CoachContextBuilder.day(activity.date, calendar: calendar))",
                "- Distance: \(Formatters.kilometers(activity.distanceMeters))",
                "- Duration: \(Formatters.duration(activity.durationSeconds))",
                "- Avg pace: \(Formatters.pace(activity.avgPaceSecondsPerKm))",
                "- Avg HR: \(Formatters.heartRate(activity.avgHeartRate))",
                "- Source: \(activity.sourceName)"
            ].joined(separator: "\n")
        case .image(let image):
            return "Image attached: \(image.filename), \(image.mediaType), \(image.data.count / 1024) KB."
        }
    }

    private static func label(
        for attachment: CoachContextAttachment,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) -> String {
        switch attachment {
        case .health:
            return "health"
        case .plannedWorkout(let uuid):
            guard let workout = plannedWorkout(uuid, in: context) else { return "workout" }
            return "\(workout.kind?.displayName ?? "workout") \(CoachContextBuilder.day(workout.date, calendar: calendar))"
        case .completedActivity(let uuid):
            guard let activity = completedActivity(uuid, in: context) else { return "run" }
            return "run \(CoachContextBuilder.day(activity.date, calendar: calendar))"
        case .image:
            return "image"
        }
    }

    private static func healthDetail(in context: ModelContext, today: Date, calendar: Calendar) -> String {
        let dayStart = calendar.startOfDay(for: today)
        let readiness = (try? context.fetch(FetchDescriptor<DailyReadiness>()).first {
            calendar.isDate($0.date, inSameDayAs: dayStart)
        })
        let latestWellness = (try? context.fetch(
            FetchDescriptor<DailyWellness>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        ).first)

        var lines = ["Health snapshot:"]
        if let readiness {
            let reasons = readiness.reasons.isEmpty ? "no flags" : readiness.reasons.joined(separator: "; ")
            lines.append("- Readiness: \(readiness.verdict.rawValue), \(reasons)")
            lines.append("- ACWR: \(Formatters.decimal(readiness.acuteChronicRatio, unit: ""))")
        } else {
            lines.append("- Readiness: not computed")
        }
        if let latestWellness {
            lines.append("- Latest wellness date: \(CoachContextBuilder.day(latestWellness.date, calendar: calendar))")
            lines.append("- HRV: \(Formatters.decimal(latestWellness.hrvSDNN, unit: "ms"))")
            lines.append("- RHR: \(Formatters.heartRate(latestWellness.restingHeartRate))")
            lines.append("- Sleep: \(Formatters.sleep(latestWellness.sleepHours))")
        }
        return lines.joined(separator: "\n")
    }

    private static func plannedWorkout(_ uuid: UUID, in context: ModelContext) -> PlannedWorkout? {
        (try? context.fetch(FetchDescriptor<PlannedWorkout>()).first { $0.uuid == uuid }) ?? nil
    }

    private static func completedActivity(_ uuid: UUID, in context: ModelContext) -> CompletedActivity? {
        (try? context.fetch(FetchDescriptor<CompletedActivity>()).first { $0.hkUUID == uuid }) ?? nil
    }
}
