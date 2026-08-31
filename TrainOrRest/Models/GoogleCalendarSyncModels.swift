import Foundation
import SwiftData

enum GoogleCalendarConnectionStatus: String, Codable, CaseIterable {
    case disconnected
    case connecting
    case initialSync
    case connected
    case syncing
    case needsReconnect
    case calendarMissing
    case partialFailure
    case offlineQueued
}

enum GoogleCalendarCompletedActivityMode: String, Codable, CaseIterable, Identifiable {
    case none
    case plannedOnly
    case allActivities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .plannedOnly: "Plan workouts only"
        case .allActivities: "All activities"
        }
    }
}

enum GoogleCalendarUnscheduledWorkoutMode: String, Codable {
    case allDay
}

enum GoogleCalendarSyncErrorCategory: String, Codable {
    case none
    case temporary
    case permissionRevoked
    case calendarMissing
    case partialEventFailure
    case rateLimited
    case notConfigured
}

enum GoogleCalendarInboundChangeStatus: String, Codable, CaseIterable {
    case pendingReview
    case applied
    case rejected
    case restored
}

enum GoogleCalendarInboundChangeReason: String, Codable, CaseIterable {
    case sameDayTimeChanged
    case sameWeekDateChanged
    case targetDayConflict
    case outsidePlannedWeek
    case planValidationFailed
    case eventDeleted
    case contentRestored
}

enum GoogleCalendarLocalEntityType: String, Codable {
    case plannedWorkout
    case completedActivity
}

enum GoogleCalendarEventSyncState: String, Codable {
    case pending
    case synced
    case failed
    case deleted
    case notVisibleInGoogleCalendar
}

enum ScheduleChangeOperationStatus: String, Codable, CaseIterable {
    case pendingValidation
    case awaitingUserReview
    case applying
    case completed
    case failed
}

enum SmartSchedulingPermissionStatus: String, Codable, CaseIterable {
    case off
    case enabled
    case needsPermission
}

enum AvailabilityWindowState: String, Codable, CaseIterable {
    case busy
    case available
    case unknown
}

struct AvailabilityWindow: Codable, Equatable, Hashable {
    var start: Date
    var end: Date
    var stateRaw: String

    init(start: Date, end: Date, state: AvailabilityWindowState) {
        self.start = start
        self.end = end
        self.stateRaw = state.rawValue
    }

    var state: AvailabilityWindowState {
        AvailabilityWindowState(rawValue: stateRaw) ?? .unknown
    }

    var durationMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }
}

enum PreferredTrainingTime: String, Codable, CaseIterable, Identifiable {
    case none
    case earlyMorning
    case morning
    case lunch
    case afternoon
    case evening
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No preference"
        case .earlyMorning: "Early morning"
        case .morning: "Morning"
        case .lunch: "Lunch"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .custom: "Custom"
        }
    }
}

@Model
final class GoogleCalendarConnection {
    var uuid: UUID
    var googleAccountID: String?
    var maskedEmail: String?
    var googleCalendarID: String?
    var calendarName: String
    var connectionStatusRaw: String
    var syncStatusRaw: String
    var lastSuccessfulSyncAt: Date?
    var lastSyncAttemptAt: Date?
    var lastSyncErrorCategoryRaw: String?
    var lastSyncSummary: String?
    var upcomingWorkoutsEnabled: Bool
    var completedActivityModeRaw: String
    var unscheduledWorkoutModeRaw: String
    var googleRemindersEnabled: Bool
    var schedulingFromGoogleEnabled: Bool?
    var smartSchedulingStatusRaw: String?
    var smartSchedulingSelectedCalendarIDs: [String]?
    var smartSchedulingLastAvailabilityRefreshAt: Date?
    var smartSchedulingLastAvailabilitySummary: String?
    var smartSchedulingPreferredTimeRaw: String?
    var smartSchedulingEarliestStartMinutes: Int?
    var smartSchedulingLatestFinishMinutes: Int?
    var smartSchedulingBufferBeforeMinutes: Int?
    var smartSchedulingBufferAfterMinutes: Int?
    var googleCalendarIncrementalSyncToken: String?
    var lastCalendarChangeCheckAt: Date?
    var lastCalendarChangeSummary: String?
    var createdAt: Date
    var updatedAt: Date

    init(now: Date = .now) {
        self.uuid = UUID()
        self.googleAccountID = nil
        self.maskedEmail = nil
        self.googleCalendarID = nil
        self.calendarName = "TrainOrRest Training"
        self.connectionStatusRaw = GoogleCalendarConnectionStatus.disconnected.rawValue
        self.syncStatusRaw = GoogleCalendarConnectionStatus.disconnected.rawValue
        self.lastSyncErrorCategoryRaw = nil
        self.lastSyncSummary = nil
        self.upcomingWorkoutsEnabled = true
        self.completedActivityModeRaw = GoogleCalendarCompletedActivityMode.plannedOnly.rawValue
        self.unscheduledWorkoutModeRaw = GoogleCalendarUnscheduledWorkoutMode.allDay.rawValue
        self.googleRemindersEnabled = false
        self.schedulingFromGoogleEnabled = false
        self.smartSchedulingStatusRaw = SmartSchedulingPermissionStatus.off.rawValue
        self.smartSchedulingSelectedCalendarIDs = []
        self.smartSchedulingLastAvailabilityRefreshAt = nil
        self.smartSchedulingLastAvailabilitySummary = nil
        self.smartSchedulingPreferredTimeRaw = PreferredTrainingTime.none.rawValue
        self.smartSchedulingEarliestStartMinutes = 5 * 60
        self.smartSchedulingLatestFinishMinutes = 21 * 60
        self.smartSchedulingBufferBeforeMinutes = 15
        self.smartSchedulingBufferAfterMinutes = 15
        self.googleCalendarIncrementalSyncToken = nil
        self.lastCalendarChangeCheckAt = nil
        self.lastCalendarChangeSummary = nil
        self.createdAt = now
        self.updatedAt = now
    }

    var connectionStatus: GoogleCalendarConnectionStatus {
        get { GoogleCalendarConnectionStatus(rawValue: connectionStatusRaw) ?? .disconnected }
        set {
            connectionStatusRaw = newValue.rawValue
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var completedActivityMode: GoogleCalendarCompletedActivityMode {
        get { GoogleCalendarCompletedActivityMode(rawValue: completedActivityModeRaw) ?? .plannedOnly }
        set {
            completedActivityModeRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var unscheduledWorkoutMode: GoogleCalendarUnscheduledWorkoutMode {
        get { GoogleCalendarUnscheduledWorkoutMode(rawValue: unscheduledWorkoutModeRaw) ?? .allDay }
        set {
            unscheduledWorkoutModeRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var lastSyncErrorCategory: GoogleCalendarSyncErrorCategory {
        get { GoogleCalendarSyncErrorCategory(rawValue: lastSyncErrorCategoryRaw ?? "") ?? .none }
        set { lastSyncErrorCategoryRaw = newValue == .none ? nil : newValue.rawValue }
    }

    var allowsSchedulingFromGoogle: Bool {
        get { schedulingFromGoogleEnabled ?? false }
        set {
            schedulingFromGoogleEnabled = newValue
            updatedAt = .now
        }
    }

    var smartSchedulingStatus: SmartSchedulingPermissionStatus {
        get { SmartSchedulingPermissionStatus(rawValue: smartSchedulingStatusRaw ?? "") ?? .off }
        set {
            smartSchedulingStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var smartSchedulingEnabled: Bool {
        get { smartSchedulingStatus == .enabled }
        set { smartSchedulingStatus = newValue ? .enabled : .off }
    }

    var preferredTrainingTime: PreferredTrainingTime {
        get { PreferredTrainingTime(rawValue: smartSchedulingPreferredTimeRaw ?? "") ?? .none }
        set {
            smartSchedulingPreferredTimeRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var smartSchedulingEarliestStartOrDefault: Int { smartSchedulingEarliestStartMinutes ?? 5 * 60 }
    var smartSchedulingLatestFinishOrDefault: Int { smartSchedulingLatestFinishMinutes ?? 21 * 60 }
    var smartSchedulingBufferBeforeOrDefault: Int { smartSchedulingBufferBeforeMinutes ?? 15 }
    var smartSchedulingBufferAfterOrDefault: Int { smartSchedulingBufferAfterMinutes ?? 15 }
    var smartSchedulingSelectedCalendarIDsOrDefault: [String] { smartSchedulingSelectedCalendarIDs ?? [] }
}

@Model
final class GoogleAvailabilityCalendar {
    @Attribute(.unique) var uuid: UUID
    var connectionID: UUID
    var googleCalendarID: String
    var displayName: String
    var accessRole: String?
    var isPrimary: Bool
    var selectedForAvailability: Bool
    var excludedByDefaultReason: String?
    var updatedAt: Date

    init(
        connectionID: UUID,
        googleCalendarID: String,
        displayName: String,
        accessRole: String?,
        isPrimary: Bool,
        selectedForAvailability: Bool,
        excludedByDefaultReason: String?,
        now: Date = .now
    ) {
        self.uuid = UUID()
        self.connectionID = connectionID
        self.googleCalendarID = googleCalendarID
        self.displayName = displayName
        self.accessRole = accessRole
        self.isPrimary = isPrimary
        self.selectedForAvailability = selectedForAvailability
        self.excludedByDefaultReason = excludedByDefaultReason
        self.updatedAt = now
    }
}

@Model
final class DayAvailability {
    @Attribute(.unique) var uuid: UUID
    var connectionID: UUID
    var date: Date
    var timezoneIdentifier: String
    var busyWindows: [AvailabilityWindow]
    var availableWindows: [AvailabilityWindow]
    var totalAvailableMinutes: Int
    var longestAvailableWindowMinutes: Int
    var lastRefreshedAt: Date

    init(
        connectionID: UUID,
        date: Date,
        timezoneIdentifier: String,
        busyWindows: [AvailabilityWindow],
        availableWindows: [AvailabilityWindow],
        lastRefreshedAt: Date
    ) {
        self.uuid = UUID()
        self.connectionID = connectionID
        self.date = date
        self.timezoneIdentifier = timezoneIdentifier
        self.busyWindows = busyWindows
        self.availableWindows = availableWindows
        self.totalAvailableMinutes = availableWindows.reduce(0) { $0 + $1.durationMinutes }
        self.longestAvailableWindowMinutes = availableWindows.map(\.durationMinutes).max() ?? 0
        self.lastRefreshedAt = lastRefreshedAt
    }
}

@Model
final class GoogleCalendarEventLink {
    var uuid: UUID
    var connectionID: UUID
    var localEntityTypeRaw: String
    var localEntityID: UUID
    var trainingPlanID: UUID?
    var googleCalendarID: String
    var googleEventID: String
    var localSyncVersion: Int
    var lastSyncedHash: String?
    var lastGoogleScheduleSignature: String?
    var lastSyncedAt: Date?
    var syncStateRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        connectionID: UUID,
        localEntityType: GoogleCalendarLocalEntityType,
        localEntityID: UUID,
        trainingPlanID: UUID?,
        googleCalendarID: String,
        googleEventID: String,
        localSyncVersion: Int = 1,
        now: Date = .now
    ) {
        self.uuid = UUID()
        self.connectionID = connectionID
        self.localEntityTypeRaw = localEntityType.rawValue
        self.localEntityID = localEntityID
        self.trainingPlanID = trainingPlanID
        self.googleCalendarID = googleCalendarID
        self.googleEventID = googleEventID
        self.localSyncVersion = localSyncVersion
        self.lastSyncedHash = nil
        self.lastGoogleScheduleSignature = nil
        self.lastSyncedAt = nil
        self.syncStateRaw = GoogleCalendarEventSyncState.pending.rawValue
        self.createdAt = now
        self.updatedAt = now
    }

    var localEntityType: GoogleCalendarLocalEntityType {
        get { GoogleCalendarLocalEntityType(rawValue: localEntityTypeRaw) ?? .plannedWorkout }
        set { localEntityTypeRaw = newValue.rawValue }
    }

    var syncState: GoogleCalendarEventSyncState {
        get { GoogleCalendarEventSyncState(rawValue: syncStateRaw) ?? .pending }
        set {
            syncStateRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}

@Model
final class GoogleCalendarInboundChange {
    @Attribute(.unique) var uuid: UUID
    var connectionID: UUID
    var localEntityID: UUID
    var googleEventID: String
    var reasonRaw: String
    var statusRaw: String
    var originalDate: Date
    var proposedDate: Date?
    var message: String
    var createdAt: Date
    var resolvedAt: Date?

    init(
        connectionID: UUID,
        localEntityID: UUID,
        googleEventID: String,
        reason: GoogleCalendarInboundChangeReason,
        status: GoogleCalendarInboundChangeStatus,
        originalDate: Date,
        proposedDate: Date?,
        message: String,
        now: Date = .now
    ) {
        self.uuid = UUID()
        self.connectionID = connectionID
        self.localEntityID = localEntityID
        self.googleEventID = googleEventID
        self.reasonRaw = reason.rawValue
        self.statusRaw = status.rawValue
        self.originalDate = originalDate
        self.proposedDate = proposedDate
        self.message = message
        self.createdAt = now
        self.resolvedAt = status == .pendingReview ? nil : now
    }

    var reason: GoogleCalendarInboundChangeReason {
        get { GoogleCalendarInboundChangeReason(rawValue: reasonRaw) ?? .planValidationFailed }
        set { reasonRaw = newValue.rawValue }
    }

    var status: GoogleCalendarInboundChangeStatus {
        get { GoogleCalendarInboundChangeStatus(rawValue: statusRaw) ?? .pendingReview }
        set {
            statusRaw = newValue.rawValue
            resolvedAt = newValue == .pendingReview ? nil : .now
        }
    }
}

@Model
final class ScheduleChangeOperation {
    @Attribute(.unique) var uuid: UUID
    var idempotencyKey: String?
    var source: String
    var affectedWorkoutIDs: [UUID]
    var requestedChanges: [String]
    var statusRaw: String
    var previousScheduleDate: Date?
    var appliedScheduleDate: Date?
    var keepTimeFixed: Bool?
    var googleCalendarState: String?
    var undoneAt: Date?
    var createdAt: Date
    var completedAt: Date?
    var failureMessage: String?

    init(
        idempotencyKey: String? = nil,
        source: String,
        affectedWorkoutIDs: [UUID],
        requestedChanges: [String],
        status: ScheduleChangeOperationStatus,
        previousScheduleDate: Date? = nil,
        appliedScheduleDate: Date? = nil,
        keepTimeFixed: Bool? = nil,
        googleCalendarState: String? = nil,
        now: Date = .now
    ) {
        self.uuid = UUID()
        self.idempotencyKey = idempotencyKey
        self.source = source
        self.affectedWorkoutIDs = affectedWorkoutIDs
        self.requestedChanges = requestedChanges
        self.statusRaw = status.rawValue
        self.previousScheduleDate = previousScheduleDate
        self.appliedScheduleDate = appliedScheduleDate
        self.keepTimeFixed = keepTimeFixed
        self.googleCalendarState = googleCalendarState
        self.undoneAt = nil
        self.createdAt = now
        self.completedAt = status == .completed || status == .failed ? now : nil
        self.failureMessage = nil
    }

    var status: ScheduleChangeOperationStatus {
        get { ScheduleChangeOperationStatus(rawValue: statusRaw) ?? .pendingValidation }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .completed || newValue == .failed ? .now : nil
        }
    }
}
