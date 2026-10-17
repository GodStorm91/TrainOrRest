import XCTest
@testable import TrainOrRest

final class PartialToolTextReaderTests: XCTestCase {
    /// Feeds the same JSON at several fragment sizes, because the network
    /// decides where an SSE delta splits and every boundary must behave.
    private func read(_ json: String, key: String = "content", file: StaticString = #filePath, line: UInt = #line) -> [String] {
        [1, 2, 3, 5, 7, 13, 1_000].map { size in
            var reader = PartialToolTextReader(key: key)
            var output = ""
            var chunk = ""
            for character in json {
                chunk.append(character)
                if chunk.count == size {
                    output += reader.consume(chunk)
                    chunk = ""
                }
            }
            if !chunk.isEmpty { output += reader.consume(chunk) }
            return output
        }
    }

    private func assertReads(_ json: String, _ expected: String, key: String = "content", file: StaticString = #filePath, line: UInt = #line) {
        for (index, output) in read(json, key: key).enumerated() {
            XCTAssertEqual(output, expected, "fragment layout \(index)", file: file, line: line)
        }
    }

    func testReadsValueWhenKeyComesFirst() {
        assertReads(#"{"content":"Easy 6 km today.","title":"Go easy"}"#, "Easy 6 km today.")
    }

    func testReadsValueWhenKeyComesAfterOtherFields() {
        assertReads(#"{"title":"Go easy","priority":3,"ok":true,"content":"Nghỉ hôm nay."}"#, "Nghỉ hôm nay.")
    }

    func testEmitsEverythingDecodedSoFarWhenTheStreamStopsMidValue() {
        assertReads(#"{"content":"Easy 6 km toda"#, "Easy 6 km toda")
    }

    func testDecodesEscapeSequences() {
        assertReads(#"{"content":"Line\nTwo \"quoted\" and \\ and \u00e9."}"#, "Line\nTwo \"quoted\" and \\ and é.")
    }

    func testDecodesSurrogatePairs() {
        assertReads(#"{"content":"ok \ud83d\ude00 done"}"#, "ok 😀 done")
    }

    func testIgnoresTheSameKeyNestedInsideAnotherObject() {
        assertReads(#"{"details":{"content":"wrong"},"content":"right"}"#, "right")
    }

    func testIgnoresTheKeyNameAppearingInsideAnotherStringValue() {
        assertReads(#"{"title":"the \"content\": field","content":"real"}"#, "real")
    }

    func testStopsAtTheClosingQuoteAndIgnoresLaterFields() {
        assertReads(#"{"content":"done","followUps":[{"id":"a","value":"c"}]}"#, "done")
    }

    func testReturnsNothingWhenTheKeyIsAbsent() {
        assertReads(#"{"title":"only"}"#, "")
    }

    func testHoldsBackAnIncompleteUnicodeEscape() {
        var reader = PartialToolTextReader(key: "content")
        XCTAssertEqual(reader.consume(#"{"content":"caf\u00"#), "caf")
        XCTAssertEqual(reader.consume(#"e9 noir"}"#), "é noir")
    }

    func testReportsFinishedOnlyAfterTheValueCloses() {
        var reader = PartialToolTextReader(key: "content")
        _ = reader.consume(#"{"content":"half"#)
        XCTAssertFalse(reader.isFinished)
        _ = reader.consume(#"done"}"#)
        XCTAssertTrue(reader.isFinished)
    }
}
