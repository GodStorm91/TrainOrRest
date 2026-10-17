import Foundation
import SwiftData

struct CoachRaceCandidate: Identifiable, Equatable {
    enum Intent: Equatable {
        case add(RaceSpec)
        case update(before: RaceSpec, after: RaceSpec)
        case remove(RaceSpec)
        case rebalance
        case result(race: RaceSpec, result: RaceResultSpec)
    }

    let id: UUID
    let intent: Intent
    let change: RaceScheduleChange
    let suggestion: RacePrioritySuggestion?
    let summary: String

    init(
        id: UUID = UUID(),
        intent: Intent,
        change: RaceScheduleChange,
        suggestion: RacePrioritySuggestion?,
        summary: String
    ) {
        self.id = id
        self.intent = intent
        self.change = change
        self.suggestion = suggestion
        self.summary = summary
    }
}

@MainActor
enum CoachRaceTools {
    static let listRacesName = "list_races"
    static let proposeAddRaceName = "propose_add_race"
    static let proposeUpdateRaceName = "propose_update_race"
    static let proposeRemoveRaceName = "propose_remove_race"
    static let proposeRebalanceForRacesName = "propose_rebalance_for_races"
    static let recordRaceResultName = "record_race_result"

    static let listRaces = ClaudeTool(
        name: listRacesName,
        description: "List the athlete's registered races and their deterministic timing context.",
        inputSchema: emptySchema
    )

    static let proposeAddRace = ClaudeTool(
        name: proposeAddRaceName,
        description: "Preview adding a race to the season. This tool never saves. Use an absolute local calendar date.",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Race name.")
                ]),
                "date": dateSchema,
                "distance_meters": .object([
                    "type": .string("number"),
                    "description": .string("Race distance in meters.")
                ]),
                "target_time_seconds": .object([
                    "type": .string("number"),
                    "description": .string("Optional target finish time in seconds.")
                ]),
                "priority": prioritySchema
            ]),
            "required": .array(["name", "date", "distance_meters"].map(JSONValue.string))
        ])
    )

    static let proposeUpdateRace = ClaudeTool(
        name: proposeUpdateRaceName,
        description: "Preview updating a registered race. This tool never saves. Include only fields that change.",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "race_id": raceIDSchema,
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Updated race name.")
                ]),
                "date": dateSchema,
                "distance_meters": .object([
                    "type": .string("number"),
                    "description": .string("Updated race distance in meters.")
                ]),
                "target_time_seconds": .object([
                    "type": .string("number"),
                    "description": .string("Updated target finish time in seconds.")
                ]),
                "priority": prioritySchema
            ]),
            "required": .array(["race_id"].map(JSONValue.string))
        ])
    )

    static let proposeRemoveRace = ClaudeTool(
        name: proposeRemoveRaceName,
        description: "Preview removing a registered race. This tool never saves.",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "race_id": raceIDSchema
            ]),
            "required": .array(["race_id"].map(JSONValue.string))
        ])
    )

    static let proposeRebalanceForRaces = ClaudeTool(
        name: proposeRebalanceForRacesName,
        description: "Preview the deterministic schedule changes for the registered race season. This tool never saves.",
        inputSchema: emptySchema
    )

    static let recordRaceResult = ClaudeTool(
        name: recordRaceResultName,
        description: "Preview recording a completed race result. This tool never saves.",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "race_id": raceIDSchema,
                "finish_time_seconds": .object([
                    "type": .string("number"),
                    "description": .string("Recorded finish time in seconds.")
                ]),
                "average_heart_rate": .object([
                    "type": .string("number"),
                    "description": .string("Optional average heart rate in beats per minute.")
                ])
            ]),
            "required": .array(["race_id", "finish_time_seconds"].map(JSONValue.string))
        ])
    )

    static let tools = [
        listRaces,
        proposeAddRace,
        proposeUpdateRace,
        proposeRemoveRace,
        proposeRebalanceForRaces,
        recordRaceResult
    ]

    enum Outcome {
        case text(String)
        case candidate(CoachRaceCandidate)
    }

    struct ListRacesPayload: Codable, Equatable {}

    struct ProposeAddRacePayload: Codable, Equatable {
        var name: String
        var date: String
        var distanceMeters: Double
        var targetTimeSeconds: Double?
        var priority: RacePriority?

        enum CodingKeys: String, CodingKey {
            case name, date, priority
            case distanceMeters = "distance_meters"
            case targetTimeSeconds = "target_time_seconds"
        }
    }

    struct ProposeUpdateRacePayload: Codable, Equatable {
        var raceID: String
        var name: String?
        var date: String?
        var distanceMeters: Double?
        var targetTimeSeconds: Double?
        var priority: RacePriority?

        enum CodingKeys: String, CodingKey {
            case name, date, priority
            case raceID = "race_id"
            case distanceMeters = "distance_meters"
            case targetTimeSeconds = "target_time_seconds"
        }
    }

    struct ProposeRemoveRacePayload: Codable, Equatable {
        var raceID: String

        enum CodingKeys: String, CodingKey {
            case raceID = "race_id"
        }
    }

    struct ProposeRebalanceForRacesPayload: Codable, Equatable {}

    struct RecordRaceResultPayload: Codable, Equatable {
        var raceID: String
        var finishTimeSeconds: Double
        var averageHeartRate: Double?

        enum CodingKeys: String, CodingKey {
            case raceID = "race_id"
            case finishTimeSeconds = "finish_time_seconds"
            case averageHeartRate = "average_heart_rate"
        }
    }

    static func contains(_ name: String) -> Bool {
        tools.contains { $0.name == name }
    }

    static func handle(
        name: String,
        input: JSONValue,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        language: CoachLanguage
    ) throws -> Outcome {
        let season = try RaceSeasonStore.season(in: context)

        switch name {
        case listRacesName:
            _ = try input.decoded(ListRacesPayload.self)
            return .text(try encodedRaceList(season.races, today: today, calendar: calendar))
        case proposeAddRaceName:
            let payload = try input.decoded(ProposeAddRacePayload.self)
            let date = try CoachTools.parseDay(payload.date, calendar: calendar)
            let suggestion = payload.priority == nil
                ? RaceScheduler.suggestPriority(for: date, races: season.races, today: today, calendar: calendar)
                : nil
            let race = RaceSpec(
                name: payload.name,
                date: date,
                distanceMeters: payload.distanceMeters,
                targetTimeSeconds: payload.targetTimeSeconds,
                priority: payload.priority ?? suggestion!.priority
            )
            return .candidate(try candidate(
                intent: .add(race),
                races: projectedRaces(season.races, replacing: race),
                suggestion: suggestion,
                in: context,
                today: today,
                calendar: calendar,
                language: language
            ))
        case proposeUpdateRaceName:
            let payload = try input.decoded(ProposeUpdateRacePayload.self)
            let raceID = try identifier(payload.raceID)
            guard let before = season.races.first(where: { $0.id == raceID }) else {
                throw CoachTools.ValidationError("The race was not found.")
            }
            let date: Date
            if let value = payload.date {
                date = try CoachTools.parseDay(value, calendar: calendar)
            } else {
                date = before.date
            }
            let after = RaceSpec(
                id: before.id,
                name: payload.name ?? before.name,
                date: date,
                distanceMeters: payload.distanceMeters ?? before.distanceMeters,
                targetTimeSeconds: payload.targetTimeSeconds ?? before.targetTimeSeconds,
                priority: payload.priority ?? before.priority,
                notes: before.notes,
                status: before.status,
                result: before.result
            )
            return .candidate(try candidate(
                intent: .update(before: before, after: after),
                races: projectedRaces(season.races, replacing: after),
                suggestion: nil,
                in: context,
                today: today,
                calendar: calendar,
                language: language
            ))
        case proposeRemoveRaceName:
            let payload = try input.decoded(ProposeRemoveRacePayload.self)
            let raceID = try identifier(payload.raceID)
            guard let race = season.races.first(where: { $0.id == raceID }) else {
                throw CoachTools.ValidationError("The race was not found.")
            }
            return .candidate(try candidate(
                intent: .remove(race),
                races: season.races.filter { $0.id != race.id },
                suggestion: nil,
                in: context,
                today: today,
                calendar: calendar,
                language: language
            ))
        case proposeRebalanceForRacesName:
            _ = try input.decoded(ProposeRebalanceForRacesPayload.self)
            return .candidate(try candidate(
                intent: .rebalance,
                races: season.races,
                suggestion: nil,
                in: context,
                today: today,
                calendar: calendar,
                language: language
            ))
        case recordRaceResultName:
            let payload = try input.decoded(RecordRaceResultPayload.self)
            let raceID = try identifier(payload.raceID)
            guard let race = season.races.first(where: { $0.id == raceID }) else {
                throw CoachTools.ValidationError("The race was not found.")
            }
            let result = RaceResultSpec(
                finishTimeSeconds: payload.finishTimeSeconds,
                averageHeartRate: payload.averageHeartRate
            )
            let completedRace = RaceSpec(
                id: race.id,
                name: race.name,
                date: race.date,
                distanceMeters: race.distanceMeters,
                targetTimeSeconds: race.targetTimeSeconds,
                priority: race.priority,
                notes: race.notes,
                status: .completed,
                result: result
            )
            return .candidate(try candidate(
                intent: .result(race: race, result: result),
                races: projectedRaces(season.races, replacing: completedRace),
                suggestion: nil,
                in: context,
                today: today,
                calendar: calendar,
                language: language
            ))
        default:
            throw CoachTools.ValidationError("Unsupported race tool \(name).")
        }
    }

    @discardableResult
    static func confirm(
        _ candidate: CoachRaceCandidate,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        now: Date
    ) throws -> UUID? {
        switch candidate.intent {
        case .add(let race):
            _ = try RaceSeasonStore.insert(race, in: context, now: now)
        case .update(_, let after):
            try RaceSeasonStore.update(id: after.id, to: after, in: context, now: now)
        case .remove(let race):
            try RaceSeasonStore.remove(id: race.id, in: context)
        case .rebalance:
            break
        case .result(let race, let result):
            try RaceSeasonStore.recordResult(id: race.id, result: result, in: context, now: now)
        }

        try RaceSeasonStore.syncGoalToARace(in: context, calendar: calendar)
        return try RacePlanApplier.apply(
            candidate.change,
            in: context,
            today: today,
            calendar: calendar,
            summary: candidate.summary
        )
    }

    private static let emptySchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "properties": .object([:]),
        "required": .array([])
    ])

    private static let dateSchema: JSONValue = .object([
        "type": .string("string"),
        "description": .string("Absolute local calendar date, formatted YYYY-MM-DD.")
    ])

    private static let prioritySchema: JSONValue = .object([
        "type": .string("string"),
        "enum": .array(["A", "B", "C"].map(JSONValue.string)),
        "description": .string("Race priority: A, B, or C.")
    ])

    private static let raceIDSchema: JSONValue = .object([
        "type": .string("string"),
        "description": .string("Registered race identifier.")
    ])

    private struct RaceListEntry: Encodable {
        var id: String
        var name: String
        var date: String
        var distanceMeters: Double
        var priority: String
        var status: String
        var daysUntil: Int

        enum CodingKeys: String, CodingKey {
            case id, name, date, priority, status
            case distanceMeters = "distance_meters"
            case daysUntil = "days_until"
        }
    }

    private static func encodedRaceList(
        _ races: [RaceSpec],
        today: Date,
        calendar: Calendar
    ) throws -> String {
        let todayDay = calendar.startOfDay(for: today)
        let entries = races.map { race in
            RaceListEntry(
                id: race.id.uuidString,
                name: race.name,
                date: CoachContextBuilder.day(race.date, calendar: calendar),
                distanceMeters: race.distanceMeters,
                priority: race.priority.rawValue,
                status: race.status.rawValue,
                daysUntil: calendar.dateComponents(
                    [.day],
                    from: todayDay,
                    to: calendar.startOfDay(for: race.date)
                ).day ?? 0
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(entries), as: UTF8.self)
    }

    private static func candidate(
        intent: CoachRaceCandidate.Intent,
        races: [RaceSpec],
        suggestion: RacePrioritySuggestion?,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        language: CoachLanguage
    ) throws -> CoachRaceCandidate {
        let change = try RacePlanApplier.preview(in: context, races: races, today: today, calendar: calendar)
        return CoachRaceCandidate(
            intent: intent,
            change: change,
            suggestion: suggestion,
            summary: summary(for: intent, language: language)
        )
    }

    private static func projectedRaces(_ races: [RaceSpec], replacing replacement: RaceSpec) -> [RaceSpec] {
        var projected = races.filter { $0.id != replacement.id }
        projected.append(replacement)
        guard replacement.priority == .a, replacement.status == .upcoming else {
            return projected.sorted { $0.date < $1.date }
        }
        projected = projected.map { race in
            guard race.id != replacement.id,
                  race.priority == .a,
                  race.status == .upcoming
            else { return race }
            return RaceSpec(
                id: race.id,
                name: race.name,
                date: race.date,
                distanceMeters: race.distanceMeters,
                targetTimeSeconds: race.targetTimeSeconds,
                priority: .b,
                notes: race.notes,
                status: race.status,
                result: race.result
            )
        }
        return projected.sorted { $0.date < $1.date }
    }

    private static func identifier(_ value: String) throws -> UUID {
        guard let identifier = UUID(uuidString: value) else {
            throw CoachTools.ValidationError("Invalid race identifier.")
        }
        return identifier
    }

    private static func summary(for intent: CoachRaceCandidate.Intent, language: CoachLanguage) -> String {
        switch intent {
        case .add(let race), .remove(let race), .result(let race, _):
            return "\(language.season.raceDetailTitle): \(race.name)"
        case .update(_, let after):
            return "\(language.season.raceDetailTitle): \(after.name)"
        case .rebalance:
            return language.season.seasonTitle
        }
    }
}
