import XCTest
@testable import TrainOrRest

final class CoachGlossaryTests: XCTestCase {
    func testResolvesACWRTermByID() {
        XCTAssertEqual(CoachGlossary.term(id: "acwr")?.canonicalLabel, "ACWR")
    }

    func testNormalizesKnownModelTyposAtWordBoundaries() {
        XCTAssertEqual(CoachGlossary.normalizeModelText("Track AWCR daily"), "Track ACWR daily")
        XCTAssertEqual(CoachGlossary.normalizeModelText("AWCRx"), "AWCRx")
        XCTAssertEqual(CoachGlossary.normalizeModelText("track awcr daily"), "track ACWR daily")
    }

    func testResolvesDistinctShortAcronymAliases() {
        XCTAssertEqual(CoachGlossary.term(matchingAlias: "HRV")?.id, "hrv")
        XCTAssertEqual(CoachGlossary.term(matchingAlias: "RHR")?.id, "rhr")
        XCTAssertNotEqual(CoachGlossary.term(matchingAlias: "HRV")?.id, CoachGlossary.term(matchingAlias: "RHR")?.id)
        XCTAssertNil(CoachGlossary.term(matchingAlias: "HR"))
    }

    func testResolvesThresholdPaceAliases() {
        XCTAssertEqual(CoachGlossary.term(matchingAlias: "T-pace")?.id, "t_pace")
        XCTAssertEqual(CoachGlossary.term(matchingAlias: "T pace")?.id, "t_pace")
        XCTAssertEqual(CoachGlossary.term(matchingAlias: "Threshold pace")?.id, "t_pace")
    }

    func testGlossarySheetResolvesLocalizedACWRContent() throws {
        let term = try XCTUnwrap(CoachGlossary.term(id: "acwr"))

        XCTAssertEqual(term.content(for: .vi).title, "Tỷ lệ tải cấp tính/mạn tính")
        XCTAssertEqual(term.content(for: .en).title, "Acute:Chronic Workload Ratio")
    }

    func testMetricLabelResolvesGlossaryID() {
        let metric = CoachMetric(id: "load", label: "ACWR", value: "1.2", interpretation: nil, status: .neutral)

        XCTAssertEqual(CoachGlossary.term(matchingAlias: metric.label)?.id, "acwr")
    }

    func testStructuredMarkupUsesPlainLabelForUnknownTerms() {
        XCTAssertEqual(CoachGlossaryMarkup.parse("[[term:xyz|Made Up]]"), [.text("Made Up")])
    }

    func testStructuredMarkupDoesNotLeakMalformedMarkers() {
        let inputs = ["a [[term:acwr]] b", "[[term:]]", "[[term:acwr|]]"]

        for input in inputs {
            XCTAssertFalse(textSegments(CoachGlossaryMarkup.parse(input)).contains { $0.contains("[[term:") })
        }
    }

    func testStructuredMarkupProducesOrderedSegments() {
        XCTAssertEqual(
            CoachGlossaryMarkup.parse("Track [[term:acwr|ACWR]] and [[term:hrv|HRV]]."),
            [
                .text("Track "),
                .term(id: "acwr", label: "ACWR"),
                .text(" and "),
                .term(id: "hrv", label: "HRV"),
                .text(".")
            ]
        )
    }

    func testStructuredMarkupDropsUnclosedStreamingMarker() {
        XCTAssertEqual(CoachGlossaryMarkup.parse("See [[term:ac"), [.text("See ")])
    }

    func testLegacySegmentsAnnotateKnownTerms() {
        XCTAssertEqual(
            CoachGlossaryMarkup.legacySegments("Track ACWR and HRV each morning"),
            [
                .text("Track "),
                .term(id: "acwr", label: "ACWR"),
                .text(" and "),
                .term(id: "hrv", label: "HRV"),
                .text(" each morning")
            ]
        )
    }

    func testLegacySegmentsAnnotatesOnlyFirstOccurrenceOfEachTerm() {
        XCTAssertEqual(
            CoachGlossaryMarkup.legacySegments("ACWR then ACWR again"),
            [.term(id: "acwr", label: "ACWR"), .text(" then ACWR again")]
        )
    }

    func testLegacySegmentsSkipsInlineCodeAndURLs() {
        XCTAssertEqual(CoachGlossaryMarkup.legacySegments("use `ACWR` in code"), [.text("use `ACWR` in code")])
        XCTAssertEqual(CoachGlossaryMarkup.legacySegments("visit https://x/ACWR"), [.text("visit https://x/ACWR")])
    }

    func testLegacySegmentsIgnoresPartialAcronyms() {
        XCTAssertEqual(
            CoachGlossaryMarkup.legacySegments("HR is not HRV"),
            [.text("HR is not "), .term(id: "hrv", label: "HRV")]
        )
    }

    func testFirstOccurrenceOnlyConvertsRepeatedTermsToText() {
        XCTAssertEqual(
            CoachGlossaryMarkup.firstOccurrenceOnly([
                .term(id: "acwr", label: "ACWR"),
                .text(" x "),
                .term(id: "acwr", label: "ACWR")
            ]),
            [.term(id: "acwr", label: "ACWR"), .text(" x ACWR")]
        )
    }

    func testGlossaryTokenURLRoundTripsTermID() {
        XCTAssertEqual(
            CoachGlossaryTokenURL.termID(from: CoachGlossaryTokenURL.url(for: "acwr")),
            "acwr"
        )
        XCTAssertNil(CoachGlossaryTokenURL.termID(from: URL(string: "https://example.com/acwr")!))
    }

    private func textSegments(_ segments: [CoachGlossarySegment]) -> [String] {
        segments.compactMap {
            guard case let .text(text) = $0 else { return nil }
            return text
        }
    }
}
