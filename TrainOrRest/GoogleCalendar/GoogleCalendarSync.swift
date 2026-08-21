import AuthenticationServices
import CryptoKit
import Foundation
import Network
import OSLog
import SwiftData
import SwiftUI
import UIKit

enum GoogleCalendarSyncSettings {
    static let clientIDKey = "GoogleCalendarOAuthClientID"
    static let redirectSchemeKey = "GoogleCalendarOAuthRedirectScheme"
    static let scope = [
        "openid",
        "email",
        "profile",
        // Sufficient for reading and writing events on calendars created by
        // RestOrTrain; do not broaden to personal calendar scopes for V1.5.
        "https://www.googleapis.com/auth/calendar.app.created"
    ].joined(separator: " ")
    static let smartSchedulingScope = [
        // FreeBusy returns only busy intervals for selected calendars.
        "https://www.googleapis.com/auth/calendar.freebusy",
        // Needed only to let the athlete choose which calendars contribute
        // availability. Event titles/descriptions are not requested or read.
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    ].joined(separator: " ")
    static let calendarName = "RestOrTrain Training"
    static let calendarDescription = "Training workouts managed by RestOrTrain"
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let calendarBaseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: clientIDKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var redirectScheme: String {
        (Bundle.main.object(forInfoDictionaryKey: redirectSchemeKey) as? String ?? Bundle.main.bundleIdentifier ?? "com.khanhnguyen.TrainOrRest")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var redirectURI: String {
        "\(redirectScheme):/oauth2redirect/google-calendar"
    }
}

struct GoogleCalendarTokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var tokenType: String
}

enum GoogleCalendarTokenStore {
    static func tokenAccount(connectionID: UUID) -> String {
        "google-calendar-token-\(connectionID.uuidString)"
    }

    static func save(_ tokens: GoogleCalendarTokenSet, connectionID: UUID) throws {
        let data = try JSONEncoder().encode(tokens)
        try KeychainStore.save(Data(data).base64EncodedString(), account: tokenAccount(connectionID: connectionID))
    }

    static func load(connectionID: UUID) throws -> GoogleCalendarTokenSet? {
        guard let encoded = try KeychainStore.load(account: tokenAccount(connectionID: connectionID)),
              let data = Data(base64Encoded: encoded) else { return nil }
        return try JSONDecoder().decode(GoogleCalendarTokenSet.self, from: data)
    }

    static func delete(connectionID: UUID) throws {
        try KeychainStore.delete(account: tokenAccount(connectionID: connectionID))
    }
}

enum GoogleCalendarOAuthError: Error, LocalizedError {
    case notConfigured
    case cancelled
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google Calendar is not configured in this build."
        case .cancelled: "Google Calendar was not connected."
        case .invalidCallback, .stateMismatch, .tokenExchangeFailed:
            "Google Calendar was not connected."
        }
    }
}

@MainActor
final class GoogleCalendarOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize() async throws -> GoogleCalendarAuthorizedAccount {
        try await authorize(scope: GoogleCalendarSyncSettings.scope, prompt: "consent", includeGrantedScopes: false)
    }

    func authorizeSmartScheduling() async throws -> GoogleCalendarAuthorizedAccount {
        try await authorize(scope: GoogleCalendarSyncSettings.smartSchedulingScope, prompt: nil, includeGrantedScopes: true)
    }

    private func authorize(scope: String, prompt: String?, includeGrantedScopes: Bool) async throws -> GoogleCalendarAuthorizedAccount {
        guard !GoogleCalendarSyncSettings.clientID.isEmpty else {
            throw GoogleCalendarOAuthError.notConfigured
        }

        let state = Self.randomURLSafeString(byteCount: 24)
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.codeChallenge(for: verifier)
        let authURL = try Self.authorizationURL(state: state, challenge: challenge, scope: scope, prompt: prompt, includeGrantedScopes: includeGrantedScopes)
        let callback = try await startSession(url: authURL)
        let code = try Self.authorizationCode(from: callback, expectedState: state)
        let tokens = try await GoogleCalendarAPIClient().exchangeCode(code, verifier: verifier)
        let profile = try await GoogleCalendarAPIClient().userInfo(accessToken: tokens.accessToken)
        return GoogleCalendarAuthorizedAccount(tokens: tokens, profile: profile)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func startSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleCalendarSyncSettings.redirectScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleCalendarOAuthError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleCalendarOAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    private static func authorizationURL(state: String, challenge: String, scope: String, prompt: String?, includeGrantedScopes: Bool) throws -> URL {
        var components = URLComponents(url: GoogleCalendarSyncSettings.authEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: GoogleCalendarSyncSettings.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleCalendarSyncSettings.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "include_granted_scopes", value: includeGrantedScopes ? "true" : "false"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if let prompt {
            items.append(URLQueryItem(name: "prompt", value: prompt))
        }
        components.queryItems = items
        guard let url = components.url else { throw GoogleCalendarOAuthError.invalidCallback }
        return url
    }

    private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw GoogleCalendarOAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GoogleCalendarOAuthError.invalidCallback
        }
        return code
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

struct GoogleCalendarAuthorizedAccount {
    var tokens: GoogleCalendarTokenSet
    var profile: GoogleCalendarUserInfo
}

struct GoogleCalendarUserInfo: Codable, Equatable {
    var sub: String
    var email: String?
}

struct GoogleCalendarListEntry: Codable, Equatable {
    var id: String
    var summary: String?
    var description: String?
    var timeZone: String?
    var accessRole: String?
    var primary: Bool?
    var selected: Bool?
    var backgroundColor: String?

    init(
        id: String,
        summary: String?,
        description: String?,
        timeZone: String?,
        accessRole: String? = nil,
        primary: Bool? = nil,
        selected: Bool? = nil,
        backgroundColor: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.description = description
        self.timeZone = timeZone
        self.accessRole = accessRole
        self.primary = primary
        self.selected = selected
        self.backgroundColor = backgroundColor
    }
}

struct GoogleCalendarListPage: Codable, Equatable {
    var items: [GoogleCalendarListEntry]
    var nextPageToken: String?
}

struct GoogleCalendarEventPayload: Codable, Equatable {
    var id: String?
    var summary: String
    var description: String?
    var start: GoogleCalendarEventDate
    var end: GoogleCalendarEventDate
    var transparency: String
    var visibility: String
    var reminders: GoogleCalendarReminders?
    var extendedProperties: GoogleCalendarExtendedProperties

    func preservingGoogleCustomizationsForPatch() -> GoogleCalendarEventPayload {
        var copy = self
        copy.reminders = nil
        return copy
    }
}

struct GoogleCalendarEventDate: Codable, Equatable {
    var date: String?
    var dateTime: String?
    var timeZone: String?
}

struct GoogleCalendarReminders: Codable, Equatable {
    var useDefault: Bool
    var overrides: [String]?
}

struct GoogleCalendarExtendedProperties: Codable, Equatable {
    var `private`: [String: String]
}

struct GoogleCalendarEventResponse: Codable {
    var id: String
}

struct GoogleCalendarRemoteEvent: Codable, Equatable {
    var id: String
    var status: String?
    var summary: String?
    var description: String?
    var start: GoogleCalendarEventDate?
    var end: GoogleCalendarEventDate?
    var updated: String?
    var extendedProperties: GoogleCalendarExtendedProperties?
}

struct GoogleCalendarEventPage: Codable, Equatable {
    var items: [GoogleCalendarRemoteEvent]
    var nextPageToken: String?
    var nextSyncToken: String?

    init(items: [GoogleCalendarRemoteEvent], nextPageToken: String? = nil, nextSyncToken: String? = nil) {
        self.items = items
        self.nextPageToken = nextPageToken
        self.nextSyncToken = nextSyncToken
    }
}

struct GoogleFreeBusyRequest: Codable, Equatable {
    var timeMin: String
    var timeMax: String
    var timeZone: String
    var calendarExpansionMax: Int
    var items: [GoogleFreeBusyItem]
}

struct GoogleFreeBusyItem: Codable, Equatable {
    var id: String
}

struct GoogleFreeBusyResponse: Codable, Equatable {
    var calendars: [String: GoogleFreeBusyCalendar]
}

struct GoogleFreeBusyCalendar: Codable, Equatable {
    var errors: [GoogleFreeBusyError]?
    var busy: [GoogleFreeBusyBlock]
}

struct GoogleFreeBusyBlock: Codable, Equatable {
    var start: String
    var end: String
}

struct GoogleFreeBusyError: Codable, Equatable {
    var domain: String?
    var reason: String?
}

enum GoogleCalendarAPIError: Error {
    case unauthorized
    case rateLimited
    case notFound
    case syncTokenExpired
    case temporary
    case permanent(Int)
    case invalidResponse
}

protocol GoogleCalendarAPIServicing {
    func exchangeCode(_ code: String, verifier: String) async throws -> GoogleCalendarTokenSet
    func refresh(_ refreshToken: String) async throws -> GoogleCalendarTokenSet
    func userInfo(accessToken: String) async throws -> GoogleCalendarUserInfo
    func calendar(id: String, accessToken: String) async throws -> GoogleCalendarListEntry
    func createCalendar(name: String, description: String, timeZone: String, accessToken: String) async throws -> GoogleCalendarListEntry
    func deleteCalendar(id: String, accessToken: String) async throws
    func revokeToken(_ token: String) async throws
    func insertEvent(calendarID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse
    func patchEvent(calendarID: String, eventID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse
    func deleteEvent(calendarID: String, eventID: String, accessToken: String) async throws
    func eventsByPrivateProperty(calendarID: String, key: String, value: String, accessToken: String) async throws -> [GoogleCalendarEventResponse]
    func listEvents(calendarID: String, syncToken: String?, accessToken: String) async throws -> GoogleCalendarEventPage
    func listCalendarList(accessToken: String) async throws -> [GoogleCalendarListEntry]
    func freeBusy(request: GoogleFreeBusyRequest, accessToken: String) async throws -> GoogleFreeBusyResponse
}

struct GoogleCalendarAPIClient: GoogleCalendarAPIServicing {
    var session: URLSession = .shared

    func exchangeCode(_ code: String, verifier: String) async throws -> GoogleCalendarTokenSet {
        let body = [
            "client_id": GoogleCalendarSyncSettings.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleCalendarSyncSettings.redirectURI
        ]
        return try await tokenRequest(body)
    }

    func refresh(_ refreshToken: String) async throws -> GoogleCalendarTokenSet {
        let body = [
            "client_id": GoogleCalendarSyncSettings.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        var refreshed = try await tokenRequest(body)
        refreshed.refreshToken = refreshToken
        return refreshed
    }

    func userInfo(accessToken: String) async throws -> GoogleCalendarUserInfo {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func calendar(id: String, accessToken: String) async throws -> GoogleCalendarListEntry {
        let url = GoogleCalendarSyncSettings.calendarBaseURL.appendingPathComponent("calendars").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func createCalendar(name: String, description: String, timeZone: String, accessToken: String) async throws -> GoogleCalendarListEntry {
        let url = GoogleCalendarSyncSettings.calendarBaseURL.appendingPathComponent("calendars")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.google.encode([
            "summary": name,
            "description": description,
            "timeZone": timeZone
        ])
        return try await send(request)
    }

    func deleteCalendar(id: String, accessToken: String) async throws {
        let url = GoogleCalendarSyncSettings.calendarBaseURL.appendingPathComponent("calendars").appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await sendRaw(request, emptySuccess: true)
    }

    func revokeToken(_ token: String) async throws {
        var components = URLComponents(url: GoogleCalendarSyncSettings.revokeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        _ = try await sendRaw(request, emptySuccess: true)
    }

    func insertEvent(calendarID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse {
        let url = GoogleCalendarSyncSettings.calendarBaseURL
            .appendingPathComponent("calendars").appendingPathComponent(calendarID)
            .appendingPathComponent("events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.google.encode(event)
        return try await send(request)
    }

    func patchEvent(calendarID: String, eventID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse {
        let url = GoogleCalendarSyncSettings.calendarBaseURL
            .appendingPathComponent("calendars").appendingPathComponent(calendarID)
            .appendingPathComponent("events").appendingPathComponent(eventID)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.google.encode(event)
        return try await send(request)
    }

    func deleteEvent(calendarID: String, eventID: String, accessToken: String) async throws {
        let url = GoogleCalendarSyncSettings.calendarBaseURL
            .appendingPathComponent("calendars").appendingPathComponent(calendarID)
            .appendingPathComponent("events").appendingPathComponent(eventID)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await sendRaw(request, emptySuccess: true)
    }

    func eventsByPrivateProperty(calendarID: String, key: String, value: String, accessToken: String) async throws -> [GoogleCalendarEventResponse] {
        var components = URLComponents(
            url: GoogleCalendarSyncSettings.calendarBaseURL
                .appendingPathComponent("calendars").appendingPathComponent(calendarID)
                .appendingPathComponent("events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "privateExtendedProperty", value: "\(key)=\(value)"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "maxResults", value: "10")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let result: EventListResponse = try await send(request)
        return result.items.map { GoogleCalendarEventResponse(id: $0.id) }
    }

    func listEvents(calendarID: String, syncToken: String?, accessToken: String) async throws -> GoogleCalendarEventPage {
        var allItems: [GoogleCalendarRemoteEvent] = []
        var nextPageToken: String?
        var nextSyncToken: String?
        repeat {
            let page = try await listEventsPage(
                calendarID: calendarID,
                syncToken: syncToken,
                pageToken: nextPageToken,
                accessToken: accessToken
            )
            allItems += page.items
            nextPageToken = page.nextPageToken
            nextSyncToken = page.nextSyncToken ?? nextSyncToken
        } while nextPageToken != nil
        return GoogleCalendarEventPage(items: allItems, nextPageToken: nil, nextSyncToken: nextSyncToken)
    }

    func listCalendarList(accessToken: String) async throws -> [GoogleCalendarListEntry] {
        var allItems: [GoogleCalendarListEntry] = []
        var nextPageToken: String?
        repeat {
            var components = URLComponents(
                url: GoogleCalendarSyncSettings.calendarBaseURL
                    .appendingPathComponent("users").appendingPathComponent("me").appendingPathComponent("calendarList"),
                resolvingAgainstBaseURL: false
            )!
            var query = [
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "showHidden", value: "false"),
                URLQueryItem(name: "maxResults", value: "250")
            ]
            if let nextPageToken {
                query.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            }
            components.queryItems = query
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let page: CalendarListResponse = try await send(request)
            allItems += page.items
            nextPageToken = page.nextPageToken
        } while nextPageToken != nil
        return allItems
    }

    func freeBusy(request body: GoogleFreeBusyRequest, accessToken: String) async throws -> GoogleFreeBusyResponse {
        let url = GoogleCalendarSyncSettings.calendarBaseURL.appendingPathComponent("freeBusy")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.google.encode(body)
        return try await send(request)
    }

    private func listEventsPage(calendarID: String, syncToken: String?, pageToken: String?, accessToken: String) async throws -> GoogleCalendarEventPage {
        var components = URLComponents(
            url: GoogleCalendarSyncSettings.calendarBaseURL
                .appendingPathComponent("calendars").appendingPathComponent(calendarID)
                .appendingPathComponent("events"),
            resolvingAgainstBaseURL: false
        )!
        var items = [
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]
        if let syncToken, !syncToken.isEmpty {
            items.append(URLQueryItem(name: "syncToken", value: syncToken))
        }
        if let pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: RemoteEventListResponse = try await send(request)
        return GoogleCalendarEventPage(
            items: response.items,
            nextPageToken: response.nextPageToken,
            nextSyncToken: response.nextSyncToken
        )
    }

    private func tokenRequest(_ body: [String: String]) async throws -> GoogleCalendarTokenSet {
        var request = URLRequest(url: GoogleCalendarSyncSettings.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let response: TokenResponse = try await send(request)
        return GoogleCalendarTokenSet(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(response.expires_in - 60, 60))),
            tokenType: response.token_type
        )
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await sendRaw(request, emptySuccess: false)
        return try JSONDecoder.google.decode(T.self, from: data)
    }

    private func sendRaw(_ request: URLRequest, emptySuccess: Bool) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarAPIError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return emptySuccess && data.isEmpty ? Data("{}".utf8) : data
        case 401, 403:
            throw GoogleCalendarAPIError.unauthorized
        case 404:
            throw GoogleCalendarAPIError.notFound
        case 410:
            throw GoogleCalendarAPIError.syncTokenExpired
        case 429:
            throw GoogleCalendarAPIError.rateLimited
        case 500..<600:
            throw GoogleCalendarAPIError.temporary
        default:
            throw GoogleCalendarAPIError.permanent(http.statusCode)
        }
    }

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private struct TokenResponse: Codable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int
        var token_type: String
    }

    private struct EventListResponse: Codable {
        var items: [GoogleCalendarEventResponse]
    }

    private struct RemoteEventListResponse: Codable {
        var items: [GoogleCalendarRemoteEvent]
        var nextPageToken: String?
        var nextSyncToken: String?
    }

    private struct CalendarListResponse: Codable {
        var items: [GoogleCalendarListEntry]
        var nextPageToken: String?
    }
}

struct GoogleCalendarDesiredEvent: Equatable {
    var entityType: GoogleCalendarLocalEntityType
    var entityID: UUID
    var trainingPlanID: UUID?
    var payload: GoogleCalendarEventPayload
    var hash: String
}

struct GoogleCalendarEventBuilder {
    static let schemaVersion = "1"
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func desiredEvents(
        plan: TrainingPlan?,
        workouts: [PlannedWorkout],
        activities: [CompletedActivity],
        connection: GoogleCalendarConnection,
        today: Date = .now
    ) -> [GoogleCalendarDesiredEvent] {
        guard let plan else { return [] }
        let start = startOfCurrentTrainingWeek(plan: plan, today: today)
        let fallbackPlanEnd = calendar.date(byAdding: .weekOfYear, value: max(plan.weekPhasesRaw.count, 1), to: plan.anchorDate) ?? start
        let planEnd = workouts.map(\.date).max() ?? fallbackPlanEnd
        let horizon = calendar.date(byAdding: .month, value: 12, to: start) ?? planEnd
        let end = minDate(planEndInclusiveEnd(planEnd), horizon)
        let matchedActivities = Dictionary(uniqueKeysWithValues: activities.map { ($0.hkUUID, $0) })

        var desired: [GoogleCalendarDesiredEvent] = []
        if connection.upcomingWorkoutsEnabled {
            let windowWorkouts = workouts.filter { $0.date >= start && $0.date < end }
            for workout in windowWorkouts {
                let completion = workout.matchedActivityUUID.flatMap { matchedActivities[$0] }
                desired.append(plannedWorkoutEvent(workout, plan: plan, completion: completion))
            }
        }

        if connection.completedActivityMode == .allActivities {
            let matchedIDs = Set(workouts.compactMap(\.matchedActivityUUID))
            for activity in activities where activity.date >= start && activity.date < end && !matchedIDs.contains(activity.hkUUID) {
                desired.append(completedActivityEvent(activity, plan: plan))
            }
        }

        return desired.sorted {
            ($0.payload.start.date ?? $0.payload.start.dateTime ?? "") < ($1.payload.start.date ?? $1.payload.start.dateTime ?? "")
        }
    }

    func plannedWorkoutEvent(_ workout: PlannedWorkout, plan: TrainingPlan, completion: CompletedActivity?) -> GoogleCalendarDesiredEvent {
        let title = "\(completion == nil ? "" : "✓ ")\(kindTitle(workout.kind)) · \(distanceText(km: workout.distanceKm))"
        let description = plannedDescription(workout, completion: completion)
        let payload = payload(
            id: Self.deterministicEventID(type: .plannedWorkout, id: workout.uuid),
            title: title,
            description: description,
            date: workout.date,
            durationSeconds: workout.expectedDurationSeconds,
            forceTimed: !calendar.isDate(workout.date, equalTo: calendar.startOfDay(for: workout.date), toGranularity: .minute),
            entityType: .plannedWorkout,
            entityID: workout.uuid,
            planID: plan.generatedAt.stableUUIDSeed
        )
        return desired(type: .plannedWorkout, id: workout.uuid, planID: plan.generatedAt.stableUUIDSeed, payload: payload)
    }

    func completedActivityEvent(_ activity: CompletedActivity, plan: TrainingPlan) -> GoogleCalendarDesiredEvent {
        let km = activity.distanceMeters.map { $0 / 1000 }
        let title = "✓ Run · \(km.map(distanceText) ?? Formatters.duration(activity.durationSeconds))"
        let payload = payload(
            id: Self.deterministicEventID(type: .completedActivity, id: activity.hkUUID),
            title: title,
            description: completedDescription(activity),
            date: activity.date,
            durationSeconds: activity.durationSeconds,
            forceTimed: true,
            entityType: .completedActivity,
            entityID: activity.hkUUID,
            planID: plan.generatedAt.stableUUIDSeed
        )
        return desired(type: .completedActivity, id: activity.hkUUID, planID: plan.generatedAt.stableUUIDSeed, payload: payload)
    }

    private func payload(
        id: String,
        title: String,
        description: String,
        date: Date,
        durationSeconds: Double?,
        forceTimed: Bool,
        entityType: GoogleCalendarLocalEntityType,
        entityID: UUID,
        planID: UUID
    ) -> GoogleCalendarEventPayload {
        let isTimed = forceTimed && durationSeconds != nil
        let eventStart: GoogleCalendarEventDate
        let eventEnd: GoogleCalendarEventDate
        if isTimed, let durationSeconds {
            let end = date.addingTimeInterval(max(durationSeconds, 60 * 15))
            eventStart = GoogleCalendarEventDate(date: nil, dateTime: Self.rfc3339(date), timeZone: timeZone.identifier)
            eventEnd = GoogleCalendarEventDate(date: nil, dateTime: Self.rfc3339(end), timeZone: timeZone.identifier)
        } else {
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            eventStart = GoogleCalendarEventDate(date: Self.localDate(start, calendar: calendar), dateTime: nil, timeZone: nil)
            eventEnd = GoogleCalendarEventDate(date: Self.localDate(end, calendar: calendar), dateTime: nil, timeZone: nil)
        }

        return GoogleCalendarEventPayload(
            id: id,
            summary: title,
            description: description,
            start: eventStart,
            end: eventEnd,
            transparency: isTimed ? "opaque" : "transparent",
            visibility: "private",
            reminders: GoogleCalendarReminders(useDefault: false, overrides: []),
            extendedProperties: GoogleCalendarExtendedProperties(private: [
                "rotEntityId": entityID.uuidString,
                "rotEntityType": entityType.rawValue,
                "rotPlanId": planID.uuidString,
                "rotSchema": Self.schemaVersion
            ])
        )
    }

    private func desired(type: GoogleCalendarLocalEntityType, id: UUID, planID: UUID, payload: GoogleCalendarEventPayload) -> GoogleCalendarDesiredEvent {
        let hashData = (try? JSONEncoder.google.encode(payload)) ?? Data()
        let hash = Data(SHA256.hash(data: hashData)).hexString
        return GoogleCalendarDesiredEvent(entityType: type, entityID: id, trainingPlanID: planID, payload: payload, hash: hash)
    }

    private func plannedDescription(_ workout: PlannedWorkout, completion: CompletedActivity?) -> String {
        var lines: [String] = ["\(kindTitle(workout.kind)) · \(distanceText(km: workout.distanceKm))", ""]
        if let completion {
            lines += [
                "Completed",
                completion.distanceMeters.map { distanceText(km: $0 / 1000) } ?? "",
                Formatters.duration(completion.durationSeconds),
                Formatters.pace(completion.avgPaceSecondsPerKm),
                ""
            ].filter { !$0.isEmpty }
        }
        if let band = workout.paceBand {
            lines += ["Target", "\(Formatters.pace(band.fastSecondsPerKm))–\(Formatters.pace(band.slowSecondsPerKm))", ""]
        }
        if !workout.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines += ["Workout", workout.details, ""]
        }
        if let seconds = workout.expectedDurationSeconds {
            lines.append("Estimated duration: \(Int((seconds / 60).rounded())) min")
            lines.append("")
        }
        lines.append("Managed by RestOrTrain")
        return lines.joined(separator: "\n")
    }

    private func completedDescription(_ activity: CompletedActivity) -> String {
        [
            "Completed Run",
            activity.distanceMeters.map { distanceText(km: $0 / 1000) },
            Formatters.duration(activity.durationSeconds),
            Formatters.pace(activity.avgPaceSecondsPerKm),
            "",
            "Managed by RestOrTrain"
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func startOfCurrentTrainingWeek(plan: TrainingPlan, today: Date) -> Date {
        let week = max(0, calendar.dateComponents([.weekOfYear], from: plan.anchorDate, to: today).weekOfYear ?? 0)
        let date = calendar.date(byAdding: .weekOfYear, value: week, to: plan.anchorDate) ?? today
        return calendar.startOfDay(for: date)
    }

    private func planEndInclusiveEnd(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    private func minDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs < rhs ? lhs : rhs
    }

    private func kindTitle(_ kind: WorkoutKind?) -> String {
        switch kind {
        case .easy: "Easy Run"
        case .long: "Long Run"
        case .tempo: "Tempo Run"
        case .intervals: "Intervals"
        case .race: "Race"
        case nil: "Run"
        }
    }

    private func distanceText(km: Double) -> String {
        abs(km.rounded() - km) < 0.05 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km)
    }

    static func localDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func rfc3339(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func deterministicEventID(type: GoogleCalendarLocalEntityType, id: UUID) -> String {
        let data = Data("\(type.rawValue):\(id.uuidString)".utf8)
        return "rot" + Data(SHA256.hash(data: data)).hexString.prefix(32)
    }
}

struct GoogleCalendarInboundOutcome: Equatable {
    var applied: Int = 0
    var needsReview: Int = 0
    var restored: Int = 0
    var deleted: Int = 0

    var total: Int { applied + needsReview + restored + deleted }
}

struct GoogleCalendarInboundReconciler {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func targetDate(from event: GoogleCalendarRemoteEvent, fallbackDurationSeconds: Double?) -> Date? {
        guard let start = event.start else { return nil }
        if let dateTime = start.dateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let parsed = formatter.date(from: dateTime) {
                return parsed
            }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: dateTime) {
                return parsed
            }
        }
        if let date = start.date, let day = Self.localDate(date, calendar: calendar) {
            return day
        }
        return nil
    }

    func scheduleSignature(for event: GoogleCalendarRemoteEvent) -> String? {
        guard let start = event.start else { return nil }
        return [start.date, start.dateTime, start.timeZone].compactMap { $0 }.joined(separator: "|")
    }

    func contentDiffers(remote event: GoogleCalendarRemoteEvent, desired: GoogleCalendarEventPayload) -> Bool {
        if event.status == "cancelled" { return true }
        if let summary = event.summary, summary != desired.summary { return true }
        if let description = event.description, description != (desired.description ?? "") { return true }
        return false
    }

    func updatedDate(from event: GoogleCalendarRemoteEvent) -> Date? {
        guard let updated = event.updated else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let parsed = formatter.date(from: updated) { return parsed }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: updated)
    }

    func decision(
        workout: PlannedWorkout,
        targetDate: Date,
        allWorkouts: [PlannedWorkout],
        plan: TrainingPlan,
        goal: GoalSpec,
        desiredPayload: GoogleCalendarEventPayload
    ) -> GoogleCalendarInboundDecision {
        let originalDay = calendar.startOfDay(for: workout.date)
        let targetDay = calendar.startOfDay(for: targetDate)
        let scheduledDate = targetDate

        if calendar.isDate(originalDay, inSameDayAs: targetDay) {
            guard abs(workout.date.timeIntervalSince(scheduledDate)) >= 60 else {
                return .ignored
            }
            return .apply(date: scheduledDate, reason: .sameDayTimeChanged, message: "Time updated from Google Calendar.")
        }

        let validation = ScheduleMoveValidationService(calendar: calendar).validate(
            workout: workout,
            targetDate: scheduledDate,
            allWorkouts: allWorkouts,
            plan: plan,
            goal: goal
        )
        switch validation.result {
        case .safeAutomatic:
            return .apply(date: scheduledDate, reason: .sameWeekDateChanged, message: "Date updated from Google Calendar.")
        case .targetDayConflict:
            return .review(reason: .targetDayConflict, message: "Calendar change needs review because the target day already contains another workout.")
        case .crossWeekReview, .crossPhaseReview:
            return .review(reason: .outsidePlannedWeek, message: "Workout moved outside its planned week. Review with Coach before changing plan structure.")
        case .outsidePlan:
            return .review(reason: .outsidePlannedWeek, message: "This calendar change cannot be applied automatically because the requested date falls outside the current training plan.")
        case .invalidDate:
            return .review(reason: .planValidationFailed, message: validation.reasons.first ?? "Review required because this move changes plan constraints.")
        case .sameDayTimeOnly:
            return .apply(date: scheduledDate, reason: .sameDayTimeChanged, message: "Time updated from Google Calendar.")
        }
    }

    private func samePlanWeek(original: Date, target: Date, weekIndex: Int, plan: TrainingPlan) -> Bool {
        let weekStart = calendar.date(
            byAdding: .day,
            value: weekIndex * 7,
            to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
        ) ?? calendar.startOfDay(for: original)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return original >= weekStart && original < weekEnd && target >= weekStart && target < weekEnd
    }

    private func validationIssuesAfterMoving(
        workout: PlannedWorkout,
        to target: Date,
        workouts: [PlannedWorkout],
        plan: TrainingPlan,
        goal: GoalSpec
    ) -> [PlanValidator.Issue] {
        let weeks = plan.weekPhasesRaw.indices.map { index in
            let phase = TrainingPhase(rawValue: plan.weekPhasesRaw[index]) ?? .base
            let start = calendar.date(
                byAdding: .day,
                value: index * 7,
                to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
            ) ?? plan.anchorDate
            let specs = workouts
                .filter { $0.weekIndex == index }
                .compactMap { row -> PlannedWorkoutSpec? in
                    guard let kind = row.kind else { return nil }
                    return PlannedWorkoutSpec(
                        date: row.uuid == workout.uuid ? target : row.date,
                        kind: kind,
                        distanceKm: row.distanceKm,
                        paceBand: row.paceBand,
                        details: row.details,
                        structure: row.structure
                    )
                }
            return WeekPlan(
                startDate: start,
                index: index,
                phase: phase,
                isDownWeek: plan.weekIsDown[index],
                isPartial: index == 0 && !calendar.isDate(plan.anchorDate, inSameDayAs: start),
                targetVolumeKm: plan.weekTargetVolumesKm[index],
                workouts: specs
            )
        }
        let spec = TrainingPlanSpec(goal: goal, anchorDate: plan.anchorDate, weeks: weeks)
        return PlanValidator.validate(spec, calendar: calendar)
    }

    private static func localDate(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day))
    }
}

enum GoogleCalendarInboundDecision: Equatable {
    case apply(date: Date, reason: GoogleCalendarInboundChangeReason, message: String)
    case review(reason: GoogleCalendarInboundChangeReason, message: String)
    case ignored
}

@MainActor
final class GoogleCalendarSyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var isOffline = false
    @Published private(set) var lastIssue: String?

    private let modelContext: ModelContext
    private let api: GoogleCalendarAPIServicing
    private let oauth: GoogleCalendarOAuthService
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.khanhnguyen.TrainOrRest", category: "google-calendar")
    private var planChangeObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "TrainOrRest.GoogleCalendar.Path")

    init(
        modelContext: ModelContext,
        api: GoogleCalendarAPIServicing = GoogleCalendarAPIClient(),
        oauth: GoogleCalendarOAuthService? = nil,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.api = api
        self.oauth = oauth ?? GoogleCalendarOAuthService()
        self.calendar = calendar
        self.timeZone = timeZone
        self.now = now
        observePlanChanges()
        observeNetwork()
    }

    deinit {
        if let planChangeObserver {
            NotificationCenter.default.removeObserver(planChangeObserver)
        }
        pathMonitor.cancel()
        debounceTask?.cancel()
    }

    func connection() -> GoogleCalendarConnection {
        if let existing = (try? modelContext.fetch(FetchDescriptor<GoogleCalendarConnection>()).first) {
            return existing
        }
        let created = GoogleCalendarConnection(now: now())
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    func connect() async {
        let connection = connection()
        connection.connectionStatus = .connecting
        do {
            logger.info("Google Calendar OAuth started")
            let authorized = try await oauth.authorize()
            connection.googleAccountID = authorized.profile.sub
            connection.maskedEmail = Self.mask(authorized.profile.email)
            connection.connectionStatus = .initialSync
            try GoogleCalendarTokenStore.save(authorized.tokens, connectionID: connection.uuid)
            try modelContext.save()
            logger.info("Google Calendar OAuth succeeded")
            await reconcile(reason: "initialSync")
        } catch {
            logger.error("Google Calendar OAuth failed: \(String(describing: error), privacy: .public)")
            connection.connectionStatus = .needsReconnect
            connection.lastSyncErrorCategory = error is GoogleCalendarOAuthError ? .notConfigured : .permissionRevoked
            lastIssue = (error as? LocalizedError)?.errorDescription ?? "Google Calendar was not connected."
            try? modelContext.save()
        }
    }

    func reconnect() async {
        await connect()
    }

    func checkForCalendarChanges(reason: String = "manualInbound") async {
        await checkForCalendarChanges(reason: reason, canResetExpiredSyncToken: true)
    }

    private func checkForCalendarChanges(reason: String, canResetExpiredSyncToken: Bool) async {
        let connection = connection()
        guard connection.connectionStatus != .disconnected else { return }
        if isOffline {
            connection.connectionStatus = .offlineQueued
            connection.lastCalendarChangeSummary = "Calendar changes will be checked when you are online."
            try? modelContext.save()
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        connection.connectionStatus = .syncing
        connection.lastSyncAttemptAt = now()
        do {
            let token = try await accessToken(for: connection)
            let calendarID = try await ensureCalendar(connection: connection, accessToken: token)
            let outcome = try await importCalendarChanges(connection: connection, calendarID: calendarID, accessToken: token)
            let outbound = try await reconcileEvents(connection: connection, calendarID: calendarID, accessToken: token)
            connection.connectionStatus = outbound.failed == 0 ? .connected : .partialFailure
            connection.lastSyncErrorCategory = outbound.failed == 0 ? .none : .partialEventFailure
            connection.lastSuccessfulSyncAt = now()
            connection.lastCalendarChangeCheckAt = now()
            connection.lastCalendarChangeSummary = inboundSummary(outcome)
            connection.lastSyncSummary = [inboundSummary(outcome), outbound.summary].filter { !$0.isEmpty }.joined(separator: " ")
            lastIssue = outcome.needsReview > 0 ? inboundSummary(outcome) : nil
            try modelContext.save()
            logger.info("Google Calendar inbound check completed: \(connection.lastSyncSummary ?? "", privacy: .public)")
        } catch GoogleCalendarAPIError.syncTokenExpired where canResetExpiredSyncToken {
            connection.googleCalendarIncrementalSyncToken = nil
            try? modelContext.save()
            logTelemetry("sync_token_reset")
            isSyncing = false
            await checkForCalendarChanges(reason: "syncTokenExpired", canResetExpiredSyncToken: false)
        } catch {
            handleSyncError(error, connection: connection)
        }
    }

    func reconcile(reason: String = "manual") async {
        await reconcile(reason: reason, canResetExpiredSyncToken: true)
    }

    private func reconcile(reason: String, canResetExpiredSyncToken: Bool) async {
        let connection = connection()
        guard connection.connectionStatus != .disconnected else { return }
        if isOffline {
            connection.connectionStatus = .offlineQueued
            connection.lastSyncSummary = "Google Calendar will update when you are online."
            try? modelContext.save()
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        connection.connectionStatus = connection.lastSuccessfulSyncAt == nil ? .initialSync : .syncing
        connection.lastSyncAttemptAt = now()
        do {
            let token = try await accessToken(for: connection)
            let calendarID = try await ensureCalendar(connection: connection, accessToken: token)
            let inbound = connection.allowsSchedulingFromGoogle
                ? try await importCalendarChanges(connection: connection, calendarID: calendarID, accessToken: token)
                : GoogleCalendarInboundOutcome()
            let result = try await reconcileEvents(connection: connection, calendarID: calendarID, accessToken: token)
            connection.connectionStatus = result.failed == 0 ? .connected : .partialFailure
            connection.lastSyncErrorCategory = result.failed == 0 ? .none : .partialEventFailure
            connection.lastSuccessfulSyncAt = now()
            if connection.allowsSchedulingFromGoogle {
                connection.lastCalendarChangeCheckAt = now()
                connection.lastCalendarChangeSummary = inboundSummary(inbound)
            }
            connection.lastSyncSummary = [connection.allowsSchedulingFromGoogle ? inboundSummary(inbound) : "", result.summary]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            lastIssue = result.failed == 0 && inbound.needsReview == 0 ? nil : connection.lastSyncSummary
            try modelContext.save()
            logger.info("Google Calendar sync completed: \(result.summary, privacy: .public)")
        } catch GoogleCalendarAPIError.syncTokenExpired where canResetExpiredSyncToken {
            connection.googleCalendarIncrementalSyncToken = nil
            try? modelContext.save()
            logTelemetry("sync_token_reset")
            isSyncing = false
            await reconcile(reason: "syncTokenExpired", canResetExpiredSyncToken: false)
        } catch {
            handleSyncError(error, connection: connection)
        }
    }

    func createCalendarAgain() async {
        let connection = connection()
        connection.googleCalendarID = nil
        let links = (try? modelContext.fetch(FetchDescriptor<GoogleCalendarEventLink>())) ?? []
        for link in links where link.connectionID == connection.uuid {
            modelContext.delete(link)
        }
        await reconcile(reason: "createCalendarAgain")
    }

    func disconnect(deleteCalendar: Bool) async {
        let connection = connection()
        let storedTokens = try? GoogleCalendarTokenStore.load(connectionID: connection.uuid)
        if deleteCalendar, let calendarID = connection.googleCalendarID,
           let token = try? await accessToken(for: connection) {
            try? await api.deleteCalendar(id: calendarID, accessToken: token)
        }
        if let revokeCandidate = storedTokens?.refreshToken ?? storedTokens?.accessToken {
            try? await api.revokeToken(revokeCandidate)
        }
        try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid)
        let links = (try? modelContext.fetch(FetchDescriptor<GoogleCalendarEventLink>())) ?? []
        for link in links where link.connectionID == connection.uuid {
            modelContext.delete(link)
        }
        connection.connectionStatus = .disconnected
        connection.googleCalendarID = deleteCalendar ? nil : connection.googleCalendarID
        connection.lastSyncSummary = nil
        try? modelContext.save()
        logger.info("Google Calendar disconnected")
    }

    func updatePreferences(completedMode: GoogleCalendarCompletedActivityMode) {
        let connection = connection()
        connection.completedActivityMode = completedMode
        try? modelContext.save()
        scheduleDebouncedReconcile()
    }

    func updateSchedulingFromGoogle(enabled: Bool) {
        let connection = connection()
        connection.allowsSchedulingFromGoogle = enabled
        if !enabled {
            connection.googleCalendarIncrementalSyncToken = nil
        }
        try? modelContext.save()
        logTelemetry(enabled ? "two_way_scheduling_enabled" : "two_way_scheduling_disabled")
        if enabled {
            scheduleDebouncedReconcile()
        }
    }

    func enableSmartScheduling() async {
        let connection = connection()
        guard connection.connectionStatus != .disconnected else { return }
        do {
            logTelemetry("smart_scheduling_enabled")
            let authorized = try await oauth.authorizeSmartScheduling()
            var tokens = authorized.tokens
            if tokens.refreshToken == nil,
               let existing = try? GoogleCalendarTokenStore.load(connectionID: connection.uuid) {
                tokens.refreshToken = existing.refreshToken
            }
            try GoogleCalendarTokenStore.save(tokens, connectionID: connection.uuid)
            connection.googleAccountID = authorized.profile.sub
            connection.maskedEmail = Self.mask(authorized.profile.email)
            connection.smartSchedulingStatus = .enabled
            try modelContext.save()
            await refreshAvailability(reason: "smartSchedulingEnabled")
        } catch {
            connection.smartSchedulingStatus = .needsPermission
            lastIssue = "Smart Scheduling needs Google Calendar permission."
            try? modelContext.save()
            logTelemetry("availability_refresh_failed", ["reason": "permission"])
        }
    }

    func disableSmartScheduling() {
        let connection = connection()
        connection.smartSchedulingStatus = .off
        connection.smartSchedulingLastAvailabilitySummary = nil
        clearAvailabilityCache(connectionID: connection.uuid)
        try? modelContext.save()
        logTelemetry("smart_scheduling_disabled")
    }

    func updateSmartSchedulingCalendar(_ calendarID: String, selected: Bool) {
        let connection = connection()
        let calendars = (try? modelContext.fetch(FetchDescriptor<GoogleAvailabilityCalendar>())) ?? []
        if let item = calendars.first(where: { $0.connectionID == connection.uuid && $0.googleCalendarID == calendarID }) {
            item.selectedForAvailability = selected
            item.updatedAt = now()
        }
        connection.smartSchedulingSelectedCalendarIDs = calendars
            .filter { $0.connectionID == connection.uuid && ($0.googleCalendarID == calendarID ? selected : $0.selectedForAvailability) }
            .map(\.googleCalendarID)
        try? modelContext.save()
    }

    func updateSmartSchedulingPreferences(
        preferredTime: PreferredTrainingTime,
        earliestStartMinutes: Int,
        latestFinishMinutes: Int,
        bufferBeforeMinutes: Int,
        bufferAfterMinutes: Int
    ) {
        let connection = connection()
        connection.preferredTrainingTime = preferredTime
        connection.smartSchedulingEarliestStartMinutes = earliestStartMinutes
        connection.smartSchedulingLatestFinishMinutes = latestFinishMinutes
        connection.smartSchedulingBufferBeforeMinutes = bufferBeforeMinutes
        connection.smartSchedulingBufferAfterMinutes = bufferAfterMinutes
        try? modelContext.save()
    }

    func refreshAvailability(reason: String = "manual") async {
        let connection = connection()
        guard connection.smartSchedulingEnabled else { return }
        if isOffline {
            connection.smartSchedulingLastAvailabilitySummary = "Calendar availability is temporarily unavailable."
            try? modelContext.save()
            return
        }
        logTelemetry("availability_refresh_started")
        do {
            let token = try await accessToken(for: connection)
            let calendars = try await api.listCalendarList(accessToken: token)
            upsertAvailabilityCalendars(calendars, connection: connection)
            let selectedIDs = selectedAvailabilityCalendarIDs(connection: connection)
            guard !selectedIDs.isEmpty else {
                connection.smartSchedulingLastAvailabilitySummary = "No availability calendars selected."
                try modelContext.save()
                return
            }
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now()) ?? now())
            let end = calendar.date(byAdding: .day, value: 15, to: start) ?? start
            let request = GoogleFreeBusyRequest(
                timeMin: ISO8601DateFormatter.google.string(from: start),
                timeMax: ISO8601DateFormatter.google.string(from: end),
                timeZone: timeZone.identifier,
                calendarExpansionMax: min(selectedIDs.count, 50),
                items: selectedIDs.prefix(50).map { GoogleFreeBusyItem(id: $0) }
            )
            let response = try await api.freeBusy(request: request, accessToken: token)
            normalizeAvailability(response: response, connection: connection, start: start, end: end)
            connection.smartSchedulingLastAvailabilityRefreshAt = now()
            connection.smartSchedulingLastAvailabilitySummary = "Availability refreshed."
            try modelContext.save()
            logTelemetry("availability_refresh_completed", ["days": "\(availabilityDays(connectionID: connection.uuid).count)"])
        } catch GoogleCalendarAPIError.unauthorized {
            connection.smartSchedulingStatus = .needsPermission
            connection.smartSchedulingLastAvailabilitySummary = "Smart Scheduling needs Google Calendar permission."
            try? modelContext.save()
            logTelemetry("permission_revoked")
        } catch {
            connection.smartSchedulingLastAvailabilitySummary = "Could not refresh calendar availability."
            try? modelContext.save()
            logTelemetry("availability_refresh_failed")
        }
    }

    func smartSchedulingCandidates(for workout: PlannedWorkout, limit: Int = 3) -> [SchedulingCandidate] {
        let connection = connection()
        guard connection.smartSchedulingEnabled,
              let plan = (try? modelContext.fetch(FetchDescriptor<TrainingPlan>()))?.first,
              let goal = (try? modelContext.fetch(FetchDescriptor<Goal>()))?.first?.spec else { return [] }
        let workouts = (try? modelContext.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let candidateDates = candidateDates(for: workout, plan: plan)
        let request = SchedulingRequest(
            workout: workout,
            candidateDates: candidateDates,
            currentTrainingWeek: workout.weekIndex,
            surroundingWorkouts: workouts,
            userPreferences: smartPreferences(connection),
            availability: availabilityDays(connectionID: connection.uuid),
            timezone: timeZone,
            plan: plan,
            goal: goal
        )
        logTelemetry("candidate_search_started")
        let candidates = SmartSchedulingEngine(calendar: calendar).candidates(for: request, limit: limit)
        logTelemetry(candidates.isEmpty ? "no_candidate_found" : "candidate_search_completed", ["count": "\(candidates.count)"])
        return candidates
    }

    func acceptSmartSchedulingCandidate(_ candidate: SchedulingCandidate) {
        guard let workout = workout(id: candidate.workoutID) else { return }
        let operation = ScheduleChangeOperation(
            source: "smartScheduling",
            affectedWorkoutIDs: [workout.uuid],
            requestedChanges: ["\(workout.uuid.uuidString): \(workout.date.ISO8601Format()) -> \(candidate.startTime.ISO8601Format())"],
            status: .applying,
            now: now()
        )
        modelContext.insert(operation)
        workout.date = candidate.startTime
        workout.manuallyOverridden = true
        workout.scheduleUpdatedFrom = "smartScheduling"
        workout.scheduleUpdatedAt = now()
        operation.status = .completed
        markOutboundPending(entityID: workout.uuid)
        try? modelContext.save()
        logTelemetry("schedule_recommendation_accepted")
        NotificationCenter.default.post(name: .planDidChange, object: nil)
        scheduleDebouncedReconcile()
    }

    func acceptSmartSchedulingCandidate(_ candidate: SchedulingCandidate, resolvingReview changeID: UUID) {
        acceptSmartSchedulingCandidate(candidate)
        guard let change = inboundChange(id: changeID) else { return }
        change.status = .applied
        change.message = "Smart Scheduling alternative accepted."
        try? modelContext.save()
        logTelemetry("schedule_recommendation_accepted", ["source": "google_review"])
    }

    func restoreOriginalSchedule(for changeID: UUID) {
        guard let change = inboundChange(id: changeID) else { return }
        change.status = .rejected
        change.message = "RestOrTrain kept the original schedule and will restore Google Calendar."
        logTelemetry("review_rejected", ["reason": change.reason.rawValue])
        markOutboundPending(entityID: change.localEntityID)
        try? modelContext.save()
        scheduleDebouncedReconcile()
    }

    func addBackToGoogleCalendar(workoutID: UUID) {
        let links = (try? modelContext.fetch(FetchDescriptor<GoogleCalendarEventLink>())) ?? []
        for link in links where link.localEntityID == workoutID && link.syncState == .notVisibleInGoogleCalendar {
            modelContext.delete(link)
        }
        let changes = (try? modelContext.fetch(FetchDescriptor<GoogleCalendarInboundChange>())) ?? []
        for change in changes where change.localEntityID == workoutID && change.reason == .eventDeleted && change.status == .pendingReview {
            change.status = .restored
            change.message = "Workout will be added back to Google Calendar."
        }
        logTelemetry("event_restored")
        try? modelContext.save()
        scheduleDebouncedReconcile()
    }

    func swapWorkouts(for changeID: UUID) {
        guard let change = inboundChange(id: changeID),
              change.reason == .targetDayConflict,
              let proposedDate = change.proposedDate,
              let workout = workout(id: change.localEntityID),
              let other = workouts(on: proposedDate).first(where: { $0.uuid != workout.uuid }) else {
            return
        }
        let originalDate = workout.date
        let operation = ScheduleChangeOperation(
            source: "googleCalendar",
            affectedWorkoutIDs: [workout.uuid, other.uuid],
            requestedChanges: [
                "\(workout.uuid.uuidString): \(originalDate.ISO8601Format()) -> \(proposedDate.ISO8601Format())",
                "\(other.uuid.uuidString): \(proposedDate.ISO8601Format()) -> \(originalDate.ISO8601Format())"
            ],
            status: .applying,
            now: now()
        )
        modelContext.insert(operation)
        workout.date = proposedDate
        other.date = originalDate
        workout.manuallyOverridden = true
        other.manuallyOverridden = true

        if let issue = validationIssuesForCurrentPlan().first {
            workout.date = originalDate
            other.date = proposedDate
            operation.status = .failed
            operation.failureMessage = issue.message
            change.message = "These workouts should not be swapped. \(issue.message)"
            try? modelContext.save()
            return
        }

        operation.status = .completed
        change.status = .applied
        change.message = "Swapped workouts from Google Calendar review."
        logTelemetry("review_accepted", ["action": "swap"])
        markScheduledFromGoogle(workout)
        markScheduledFromGoogle(other)
        markOutboundPending(entityID: workout.uuid)
        markOutboundPending(entityID: other.uuid)
        try? modelContext.save()
        scheduleDebouncedReconcile()
    }

    func moveReviewedWorkout(for changeID: UUID, to targetDate: Date) {
        guard let change = inboundChange(id: changeID),
              change.status == .pendingReview,
              let workout = workout(id: change.localEntityID) else {
            return
        }
        if workouts(on: targetDate).contains(where: { $0.uuid != workout.uuid }) {
            change.reason = .targetDayConflict
            change.proposedDate = targetDate
            change.message = "Calendar change needs review. The chosen day already contains another workout."
            try? modelContext.save()
            return
        }

        let original = workout.date
        workout.date = targetDate
        workout.manuallyOverridden = true

        if let issue = validationIssuesForCurrentPlan().first {
            workout.date = original
            change.reason = .planValidationFailed
            change.proposedDate = targetDate
            change.message = "This move needs review. \(issue.message)"
            try? modelContext.save()
            return
        }

        change.status = .applied
        change.proposedDate = targetDate
        change.message = "Moved workout from calendar review."
        logTelemetry("review_accepted", ["action": "choose_another_day"])
        markScheduledFromGoogle(workout)
        markOutboundPending(entityID: workout.uuid)
        try? modelContext.save()
        scheduleDebouncedReconcile()
    }

    private func upsertAvailabilityCalendars(_ entries: [GoogleCalendarListEntry], connection: GoogleCalendarConnection) {
        let existing = (try? modelContext.fetch(FetchDescriptor<GoogleAvailabilityCalendar>())) ?? []
        for entry in entries {
            let name = entry.summary ?? "Calendar"
            let excludedReason = defaultAvailabilityExclusionReason(entry, connection: connection)
            let selected = excludedReason == nil && (entry.selected ?? true)
            if let row = existing.first(where: { $0.connectionID == connection.uuid && $0.googleCalendarID == entry.id }) {
                row.displayName = name
                row.accessRole = entry.accessRole
                row.isPrimary = entry.primary ?? false
                row.excludedByDefaultReason = excludedReason
                row.updatedAt = now()
            } else {
                modelContext.insert(GoogleAvailabilityCalendar(
                    connectionID: connection.uuid,
                    googleCalendarID: entry.id,
                    displayName: name,
                    accessRole: entry.accessRole,
                    isPrimary: entry.primary ?? false,
                    selectedForAvailability: selected,
                    excludedByDefaultReason: excludedReason,
                    now: now()
                ))
            }
        }
        let all = (try? modelContext.fetch(FetchDescriptor<GoogleAvailabilityCalendar>())) ?? []
        connection.smartSchedulingSelectedCalendarIDs = all
            .filter { $0.connectionID == connection.uuid && $0.selectedForAvailability }
            .map(\.googleCalendarID)
    }

    private func defaultAvailabilityExclusionReason(_ entry: GoogleCalendarListEntry, connection: GoogleCalendarConnection) -> String? {
        let name = (entry.summary ?? "").lowercased()
        if entry.id == connection.googleCalendarID || entry.summary == connection.calendarName {
            return "RestOrTrain Training calendar is excluded to avoid double-counting workouts."
        }
        if name.contains("holiday") || name.contains("birthday") {
            return "Holiday and birthday calendars are excluded by default."
        }
        return nil
    }

    private func selectedAvailabilityCalendarIDs(connection: GoogleCalendarConnection) -> [String] {
        let rows = (try? modelContext.fetch(FetchDescriptor<GoogleAvailabilityCalendar>())) ?? []
        let selected = rows
            .filter { $0.connectionID == connection.uuid && $0.selectedForAvailability }
            .map(\.googleCalendarID)
        return selected.isEmpty ? connection.smartSchedulingSelectedCalendarIDsOrDefault : selected
    }

    private func normalizeAvailability(response: GoogleFreeBusyResponse, connection: GoogleCalendarConnection, start: Date, end: Date) {
        clearAvailabilityCache(connectionID: connection.uuid)
        let busy = response.calendars.values
            .flatMap(\.busy)
            .compactMap { block -> AvailabilityWindow? in
                guard let start = Self.googleDate(from: block.start),
                      let end = Self.googleDate(from: block.end),
                      end > start else { return nil }
                return AvailabilityWindow(start: start, end: end, state: .busy)
            }
        var day = calendar.startOfDay(for: start)
        while day < end {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? end
            let dayBusy = mergeBusyWindows(busy.filter { $0.start < next && $0.end > day }, dayStart: day, dayEnd: next)
            let available = availableWindows(from: dayBusy, dayStart: day, dayEnd: next)
            modelContext.insert(DayAvailability(
                connectionID: connection.uuid,
                date: day,
                timezoneIdentifier: timeZone.identifier,
                busyWindows: dayBusy,
                availableWindows: available,
                lastRefreshedAt: now()
            ))
            day = next
        }
    }

    private func mergeBusyWindows(_ windows: [AvailabilityWindow], dayStart: Date, dayEnd: Date) -> [AvailabilityWindow] {
        let clipped = windows
            .map { AvailabilityWindow(start: max($0.start, dayStart), end: min($0.end, dayEnd), state: .busy) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [AvailabilityWindow] = []
        for window in clipped {
            if let last = merged.last, window.start <= last.end {
                merged.removeLast()
                merged.append(AvailabilityWindow(start: last.start, end: max(last.end, window.end), state: .busy))
            } else {
                merged.append(window)
            }
        }
        return merged
    }

    private func availableWindows(from busy: [AvailabilityWindow], dayStart: Date, dayEnd: Date) -> [AvailabilityWindow] {
        var available: [AvailabilityWindow] = []
        var cursor = dayStart
        for block in busy {
            if block.start > cursor {
                available.append(AvailabilityWindow(start: cursor, end: block.start, state: .available))
            }
            cursor = max(cursor, block.end)
        }
        if cursor < dayEnd {
            available.append(AvailabilityWindow(start: cursor, end: dayEnd, state: .available))
        }
        return available.filter { $0.durationMinutes >= 15 }
    }

    private func clearAvailabilityCache(connectionID: UUID) {
        let days = (try? modelContext.fetch(FetchDescriptor<DayAvailability>())) ?? []
        for day in days where day.connectionID == connectionID {
            modelContext.delete(day)
        }
    }

    private func availabilityDays(connectionID: UUID) -> [DayAvailability] {
        ((try? modelContext.fetch(FetchDescriptor<DayAvailability>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.connectionID == connectionID }
    }

    private func smartPreferences(_ connection: GoogleCalendarConnection) -> SmartSchedulingPreferences {
        SmartSchedulingPreferences(
            preferredTime: connection.preferredTrainingTime,
            earliestStartMinutes: connection.smartSchedulingEarliestStartOrDefault,
            latestFinishMinutes: connection.smartSchedulingLatestFinishOrDefault,
            bufferBeforeMinutes: connection.smartSchedulingBufferBeforeOrDefault,
            bufferAfterMinutes: connection.smartSchedulingBufferAfterOrDefault
        )
    }

    private func candidateDates(for workout: PlannedWorkout, plan: TrainingPlan) -> [Date] {
        let weekStart = calendar.date(
            byAdding: .day,
            value: workout.weekIndex * 7,
            to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
        ) ?? calendar.startOfDay(for: workout.date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private static func googleDate(from string: String) -> Date? {
        ISO8601DateFormatter.google.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private func accessToken(for connection: GoogleCalendarConnection) async throws -> String {
        guard var tokens = try GoogleCalendarTokenStore.load(connectionID: connection.uuid) else {
            throw GoogleCalendarAPIError.unauthorized
        }
        if tokens.expiresAt <= now(), let refresh = tokens.refreshToken {
            let refreshed = try await api.refresh(refresh)
            tokens = refreshed
            try GoogleCalendarTokenStore.save(tokens, connectionID: connection.uuid)
        }
        return tokens.accessToken
    }

    private func inboundChange(id: UUID) -> GoogleCalendarInboundChange? {
        ((try? modelContext.fetch(FetchDescriptor<GoogleCalendarInboundChange>())) ?? [])
            .first { $0.uuid == id }
    }

    private func workout(id: UUID) -> PlannedWorkout? {
        ((try? modelContext.fetch(FetchDescriptor<PlannedWorkout>())) ?? [])
            .first { $0.uuid == id }
    }

    private func workouts(on date: Date) -> [PlannedWorkout] {
        ((try? modelContext.fetch(FetchDescriptor<PlannedWorkout>())) ?? [])
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func markOutboundPending(entityID: UUID) {
        let links = (try? modelContext.fetch(FetchDescriptor<GoogleCalendarEventLink>())) ?? []
        for link in links where link.localEntityID == entityID {
            link.syncState = .pending
            link.lastSyncedHash = nil
        }
    }

    private func validationIssuesForCurrentPlan() -> [PlanValidator.Issue] {
        guard let goalModel = try? PlanStore.activeGoal(in: modelContext),
              let goal = goalModel.spec,
              let plan = try? PlanStore.activePlan(in: modelContext) else {
            return []
        }
        let workouts = ((try? modelContext.fetch(FetchDescriptor<PlannedWorkout>())) ?? [])
        let weeks = plan.weekPhasesRaw.indices.map { index in
            let phase = TrainingPhase(rawValue: plan.weekPhasesRaw[index]) ?? .base
            let start = calendar.date(
                byAdding: .day,
                value: index * 7,
                to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
            ) ?? plan.anchorDate
            return WeekPlan(
                startDate: start,
                index: index,
                phase: phase,
                isDownWeek: plan.weekIsDown[index],
                isPartial: index == 0 && !calendar.isDate(plan.anchorDate, inSameDayAs: start),
                targetVolumeKm: plan.weekTargetVolumesKm[index],
                workouts: workouts
                    .filter { $0.weekIndex == index }
                    .compactMap { row in
                        guard let kind = row.kind else { return nil }
                        return PlannedWorkoutSpec(
                            date: row.date,
                            kind: kind,
                            distanceKm: row.distanceKm,
                            paceBand: row.paceBand,
                            details: row.details,
                            structure: row.structure
                        )
                    }
            )
        }
        return PlanValidator.validate(TrainingPlanSpec(goal: goal, anchorDate: plan.anchorDate, weeks: weeks), calendar: calendar)
    }

    private func ensureCalendar(connection: GoogleCalendarConnection, accessToken: String) async throws -> String {
        if let id = connection.googleCalendarID, !id.isEmpty {
            _ = try await api.calendar(id: id, accessToken: accessToken)
            return id
        }
        let created = try await api.createCalendar(
            name: GoogleCalendarSyncSettings.calendarName,
            description: GoogleCalendarSyncSettings.calendarDescription,
            timeZone: timeZone.identifier,
            accessToken: accessToken
        )
        connection.googleCalendarID = created.id
        connection.calendarName = created.summary ?? GoogleCalendarSyncSettings.calendarName
        try modelContext.save()
        logger.info("Google Calendar secondary calendar created")
        return created.id
    }

    private func importCalendarChanges(connection: GoogleCalendarConnection, calendarID: String, accessToken: String) async throws -> GoogleCalendarInboundOutcome {
        guard connection.allowsSchedulingFromGoogle else { return GoogleCalendarInboundOutcome() }
        logTelemetry("inbound_sync_started")
        let page = try await api.listEvents(
            calendarID: calendarID,
            syncToken: connection.googleCalendarIncrementalSyncToken,
            accessToken: accessToken
        )
        connection.googleCalendarIncrementalSyncToken = page.nextSyncToken
        guard !page.items.isEmpty else { return GoogleCalendarInboundOutcome() }

        let plan = try PlanStore.activePlan(in: modelContext)
        let goal = try PlanStore.activeGoal(in: modelContext)?.spec
        let workouts = try modelContext.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
        let activities = try modelContext.fetch(FetchDescriptor<CompletedActivity>(sortBy: [SortDescriptor(\.date)]))
        let desired = GoogleCalendarEventBuilder(calendar: calendar, timeZone: timeZone)
            .desiredEvents(plan: plan, workouts: workouts, activities: activities, connection: connection, today: now())
        let desiredByEventID = Dictionary(uniqueKeysWithValues: desired.compactMap { desired -> (String, GoogleCalendarDesiredEvent)? in
            guard let id = desired.payload.id else { return nil }
            return (id, desired)
        })
        let links = try modelContext.fetch(FetchDescriptor<GoogleCalendarEventLink>())
            .filter { $0.connectionID == connection.uuid && $0.localEntityType == .plannedWorkout }
        let linksByEventID = Dictionary(uniqueKeysWithValues: links.map { ($0.googleEventID, $0) })
        let reconciler = GoogleCalendarInboundReconciler(calendar: calendar)
        var outcome = GoogleCalendarInboundOutcome()

        for event in page.items {
            guard let link = linksByEventID[event.id],
                  let workout = workouts.first(where: { $0.uuid == link.localEntityID }),
                  let desiredEvent = desiredByEventID[event.id],
                  let plan,
                  let goal else {
                continue
            }

            if event.status == "cancelled" {
                link.syncState = .notVisibleInGoogleCalendar
                link.lastGoogleScheduleSignature = nil
                link.lastSyncedHash = nil
                recordInboundChange(
                    connection: connection,
                    workout: workout,
                    eventID: event.id,
                    reason: .eventDeleted,
                    status: .pendingReview,
                    proposedDate: nil,
                    message: "Google Calendar event was deleted. RestOrTrain kept the workout and will restore the calendar event."
                )
                logTelemetry("google_deletion_suppressed")
                outcome.deleted += 1
                outcome.needsReview += 1
                continue
            }

            if reconciler.contentDiffers(remote: event, desired: desiredEvent.payload) {
                link.syncState = .pending
                link.lastSyncedHash = nil
                recordInboundChange(
                    connection: connection,
                    workout: workout,
                    eventID: event.id,
                    reason: .contentRestored,
                    status: .restored,
                    proposedDate: workout.date,
                    message: "Google Calendar title or notes were edited. RestOrTrain restored the authoritative workout content."
                )
                logTelemetry("google_content_edit_normalized")
                outcome.restored += 1
            }

            guard let scheduleSignature = reconciler.scheduleSignature(for: event),
                  scheduleSignature != link.lastGoogleScheduleSignature,
                  let targetDate = reconciler.targetDate(from: event, fallbackDurationSeconds: workout.expectedDurationSeconds) else {
                continue
            }
            if let remoteUpdated = reconciler.updatedDate(from: event),
               let lastOutbound = link.lastSyncedAt,
               remoteUpdated <= lastOutbound {
                logger.info("Ignored stale Google Calendar schedule change for \(event.id, privacy: .public)")
                logTelemetry("stale_inbound_event_ignored")
                continue
            }

            switch reconciler.decision(
                workout: workout,
                targetDate: targetDate,
                allWorkouts: workouts,
                plan: plan,
                goal: goal,
                desiredPayload: desiredEvent.payload
            ) {
            case .apply(let date, let reason, let message):
                let original = workout.date
                workout.date = date
                workout.manuallyOverridden = true
                markScheduledFromGoogle(workout)
                link.lastGoogleScheduleSignature = scheduleSignature
                link.syncState = .pending
                link.lastSyncedHash = nil
                recordInboundChange(
                    connection: connection,
                    workout: workout,
                    eventID: event.id,
                    reason: reason,
                    status: .applied,
                    originalDate: original,
                    proposedDate: date,
                    message: message
                )
                logTelemetry(reason == .sameDayTimeChanged ? "same_day_time_change_applied" : "same_week_date_change_applied")
                outcome.applied += 1
            case .review(let reason, let message):
                link.lastGoogleScheduleSignature = scheduleSignature
                link.syncState = .pending
                link.lastSyncedHash = nil
                recordInboundChange(
                    connection: connection,
                    workout: workout,
                    eventID: event.id,
                    reason: reason,
                    status: .pendingReview,
                    proposedDate: targetDate,
                    message: message
                )
                logTelemetry("review_item_created", ["reason": reason.rawValue])
                if reason == .targetDayConflict {
                    logTelemetry("conflict_detected")
                } else if reason == .outsidePlannedWeek {
                    logTelemetry("cross_week_move_detected")
                }
                outcome.needsReview += 1
            case .ignored:
                link.lastGoogleScheduleSignature = scheduleSignature
                logTelemetry("sync_loop_prevented")
            }
        }

        try modelContext.save()
        logTelemetry("inbound_sync_completed", [
            "applied": "\(outcome.applied)",
            "review": "\(outcome.needsReview)",
            "restored": "\(outcome.restored)",
            "deleted": "\(outcome.deleted)"
        ])
        return outcome
    }

    private func reconcileEvents(connection: GoogleCalendarConnection, calendarID: String, accessToken: String) async throws -> SyncResult {
        let plan = try PlanStore.activePlan(in: modelContext)
        let workouts = try modelContext.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
        let activities = try modelContext.fetch(FetchDescriptor<CompletedActivity>(sortBy: [SortDescriptor(\.date)]))
        let desired = GoogleCalendarEventBuilder(calendar: calendar, timeZone: timeZone)
            .desiredEvents(plan: plan, workouts: workouts, activities: activities, connection: connection, today: now())
        let desiredKeys = Set(desired.map { entityKey($0.entityType, $0.entityID) })
        let links = try modelContext.fetch(FetchDescriptor<GoogleCalendarEventLink>())
            .filter { $0.connectionID == connection.uuid }
        var linksByKey = Dictionary(uniqueKeysWithValues: links.map { (entityKey($0.localEntityType, $0.localEntityID), $0) })
        var created = 0
        var updated = 0
        var skipped = 0
        var deleted = 0
        var failed = 0

        for event in desired {
            do {
                let key = entityKey(event.entityType, event.entityID)
                if linksByKey[key]?.syncState == .notVisibleInGoogleCalendar {
                    skipped += 1
                    continue
                }
                if let link = linksByKey[key], link.lastSyncedHash == event.hash, link.syncState == .synced {
                    skipped += 1
                    continue
                }
                if let link = linksByKey[key] {
                    _ = try await api.patchEvent(
                        calendarID: calendarID,
                        eventID: link.googleEventID,
                        event: event.payload.preservingGoogleCustomizationsForPatch(),
                        accessToken: accessToken
                    )
                    update(link, event: event)
                    updated += 1
                } else if let repaired = try await api.eventsByPrivateProperty(
                    calendarID: calendarID,
                    key: "rotEntityId",
                    value: event.entityID.uuidString,
                    accessToken: accessToken
                ).first {
                    let link = GoogleCalendarEventLink(
                        connectionID: connection.uuid,
                        localEntityType: event.entityType,
                        localEntityID: event.entityID,
                        trainingPlanID: event.trainingPlanID,
                        googleCalendarID: calendarID,
                        googleEventID: repaired.id,
                        now: now()
                    )
                    update(link, event: event)
                    modelContext.insert(link)
                    linksByKey[key] = link
                    _ = try await api.patchEvent(
                        calendarID: calendarID,
                        eventID: repaired.id,
                        event: event.payload.preservingGoogleCustomizationsForPatch(),
                        accessToken: accessToken
                    )
                    updated += 1
                } else {
                    let response = try await api.insertEvent(calendarID: calendarID, event: event.payload, accessToken: accessToken)
                    let link = GoogleCalendarEventLink(
                        connectionID: connection.uuid,
                        localEntityType: event.entityType,
                        localEntityID: event.entityID,
                        trainingPlanID: event.trainingPlanID,
                        googleCalendarID: calendarID,
                        googleEventID: response.id,
                        now: now()
                    )
                    update(link, event: event)
                    modelContext.insert(link)
                    linksByKey[key] = link
                    created += 1
                }
            } catch {
                failed += 1
            }
        }

        for link in links where !desiredKeys.contains(entityKey(link.localEntityType, link.localEntityID)) && link.syncState != .deleted && link.syncState != .notVisibleInGoogleCalendar {
            do {
                try await api.deleteEvent(calendarID: calendarID, eventID: link.googleEventID, accessToken: accessToken)
                link.syncState = .deleted
                deleted += 1
            } catch {
                failed += 1
            }
        }
        try modelContext.save()
        return SyncResult(created: created, updated: updated, skipped: skipped, deleted: deleted, failed: failed)
    }

    private func update(_ link: GoogleCalendarEventLink, event: GoogleCalendarDesiredEvent) {
        link.trainingPlanID = event.trainingPlanID
        link.lastSyncedHash = event.hash
        link.lastGoogleScheduleSignature = [
            event.payload.start.date,
            event.payload.start.dateTime,
            event.payload.start.timeZone
        ].compactMap { $0 }.joined(separator: "|")
        link.lastSyncedAt = now()
        link.syncState = .synced
    }

    private func markScheduledFromGoogle(_ workout: PlannedWorkout) {
        workout.scheduleUpdatedFrom = "googleCalendar"
        workout.scheduleUpdatedAt = now()
    }

    private func recordInboundChange(
        connection: GoogleCalendarConnection,
        workout: PlannedWorkout,
        eventID: String,
        reason: GoogleCalendarInboundChangeReason,
        status: GoogleCalendarInboundChangeStatus,
        originalDate: Date? = nil,
        proposedDate: Date?,
        message: String
    ) {
        let existing = ((try? modelContext.fetch(FetchDescriptor<GoogleCalendarInboundChange>())) ?? [])
            .first {
                $0.connectionID == connection.uuid
                    && $0.googleEventID == eventID
                    && $0.status == .pendingReview
            }
        if let existing {
            existing.reason = reason
            existing.originalDate = originalDate ?? workout.date
            existing.proposedDate = proposedDate
            existing.message = message
            existing.createdAt = now()
            return
        }
        modelContext.insert(GoogleCalendarInboundChange(
            connectionID: connection.uuid,
            localEntityID: workout.uuid,
            googleEventID: eventID,
            reason: reason,
            status: status,
            originalDate: originalDate ?? workout.date,
            proposedDate: proposedDate,
            message: message,
            now: now()
        ))
    }

    private func inboundSummary(_ outcome: GoogleCalendarInboundOutcome) -> String {
        guard outcome.total > 0 else { return "No Google schedule changes." }
        var parts: [String] = []
        if outcome.applied > 0 { parts.append("\(outcome.applied) schedule change applied") }
        if outcome.needsReview > 0 { parts.append("\(outcome.needsReview) need review") }
        if outcome.restored > 0 { parts.append("\(outcome.restored) content restored") }
        return parts.joined(separator: ", ") + "."
    }

    private func handleSyncError(_ error: Error, connection: GoogleCalendarConnection) {
        switch error {
        case GoogleCalendarAPIError.notFound:
            connection.connectionStatus = .calendarMissing
            connection.lastSyncErrorCategory = .calendarMissing
            connection.lastSyncSummary = "Training calendar was removed."
        case GoogleCalendarAPIError.unauthorized:
            connection.connectionStatus = .needsReconnect
            connection.lastSyncErrorCategory = .permissionRevoked
            connection.lastSyncSummary = "Reconnect Google Calendar."
        case GoogleCalendarAPIError.rateLimited:
            connection.connectionStatus = .partialFailure
            connection.lastSyncErrorCategory = .rateLimited
            connection.lastSyncSummary = "Sync delayed. Google Calendar is limiting updates."
        default:
            connection.connectionStatus = .partialFailure
            connection.lastSyncErrorCategory = .temporary
            connection.lastSyncSummary = "Could not finish calendar sync."
        }
        try? modelContext.save()
    }

    private func logTelemetry(_ event: String, _ metadata: [String: String] = [:]) {
        let detail = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if detail.isEmpty {
            logger.info("telemetry event=\(event, privacy: .public)")
        } else {
            logger.info("telemetry event=\(event, privacy: .public) \(detail, privacy: .public)")
        }
    }

    private func observePlanChanges() {
        planChangeObserver = NotificationCenter.default.addObserver(
            forName: .planDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleDebouncedReconcile() }
        }
    }

    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied
                if wasOffline && path.status == .satisfied {
                    await self?.reconcile(reason: "networkRestored")
                }
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    private func scheduleDebouncedReconcile() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.reconcile(reason: "planChanged")
        }
    }

    private func entityKey(_ type: GoogleCalendarLocalEntityType, _ id: UUID) -> String {
        "\(type.rawValue):\(id.uuidString)"
    }

    static func mask(_ email: String?) -> String? {
        guard let email, let at = email.firstIndex(of: "@") else { return email }
        let name = String(email[..<at])
        let domain = String(email[at...])
        let prefix = name.prefix(2)
        return "\(prefix)••••••\(domain)"
    }

    private struct SyncResult {
        var created: Int
        var updated: Int
        var skipped: Int
        var deleted: Int
        var failed: Int

        var summary: String {
            if failed > 0 {
                return "\(created + updated + skipped) synced, \(failed) will retry."
            }
            return "\(created + updated + skipped) workouts synced."
        }
    }
}

private extension JSONEncoder {
    static var google: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var google: JSONDecoder { JSONDecoder() }
}

extension ISO8601DateFormatter {
    static var google: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Date {
    var stableUUIDSeed: UUID {
        let data = Data(ISO8601DateFormatter().string(from: self).utf8)
        let hash = Data(SHA256.hash(data: data)).hexString
        let uuid = "\(hash.prefix(8))-\(hash.dropFirst(8).prefix(4))-\(hash.dropFirst(12).prefix(4))-\(hash.dropFirst(16).prefix(4))-\(hash.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuid) ?? UUID()
    }
}
