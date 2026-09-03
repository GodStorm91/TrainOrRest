import XCTest
@testable import TrainOrRest

final class KeychainStoreTests: XCTestCase {
    func testIntervalsICUAccountRoundTripsThroughKeychain() throws {
        let account = "\(KeychainStore.intervalsICUAccount)-unit-test-\(UUID().uuidString)"
        defer { try? KeychainStore.delete(account: account) }

        try KeychainStore.save("dummy-intervals-key", account: account)
        XCTAssertEqual(try KeychainStore.load(account: account), "dummy-intervals-key")

        try KeychainStore.save("updated-dummy-intervals-key", account: account)
        XCTAssertEqual(try KeychainStore.load(account: account), "updated-dummy-intervals-key")

        try KeychainStore.delete(account: account)
        XCTAssertNil(try KeychainStore.load(account: account))
    }
}
