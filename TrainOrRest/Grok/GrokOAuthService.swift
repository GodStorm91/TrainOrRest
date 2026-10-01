import Foundation

enum GrokOAuthError: LocalizedError, Equatable {
    case cancelled
    case expired
    case declined
    case invalidResponse
    case endpointRejected
    case http(Int, code: String?)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Grok sign-in was cancelled."
        case .expired: "The Grok sign-in code expired. Start again."
        case .declined: "Grok sign-in was declined."
        case .invalidResponse: "Grok returned an unexpected sign-in response."
        case .endpointRejected: "Grok sign-in refused an untrusted address."
        case .http(let status, let code):
            "Grok sign-in failed (\(code ?? "HTTP \(status)"))."
        }
    }
}

struct GrokDeviceAuthorization: Equatable, Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURL: URL
    var expiresAt: Date
    var interval: TimeInterval
}

struct GrokTokenSet: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum GrokDevicePoll: Equatable {
    case pending
    case slowDown
    case complete(GrokTokenSet)
}

struct GrokIdentity: Equatable, Sendable {
    var subject: String?
    var email: String?
}

enum GrokOAuthParsing {
    static func deviceAuthorization(from data: Data, now: Date = Date()) throws -> GrokDeviceAuthorization {
        let payload = try jsonObject(data)
        let deviceCode = trimmedString(payload["device_code"])
        let userCode = trimmedString(payload["user_code"])
        let verificationURI = trimmedString(payload["verification_uri"])
        let verificationComplete = trimmedString(payload["verification_uri_complete"])
        guard let deviceCode, let userCode, let verificationURI, let verificationComplete,
              let expiresIn = positiveNumber(payload["expires_in"]),
              let interval = positiveNumber(payload["interval"]) else {
            throw GrokOAuthError.invalidResponse
        }
        _ = try validateAuthEndpoint(verificationURI, field: "verification_uri")
        let complete = try validateAuthEndpoint(verificationComplete, field: "verification_uri_complete")
        guard let url = URL(string: complete) else { throw GrokOAuthError.endpointRejected }
        return GrokDeviceAuthorization(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: url,
            expiresAt: now.addingTimeInterval(expiresIn),
            interval: interval
        )
    }

    static func poll(status: Int, data: Data, now: Date = Date(), refreshFallback: String? = nil) throws -> GrokDevicePoll {
        let payload = try jsonObject(data)
        if let code = trimmedString(payload["error"]) {
            switch code {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "expired_token", "expired": throw GrokOAuthError.expired
            case "access_denied": throw GrokOAuthError.declined
            default: throw GrokOAuthError.http(status, code: code)
            }
        }
        guard (200..<300).contains(status) else {
            throw GrokOAuthError.http(status, code: nil)
        }
        return .complete(try tokenSet(from: payload, now: now, refreshFallback: refreshFallback))
    }

    static func tokenSet(from data: Data, now: Date = Date(), refreshFallback: String? = nil) throws -> GrokTokenSet {
        try tokenSet(from: jsonObject(data), now: now, refreshFallback: refreshFallback)
    }

    static func identity(from data: Data) -> GrokIdentity? {
        guard let payload = try? jsonObject(data) else { return nil }
        let subject = trimmedString(payload["sub"])
        let email = trimmedString(payload["email"])?.lowercased()
        guard subject != nil || email != nil else { return nil }
        return GrokIdentity(subject: subject, email: email)
    }

    static func tokenEndpoint(from data: Data) throws -> URL {
        let payload = try jsonObject(data)
        guard let raw = trimmedString(payload["token_endpoint"]) else {
            throw GrokOAuthError.invalidResponse
        }
        let pinned = try validateAuthEndpoint(raw, field: "token_endpoint")
        guard let url = URL(string: pinned) else { throw GrokOAuthError.endpointRejected }
        return url
    }

    static func validateAuthEndpoint(_ raw: String, field: String) throws -> String {
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host == "x.ai" || host.hasSuffix(".x.ai") else {
            throw GrokOAuthError.endpointRejected
        }
        _ = field
        return raw
    }

    private static func tokenSet(
        from payload: [String: Any],
        now: Date,
        refreshFallback: String?
    ) throws -> GrokTokenSet {
        guard let accessToken = trimmedString(payload["access_token"]),
              let refreshToken = trimmedString(payload["refresh_token"]) ?? refreshFallback.flatMap(trimmed),
              let expiresIn = finiteNumber(payload["expires_in"]) else {
            throw GrokOAuthError.invalidResponse
        }
        let skew = min(GrokAuthConfiguration.accessTokenSkew, expiresIn / 2)
        return GrokTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(max(30, expiresIn - skew))
        )
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokOAuthError.invalidResponse
        }
        return object
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        return trimmed(string)
    }

    private static func trimmed(_ string: String) -> String? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func positiveNumber(_ value: Any?) -> TimeInterval? {
        guard let number = finiteNumber(value), number > 0 else { return nil }
        return number
    }

    private static func finiteNumber(_ value: Any?) -> TimeInterval? {
        let number: Double?
        if let value = value as? Double {
            number = value
        } else if let value = value as? Int {
            number = Double(value)
        } else if let value = value as? NSNumber {
            number = value.doubleValue
        } else {
            number = nil
        }
        guard let number, number.isFinite else { return nil }
        return number
    }
}

/// Refuses redirects so a device code or refresh token cannot be posted to another host.
final class GrokRedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class GrokOAuthService: @unchecked Sendable {
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(session: URLSession? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            self.session = URLSession(configuration: configuration, delegate: GrokRedirectRefuser(), delegateQueue: nil)
        }
        self.now = now
    }

    func startDeviceAuthorization() async throws -> GrokDeviceAuthorization {
        let data = try await post(
            GrokAuthConfiguration.deviceCodeURL,
            form: [
                "client_id": GrokAuthConfiguration.clientID,
                "scope": GrokAuthConfiguration.scope
            ]
        )
        guard (200..<300).contains(data.status) else {
            throw GrokOAuthError.http(data.status, code: "device_code")
        }
        return try GrokOAuthParsing.deviceAuthorization(from: data.body, now: now())
    }

    func poll(_ authorization: GrokDeviceAuthorization, tokenEndpoint: URL) async throws -> GrokDevicePoll {
        let data = try await post(
            tokenEndpoint,
            form: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": GrokAuthConfiguration.clientID,
                "device_code": authorization.deviceCode
            ]
        )
        return try GrokOAuthParsing.poll(status: data.status, data: data.body, now: now())
    }

    func refresh(refreshToken: String, tokenEndpoint: URL) async throws -> GrokTokenSet {
        let data = try await post(
            tokenEndpoint,
            form: [
                "grant_type": "refresh_token",
                "client_id": GrokAuthConfiguration.clientID,
                "refresh_token": refreshToken
            ]
        )
        guard (200..<300).contains(data.status) else {
            let code = (try? JSONSerialization.jsonObject(with: data.body) as? [String: Any])
                .flatMap { $0["error"] as? String }
            throw GrokOAuthError.http(data.status, code: code)
        }
        return try GrokOAuthParsing.tokenSet(from: data.body, now: now(), refreshFallback: refreshToken)
    }

    func discoverTokenEndpoint() async throws -> URL {
        var request = URLRequest(url: GrokAuthConfiguration.discoveryURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        guard data.status == 200 else { throw GrokOAuthError.http(data.status, code: "discovery") }
        return try GrokOAuthParsing.tokenEndpoint(from: data.body)
    }

    func identity(accessToken: String) async -> GrokIdentity? {
        var request = URLRequest(url: GrokAuthConfiguration.userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = try? await send(request), data.status == 200 else { return nil }
        return GrokOAuthParsing.identity(from: data.body)
    }

    func pollUntilComplete(_ authorization: GrokDeviceAuthorization, tokenEndpoint: URL) async throws -> GrokTokenSet {
        var interval = authorization.interval
        while !Task.isCancelled {
            if now() >= authorization.expiresAt { throw GrokOAuthError.expired }
            switch try await poll(authorization, tokenEndpoint: tokenEndpoint) {
            case .pending:
                break
            case .slowDown:
                interval += 5
            case .complete(let tokens):
                return tokens
            }
            let remaining = authorization.expiresAt.timeIntervalSince(now())
            if remaining <= 0 { throw GrokOAuthError.expired }
            try await Task.sleep(for: .seconds(min(interval, remaining)))
        }
        throw GrokOAuthError.cancelled
    }

    private func post(_ url: URL, form: [String: String]) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded(form)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw GrokOAuthError.cancelled
        } catch {
            throw GrokOAuthError.http(-1, code: "network")
        }
        guard let http = response as? HTTPURLResponse else { throw GrokOAuthError.invalidResponse }
        if (300..<400).contains(http.statusCode) { throw GrokOAuthError.endpointRejected }
        return (http.statusCode, data)
    }

    private func formURLEncoded(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}
