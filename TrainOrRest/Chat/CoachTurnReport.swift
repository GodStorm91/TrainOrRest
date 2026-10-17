import Foundation
import StoreKit
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Tracks whether this build may show the Coach turn log. The log carries the
/// text the person typed, so it stays in DEBUG and TestFlight. An unreadable
/// `AppTransaction` hides it, unlike `ChatGPTDiagnostics`, which shows its
/// secret-free HTTP log in that case.
@MainActor
@Observable
final class CoachDiagnosticsAvailability {
    static let shared = CoachDiagnosticsAvailability()

    private(set) var isEnabled = false
    private var hasResolved = false

    private init() {}

    func resolve() async {
        guard !hasResolved else { return }
        hasResolved = true
        #if DEBUG
        isEnabled = true
        #else
        guard let transaction = try? await AppTransaction.shared else { return }
        isEnabled = transaction.unsafePayloadValue.environment != .production
        #endif
    }
}

/// A JSON transcript of recent Coach turns, built for a human to paste into a
/// bug report. It carries what the app read and what it did, never the Coach
/// prose and never health rows, so the user can hand it over without reading
/// every line first.
enum CoachTurnReport {
    static let defaultTurnLimit = 20

    /// Window used to attribute an applied plan edit to a turn when the report
    /// covers a single message. Plan edits carry no turn ID, so the report
    /// pairs them by time and says so in the key name.
    private static let planEditWindow: TimeInterval = 15 * 60

    static func report(for message: ChatMessage, in context: ModelContext) -> String {
        let anchor = message.date
        let window = DateInterval(
            start: anchor.addingTimeInterval(-planEditWindow),
            end: anchor.addingTimeInterval(planEditWindow)
        )
        let messages = fetchMessages(in: context, limit: defaultTurnLimit * 2)
        let related = messages.filter { related($0, to: message) }
        return encode(
            Payload(
                generatedAt: .now,
                scope: "single turn",
                environment: Environment.current,
                turns: related.map { turn(for: $0, in: context) },
                planEditsNearby: planEdits(in: context, within: window)
            )
        )
    }

    static func bundle(limit: Int = defaultTurnLimit, in context: ModelContext) -> String {
        let messages = fetchMessages(in: context, limit: limit * 2)
        let now = Date.now
        let window = messages.first.map {
            DateInterval(start: min($0.date, now), end: now.addingTimeInterval(planEditWindow))
        }
        return encode(
            Payload(
                generatedAt: .now,
                scope: "last \(limit) turns",
                environment: Environment.current,
                turns: messages.map { turn(for: $0, in: context) },
                planEditsNearby: window.map { planEdits(in: context, within: $0) } ?? []
            )
        )
    }

    private static func related(_ candidate: ChatMessage, to message: ChatMessage) -> Bool {
        if candidate.turnID == message.turnID { return true }
        if let parent = message.parentUserTurnID, candidate.turnID == parent { return true }
        if let parent = candidate.parentUserTurnID, parent == message.turnID { return true }
        return false
    }

    private static func fetchMessages(in context: ModelContext, limit: Int) -> [ChatMessage] {
        var descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.reversed()
    }

    static func recordedTurnCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<CoachRequestSnapshot>())) ?? 0
    }

    private static func planEdits(in context: ModelContext, within window: DateInterval) -> [PlanEditEntry] {
        let start = window.start
        let end = window.end
        let descriptor = FetchDescriptor<PlanEdit>(
            predicate: #Predicate { $0.appliedAt >= start && $0.appliedAt <= end },
            sortBy: [SortDescriptor(\.appliedAt, order: .forward)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map(PlanEditEntry.init)
    }

    private static func snapshot(for message: ChatMessage, in context: ModelContext) -> CoachRequestSnapshot? {
        let turnID = message.turnID
        if let id = message.requestSnapshotID {
            let descriptor = FetchDescriptor<CoachRequestSnapshot>(predicate: #Predicate { $0.id == id })
            if let row = try? context.fetch(descriptor).first { return row }
        }
        guard message.role == .user else { return nil }
        let descriptor = FetchDescriptor<CoachRequestSnapshot>(
            predicate: #Predicate { $0.userTurnID == turnID }
        )
        return try? context.fetch(descriptor).first
    }

    private static func turn(for message: ChatMessage, in context: ModelContext) -> Turn {
        var turn = Turn(id: message.turnID, date: message.date, role: message.roleRaw)
        turn.threadID = message.threadID
        turn.replyCharacters = message.text.count

        if message.role == .assistant {
            turn.status = message.statusRaw
            turn.errorCategory = message.errorCategoryRaw
            turn.errorMessage = message.errorMessage
            turn.errorDetail = message.errorDetail
            turn.attempts = message.attemptCountStorage
            turn.startedAt = message.generationStartedAt
            turn.firstReadableAt = message.firstReadableAt
            turn.completedAt = message.completedAt
            turn.secondsToFirstWord = message.firstReadableDuration.map(rounded)
            turn.secondsToComplete = message.generationDuration.map(rounded)
            turn.appliedAdjustment = message.appliedAdjustment
            turn.groundingFootnote = message.groundingFootnote
            turn.offeredOptions = message.interaction.map { options(in: $0) }
            turn.structuredResponse = truncated(message.structuredResponseJSON)
        }

        guard let snapshot = snapshot(for: message, in: context) else { return turn }
        let visible = snapshot.displayText ?? snapshot.messageText
        turn.visibleText = visible
        turn.submittedText = snapshot.messageText
        turn.textsDiffer = visible != snapshot.messageText
        turn.interactionID = snapshot.interactionId
        turn.selectedOptionID = snapshot.selectedOptionId
        turn.isCustomResponse = snapshot.isCustomInteractionResponse
        turn.actionType = snapshot.actionTypeRaw
        turn.locale = snapshot.locale
        turn.units = snapshot.unitPreferences
        turn.attachments = snapshot.attachmentReferences.map(\.kind.rawValue)
        if let offered = CoachInteractionCodec.decode(snapshot.expectedResponseInteractionJSON) {
            turn.optionsOnScreen = options(in: offered)
        }
        return turn
    }

    private static func options(in interaction: CoachResponseInteraction) -> [Option] {
        interaction.options.map {
            Option(id: $0.id, label: $0.label, submits: $0.submissionText)
        }
    }

    private static func rounded(_ value: TimeInterval) -> Double {
        (value * 1000).rounded() / 1000
    }

    private static func truncated(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let limit = 4000
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "…[truncated]"
    }

    private static func encode(_ payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else {
            return "{\"error\":\"the report could not be encoded\"}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension CoachTurnReport {
    fileprivate struct Payload: Encodable {
        var generatedAt: Date
        var scope: String
        var environment: Environment
        var turns: [Turn]
        var planEditsNearby: [PlanEditEntry]
    }

    fileprivate struct Environment: Encodable {
        var app: String
        var build: String
        var system: String
        var device: String
        var locale: String

        static var current: Environment {
            let info = Bundle.main.infoDictionary
            #if canImport(UIKit)
            let device = UIDevice.current
            let system = "\(device.systemName) \(device.systemVersion)"
            let model = device.model
            #else
            let system = ProcessInfo.processInfo.operatingSystemVersionString
            let model = "unknown"
            #endif
            return Environment(
                app: info?["CFBundleShortVersionString"] as? String ?? "unknown",
                build: info?["CFBundleVersion"] as? String ?? "unknown",
                system: system,
                device: model,
                locale: Locale.current.identifier
            )
        }
    }

    fileprivate struct Option: Encodable {
        var id: String
        var label: String
        var submits: String
    }

    fileprivate struct Turn: Encodable {
        var id: UUID
        var date: Date
        var role: String
        var threadID: UUID?

        var visibleText: String?
        var submittedText: String?
        var textsDiffer: Bool?
        var interactionID: String?
        var selectedOptionID: String?
        var isCustomResponse: Bool?
        var actionType: String?
        var locale: String?
        var units: String?
        var attachments: [String]?
        var optionsOnScreen: [Option]?

        var status: String?
        var errorCategory: String?
        var errorMessage: String?
        var errorDetail: String?
        var attempts: Int?
        var startedAt: Date?
        var firstReadableAt: Date?
        var completedAt: Date?
        var secondsToFirstWord: Double?
        var secondsToComplete: Double?
        var replyCharacters: Int?
        var appliedAdjustment: String?
        var groundingFootnote: String?
        var offeredOptions: [Option]?
        var structuredResponse: String?
    }

    fileprivate struct PlanEditEntry: Encodable {
        var appliedAt: Date
        var workoutDate: Date
        var source: String
        var summary: String?
        var revertedAt: Date?
        var beforeKind: String
        var beforeDistanceKm: Double
        var afterKind: String
        var afterDistanceKm: Double
        var weekVolumeBeforeKm: Double
        var weekVolumeAfterKm: Double

        init(_ edit: PlanEdit) {
            appliedAt = edit.appliedAt
            workoutDate = edit.workoutDate
            source = edit.source
            summary = edit.summaryText
            revertedAt = edit.revertedAt
            beforeKind = edit.kindRaw
            beforeDistanceKm = edit.distanceKm
            afterKind = edit.afterKindRaw
            afterDistanceKm = edit.afterDistanceKm
            weekVolumeBeforeKm = edit.weekTargetVolumeKmBefore
            weekVolumeAfterKm = edit.weekTargetVolumeKmAfter
        }
    }
}
