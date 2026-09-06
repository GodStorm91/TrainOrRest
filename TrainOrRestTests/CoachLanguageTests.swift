import XCTest
@testable import TrainOrRest

/// The coach's user-facing strings must exist, differ, and default to English.
final class CoachLanguageTests: XCTestCase {
    func testEnglishIsTheDefaultForUnknownStoredValues() {
        XCTAssertEqual(CoachLanguage(rawValue: "klingon") ?? .en, .en)
    }

    func testEveryLanguageHasDistinctCopyLabels() {
        for language in CoachLanguage.allCases {
            XCTAssertFalse(language.copyLabel.isEmpty, "\(language) has no copy label")
            XCTAssertFalse(language.copiedLabel.isEmpty, "\(language) has no copied label")
            XCTAssertNotEqual(
                language.copyLabel,
                language.copiedLabel,
                "\(language): the copied confirmation must read differently from the idle action"
            )
        }
    }

    func testCopyLabelsAreLocalizedPerLanguage() {
        XCTAssertEqual(CoachLanguage.en.copyLabel, "Copy")
        XCTAssertEqual(CoachLanguage.ja.copyLabel, "コピー")
        XCTAssertEqual(CoachLanguage.vi.copyLabel, "Sao chép")
        XCTAssertEqual(CoachLanguage.en.copiedLabel, "Copied")
        XCTAssertEqual(CoachLanguage.ja.copiedLabel, "コピーしました")
        XCTAssertEqual(CoachLanguage.vi.copiedLabel, "Đã sao chép")
    }

    /// No two languages should share a copy label, or the picker would look broken.
    func testCopyLabelsAreUniqueAcrossLanguages() {
        let labels = CoachLanguage.allCases.map(\.copyLabel)
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    // MARK: - Plan update card

    func testPlanUpdateStringsExistForEveryLanguage() {
        for language in CoachLanguage.allCases {
            XCTAssertFalse(language.planUpdateTitle.isEmpty, "\(language)")
            XCTAssertFalse(language.planUpdateNewBadge.isEmpty, "\(language)")
            XCTAssertFalse(language.whySwapPrompt.isEmpty, "\(language)")
            XCTAssertFalse(language.applyChangesLabel.isEmpty, "\(language)")
            for kind in WorkoutKind.allCases {
                XCTAssertFalse(language.keepExistingLabel(kind).isEmpty, "\(language)/\(kind)")
            }
        }
    }

    func testPlanLoadWarningStringsExistForEveryLanguage() {
        for language in CoachLanguage.allCases {
            XCTAssertFalse(language.planLoadWarningTitle.isEmpty, "\(language)")
            XCTAssertFalse(language.planLoadWarningConfirmHint.isEmpty, "\(language)")
            XCTAssertFalse(language.ledgerValidatedWithWarningLabel.isEmpty, "\(language)")
            XCTAssertFalse(language.validationReceiptWarningTitle.isEmpty, "\(language)")
            XCTAssertFalse(language.validationReceiptWarningSubtitle.isEmpty, "\(language)")
            XCTAssertFalse(language.applyDespiteLoadRiskLabel.isEmpty, "\(language)")
            XCTAssertNotEqual(
                language.ledgerValidatedWithWarningLabel,
                language.ledgerValidatedLabel,
                "\(language): warning ledger must not reuse the safe Validated chip"
            )
            XCTAssertNotEqual(
                language.applyDespiteLoadRiskLabel,
                language.applyChangesLabel,
                "\(language): risky Apply must not reuse the safe Apply label"
            )
            XCTAssertNotEqual(
                language.validationReceiptWarningTitle,
                language.validationReceiptTitle,
                "\(language): warning receipt must not claim Plan checks passed"
            )
        }
    }

    func testCardActionLabelsMatchTheDesign() {
        XCTAssertEqual(CoachLanguage.en.applyChangesLabel, "Apply changes")
        XCTAssertEqual(CoachLanguage.en.keepExistingLabel(.tempo), "Keep tempo")
        XCTAssertEqual(CoachLanguage.en.keepExistingLabel(.intervals), "Keep intervals")
    }

    func testLoadWarningApplyCopyMatchesTheDesign() {
        XCTAssertEqual(CoachLanguage.en.ledgerValidatedWithWarningLabel, "With warning")
        XCTAssertEqual(CoachLanguage.en.validationReceiptWarningTitle, "Checks passed with load warning")
        XCTAssertEqual(CoachLanguage.en.applyDespiteLoadRiskLabel, "Apply despite load risk")
    }

    func testValidationReceiptChecksMatchIssueKinds() {
        XCTAssertEqual(
            CoachLanguage.en.planValidationChecks.count,
            PlanValidator.Issue.Kind.allCases.count
        )
    }

    func testWorkoutRowTextDropsTrailingZeroDistance() {
        let whole = WorkoutReplacementSummary(kind: .tempo, distanceKm: 8)
        let fractional = WorkoutReplacementSummary(kind: .easy, distanceKm: 7.5)
        XCTAssertEqual(CoachLanguage.en.workoutRowText(whole), "Tempo run · 8 km")
        XCTAssertEqual(CoachLanguage.en.workoutRowText(fractional), "Easy run · 7.5 km")
    }

    /// The footer reports the real weekly-volume delta — signed, and never a
    /// projected ACWR, which the engine does not compute.
    func testWeeklyVolumeDeltaTextIsSigned() {
        XCTAssertEqual(CoachLanguage.en.weeklyVolumeDeltaText(-2.4), "Projected weekly volume −2.4 km")
        XCTAssertEqual(CoachLanguage.en.weeklyVolumeDeltaText(3), "Projected weekly volume +3 km")
    }

    func testWeeklyVolumeDeltaTextReportsNoChange() {
        for language in CoachLanguage.allCases {
            let text = language.weeklyVolumeDeltaText(0)
            XCTAssertFalse(text.contains("+"), "\(language) must not sign a zero delta")
            XCTAssertFalse(text.contains("−"), "\(language) must not sign a zero delta")
        }
        XCTAssertEqual(CoachLanguage.en.weeklyVolumeDeltaText(0), "Weekly volume unchanged")
        // Rounding noise below 0.05 km reads as unchanged, not "+0 km".
        XCTAssertEqual(CoachLanguage.en.weeklyVolumeDeltaText(0.01), "Weekly volume unchanged")
    }
}
