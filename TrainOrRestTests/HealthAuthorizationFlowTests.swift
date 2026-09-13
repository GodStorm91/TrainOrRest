import HealthKit
import XCTest
@testable import TrainOrRest

@MainActor
final class HealthAuthorizationFlowTests: XCTestCase {
    func testExplanationStartsExactlyOneRequest() {
        var flow = FirstRunHealthAuthorizationFlow()

        XCTAssertEqual(flow.state, .explanation)
        XCTAssertTrue(flow.beginRequest())
        XCTAssertEqual(flow.state, .requesting)
        XCTAssertFalse(flow.beginRequest())
    }

    func testCompletedNativeDecisionAdvancesWithSettingsGuidance() {
        var flow = FirstRunHealthAuthorizationFlow()
        XCTAssertTrue(flow.beginRequest())

        XCTAssertEqual(
            flow.finish(.requestCompleted),
            .advance(showSettingsGuidance: true)
        )
    }

    func testPreviouslyRequestedAccessAdvancesWithoutRequestLoop() {
        var flow = FirstRunHealthAuthorizationFlow()
        XCTAssertTrue(flow.beginRequest())

        XCTAssertEqual(
            flow.finish(.previouslyRequested),
            .advance(showSettingsGuidance: true)
        )
    }

    func testDeniedAccessShowsRecoveryAndCannotRequestAgain() {
        var flow = FirstRunHealthAuthorizationFlow()
        XCTAssertTrue(flow.beginRequest())

        XCTAssertEqual(flow.finish(.denied), .stay)
        XCTAssertEqual(flow.state, .denied)
        XCTAssertFalse(flow.beginRequest())
    }

    func testRestrictedAccessShowsFeedbackAndCannotRequestAgain() {
        var flow = FirstRunHealthAuthorizationFlow()
        XCTAssertTrue(flow.beginRequest())

        XCTAssertEqual(flow.finish(.restricted), .stay)
        XCTAssertEqual(flow.state, .restricted)
        XCTAssertFalse(flow.beginRequest())
    }

    func testNotDeterminedAndTransientErrorsCanRetry() {
        var notDetermined = FirstRunHealthAuthorizationFlow()
        XCTAssertTrue(notDetermined.beginRequest())
        XCTAssertEqual(notDetermined.finish(.notDetermined), .stay)
        XCTAssertEqual(notDetermined.state, .notDetermined)
        XCTAssertTrue(notDetermined.beginRequest())

        var failed = FirstRunHealthAuthorizationFlow()
        XCTAssertTrue(failed.beginRequest())
        XCTAssertEqual(failed.finish(.failed("Offline")), .stay)
        XCTAssertEqual(failed.state, .failed("Offline"))
        XCTAssertTrue(failed.beginRequest())
    }

    func testServiceChecksStatusThenCallsNativeRequest() async {
        var events: [String] = []
        let service = HealthKitService(
            authorization: .init(
                requestStatus: {
                    events.append("status")
                    return .shouldRequest
                },
                request: {
                    events.append("request")
                }
            )
        )

        let outcome = await service.requestAuthorization()

        XCTAssertEqual(outcome, .requestCompleted)
        XCTAssertEqual(events, ["status", "request"])
    }

    func testServiceDoesNotRequestAgainAfterHealthKitDecision() async {
        var requestCount = 0
        let service = HealthKitService(
            authorization: .init(
                requestStatus: { .unnecessary },
                request: { requestCount += 1 }
            )
        )

        let outcome = await service.requestAuthorization()

        XCTAssertEqual(outcome, .previouslyRequested)
        XCTAssertEqual(requestCount, 0)
    }

    func testServiceCoalescesConcurrentRequests() async {
        var statusCount = 0
        var requestCount = 0
        let service = HealthKitService(
            authorization: .init(
                requestStatus: {
                    statusCount += 1
                    return .shouldRequest
                },
                request: {
                    requestCount += 1
                    try await Task.sleep(nanoseconds: 30_000_000)
                }
            )
        )

        async let first = service.requestAuthorization()
        async let second = service.requestAuthorization()
        let outcomes = await [first, second]

        XCTAssertEqual(outcomes, [.requestCompleted, .requestCompleted])
        XCTAssertEqual(statusCount, 1)
        XCTAssertEqual(requestCount, 1)
    }

    func testServiceClassifiesHealthKitAuthorizationErrors() async {
        let denied = await outcome(throwing: .errorAuthorizationDenied)
        let restricted = await outcome(throwing: .errorHealthDataRestricted)
        let notDetermined = await outcome(throwing: .errorAuthorizationNotDetermined)

        XCTAssertEqual(denied, .denied)
        XCTAssertEqual(restricted, .restricted)
        XCTAssertEqual(notDetermined, .notDetermined)
    }

    func testServiceSurfacesUnknownAuthorizationErrors() async {
        let service = HealthKitService(
            authorization: .init(
                requestStatus: { .shouldRequest },
                request: {
                    throw NSError(domain: "HealthAuthorizationFlowTests", code: 7)
                }
            )
        )

        guard case let .failed(message) = await service.requestAuthorization() else {
            return XCTFail("Expected an explicit failure outcome")
        }
        XCTAssertFalse(message.isEmpty)
    }

    private func outcome(throwing code: HKError.Code) async -> HealthAuthorizationOutcome {
        let service = HealthKitService(
            authorization: .init(
                requestStatus: { .shouldRequest },
                request: {
                    throw NSError(domain: HKErrorDomain, code: code.rawValue)
                }
            )
        )
        return await service.requestAuthorization()
    }
}
