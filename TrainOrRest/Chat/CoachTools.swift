import Foundation
import SwiftData

struct PlanAdjustmentProposal: Codable, Equatable {
    var changes: [Change]

    struct Change: Codable, Equatable {
        enum Action: String, Codable {
            case swap, downgrade, rest, move, create, replace
        }

        var date: String
        var action: Action
        var detail: String? = nil
        var workout: CreateWorkout? = nil

        enum CodingKeys: String, CodingKey {
            case date, action, detail, workout, kind, blocks
        }

        init(date: String, action: Action, detail: String? = nil, workout: CreateWorkout? = nil) {
            self.date = date
            self.action = action
            self.detail = detail
            self.workout = workout
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            action = try container.decode(Action.self, forKey: .action)
            detail = try container.decodeIfPresent(String.self, forKey: .detail)
            var workoutDecodeError: Error?
            do {
                workout = try container.decodeIfPresent(CreateWorkout.self, forKey: .workout)
            } catch {
                workout = nil
                workoutDecodeError = error
            }

            // Model outputs sometimes flatten a create payload as
            // { action:create, workout:"Easy", blocks:[...] } or
            // { action:create, kind:"easy", blocks:[...] }. Normalize that
            // obvious shape so the user sees a real confirmation card instead
            // of a low-level JSON "missing data" failure.
            if (action == .create || action == .replace), workout == nil,
               let blocks = try? container.decodeIfPresent([CreateWorkout.Block].self, forKey: .blocks),
               let kind = Self.decodeCreateKind(from: container) {
                workout = CreateWorkout(kind: kind, blocks: blocks)
            }

            // A workout that is present but malformed (a missing or wrong-typed
            // field in the nested blocks/steps) must not be reported as an
            // absent workout — that hides which field is wrong. When the flatten
            // fallback cannot salvage it, surface the real decode error so the
            // coach and the retry loop see the exact field.
            if workout == nil, container.contains(.workout), let workoutDecodeError,
               action == .create || action == .replace {
                throw workoutDecodeError
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encode(action, forKey: .action)
            try container.encodeIfPresent(detail, forKey: .detail)
            try container.encodeIfPresent(workout, forKey: .workout)
        }

        private struct WorkoutKindOnly: Decodable {
            var kind: String
        }

        private static func decodeCreateKind(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
            let raw = (try? container.decodeIfPresent(String.self, forKey: .kind))
                ?? (try? container.decodeIfPresent(String.self, forKey: .workout))
                ?? (try? container.decodeIfPresent(WorkoutKindOnly.self, forKey: .workout))?.kind
            guard let raw else { return nil }
            let lowercased = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowercased.contains("interval") { return "intervals" }
            if lowercased.contains("tempo") { return "tempo" }
            if lowercased.contains("long") { return "long" }
            if lowercased.contains("easy") || lowercased.contains("recovery") { return "easy" }
            return lowercased
        }
    }

    /// A structured workout the coach asked the app to build. Only shape and
    /// zones come from the model; the app resolves every pace itself.
    struct CreateWorkout: Codable, Equatable {
        var kind: String
        var blocks: [Block]

        struct Block: Codable, Equatable {
            var repeatCount: Int
            var steps: [Step]

            enum CodingKeys: String, CodingKey {
                case repeatCount = "repeat_count"
                case steps
            }
        }

        struct Step: Codable, Equatable {
            var role: String
            var targetType: String
            var targetValue: Double
            var paceZone: String

            enum CodingKeys: String, CodingKey {
                case role
                case targetType = "target_type"
                case targetValue = "target_value"
                case paceZone = "pace_zone"
            }
        }
    }
}

struct AppliedAdjustment: Equatable {
    var summary: String
}

struct PlanEditPreflight: Equatable {
    var summary: String
    var warnings: [PlanValidator.Issue]
}


@MainActor
enum CoachTools {
    static let toolName = "propose_plan_adjustment"
    /// Bounds untrusted batches before any allocation or persistence.
    static let maxChangesPerProposal = 5
    static let staleReplacementMessage = ReplacementError.staleTargetMessage

    enum ReplacementError: LocalizedError, Equatable {
        case staleTarget

        static let staleTargetMessage = "That scheduled workout changed before confirmation. Please ask again."

        var errorDescription: String? {
            switch self {
            case .staleTarget:
                return Self.staleTargetMessage
            }
        }
    }

    static var tool: ClaudeTool {
        ClaudeTool(
            name: toolName,
            description: """
            Propose safe edits to the user's planned workouts, or create a new structured workout \
            on a free training day. This is the only supported way for the coach to change the \
            app Calendar and downstream intervals.icu workouts. Do not output ICS/iCalendar files \
            or calendar import instructions. The app validates every proposal (dates, collisions, \
            volume, intensity spacing), sets paces when it has enough recent runs, and otherwise \
            shows a note before applying it.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "changes": .object([
                        "type": .string("array"),
                        "minItems": .number(1),
                        "maxItems": .number(Double(maxChangesPerProposal)),
                        "items": changeSchema
                    ])
                ]),
                "required": .array([.string("changes")])
            ])
        )
    }

    private static var changeSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "date": .object([
                    "type": .string("string"),
                    "description": .string("Absolute local workout date, formatted YYYY-MM-DD")
                ]),
                "action": .object([
                    "type": .string("string"),
                    "enum": .array(["swap", "downgrade", "rest", "move", "create", "replace"].map(JSONValue.string)),
                    "description": .string("replace changes the existing workout on date to the supplied workout payload and must be used for requests like changing a tempo run into intervals; create adds a new workout on a free date, including an explicit rest/unavailable day; move uses date as the existing source workout day and detail as the empty target day; swap/rest/downgrade edit the workout already on date")
                ]),
                "detail": .object([
                    "type": .string("string"),
                    "description": .string("Target date as YYYY-MM-DD; required for swap and move, forbidden otherwise. For move, this is the destination day, not another existing workout, and it may be a rest/unavailable day.")
                ]),
                "workout": workoutSchema
            ]),
            "required": .array(["date", "action"].map(JSONValue.string))
        ])
    }

    private static var workoutSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "description": .string("Required for action=create and action=replace; forbidden otherwise. Race workouts cannot be created or used as replacements."),
            "properties": .object([
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array(["easy", "long", "tempo", "threshold", "intervals"].map(JSONValue.string))
                ]),
                "blocks": .object([
                    "type": .string("array"),
                    "minItems": .number(1),
                    "maxItems": .number(Double(WorkoutFactory.Limits.maxBlocks)),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "repeat_count": .object([
                                "type": .string("integer"),
                                "minimum": .number(1),
                                "maximum": .number(Double(WorkoutFactory.Limits.maxRepeatCount)),
                                "description": .string("How many times the steps in this block repeat")
                            ]),
                            "steps": .object([
                                "type": .string("array"),
                                "minItems": .number(1),
                                "maxItems": .number(Double(WorkoutFactory.Limits.maxStepsPerBlock)),
                                "items": stepSchema
                            ])
                        ]),
                        "required": .array(["repeat_count", "steps"].map(JSONValue.string))
                    ])
                ])
            ]),
            "required": .array(["kind", "blocks"].map(JSONValue.string))
        ])
    }

    private static var stepSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "role": .object([
                    "type": .string("string"),
                    "enum": .array(["warm_up", "work", "recovery", "cool_down"].map(JSONValue.string))
                ]),
                "target_type": .object([
                    "type": .string("string"),
                    "enum": .array(["distance_km", "duration_seconds"].map(JSONValue.string))
                ]),
                "target_value": .object([
                    "type": .string("number"),
                    "exclusiveMinimum": .number(0),
                    "description": .string("Kilometres for distance_km, seconds for duration_seconds")
                ]),
                "pace_zone": .object([
                    "type": .string("string"),
                    "enum": .array(["easy", "threshold", "interval", "none"].map(JSONValue.string)),
                    "description": .string("Tempo work uses threshold; interval work uses interval; everything else easy. The app supplies the actual pace.")
                ])
            ]),
            "required": .array(["role", "target_type", "target_value", "pace_zone"].map(JSONValue.string))
        ])
    }

    // MARK: - Apply

    static func summary(for proposal: PlanAdjustmentProposal) -> String {
        proposal.changes.map { change in
            switch change.action {
            case .create:
                let kind = change.workout?.kind ?? "workout"
                return "Create \(kind) on \(change.date)"
            case .rest:
                return "Rest on \(change.date)"
            case .downgrade:
                return "Downgrade \(change.date)"
            case .move:
                return "Move \(change.date) to \(change.detail ?? "another day")"
            case .replace:
                let kind = change.workout?.kind ?? "workout"
                return "Replace \(change.date) with \(kind)"
            case .swap:
                return "Swap \(change.date) with \(change.detail ?? "another day")"
            }
        }.joined(separator: "; ")
    }

    static func apply(
        proposal: PlanAdjustmentProposal,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        acknowledging: [PlanValidator.Issue] = []
    ) throws -> AppliedAdjustment {
        let candidate = try CoachPlanCandidateEngine.prepare(
            proposal: proposal,
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
        switch try CoachPlanCandidateEngine.commit(
            candidate,
            in: context,
            today: today,
            calendar: calendar,
            language: .en,
            acknowledging: acknowledging
        ) {
        case .applied(let receipt):
            return AppliedAdjustment(summary: receipt.summary)
        case .stale:
            throw ReplacementError.staleTarget
        }
    }

    /// Prepares the exact candidate later committed by Chat. Structural
    /// violations refuse staging; user-overridable load risks are returned as
    /// warnings for explicit confirmation.
    static func validateForConfirmation(
        proposal: PlanAdjustmentProposal,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> PlanEditPreflight {
        let candidate = try CoachPlanCandidateEngine.prepare(
            proposal: proposal,
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
        return PlanEditPreflight(summary: candidate.summary, warnings: candidate.warnings)
    }



    /// Exact `YYYY-MM-DD` in the app's calendar. Rejects locale text, timestamps,
    /// short fields and rollover dates (`2026-02-30`) by requiring the parsed day
    /// to render back to the same string.
    static func parseDay(_ value: String, calendar: Calendar) throws -> Date {
        func invalid() -> ValidationError { ValidationError("Invalid date \(value). Use YYYY-MM-DD.") }

        guard value.count == 10 else { throw invalid() }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { throw invalid() }

        let dayStart = calendar.startOfDay(for: date)
        guard CoachContextBuilder.day(dayStart, calendar: calendar) == value else { throw invalid() }
        return dayStart
    }

    struct ValidationError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
