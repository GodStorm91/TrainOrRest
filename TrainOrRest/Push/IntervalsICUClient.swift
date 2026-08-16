import Foundation

protocol IntervalsICUSessioning {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: IntervalsICUSessioning {}

protocol IntervalsICUServicing {
    func bulkUpsert(
        _ events: [IntervalsWorkoutEvent],
        credentials: IntervalsICUCredentials
    ) async throws -> [RemoteWorkoutEvent]
    func events(
        credentials: IntervalsICUCredentials,
        oldest: String,
        newest: String
    ) async throws -> [RemoteWorkoutEvent]
    func deleteEvent(id: Int, credentials: IntervalsICUCredentials) async throws
}

struct IntervalsICUCredentials: Equatable {
    var athleteID: String
    var apiKey: String
}

struct IntervalsWorkoutEvent: Encodable, Equatable {
    var externalID: String
    var category: String = "WORKOUT"
    var type: String = "Run"
    var startDateLocal: String
    var name: String
    var description: String
    var movingTime: Int

    enum CodingKeys: String, CodingKey {
        case category, type, name, description
        case externalID = "external_id"
        case startDateLocal = "start_date_local"
        case movingTime = "moving_time"
    }
}

struct RemoteWorkoutEvent: Decodable, Equatable {
    var id: Int
    var externalID: String?
    var startDateLocal: String?
    var name: String?
    var pushErrors: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case externalID = "external_id"
        case startDateLocal = "start_date_local"
        case pushErrors = "push_errors"
    }

    init(
        id: Int,
        externalID: String?,
        startDateLocal: String? = nil,
        name: String? = nil,
        pushErrors: String? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.startDateLocal = startDateLocal
        self.name = name
        self.pushErrors = pushErrors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        startDateLocal = try container.decodeIfPresent(String.self, forKey: .startDateLocal)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        pushErrors = try? container.decodeIfPresent(String.self, forKey: .pushErrors)
    }
}

enum IntervalsICUError: LocalizedError, Equatable {
    case unauthorized
    case offline
    case invalidResponse
    case apiStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your intervals.icu API key was rejected. Check it in Settings."
        case .offline:
            "No network connection. Workout push will retry later."
        case .invalidResponse:
            "intervals.icu returned an unexpected response."
        case .apiStatus(let status, _):
            "intervals.icu API error \(status)."
        }
    }
}

final class IntervalsICUClient: IntervalsICUServicing {
    private let session: IntervalsICUSessioning
    private let baseURL: URL

    init(
        session: IntervalsICUSessioning = URLSession.shared,
        baseURL: URL = URL(string: "https://intervals.icu/api/v1")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func bulkUpsert(
        _ events: [IntervalsWorkoutEvent],
        credentials: IntervalsICUCredentials
    ) async throws -> [RemoteWorkoutEvent] {
        guard !events.isEmpty else { return [] }
        var components = URLComponents(
            url: athleteURL(credentials)
                .appendingPathComponent("events")
                .appendingPathComponent("bulk"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "upsert", value: "true")]

        var request = authenticatedRequest(url: components.url!, credentials: credentials)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(events)
        return try await decodedResponse(for: request, as: [RemoteWorkoutEvent].self)
    }

    func events(
        credentials: IntervalsICUCredentials,
        oldest: String,
        newest: String
    ) async throws -> [RemoteWorkoutEvent] {
        var components = URLComponents(
            url: athleteURL(credentials).appendingPathComponent("events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "oldest", value: oldest),
            URLQueryItem(name: "newest", value: newest),
        ]

        var request = authenticatedRequest(url: components.url!, credentials: credentials)
        request.httpMethod = "GET"
        return try await decodedResponse(for: request, as: [RemoteWorkoutEvent].self)
    }

    func deleteEvent(id: Int, credentials: IntervalsICUCredentials) async throws {
        var request = authenticatedRequest(
            url: athleteURL(credentials)
                .appendingPathComponent("events")
                .appendingPathComponent("\(id)"),
            credentials: credentials
        )
        request.httpMethod = "DELETE"
        _ = try await responseData(for: request)
    }

    private func athleteURL(_ credentials: IntervalsICUCredentials) -> URL {
        baseURL
            .appendingPathComponent("athlete")
            .appendingPathComponent(credentials.athleteID)
    }

    private func authenticatedRequest(url: URL, credentials: IntervalsICUCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        let token = Data("API_KEY:\(credentials.apiKey)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    private func decodedResponse<T: Decodable>(for request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await responseData(for: request)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw IntervalsICUError.invalidResponse
        }
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw IntervalsICUError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw IntervalsICUError.unauthorized
            default:
                throw IntervalsICUError.apiStatus(http.statusCode, Self.errorMessage(from: data))
            }
        } catch let error as IntervalsICUError {
            throw error
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw IntervalsICUError.offline
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else { return nil }
        return message
    }
}
