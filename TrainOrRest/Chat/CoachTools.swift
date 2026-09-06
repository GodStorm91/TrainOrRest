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
            volume, intensity spacing) and resolves all paces itself before applying it.
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
        guard !proposal.changes.isEmpty else { throw ValidationError("No changes proposed.") }
        guard proposal.changes.count <= maxChangesPerProposal else {
            throw ValidationError("At most \(maxChangesPerProposal) changes per proposal.")
        }
        for change in proposal.changes { try validateFields(change) }

        let creates = proposal.changes.filter { $0.action == .create }
        if creates.count == proposal.changes.count {
            return try applyCreates(
                creates,
                in: context,
                today: today,
                calendar: calendar,
                acknowledging: acknowledging
            )
        }

        var spec = try currentPlanSpec(in: context, today: today, calendar: calendar)
        let baseline = spec
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }
        let dayStart = calendar.startOfDay(for: today)
        let raceDay = calendar.startOfDay(for: spec.goal.raceDate)

        var summaries: [String] = []
        var proposedCreateDates: Set<Date> = []
        var editedDates: Set<Date> = []

        // Apply non-create edits first, so a request like "make today rest and
        // add an easy run tomorrow" can be represented naturally as one safe
        // proposal. The final candidate plan is still validated as a whole.
        for change in proposal.changes where change.action != .create {
            let date = try parseDay(change.date, calendar: calendar)
            guard date >= dayStart else { throw ValidationError("Cannot edit past workouts.") }
            editedDates.insert(date)
            summaries.append(try apply(change, date: date, paces: paces, to: &spec, calendar: calendar))
        }

        for change in proposal.changes where change.action == .create {
            let date = try parseDay(change.date, calendar: calendar)
            guard date >= dayStart else { throw ValidationError("Cannot create a workout in the past.") }
            guard !editedDates.contains(date) else {
                throw ValidationError("Create the replacement workout on a different date, or ask to replace the workout explicitly.")
            }
            guard date != raceDay else { throw ValidationError("Race day cannot hold another workout.") }
            guard date < raceDay else { throw ValidationError("\(change.date) is after race day.") }
            guard proposedCreateDates.insert(date).inserted else {
                throw ValidationError("Two workouts proposed for \(change.date).")
            }
            guard locate(date, in: spec) == nil else {
                throw ValidationError("\(change.date) already has a workout.")
            }
            guard let weekIndex = weekIndex(for: date, in: spec, calendar: calendar) else {
                throw ValidationError("\(change.date) is outside the training plan.")
            }
            guard let payload = change.workout else { throw ValidationError("create requires a workout.") }
            let built = try WorkoutFactory.build(try recipe(from: payload), paces: paces)
            var week = spec.weeks[weekIndex]
            week.workouts.append(PlannedWorkoutSpec(
                date: date,
                kind: built.kind,
                distanceKm: built.distanceKm,
                paceBand: built.paceBand,
                details: built.details,
                structure: built.structure
            ))
            week.workouts.sort { $0.date < $1.date }
            week.targetVolumeKm = PlanGenerator.rounded(week.targetVolumeKm + built.distanceKm)
            spec.weeks[weekIndex] = week
            summaries.append("Created \(built.kind.rawValue) on \(change.date)")
        }

        let peakCap = fitness.map { max($0.weeklyVolumeKm * 1.35, $0.longestRecentRunKm * 2) }
        let issues = introducedValidationIssues(
            in: spec, comparedTo: baseline, calendar: calendar, peakCapKm: peakCap
        )
        try rejectUnacknowledgedIssues(issues, acknowledging: acknowledging)

        try persist(spec, in: context, from: today, calendar: calendar)
        try context.save()
        return AppliedAdjustment(summary: summaries.joined(separator: "; "))
    }

    /// Read-only preflight for proposals that will be shown behind an Apply
    /// button. Structural violations refuse staging; user-overridable load
    /// risks are returned as warnings for the confirmation card.
    static func validateForConfirmation(
        proposal: PlanAdjustmentProposal,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> PlanEditPreflight {
        guard !proposal.changes.isEmpty else { throw ValidationError("No changes proposed.") }
        guard proposal.changes.count <= maxChangesPerProposal else {
            throw ValidationError("At most \(maxChangesPerProposal) changes per proposal.")
        }
        for change in proposal.changes { try validateFields(change) }

        let creates = proposal.changes.filter { $0.action == .create }
        if creates.count == proposal.changes.count {
            let candidatePlan = try createCandidates(
                creates,
                in: context,
                today: today,
                calendar: calendar
            )
            let summary = candidatePlan.candidates
                .map { "Created \($0.built.kind.rawValue) on \(CoachContextBuilder.day($0.date, calendar: calendar))" }
                .joined(separator: "; ")
            return PlanEditPreflight(
                summary: summary,
                warnings: try warningsForConfirmation(from: candidatePlan.issues)
            )

        }

        var spec = try currentPlanSpec(in: context, today: today, calendar: calendar)
        let baseline = spec
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }
        let dayStart = calendar.startOfDay(for: today)
        let raceDay = calendar.startOfDay(for: spec.goal.raceDate)

        var summaries: [String] = []
        var proposedCreateDates: Set<Date> = []
        var editedDates: Set<Date> = []

        for change in proposal.changes where change.action != .create {
            let date = try parseDay(change.date, calendar: calendar)
            guard date >= dayStart else { throw ValidationError("Cannot edit past workouts.") }
            editedDates.insert(date)
            summaries.append(try apply(change, date: date, paces: paces, to: &spec, calendar: calendar))
        }

        for change in proposal.changes where change.action == .create {
            let date = try parseDay(change.date, calendar: calendar)
            guard date >= dayStart else { throw ValidationError("Cannot create a workout in the past.") }
            guard !editedDates.contains(date) else {
                throw ValidationError("Create the replacement workout on a different date, or ask to replace the workout explicitly.")
            }
            guard date != raceDay else { throw ValidationError("Race day cannot hold another workout.") }
            guard date < raceDay else { throw ValidationError("\(change.date) is after race day.") }
            guard proposedCreateDates.insert(date).inserted else {
                throw ValidationError("Two workouts proposed for \(change.date).")
            }
            guard locate(date, in: spec) == nil else {
                throw ValidationError("\(change.date) already has a workout.")
            }
            guard let weekIndex = weekIndex(for: date, in: spec, calendar: calendar) else {
                throw ValidationError("\(change.date) is outside the training plan.")
            }
            guard let payload = change.workout else { throw ValidationError("create requires a workout.") }
            let built = try WorkoutFactory.build(try recipe(from: payload), paces: paces)
            var week = spec.weeks[weekIndex]
            week.workouts.append(PlannedWorkoutSpec(
                date: date,
                kind: built.kind,
                distanceKm: built.distanceKm,
                paceBand: built.paceBand,
                details: built.details,
                structure: built.structure
            ))
            week.workouts.sort { $0.date < $1.date }
            week.targetVolumeKm = PlanGenerator.rounded(week.targetVolumeKm + built.distanceKm)
            spec.weeks[weekIndex] = week
            summaries.append("Created \(built.kind.rawValue) on \(change.date)")
        }

        let peakCap = fitness.map { max($0.weeklyVolumeKm * 1.35, $0.longestRecentRunKm * 2) }
        let issues = introducedValidationIssues(
            in: spec, comparedTo: baseline, calendar: calendar, peakCapKm: peakCap
        )
        return PlanEditPreflight(
            summary: summaries.joined(separator: "; "),
            warnings: try warningsForConfirmation(from: issues)
        )
    }

    private static func warningsForConfirmation(
        from issues: [PlanValidator.Issue]
    ) throws -> [PlanValidator.Issue] {
        let blockingIssues = issues.filter { !$0.kind.isUserOverridableLoadRisk }
        guard blockingIssues.isEmpty else {
            throw ValidationError(blockingIssues.map(\.message).joined(separator: "; "))
        }
        return issues
    }

    private static func rejectUnacknowledgedIssues(
        _ issues: [PlanValidator.Issue],
        acknowledging acknowledgements: [PlanValidator.Issue]
    ) throws {
        let acknowledgedLoadRisks = acknowledgements.filter { $0.kind.isUserOverridableLoadRisk }
        let remainingIssues = issues.filter {
            !$0.kind.isUserOverridableLoadRisk || !acknowledgedLoadRisks.contains($0)
        }
        guard remainingIssues.isEmpty else {
            throw ValidationError(remainingIssues.map(\.message).joined(separator: "; "))
        }
    }

    /// Action-dependent field rules. The JSON Schema cannot express these, so
    /// Swift stays authoritative.
    private static func validateFields(_ change: PlanAdjustmentProposal.Change) throws {
        switch change.action {
        case .create, .replace:
            guard change.workout != nil else { throw ValidationError("\(change.action.rawValue) requires a workout.") }
            guard change.detail == nil else { throw ValidationError("\(change.action.rawValue) does not take a detail date.") }
        case .move, .swap:
            guard change.detail != nil else {
                throw ValidationError("\(change.action.rawValue) requires a target date.")
            }
            guard change.workout == nil else {
                throw ValidationError("\(change.action.rawValue) does not take a workout.")
            }
        case .rest, .downgrade:
            guard change.detail == nil, change.workout == nil else {
                throw ValidationError("\(change.action.rawValue) takes only a date.")
            }
        }
    }

    // MARK: - Create

    private struct Candidate {
        var date: Date
        var built: BuiltWorkout
        var weekIndex: Int
    }

    /// Returns a replacement that needs explicit user confirmation when one
    /// create targets an eligible occupied day. This is intentionally read-only:
    /// the coordinator owns the only destructive commit path.
    static func pendingReplacement(
        for proposal: PlanAdjustmentProposal,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        language: CoachLanguage
    ) throws -> PendingWorkoutReplacement? {
        guard proposal.changes.count == 1,
              let change = proposal.changes.first,
              change.action == .create || change.action == .replace else { return nil }
        try validateFields(change)

        guard let goal = try PlanStore.activeGoal(in: context)?.spec,
              let plan = try PlanStore.activePlan(in: context) else {
            throw ValidationError("No active plan.")
        }
        let date = try parseDay(change.date, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        guard date >= todayStart else { return nil }
        guard date != raceDay, date < raceDay else { return nil }

        var spec = try currentPlanSpec(in: context, today: today, calendar: calendar)
        guard let location = locate(date, in: spec) else { return nil }
        let rows = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let matchingRows = rows.filter { calendar.isDate($0.date, inSameDayAs: date) }
        guard matchingRows.count == 1,
              let existing = matchingRows.first,
              existing.kind != .race,
              existing.plan === plan,
              let existingKind = existing.kind,
              let payload = change.workout else { return nil }

        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }
        let built = try WorkoutFactory.build(try recipe(from: payload), paces: paces)
        let old = spec.weeks[location.week].workouts[location.workout]
        if old.kind == built.kind && abs(old.distanceKm - built.distanceKm) < 0.01 {
            throw ValidationError("No change to apply; the proposed workout matches the current one.")
        }
        spec.weeks[location.week].workouts[location.workout] = PlannedWorkoutSpec(
            date: date,
            kind: built.kind,
            distanceKm: built.distanceKm,
            paceBand: built.paceBand,
            details: built.details,
            structure: built.structure
        )
        let delta = built.distanceKm - old.distanceKm
        spec.weeks[location.week].targetVolumeKm = PlanGenerator.rounded(
            spec.weeks[location.week].targetVolumeKm + delta
        )

        let existingSummary = WorkoutReplacementSummary(kind: existingKind, distanceKm: existing.distanceKm)
        let proposedSummary = WorkoutReplacementSummary(kind: built.kind, distanceKm: built.distanceKm)
        return PendingWorkoutReplacement(
            expected: WorkoutReplacementFingerprint(workout: existing),
            date: date,
            payload: payload,
            presentation: language.replacementPresentation(
                date: date, existing: existingSummary, proposed: proposedSummary
            ),
            existing: existingSummary,
            proposed: proposedSummary,
            volumeDeltaKm: PlanGenerator.rounded(delta),
            appliedSummary: language.replacementAppliedSummary(
                date: date, existing: existingSummary, proposed: proposedSummary
            ),
            successMessage: language.replacementSuccessMessage(
                date: date, proposed: proposedSummary
            ),
            failureMessage: language.replacementFailureMessage
        )
    }

    /// Rebuilds and commits a previously confirmed replacement in an isolated
    /// context. Every identity and plan invariant is checked again because the
    /// alert may have been visible while the schedule changed elsewhere.
    static func confirmReplacement(
        _ pending: PendingWorkoutReplacement,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        guard let goal = try PlanStore.activeGoal(in: context)?.spec,
              let plan = try PlanStore.activePlan(in: context) else {
            throw ValidationError("The active plan is no longer available.")
        }
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        guard pending.date < raceDay else {
            throw ValidationError("That date is no longer available for a workout.")
        }
        let rows = try context.fetch(FetchDescriptor<PlannedWorkout>())
        guard let existing = rows.first(where: { $0.uuid == pending.expected.uuid }),
              pending.expected.matches(existing),
              calendar.isDate(existing.date, inSameDayAs: pending.date),
              pending.date >= calendar.startOfDay(for: today),
              existing.kind != .race,
              existing.plan === plan else {
            throw ReplacementError.staleTarget
        }

        var spec = try currentPlanSpec(in: context, today: today, calendar: calendar)
        guard let location = locate(pending.date, in: spec) else {
            throw ValidationError("That scheduled workout is no longer available.")
        }
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }
        let built = try WorkoutFactory.build(try recipe(from: pending.payload), paces: paces)
        let old = spec.weeks[location.week].workouts[location.workout]
        spec.weeks[location.week].workouts[location.workout] = PlannedWorkoutSpec(
            date: pending.date,
            kind: built.kind,
            distanceKm: built.distanceKm,
            paceBand: built.paceBand,
            details: built.details,
            structure: built.structure
        )
        spec.weeks[location.week].targetVolumeKm = PlanGenerator.rounded(
            spec.weeks[location.week].targetVolumeKm + built.distanceKm - old.distanceKm
        )

        let weekTargetVolumeKmBefore = plan.weekTargetVolumesKm[location.week]
        let weekTargetVolumeKmAfter = spec.weeks[location.week].targetVolumeKm
        let edit = PlanEdit(
            appliedAt: today,
            workout: existing,
            weekTargetVolumeKmBefore: weekTargetVolumeKmBefore,
            afterKindRaw: built.kind.rawValue,
            afterDistanceKm: built.distanceKm,
            afterPaceFastSecondsPerKm: built.paceBand?.fastSecondsPerKm,
            afterPaceSlowSecondsPerKm: built.paceBand?.slowSecondsPerKm,
            afterDetails: built.details,
            afterStructure: built.structure,
            afterStatusRaw: WorkoutStatus.planned.rawValue,
            afterManuallyOverridden: true,
            afterMatchedActivityUUID: nil,
            weekTargetVolumeKmAfter: weekTargetVolumeKmAfter
        )
        context.insert(edit)

        existing.kindRaw = built.kind.rawValue
        existing.distanceKm = built.distanceKm
        existing.paceFastSecondsPerKm = built.paceBand?.fastSecondsPerKm
        existing.paceSlowSecondsPerKm = built.paceBand?.slowSecondsPerKm
        existing.details = built.details
        existing.structure = built.structure
        existing.status = .planned
        existing.manuallyOverridden = true
        existing.matchedActivityUUID = nil
        existing.isScheduleLocked = false
        var targets = plan.weekTargetVolumesKm
        targets[location.week] = weekTargetVolumeKmAfter
        plan.weekTargetVolumesKm = targets
        context.insert(ChatMessage(
            role: .assistant,
            text: pending.successMessage,
            date: .now,
            appliedAdjustment: pending.appliedSummary
        ))
        try context.save()
    }

    /// Creates are assembled against a copied plan before their validation
    /// outcome is either surfaced for confirmation or acknowledged for commit.
    private struct CreateCandidatePlan {
        var plan: TrainingPlan
        var spec: TrainingPlanSpec
        var candidates: [Candidate]
        var issues: [PlanValidator.Issue]
    }

    private static func applyCreates(
        _ changes: [PlanAdjustmentProposal.Change],
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        acknowledging: [PlanValidator.Issue]
    ) throws -> AppliedAdjustment {
        let candidatePlan = try createCandidates(
            changes,
            in: context,
            today: today,
            calendar: calendar
        )
        try rejectUnacknowledgedIssues(candidatePlan.issues, acknowledging: acknowledging)
        try insert(
            candidatePlan.candidates,
            into: candidatePlan.plan,
            spec: candidatePlan.spec,
            in: context,
            calendar: calendar
        )
        let summary = candidatePlan.candidates
            .map { "Created \($0.built.kind.rawValue) on \(CoachContextBuilder.day($0.date, calendar: calendar))" }
            .joined(separator: "; ")
        return AppliedAdjustment(summary: summary)
    }

    private static func createCandidates(
        _ changes: [PlanAdjustmentProposal.Change],
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> CreateCandidatePlan {
        guard let goal = try PlanStore.activeGoal(in: context)?.spec,
              let plan = try PlanStore.activePlan(in: context) else {
            throw ValidationError("No active plan.")
        }
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }
        var spec = try currentPlanSpec(in: context, today: today, calendar: calendar)
        let baseline = spec

        let dayStart = calendar.startOfDay(for: today)
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        var candidates: [Candidate] = []
        var proposedDates: Set<Date> = []

        for change in changes {
            let date = try parseDay(change.date, calendar: calendar)
            guard date >= dayStart else { throw ValidationError("Cannot create a workout in the past.") }
            guard date != raceDay else { throw ValidationError("Race day cannot hold another workout.") }
            guard date < raceDay else { throw ValidationError("\(change.date) is after race day.") }
            guard proposedDates.insert(date).inserted else {
                throw ValidationError("Two workouts proposed for \(change.date).")
            }
            guard locate(date, in: spec) == nil else {
                throw ValidationError("\(change.date) already has a workout.")
            }
            guard let weekIndex = weekIndex(for: date, in: spec, calendar: calendar) else {
                throw ValidationError("\(change.date) is outside the training plan.")
            }
            guard let payload = change.workout else { throw ValidationError("create requires a workout.") }
            let built = try WorkoutFactory.build(try recipe(from: payload), paces: paces)
            candidates.append(Candidate(date: date, built: built, weekIndex: weekIndex))
        }

        // Candidate plan: add each workout and raise its week's target volume so
        // the existing volume, ramp and taper checks see the real load.
        for candidate in candidates {
            var week = spec.weeks[candidate.weekIndex]
            week.workouts.append(PlannedWorkoutSpec(
                date: candidate.date,
                kind: candidate.built.kind,
                distanceKm: candidate.built.distanceKm,
                paceBand: candidate.built.paceBand,
                details: candidate.built.details,
                structure: candidate.built.structure
            ))
            week.workouts.sort { $0.date < $1.date }
            week.targetVolumeKm = PlanGenerator.rounded(week.targetVolumeKm + candidate.built.distanceKm)
            spec.weeks[candidate.weekIndex] = week
        }

        let peakCap = fitness.map { max($0.weeklyVolumeKm * 1.35, $0.longestRecentRunKm * 2) }
        let issues = introducedValidationIssues(
            in: spec, comparedTo: baseline, calendar: calendar, peakCapKm: peakCap
        )
        return CreateCandidatePlan(plan: plan, spec: spec, candidates: candidates, issues: issues)
    }

    /// Targeted persistence: insert the new rows and update only the affected
    /// week targets, then save once. Any failure removes everything staged.
    private static func insert(
        _ candidates: [Candidate],
        into plan: TrainingPlan,
        spec: TrainingPlanSpec,
        in context: ModelContext,
        calendar: Calendar
    ) throws {
        // Re-check collisions against the store immediately before staging.
        let existing = try context.fetch(FetchDescriptor<PlannedWorkout>())
        for candidate in candidates where existing.contains(where: {
            calendar.isDate($0.date, inSameDayAs: candidate.date)
        }) {
            throw ValidationError("A workout already exists on \(CoachContextBuilder.day(candidate.date, calendar: calendar)).")
        }

        let originalTargets = plan.weekTargetVolumesKm
        var staged: [PlannedWorkout] = []
        do {
            for candidate in candidates {
                guard let phase = plan.phase(forWeek: candidate.weekIndex) else {
                    throw ValidationError("Plan week \(candidate.weekIndex) is missing.")
                }
                let row = PlannedWorkout(
                    spec: PlannedWorkoutSpec(
                        date: candidate.date,
                        kind: candidate.built.kind,
                        distanceKm: candidate.built.distanceKm,
                        paceBand: candidate.built.paceBand,
                        details: candidate.built.details,
                        structure: candidate.built.structure
                    ),
                    weekIndex: candidate.weekIndex,
                    phase: phase
                )
                row.manuallyOverridden = true
                row.plan = plan
                context.insert(row)
                staged.append(row)
            }
            var targets = plan.weekTargetVolumesKm
            for candidate in candidates {
                targets[candidate.weekIndex] = spec.weeks[candidate.weekIndex].targetVolumeKm
            }
            plan.weekTargetVolumesKm = targets
            try context.save()
        } catch {
            for row in staged { context.delete(row) }
            plan.weekTargetVolumesKm = originalTargets
            throw error
        }
    }

    /// Existing plans can contain violations from an earlier generator or
    /// changed fitness profile. A coach edit must not be blocked by untouched
    /// historical issues, but it may never introduce or worsen one.
    private static func introducedValidationIssues(
        in candidate: TrainingPlanSpec,
        comparedTo baseline: TrainingPlanSpec,
        calendar: Calendar,
        peakCapKm: Double?
    ) -> [PlanValidator.Issue] {
        var remainingBaselineIssues = PlanValidator.validate(
            baseline, calendar: calendar, peakCapKm: peakCapKm
        )
        return PlanValidator.validate(candidate, calendar: calendar, peakCapKm: peakCapKm)
            .compactMap { issue in
                // Manual coach edits are allowed to intentionally put a one-off
                // workout on a normal rest/unavailable day. Availability guides
                // generated plans; it should not block an explicit user move or
                // create. Keep the harder guards: collisions, race day, past,
                // volume caps, distance validity and hard-session spacing.
                guard issue.kind != .workoutOnUnavailableDay else { return nil }
                guard let match = remainingBaselineIssues.firstIndex(of: issue) else { return issue }
                remainingBaselineIssues.remove(at: match)
                return nil
            }
    }

    private static func recipe(from payload: PlanAdjustmentProposal.CreateWorkout) throws -> WorkoutRecipe {
        guard let kind = WorkoutKind(rawValue: payload.kind) else {
            throw ValidationError("Unknown workout kind \(payload.kind).")
        }
        guard kind != .race else { throw ValidationError("Race workouts cannot be created.") }
        guard !payload.blocks.isEmpty, payload.blocks.count <= WorkoutFactory.Limits.maxBlocks else {
            throw ValidationError("A workout needs 1 to \(WorkoutFactory.Limits.maxBlocks) blocks.")
        }

        let blocks = try payload.blocks.map { block -> WorkoutRecipe.Block in
            guard !block.steps.isEmpty, block.steps.count <= WorkoutFactory.Limits.maxStepsPerBlock else {
                throw ValidationError("A block needs 1 to \(WorkoutFactory.Limits.maxStepsPerBlock) steps.")
            }
            return WorkoutRecipe.Block(
                repeatCount: block.repeatCount,
                steps: try block.steps.map(step)
            )
        }
        return WorkoutRecipe(kind: kind, blocks: blocks)
    }

    private static func step(_ payload: PlanAdjustmentProposal.CreateWorkout.Step) throws -> WorkoutRecipe.Step {
        guard let role = role(payload.role) else {
            throw ValidationError("Unknown step role \(payload.role).")
        }
        guard let zone = PaceZone(rawValue: payload.paceZone) else {
            throw ValidationError("Unknown pace zone \(payload.paceZone).")
        }
        switch payload.targetType {
        case "distance_km":
            return .distance(role, payload.targetValue, zone)
        case "duration_seconds":
            return .duration(role, payload.targetValue, zone)
        default:
            throw ValidationError("Unknown target type \(payload.targetType).")
        }
    }

    private static func role(_ value: String) -> WorkoutStepRole? {
        switch value {
        case "warm_up": .warmUp
        case "work": .work
        case "recovery": .recovery
        case "cool_down": .coolDown
        default: nil
        }
    }

    private static func weekIndex(for date: Date, in spec: TrainingPlanSpec, calendar: Calendar) -> Int? {
        spec.weeks.firstIndex { week in
            guard let end = calendar.date(byAdding: .day, value: 7, to: week.startDate) else { return false }
            return date >= week.startDate && date < end
        }
    }

    // MARK: - Edit actions

    private static func apply(
        _ change: PlanAdjustmentProposal.Change,
        date: Date,
        paces: TrainingPaces?,
        to spec: inout TrainingPlanSpec,
        calendar: Calendar
    ) throws -> String {
        guard let location = locate(date, in: spec) else {
            throw ValidationError("No workout on \(change.date). For move, set date to the source day that already has the workout and detail to the empty target day. To add a new workout on this date, use create with a workout payload.")
        }
        let workout = spec.weeks[location.week].workouts[location.workout]
        guard workout.kind != .race else { throw ValidationError("Race day cannot be edited.") }

        switch change.action {
        case .create:
            throw ValidationError("create is handled as its own batch.")
        case .replace:
            throw ValidationError("replace requires workout replacement confirmation.")
        case .rest:
            spec.weeks[location.week].workouts.remove(at: location.workout)
            return "Rested \(change.date)"
        case .downgrade:
            let built = WorkoutFactory.canonicalEasy(distanceKm: workout.distanceKm, paces: paces)
            spec.weeks[location.week].workouts[location.workout] = PlannedWorkoutSpec(
                date: date, kind: built.kind, distanceKm: built.distanceKm,
                paceBand: built.paceBand, details: built.details,
                structure: built.structure
            )
            return "Downgraded \(change.date) to easy"
        case .move:
            let target = try targetDay(change.detail, calendar: calendar)
            guard locate(target, in: spec) == nil else { throw ValidationError("Target date already has a workout.") }
            guard let targetWeek = weekIndex(for: target, in: spec, calendar: calendar) else {
                throw ValidationError("\(CoachContextBuilder.day(target, calendar: calendar)) is outside the training plan.")
            }
            var moved = workout
            spec.weeks[location.week].workouts.remove(at: location.workout)
            if targetWeek != location.week {
                spec.weeks[location.week].targetVolumeKm = PlanGenerator.rounded(
                    spec.weeks[location.week].targetVolumeKm - workout.distanceKm
                )
                spec.weeks[targetWeek].targetVolumeKm = PlanGenerator.rounded(
                    spec.weeks[targetWeek].targetVolumeKm + workout.distanceKm
                )
            }
            moved.date = target
            spec.weeks[targetWeek].workouts.append(moved)
            spec.weeks[targetWeek].workouts.sort { $0.date < $1.date }
            return "Moved \(change.date) to \(CoachContextBuilder.day(target, calendar: calendar))"
        case .swap:
            let target = try targetDay(change.detail, calendar: calendar)
            guard let other = locate(target, in: spec) else { throw ValidationError("No workout on target date.") }
            spec.weeks[location.week].workouts[location.workout].date = target
            spec.weeks[other.week].workouts[other.workout].date = date
            return "Swapped \(change.date) with \(CoachContextBuilder.day(target, calendar: calendar))"
        }
    }

    private static func currentPlanSpec(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> TrainingPlanSpec {
        guard let goal = try PlanStore.activeGoal(in: context)?.spec,
              let plan = try PlanStore.activePlan(in: context) else {
            throw ValidationError("No active plan.")
        }
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
        let weeks = plan.weekPhasesRaw.indices.map { index in
            let phase = TrainingPhase(rawValue: plan.weekPhasesRaw[index]) ?? .base
            let start = calendar.date(byAdding: .day, value: index * 7, to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar))!
            let rows = workouts.filter { $0.weekIndex == index }.compactMap(toSpec)
            return WeekPlan(
                startDate: start, index: index, phase: phase,
                isDownWeek: plan.weekIsDown[index],
                isPartial: index == 0 && !calendar.isDate(plan.anchorDate, inSameDayAs: start),
                targetVolumeKm: plan.weekTargetVolumesKm[index],
                workouts: rows
            )
        }
        return TrainingPlanSpec(goal: goal, anchorDate: calendar.startOfDay(for: today), weeks: weeks)
    }

    private static func persist(
        _ spec: TrainingPlanSpec,
        in context: ModelContext,
        from today: Date,
        calendar: Calendar
    ) throws {
        let dayStart = calendar.startOfDay(for: today)
        let rows = try context.fetch(FetchDescriptor<PlannedWorkout>())
        for row in rows where row.date >= dayStart && row.status == .planned && !row.manuallyOverridden {
            context.delete(row)
        }
        guard let plan = try PlanStore.activePlan(in: context) else { return }
        plan.weekTargetVolumesKm = spec.weeks.map(\.targetVolumeKm)
        for week in spec.weeks {
            for workout in week.workouts where workout.date >= dayStart {
                let row = PlannedWorkout(spec: workout, weekIndex: week.index, phase: week.phase)
                row.manuallyOverridden = true
                row.plan = plan
                context.insert(row)
            }
        }
        plan.generatedAt = today
    }

    private static func toSpec(_ row: PlannedWorkout) -> PlannedWorkoutSpec? {
        guard let kind = row.kind else { return nil }
        return PlannedWorkoutSpec(
            date: row.date, kind: kind, distanceKm: row.distanceKm,
            paceBand: row.paceBand, details: row.details, structure: row.structure
        )
    }

    private static func locate(_ date: Date, in spec: TrainingPlanSpec) -> (week: Int, workout: Int)? {
        for weekIndex in spec.weeks.indices {
            if let workoutIndex = spec.weeks[weekIndex].workouts.firstIndex(where: { $0.date == date }) {
                return (weekIndex, workoutIndex)
            }
        }
        return nil
    }

    private static func targetDay(_ value: String?, calendar: Calendar) throws -> Date {
        guard let value else { throw ValidationError("Target date is required.") }
        return try parseDay(value, calendar: calendar)
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
