import AuthenticationServices
import Foundation
import UIKit

struct IntervalsOAuthConfiguration: Equatable {
    static let clientIDKey = "IntervalsICUOAuthClientID"
    static let workerCallbackURLKey = "IntervalsICUOAuthWorkerCallbackURL"
    static let authorizationEndpoint = URL(string: "https://intervals.icu/oauth/authorize")!
    static let callbackScheme = "trainorrest"
    static let scope = "CALENDAR:WRITE,ACTIVITY:READ"

    var clientID: String
    var workerCallbackURL: URL

    static var current: IntervalsOAuthConfiguration? {
        let clientID = (Bundle.main.object(forInfoDictionaryKey: clientIDKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = (Bundle.main.object(forInfoDictionaryKey: workerCallbackURLKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty,
              let workerCallbackURL = URL(string: callback),
              workerCallbackURL.scheme == "https" else { return nil }
        return IntervalsOAuthConfiguration(clientID: clientID, workerCallbackURL: workerCallbackURL)
    }
}

enum IntervalsOAuthError: LocalizedError, Equatable {
    case notConfigured
    case cancelled
    case authorizationDenied
    case invalidCallback
    case stateMismatch

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Secure intervals.icu sign-in is not configured in this build."
        case .cancelled, .authorizationDenied:
            "intervals.icu was not connected."
        case .invalidCallback, .stateMismatch:
            "intervals.icu could not complete sign-in. Try again."
        }
    }
}

struct IntervalsOAuthCallback: Equatable {
    var accessToken: String
    var athleteID: String
    var athleteName: String?
    var scope: String?
    var refreshToken: String?
    var expiresIn: TimeInterval?

    static func parse(url: URL, expectedState: String) throws -> IntervalsOAuthCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw IntervalsOAuthError.stateMismatch
        }
        if items.first(where: { $0.name == "error" })?.value != nil {
            throw IntervalsOAuthError.authorizationDenied
        }
        guard let accessToken = items.first(where: { $0.name == "access_token" })?.value,
              !accessToken.isEmpty,
              let athleteID = items.first(where: { $0.name == "athlete_id" })?.value,
              !athleteID.isEmpty else {
            throw IntervalsOAuthError.invalidCallback
        }
        return IntervalsOAuthCallback(
            accessToken: accessToken,
            athleteID: athleteID,
            athleteName: items.first(where: { $0.name == "athlete_name" })?.value,
            scope: items.first(where: { $0.name == "scope" })?.value,
            refreshToken: items.first(where: { $0.name == "refresh_token" })?.value,
            expiresIn: items.first(where: { $0.name == "expires_in" })?.value.flatMap(TimeInterval.init)
        )
    }
}

@MainActor
final class IntervalsOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize() async throws -> IntervalsOAuthCallback {
        guard let configuration = IntervalsOAuthConfiguration.current else {
            throw IntervalsOAuthError.notConfigured
        }
        let state = Self.randomState()
        let authorizationURL = try Self.authorizationURL(configuration: configuration, state: state)
        let callback = try await startSession(url: authorizationURL)
        return try IntervalsOAuthCallback.parse(url: callback, expectedState: state)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    nonisolated static func authorizationURL(configuration: IntervalsOAuthConfiguration, state: String) throws -> URL {
        var components = URLComponents(url: IntervalsOAuthConfiguration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.workerCallbackURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: IntervalsOAuthConfiguration.scope),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw IntervalsOAuthError.invalidCallback }
        return url
    }

    private func startSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: IntervalsOAuthConfiguration.callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: IntervalsOAuthError.cancelled)
                    return
                }
                if error != nil {
                    continuation.resume(throwing: IntervalsOAuthError.invalidCallback)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: IntervalsOAuthError.invalidCallback)
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

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
enum IntervalsOAuthAction {
    enum Outcome: Equatable {
        case connected
        case cancelled
        case failed(String)
    }

    static func connect(
        store: IntervalsConnectionStore,
        oauth: IntervalsOAuthService,
        client: IntervalsICUServicing
    ) async -> Outcome {
        do {
            let callback = try await oauth.authorize()
            try store.saveOAuth(callback)
            let today = Date.now
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            let credentials = IntervalsICUCredentials(
                athleteID: callback.athleteID,
                authentication: .oauth(accessToken: callback.accessToken)
            )
            _ = try await client.events(
                credentials: credentials,
                oldest: dateQuery(today),
                newest: dateQuery(tomorrow)
            )
            store.markOAuthValidated()
            return .connected
        } catch {
            if isCancellation(error) { return .cancelled }
            store.markNeedsReconnectIfOAuth()
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? IntervalsOAuthError) == .cancelled
    }

    private static func dateQuery(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
