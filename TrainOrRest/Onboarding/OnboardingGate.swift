import Foundation

/// First-run completion. Existing installs that already saw the Health sheet
/// are treated as complete so the new tour does not appear mid-training.
enum OnboardingGate {
    static let completedKey = "onboardingCompleted"

    static func isCompleted(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    static func markCompleted(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }

    static func adoptExistingInstallIfNeeded(
        healthAlreadyRequested: Bool,
        defaults: UserDefaults = .standard
    ) {
        guard !isCompleted(defaults), healthAlreadyRequested else { return }
        markCompleted(defaults)
    }

    static func shouldShowFirstRun(completed: Bool, healthUnavailable: Bool) -> Bool {
        !completed && !healthUnavailable
    }
}
