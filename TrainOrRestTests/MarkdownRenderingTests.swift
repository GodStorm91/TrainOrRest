import XCTest
@testable import TrainOrRest

/// Regressions for the coach-reply "wall" bug: multi-line prose collapsing into
/// one run of text with ordered-list numbers eaten. Two independent layers had
/// to preserve line structure — the block parser and the inline renderer.
final class MarkdownRenderingTests: XCTestCase {
    // Layer A — the block parser must keep author line breaks inside a
    // paragraph. It previously joined consecutive lines with a space, so a
    // multi-line reply became a single unreadable block.
    func testParagraphPreservesSoftLineBreaks() {
        let blocks = MarkdownBlockParser.parse("Ket luan: X\nLy do: Y\nBan muon?")

        XCTAssertEqual(blocks, [.paragraph("Ket luan: X\nLy do: Y\nBan muon?")])
    }

    // A blank line is still a real paragraph boundary after the fix.
    func testBlankLineStillSeparatesParagraphs() {
        let blocks = MarkdownBlockParser.parse("First line\nsecond line\n\nThird block")

        XCTAssertEqual(blocks, [
            .paragraph("First line\nsecond line"),
            .paragraph("Third block"),
        ])
    }

    // Layer B — inline rendering must preserve newlines. The default `.full`
    // markdown syntax collapses soft newlines to spaces.
    func testInlineMarkdownPreservesNewlines() {
        let rendered = String(InlineMarkdown.attributed("a\nb\nc").characters)

        XCTAssertEqual(rendered, "a\nb\nc")
    }

    // Layer B — inline rendering must keep literal ordered-list markers. The
    // default `.full` syntax parses `1) ` / `1. ` as a list and drops the
    // number, producing "abc" from three numbered lines.
    func testInlineMarkdownKeepsOrderedListMarkers() {
        let rendered = String(InlineMarkdown.attributed("1) a\n2) b\n3) c").characters)

        XCTAssertEqual(rendered, "1) a\n2) b\n3) c")
    }
}
