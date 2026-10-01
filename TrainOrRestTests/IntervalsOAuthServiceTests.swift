import XCTest
@testable import TrainOrRest

final class IntervalsOAuthServiceTests: XCTestCase {
    func testAuthorizationURLUsesConfiguredWorkerCallbackAndExactScopes() throws {
        let configuration = IntervalsOAuthConfiguration(
            clientID: "client-id",
            workerCallbackURL: try XCTUnwrap(URL(string: "https://worker.example/intervals/callback"))
        )

        let url = try IntervalsOAuthService.authorizationURL(configuration: configuration, state: "random-state")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        XCTAssertEqual(url.absoluteString.split(separator: "?").first, "https://intervals.icu/oauth/authorize")
        XCTAssertEqual(items?.first { $0.name == "client_id" }?.value, "client-id")
        XCTAssertEqual(items?.first { $0.name == "redirect_uri" }?.value, "https://worker.example/intervals/callback")
        XCTAssertEqual(items?.first { $0.name == "response_type" }?.value, "code")
        XCTAssertEqual(items?.first { $0.name == "scope" }?.value, "CALENDAR:WRITE,ACTIVITY:READ")
        XCTAssertEqual(items?.first { $0.name == "state" }?.value, "random-state")
    }

    func testCallbackRejectsMismatchedState() throws {
        let url = try XCTUnwrap(URL(string: "trainorrest://oauth/intervals?state=wrong&access_token=token&athlete_id=42"))

        XCTAssertThrowsError(try IntervalsOAuthCallback.parse(url: url, expectedState: "expected")) {
            XCTAssertEqual($0 as? IntervalsOAuthError, .stateMismatch)
        }
    }

    func testCallbackParsesValidatedWorkerResponse() throws {
        let url = try XCTUnwrap(URL(string: "trainorrest://oauth/intervals?state=expected&access_token=token&athlete_id=42&athlete_name=Ada&scope=CALENDAR:WRITE,ACTIVITY:READ&expires_in=3600"))

        let callback = try IntervalsOAuthCallback.parse(url: url, expectedState: "expected")

        XCTAssertEqual(callback.accessToken, "token")
        XCTAssertEqual(callback.athleteID, "42")
        XCTAssertEqual(callback.athleteName, "Ada")
        XCTAssertEqual(callback.scope, "CALENDAR:WRITE,ACTIVITY:READ")
        XCTAssertEqual(callback.expiresIn, 3600)
    }
}
