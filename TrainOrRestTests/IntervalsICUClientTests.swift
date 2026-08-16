import XCTest
@testable import TrainOrRest

final class IntervalsICUClientTests: XCTestCase {
    private let credentials = IntervalsICUCredentials(athleteID: "i636286", apiKey: "test-api-key")

    func testBulkUpsertBuildsAuthenticatedRequestAndDecodesResponse() async throws {
        let session = MockIntervalsICUSession(body: """
        [{"id":121441717,"external_id":"trainorrest-abc","start_date_local":"2026-07-10T00:00:00","name":"Run","push_errors":null}]
        """)
        let client = IntervalsICUClient(session: session)
        let event = IntervalsWorkoutEvent(
            externalID: "trainorrest-abc",
            startDateLocal: "2026-07-10T00:00:00",
            name: "TrainOrRest API Spike Pace DSL",
            description: "- 1km 4:45-4:30/km Pace",
            movingTime: 300
        )

        let response = try await client.bulkUpsert([event], credentials: credentials)

        XCTAssertEqual(response.map(\.id), [121441717])
        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/athlete/i636286/events/bulk")
        XCTAssertEqual(request.url?.query, "upsert=true")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Basic \(Data("API_KEY:test-api-key".utf8).base64EncodedString())"
        )
        XCTAssertFalse(request.value(forHTTPHeaderField: "Authorization")?.contains("test-api-key") ?? true)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(json.first?["external_id"] as? String, "trainorrest-abc")
        XCTAssertEqual(json.first?["category"] as? String, "WORKOUT")
        XCTAssertEqual(json.first?["type"] as? String, "Run")
        XCTAssertEqual(json.first?["moving_time"] as? Int, 300)
        XCTAssertEqual(json.first?["description"] as? String, "- 1km 4:45-4:30/km Pace")
    }

    func testEventsBuildsWindowQueryAndDecodesExternalID() async throws {
        let session = MockIntervalsICUSession(body: """
        [{"id":7,"external_id":"trainorrest-def","start_date_local":"2026-07-11T00:00:00","name":"Easy"}]
        """)
        let client = IntervalsICUClient(session: session)

        let events = try await client.events(
            credentials: credentials,
            oldest: "2026-07-10",
            newest: "2026-07-17"
        )

        XCTAssertEqual(events.first?.externalID, "trainorrest-def")
        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/athlete/i636286/events")
        let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first { $0.name == "oldest" }?.value, "2026-07-10")
        XCTAssertEqual(components?.queryItems?.first { $0.name == "newest" }?.value, "2026-07-17")
    }

    func testDeleteEventBuildsDeleteRequest() async throws {
        let session = MockIntervalsICUSession(body: "")
        let client = IntervalsICUClient(session: session)

        try await client.deleteEvent(id: 99, credentials: credentials)

        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/athlete/i636286/events/99")
    }

    func testUnauthorizedStatusMapsToTypedError() async throws {
        let session = MockIntervalsICUSession(statusCode: 401, body: "{}")
        let client = IntervalsICUClient(session: session)
        let event = IntervalsWorkoutEvent(
            externalID: "trainorrest-abc",
            startDateLocal: "2026-07-10T00:00:00",
            name: "Run",
            description: "- 1km",
            movingTime: 300
        )

        do {
            _ = try await client.bulkUpsert([event], credentials: credentials)
            XCTFail("Expected unauthorized error")
        } catch let error as IntervalsICUError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testEmptyBulkUpsertSkipsNetwork() async throws {
        let session = MockIntervalsICUSession(body: "[]")
        let client = IntervalsICUClient(session: session)

        let response = try await client.bulkUpsert([], credentials: credentials)

        XCTAssertTrue(response.isEmpty)
        XCTAssertTrue(session.requests.isEmpty)
    }

    func testOfflineErrorMapsToTypedError() async throws {
        let session = MockIntervalsICUSession(error: URLError(.notConnectedToInternet), body: "")
        let client = IntervalsICUClient(session: session)

        do {
            _ = try await client.events(credentials: credentials, oldest: "2026-07-10", newest: "2026-07-17")
            XCTFail("Expected offline error")
        } catch let error as IntervalsICUError {
            XCTAssertEqual(error, .offline)
        }
    }

    func testInvalidSuccessResponseMapsToInvalidResponse() async throws {
        let session = MockIntervalsICUSession(body: "{}")
        let client = IntervalsICUClient(session: session)

        do {
            _ = try await client.events(credentials: credentials, oldest: "2026-07-10", newest: "2026-07-17")
            XCTFail("Expected invalid response error")
        } catch let error as IntervalsICUError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testAPIStatusPreservesServerMessageButUsesSanitizedDescription() async throws {
        let session = MockIntervalsICUSession(statusCode: 500, body: #"{"message":"maintenance"}"#)
        let client = IntervalsICUClient(session: session)

        do {
            _ = try await client.events(credentials: credentials, oldest: "2026-07-10", newest: "2026-07-17")
            XCTFail("Expected API status error")
        } catch let error as IntervalsICUError {
            XCTAssertEqual(error, .apiStatus(500, "maintenance"))
            XCTAssertEqual(error.errorDescription, "intervals.icu API error 500.")
        }
    }
}

private final class MockIntervalsICUSession: IntervalsICUSessioning {
    private let statusCode: Int
    private let body: String
    private let error: Error?
    var requests: [URLRequest] = []

    init(statusCode: Int = 200, error: Error? = nil, body: String) {
        self.statusCode = statusCode
        self.error = error
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if let error {
            throw error
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
