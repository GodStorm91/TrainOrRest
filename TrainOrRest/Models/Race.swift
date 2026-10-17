import Foundation
import SwiftData

@Model
final class Race {
    var id: UUID
    var name: String
    var date: Date
    var distanceMeters: Double
    var targetTimeSeconds: Double?
    var priorityRaw: String
    var notes: String?
    var statusRaw: String
    var resultFinishTimeSeconds: Double?
    var resultAverageHeartRate: Double?
    var resultHealthKitWorkoutID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(spec: RaceSpec, createdAt: Date, updatedAt: Date) {
        id = spec.id
        name = spec.name
        date = spec.date
        distanceMeters = spec.distanceMeters
        targetTimeSeconds = spec.targetTimeSeconds
        priorityRaw = spec.priority.rawValue
        notes = spec.notes
        statusRaw = spec.status.rawValue
        resultFinishTimeSeconds = spec.result?.finishTimeSeconds
        resultAverageHeartRate = spec.result?.averageHeartRate
        resultHealthKitWorkoutID = spec.result?.healthKitWorkoutID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var spec: RaceSpec? {
        guard let priority = RacePriority(rawValue: priorityRaw),
              let status = RaceStatus(rawValue: statusRaw)
        else { return nil }

        let result = resultFinishTimeSeconds.map {
            RaceResultSpec(
                finishTimeSeconds: $0,
                averageHeartRate: resultAverageHeartRate,
                healthKitWorkoutID: resultHealthKitWorkoutID
            )
        }
        return RaceSpec(
            id: id,
            name: name,
            date: date,
            distanceMeters: distanceMeters,
            targetTimeSeconds: targetTimeSeconds,
            priority: priority,
            notes: notes,
            status: status,
            result: result
        )
    }

    func apply(_ spec: RaceSpec, updatedAt: Date) {
        id = spec.id
        name = spec.name
        date = spec.date
        distanceMeters = spec.distanceMeters
        targetTimeSeconds = spec.targetTimeSeconds
        priorityRaw = spec.priority.rawValue
        notes = spec.notes
        statusRaw = spec.status.rawValue
        resultFinishTimeSeconds = spec.result?.finishTimeSeconds
        resultAverageHeartRate = spec.result?.averageHeartRate
        resultHealthKitWorkoutID = spec.result?.healthKitWorkoutID
        self.updatedAt = updatedAt
    }
}
