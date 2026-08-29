import XCTest
@testable import TrainOrRest

final class OnboardingGateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNewInstallShowsFirstRun() {
        XCTAssertFalse(OnboardingGate.isCompleted(defaults))
        XCTAssertTrue(
            OnboardingGate.shouldShowFirstRun(completed: false, healthUnavailable: false)
        )
    }

    func testCompletedInstallSkipsFirstRun() {
        OnboardingGate.markCompleted(defaults)
        XCTAssertTrue(OnboardingGate.isCompleted(defaults))
        XCTAssertFalse(
            OnboardingGate.shouldShowFirstRun(completed: true, healthUnavailable: false)
        )
    }

    func testUnavailableHealthNeverShowsFirstRun() {
        XCTAssertFalse(
            OnboardingGate.shouldShowFirstRun(completed: false, healthUnavailable: true)
        )
    }

    func testExistingHealthUserIsAdoptedOnce() {
        OnboardingGate.adoptExistingInstallIfNeeded(healthAlreadyRequested: true, defaults: defaults)
        XCTAssertTrue(OnboardingGate.isCompleted(defaults))
        XCTAssertFalse(
            OnboardingGate.shouldShowFirstRun(
                completed: OnboardingGate.isCompleted(defaults),
                healthUnavailable: false
            )
        )
    }

    func testNewHealthUserIsNotAdopted() {
        OnboardingGate.adoptExistingInstallIfNeeded(healthAlreadyRequested: false, defaults: defaults)
        XCTAssertFalse(OnboardingGate.isCompleted(defaults))
    }

    func testAdoptionDoesNotClearCompletedFlag() {
        OnboardingGate.markCompleted(defaults)
        OnboardingGate.adoptExistingInstallIfNeeded(healthAlreadyRequested: false, defaults: defaults)
        XCTAssertTrue(OnboardingGate.isCompleted(defaults))
    }
}
