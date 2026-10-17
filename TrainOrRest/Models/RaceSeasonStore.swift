import Foundation
import SwiftData

@MainActor
enum RaceSeasonStore {
    static func season(in context: ModelContext) throws -> RaceSeason {
        RaceSeason(races: try races(in: context).compactMap { $0.spec })
    }

    static func races(in context: ModelContext) throws -> [Race] {
        let descriptor = FetchDescriptor<Race>(sortBy: [SortDescriptor(\.date)])
        return try context.fetch(descriptor)
    }

    static func race(id: UUID, in context: ModelContext) throws -> Race? {
        try races(in: context).first { $0.id == id }
    }

    static func existingARace(in context: ModelContext) throws -> Race? {
        try races(in: context).first {
            $0.priorityRaw == RacePriority.a.rawValue
                && $0.statusRaw == RaceStatus.upcoming.rawValue
        }
    }

    @discardableResult
    static func insert(_ spec: RaceSpec, in context: ModelContext, now: Date) throws -> Race {
        let race = Race(spec: spec, createdAt: now, updatedAt: now)
        context.insert(race)
        try demoteOtherUpcomingARaces(excluding: race, in: context, now: now)
        try context.save()
        return race
    }

    static func update(id: UUID, to spec: RaceSpec, in context: ModelContext, now: Date) throws {
        guard let race = try race(id: id, in: context) else {
            throw StoreError.raceNotFound
        }

        race.apply(spec, updatedAt: now)
        try demoteOtherUpcomingARaces(excluding: race, in: context, now: now)
        try context.save()
    }

    static func remove(id: UUID, in context: ModelContext) throws {
        guard let race = try race(id: id, in: context) else {
            throw StoreError.raceNotFound
        }

        context.delete(race)
        try context.save()
    }

    static func recordResult(
        id: UUID,
        result: RaceResultSpec,
        in context: ModelContext,
        now: Date
    ) throws {
        guard let race = try race(id: id, in: context) else {
            throw StoreError.raceNotFound
        }

        race.resultFinishTimeSeconds = result.finishTimeSeconds
        race.resultAverageHeartRate = result.averageHeartRate
        race.resultHealthKitWorkoutID = result.healthKitWorkoutID
        race.statusRaw = RaceStatus.completed.rawValue
        race.updatedAt = now
        try context.save()
    }

    /// Set once the goal-to-race migration runs, so deleting the migrated race
    /// does not resurrect it on the next launch.
    private static let migrationMarkerKey = "race.season.goalMigrated"

    static func migrateGoalIfNeeded(
        in context: ModelContext,
        now: Date,
        calendar: Calendar,
        defaults: UserDefaults = .standard
    ) throws {
        guard !defaults.bool(forKey: migrationMarkerKey) else { return }
        defaults.set(true, forKey: migrationMarkerKey)
        guard try races(in: context).isEmpty,
              let goal = try PlanStore.activeGoal(in: context),
              let distance = RaceDistance(rawValue: goal.distanceRaw)
        else { return }

        let status: RaceStatus = calendar.startOfDay(for: goal.raceDate) < calendar.startOfDay(for: now)
            ? .completed
            : .upcoming
        let spec = RaceSpec(
            name: distance.displayName,
            date: goal.raceDate,
            distanceMeters: distance.meters,
            targetTimeSeconds: goal.targetTimeSeconds > 0 ? goal.targetTimeSeconds : nil,
            priority: .a,
            status: status
        )
        context.insert(Race(spec: spec, createdAt: now, updatedAt: now))
        try context.save()
    }

    static func syncGoalToARace(in context: ModelContext, calendar: Calendar) throws {
        guard let aRace = try existingARace(in: context),
              let goal = try PlanStore.activeGoal(in: context)
        else { return }

        let distanceRaw = RaceDistance.matching(meters: aRace.distanceMeters)?.rawValue ?? goal.distanceRaw
        let targetTimeSeconds = aRace.targetTimeSeconds ?? goal.targetTimeSeconds
        guard !calendar.isDate(goal.raceDate, inSameDayAs: aRace.date)
                || goal.distanceRaw != distanceRaw
                || goal.targetTimeSeconds != targetTimeSeconds
        else { return }

        goal.raceDate = aRace.date
        goal.distanceRaw = distanceRaw
        goal.targetTimeSeconds = targetTimeSeconds
        try context.save()
    }

    private static func demoteOtherUpcomingARaces(
        excluding race: Race,
        in context: ModelContext,
        now: Date
    ) throws {
        guard race.priorityRaw == RacePriority.a.rawValue,
              race.statusRaw == RaceStatus.upcoming.rawValue
        else { return }

        for existing in try races(in: context) where existing !== race
            && existing.priorityRaw == RacePriority.a.rawValue
            && existing.statusRaw == RaceStatus.upcoming.rawValue {
            existing.priorityRaw = RacePriority.b.rawValue
            existing.updatedAt = now
        }
    }

    private enum StoreError: LocalizedError {
        case raceNotFound

        var errorDescription: String? {
            "The race was not found."
        }
    }
}
