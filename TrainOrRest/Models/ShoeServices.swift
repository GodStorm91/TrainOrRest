import Foundation
import SwiftData
import UserNotifications

struct ShoeAssignmentResult: Equatable {
    var shoeID: UUID?
    var source: ShoeAssignmentSource
    var isNearMileageRange: Bool

    static let none = ShoeAssignmentResult(shoeID: nil, source: .none, isNearMileageRange: false)
}

enum ShoeWearStatusService {
    static func wearStatus(currentMileageKm: Double, expectedLifespanKm: Double) -> ShoeWearStatus {
        guard expectedLifespanKm > 0 else { return .normal }
        let ratio = currentMileageKm / expectedLifespanKm
        if ratio >= 1 { return .pastRange }
        if ratio >= 0.9 { return .inspect }
        if ratio >= 0.8 { return .approaching }
        return .normal
    }

    static func wearStatus(for shoe: RunningShoe, ledger: [ShoeMileageEntry]) -> ShoeWearStatus {
        wearStatus(
            currentMileageKm: ShoeMileageService.currentMileageKm(for: shoe, ledger: ledger),
            expectedLifespanKm: shoe.expectedLifespanKm
        )
    }

    static func isNearRetirement(_ shoe: RunningShoe, ledger: [ShoeMileageEntry], thresholdPercent: Double) -> Bool {
        guard shoe.expectedLifespanKm > 0 else { return false }
        let current = ShoeMileageService.currentMileageKm(for: shoe, ledger: ledger)
        return current / shoe.expectedLifespanKm >= thresholdPercent / 100
    }

    static func reminderStage(currentMileageKm: Double, expectedLifespanKm: Double) -> ShoeWearReminderStage {
        switch wearStatus(currentMileageKm: currentMileageKm, expectedLifespanKm: expectedLifespanKm) {
        case .normal, .approaching: .none
        case .inspect: .inspect
        case .pastRange: .replace
        }
    }
}
enum ShoeWearReminderStage: Int, Equatable {
    case none
    case inspect
    case replace
}


enum ShoeAssignmentService {
    static func selectShoeForWorkout(
        workoutType: ShoeWorkoutType,
        activeShoes: [RunningShoe],
        preferences: RunningShoePreferences,
        existingShoeID: UUID?,
        existingAssignmentSource: ShoeAssignmentSource,
        mileageEntries: [ShoeMileageEntry] = []
    ) -> ShoeAssignmentResult {
        if existingAssignmentSource == .manual, let existingShoeID {
            return ShoeAssignmentResult(
                shoeID: existingShoeID,
                source: .manual,
                isNearMileageRange: activeShoes.first(where: { $0.id == existingShoeID }).map {
                    ShoeWearStatusService.isNearRetirement(
                        $0,
                        ledger: mileageEntries,
                        thresholdPercent: preferences.nearRetirementThresholdPercent
                    )
                } ?? false
            )
        }

        guard preferences.shoeAutoAssignmentEnabled else { return .none }

        let active = activeShoes.filter { $0.status == .active }
        guard !active.isEmpty else { return .none }

        let matching = active.filter { $0.preferredWorkoutTypes.contains(workoutType) }
        let pool = matching.isEmpty ? active : matching
        let safePool = preferences.avoidNearRetirementShoes
            ? pool.filter {
                !ShoeWearStatusService.isNearRetirement(
                    $0,
                    ledger: mileageEntries,
                    thresholdPercent: preferences.nearRetirementThresholdPercent
                )
            }
            : pool
        let candidates = safePool.isEmpty ? pool : safePool
        guard let selected = ranked(candidates, workoutType: workoutType, strategy: preferences.shoeAutoAssignmentStrategy, ledger: mileageEntries).first else {
            return .none
        }

        return ShoeAssignmentResult(
            shoeID: selected.id,
            source: .auto,
            isNearMileageRange: ShoeWearStatusService.isNearRetirement(
                selected,
                ledger: mileageEntries,
                thresholdPercent: preferences.nearRetirementThresholdPercent
            )
        )
    }

    @MainActor
    static func assignAutomaticShoes(to workouts: [PlannedWorkout], in context: ModelContext) throws {
        let shoes = try context.fetch(FetchDescriptor<RunningShoe>())
        let entries = try context.fetch(FetchDescriptor<ShoeMileageEntry>())
        let preferences = try ShoePreferencesStore.preferences(in: context)
        for workout in workouts where shouldAutoAssign(workout) {
            applySelection(to: workout, shoes: shoes, preferences: preferences, entries: entries)
        }
    }

    @MainActor
    static func reassignFutureAutomaticWorkouts(in context: ModelContext, calendar: Calendar = .current, from today: Date = .now) throws {
        let start = calendar.startOfDay(for: today)
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= start }
        ))
        let shoes = try context.fetch(FetchDescriptor<RunningShoe>())
        let entries = try context.fetch(FetchDescriptor<ShoeMileageEntry>())
        let preferences = try ShoePreferencesStore.preferences(in: context)
        for workout in workouts where shouldAutoAssign(workout) {
            applySelection(to: workout, shoes: shoes, preferences: preferences, entries: entries)
        }
    }

    @MainActor
    static func assignAutomaticShoesToUnassignedActivities(in context: ModelContext) throws {
        let activities = try context.fetch(FetchDescriptor<CompletedActivity>())
        let unassigned = activities.filter {
            $0.shoeID == nil
                && $0.shoeAssignmentSource != .manual
                && $0.shoeAssignmentSource != .syncedProvider
        }
        guard !unassigned.isEmpty else { return }

        let shoes = try context.fetch(FetchDescriptor<RunningShoe>())
        var entries = try context.fetch(FetchDescriptor<ShoeMileageEntry>())
        let preferences = try ShoePreferencesStore.preferences(in: context)

        for activity in unassigned {
            let result = selectShoeForWorkout(
                workoutType: .other,
                activeShoes: shoes,
                preferences: preferences,
                existingShoeID: nil,
                existingAssignmentSource: .none,
                mileageEntries: entries
            )
            activity.shoeID = result.shoeID
            activity.shoeAssignmentSource = result.source
            try ShoeMileageService.syncMileage(for: activity, in: context)
            entries = try context.fetch(FetchDescriptor<ShoeMileageEntry>())
        }
    }

    @MainActor
    static func applySelection(to workout: PlannedWorkout, shoes: [RunningShoe], preferences: RunningShoePreferences, entries: [ShoeMileageEntry]) {
        let result = selectShoeForWorkout(
            workoutType: ShoeWorkoutType.normalized(from: workout.kind),
            activeShoes: shoes,
            preferences: preferences,
            existingShoeID: workout.shoeID,
            existingAssignmentSource: workout.shoeAssignmentSource,
            mileageEntries: entries
        )
        workout.shoeID = result.shoeID
        workout.shoeAssignmentSource = result.source
    }

    /// Copies a planned workout's shoe onto a completed activity that has none.
    /// Returns true when the activity was updated.
    @discardableResult
    static func inheritPlannedShoe(onto activity: CompletedActivity, from planned: PlannedWorkout?) -> Bool {
        guard activity.shoeID == nil, let planned, planned.shoeID != nil else { return false }
        activity.shoeID = planned.shoeID
        activity.shoeAssignmentSource = planned.shoeAssignmentSource
        return true
    }

    private static func shouldAutoAssign(_ workout: PlannedWorkout) -> Bool {
        workout.shoeAssignmentSource != .manual
    }

    private static func ranked(
        _ shoes: [RunningShoe],
        workoutType: ShoeWorkoutType,
        strategy: ShoeAutoAssignmentStrategy,
        ledger: [ShoeMileageEntry]
    ) -> [RunningShoe] {
        switch strategy {
        case .bestMatch:
            return shoes.sorted {
                sortKey($0, workoutType: workoutType, ledger: ledger) < sortKey($1, workoutType: workoutType, ledger: ledger)
            }
        case .newestMatched:
            return shoes.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.displayName < $1.displayName
            }
        case .rotateMatched:
            return shoes.sorted {
                let leftUsed = lastUsedAt($0, ledger: ledger)
                let rightUsed = lastUsedAt($1, ledger: ledger)
                if leftUsed != rightUsed {
                    if leftUsed == nil { return true }
                    if rightUsed == nil { return false }
                    return leftUsed! < rightUsed!
                }
                let leftMileage = ShoeMileageService.currentMileageKm(for: $0, ledger: ledger)
                let rightMileage = ShoeMileageService.currentMileageKm(for: $1, ledger: ledger)
                if leftMileage != rightMileage { return leftMileage < rightMileage }
                return $0.createdAt > $1.createdAt
            }
        }
    }

    private static func sortKey(_ shoe: RunningShoe, workoutType: ShoeWorkoutType, ledger: [ShoeMileageEntry]) -> BestMatchKey {
        BestMatchKey(
            primaryPenalty: shoe.primaryWorkoutType == workoutType ? 0 : 1,
            preferredPenalty: shoe.preferredWorkoutTypes.contains(workoutType) ? 0 : 1,
            recentUsagePenalty: lastUsedAt(shoe, ledger: ledger)?.timeIntervalSince1970 ?? 0,
            newestPenalty: -shoe.createdAt.timeIntervalSince1970,
            name: shoe.displayName
        )
    }

    private static func lastUsedAt(_ shoe: RunningShoe, ledger: [ShoeMileageEntry]) -> Date? {
        ledger
            .filter { $0.shoeID == shoe.id }
            .map(\.createdAt)
            .max()
    }
}

private struct BestMatchKey: Comparable {
    var primaryPenalty: Int
    var preferredPenalty: Int
    var recentUsagePenalty: TimeInterval
    var newestPenalty: TimeInterval
    var name: String

    static func < (lhs: BestMatchKey, rhs: BestMatchKey) -> Bool {
        if lhs.primaryPenalty != rhs.primaryPenalty { return lhs.primaryPenalty < rhs.primaryPenalty }
        if lhs.preferredPenalty != rhs.preferredPenalty { return lhs.preferredPenalty < rhs.preferredPenalty }
        if lhs.recentUsagePenalty != rhs.recentUsagePenalty { return lhs.recentUsagePenalty < rhs.recentUsagePenalty }
        if lhs.newestPenalty != rhs.newestPenalty { return lhs.newestPenalty < rhs.newestPenalty }
        return lhs.name < rhs.name
    }
}

enum ShoeMileageService {
    static func currentMileageKm(for shoe: RunningShoe, ledger: [ShoeMileageEntry]) -> Double {
        shoe.initialMileageKm + ledger
            .filter { $0.shoeID == shoe.id }
            .map(\.distanceKm)
            .reduce(0, +)
    }

    static func applyingMileage(
        activityID: UUID,
        shoeID: UUID?,
        distanceKm: Double?,
        to ledger: [ShoeMileageEntry],
        now: Date = .now
    ) -> [ShoeMileageEntry] {
        guard let shoeID, let distanceKm else {
            return ledger.filter { $0.activityID != activityID }
        }
        var updated = ledger
        if let existing = updated.first(where: { $0.activityID == activityID }) {
            existing.shoeID = shoeID
            existing.distanceKm = max(0, distanceKm)
            existing.updatedAt = now
        } else {
            updated.append(ShoeMileageEntry(shoeID: shoeID, activityID: activityID, distanceKm: distanceKm, createdAt: now))
        }
        return updated
    }

    @MainActor
    static func currentMileageKm(for shoe: RunningShoe, in context: ModelContext) throws -> Double {
        let entries = try context.fetch(FetchDescriptor<ShoeMileageEntry>())
        return currentMileageKm(for: shoe, ledger: entries)
    }

    @MainActor
    static func syncMileage(for activity: CompletedActivity, in context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<ShoeMileageEntry>())
        guard let shoeID = activity.shoeID, let distanceKm = activity.distanceMeters.map({ max(0, $0 / 1000) }) else {
            for entry in entries where entry.activityID == activity.hkUUID {
                context.delete(entry)
            }
            return
        }

        if let existing = entries.first(where: { $0.activityID == activity.hkUUID }) {
            existing.shoeID = shoeID
            existing.distanceKm = distanceKm
            existing.updatedAt = .now
        } else {
            context.insert(ShoeMileageEntry(shoeID: shoeID, activityID: activity.hkUUID, distanceKm: distanceKm))
        }
    }

    @MainActor
    static func removeMileage(forActivityID activityID: UUID, in context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<ShoeMileageEntry>())
        for entry in entries where entry.activityID == activityID {
            context.delete(entry)
        }
    }
}

@MainActor
enum ShoePreferencesStore {
    static func preferences(in context: ModelContext) throws -> RunningShoePreferences {
        if let existing = try context.fetch(FetchDescriptor<RunningShoePreferences>()).first {
            return existing
        }
        let preferences = RunningShoePreferences()
        context.insert(preferences)
        return preferences
    }
}

@MainActor
enum ShoeWearNotifier {
    static func notifyIfNeeded(in context: ModelContext) async {
        guard
            let shoes = try? context.fetch(FetchDescriptor<RunningShoe>()),
            let entries = try? context.fetch(FetchDescriptor<ShoeMileageEntry>())
        else { return }

        let candidates = shoes
            .filter { $0.status == .active }
            .compactMap { shoe -> (RunningShoe, Double, ShoeWearReminderStage)? in
                let mileage = ShoeMileageService.currentMileageKm(for: shoe, ledger: entries)
                let stage = ShoeWearStatusService.reminderStage(
                    currentMileageKm: mileage,
                    expectedLifespanKm: shoe.expectedLifespanKm
                )
                let key = reminderKey(for: shoe)
                let notifiedStage = ShoeWearReminderStage(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .none
                if stage.rawValue < notifiedStage.rawValue {
                    UserDefaults.standard.set(stage.rawValue, forKey: key)
                }
                guard stage.rawValue > notifiedStage.rawValue else { return nil }
                return (shoe, mileage, stage)
            }
            .sorted {
                if $0.2.rawValue != $1.2.rawValue { return $0.2.rawValue > $1.2.rawValue }
                return ($0.1 / $0.0.expectedLifespanKm) > ($1.1 / $1.0.expectedLifespanKm)
            }

        guard let (shoe, mileage, stage) = candidates.first else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let copy = CoachLanguage.current.integrations
        let content = UNMutableNotificationContent()
        switch stage {
        case .none:
            return
        case .inspect:
            content.title = copy.shoeInspectionReminderTitle(shoe.displayName)
            content.body = copy.shoeInspectionReminderBody(Formatters.kilometers(mileage * 1000))
        case .replace:
            content.title = copy.shoeReplacementReminderTitle(shoe.displayName)
            content.body = copy.shoeReplacementReminderBody(Formatters.kilometers(mileage * 1000))
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "shoe-wear-\(shoe.id.uuidString)-\(stage.rawValue)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            UserDefaults.standard.set(stage.rawValue, forKey: reminderKey(for: shoe))
        } catch {
            // Best-effort: leave the stage unchanged so a later sync can retry.
        }
    }

    private static func reminderKey(for shoe: RunningShoe) -> String {
        "shoe-wear-reminder-stage-\(shoe.id.uuidString)"
    }
}
