import Foundation
import SwiftData

enum ShoeWorkoutType: String, Codable, CaseIterable, Identifiable {
    case recovery
    case easy
    case longRun = "long_run"
    case steady
    case tempo
    case threshold
    case intervals
    case race
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recovery: "Recovery"
        case .easy: "Easy"
        case .longRun: "Long Run"
        case .steady: "Steady"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .intervals: "Intervals"
        case .race: "Race"
        case .other: "Other"
        }
    }

    static func normalized(from workoutKind: WorkoutKind?) -> ShoeWorkoutType {
        switch workoutKind {
        case .easy: .easy
        case .long: .longRun
        case .tempo: .tempo
        case .intervals: .intervals
        case .race: .race
        case nil: .other
        }
    }
}

enum RunningShoeStatus: String, Codable, CaseIterable {
    case active
    case retired
}

enum ShoeAssignmentSource: String, Codable, CaseIterable {
    case manual
    case auto
    case planned
    case syncedProvider = "synced_provider"
    case none
}

enum ShoeAutoAssignmentStrategy: String, Codable, CaseIterable, Identifiable {
    case bestMatch = "best_match"
    case newestMatched = "newest_matched"
    case rotateMatched = "rotate_matched"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bestMatch: "Best match"
        case .newestMatched: "Newest matched shoe"
        case .rotateMatched: "Rotate matched shoes"
        }
    }

    var description: String {
        switch self {
        case .bestMatch: "Prefer the shoe best suited to the workout."
        case .newestMatched: "Prefer the newest eligible shoe for that workout type."
        case .rotateMatched: "Prefer the least recently used matching shoe."
        }
    }
}

enum ShoeWearStatus: Equatable {
    case normal
    case approaching
    case inspect
    case pastRange
}

@Model
final class RunningShoe {
    @Attribute(.unique) var id: UUID
    var userId: String
    var brand: String
    var model: String
    var nickname: String?
    var purchaseDate: Date?
    var initialMileageKm: Double
    var statusRaw: String
    var preferredWorkoutTypeRawValues: [String]
    var primaryWorkoutTypeRaw: String?
    var expectedLifespanKm: Double
    var createdAt: Date
    var updatedAt: Date
    var retiredAt: Date?

    init(
        id: UUID = UUID(),
        userId: String = RunningShoePreferences.defaultUserId,
        brand: String,
        model: String,
        nickname: String? = nil,
        purchaseDate: Date? = nil,
        initialMileageKm: Double = 0,
        currentMileageKm: Double? = nil,
        status: RunningShoeStatus = .active,
        preferredWorkoutTypes: [ShoeWorkoutType] = [],
        primaryWorkoutType: ShoeWorkoutType? = nil,
        expectedLifespanKm: Double = 600,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        retiredAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.brand = brand
        self.model = model
        self.nickname = nickname
        self.purchaseDate = purchaseDate
        self.initialMileageKm = max(0, initialMileageKm)
        self.statusRaw = status.rawValue
        self.preferredWorkoutTypeRawValues = preferredWorkoutTypes.map(\.rawValue)
        self.primaryWorkoutTypeRaw = primaryWorkoutType?.rawValue ?? preferredWorkoutTypes.first?.rawValue
        self.expectedLifespanKm = max(1, expectedLifespanKm)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.retiredAt = retiredAt
    }

    var status: RunningShoeStatus {
        get { RunningShoeStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            retiredAt = newValue == .retired ? (retiredAt ?? .now) : nil
            updatedAt = .now
        }
    }

    var preferredWorkoutTypes: [ShoeWorkoutType] {
        get { preferredWorkoutTypeRawValues.compactMap(ShoeWorkoutType.init(rawValue:)) }
        set {
            preferredWorkoutTypeRawValues = newValue.map(\.rawValue)
            if let primary = primaryWorkoutType, !newValue.contains(primary) {
                primaryWorkoutTypeRaw = newValue.first?.rawValue
            } else if primaryWorkoutTypeRaw == nil {
                primaryWorkoutTypeRaw = newValue.first?.rawValue
            }
            updatedAt = .now
        }
    }

    var primaryWorkoutType: ShoeWorkoutType? {
        get { primaryWorkoutTypeRaw.flatMap(ShoeWorkoutType.init(rawValue:)) }
        set {
            primaryWorkoutTypeRaw = newValue?.rawValue
            updatedAt = .now
        }
    }

    var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nickname
        }
        return [brand, model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var preferredTypesText: String {
        let types = preferredWorkoutTypes
        guard !types.isEmpty else { return "Any run" }
        return types.map(\.displayName).joined(separator: " · ")
    }
}

@Model
final class ShoeMileageEntry {
    @Attribute(.unique) var activityID: UUID
    var id: UUID
    var shoeID: UUID
    var distanceKm: Double
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), shoeID: UUID, activityID: UUID, distanceKm: Double, createdAt: Date = .now) {
        self.id = id
        self.shoeID = shoeID
        self.activityID = activityID
        self.distanceKm = max(0, distanceKm)
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class RunningShoePreferences {
    static let singletonID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let defaultUserId = "local"

    @Attribute(.unique) var id: UUID
    var userId: String
    var shoeAutoAssignmentEnabled: Bool
    var shoeAutoAssignmentStrategyRaw: String
    var avoidNearRetirementShoes: Bool
    var nearRetirementThresholdPercent: Double
    var updatedAt: Date

    init(
        id: UUID = RunningShoePreferences.singletonID,
        userId: String = RunningShoePreferences.defaultUserId,
        shoeAutoAssignmentEnabled: Bool = true,
        shoeAutoAssignmentStrategy: ShoeAutoAssignmentStrategy = .bestMatch,
        avoidNearRetirementShoes: Bool = true,
        nearRetirementThresholdPercent: Double = 90,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userId = userId
        self.shoeAutoAssignmentEnabled = shoeAutoAssignmentEnabled
        self.shoeAutoAssignmentStrategyRaw = shoeAutoAssignmentStrategy.rawValue
        self.avoidNearRetirementShoes = avoidNearRetirementShoes
        self.nearRetirementThresholdPercent = nearRetirementThresholdPercent
        self.updatedAt = updatedAt
    }

    var shoeAutoAssignmentStrategy: ShoeAutoAssignmentStrategy {
        get { ShoeAutoAssignmentStrategy(rawValue: shoeAutoAssignmentStrategyRaw) ?? .bestMatch }
        set {
            shoeAutoAssignmentStrategyRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}

extension PlannedWorkout {
    var shoeAssignmentSource: ShoeAssignmentSource {
        get { ShoeAssignmentSource(rawValue: shoeAssignmentSourceRaw ?? "") ?? .none }
        set { shoeAssignmentSourceRaw = newValue.rawValue }
    }
}

extension CompletedActivity {
    var shoeAssignmentSource: ShoeAssignmentSource {
        get { ShoeAssignmentSource(rawValue: shoeAssignmentSourceRaw ?? "") ?? .none }
        set { shoeAssignmentSourceRaw = newValue.rawValue }
    }
}
