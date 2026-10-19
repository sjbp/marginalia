import XCTest
@testable import MarginaliaCore

final class SmartEditTests: XCTestCase {
    func info(_ src: String, line: Int) -> LineInfo { MarkdownParser.parse(src).lines[line] }

    func apply(_ text: String, _ e: SmartEdit.Edit) -> String { (text as NSString).replacingCharacters(in: e.range, with: e.replacement) }

    func testBulletContinues() {
        let src = "- item"
        let e = SmartEdit.newline(line: "- item", lineStart: 0, caretInLine: 6, info: info(src, line: 0))!
        XCTAssertEqual(apply(src, e), "- item\n- ")
        XCTAssertEqual(e.caret, 9)
    }

    func testNumberedIncrements() {
        let src = "10. ten"
        let e = SmartEdit.newline(line: "10. ten", lineStart: 0, caretInLine: 7, info: info(src, line: 0))!
        XCTAssertEqual(apply(src, e), "10. ten\n11. ")
    }

    func testTaskContinuesUnchecked() {
        let src = "- [x] done"
        let e = SmartEdit.newline(line: "- [x] done", lineStart: 0, caretInLine: 10, info: info(src, line: 0))!
        XCTAssertEqual(apply(src, e), "- [x] done\n- [ ] ")
    }

    func testEmptyItemRemovesMarker() {
        let src = "- a\n- "
        let e = SmartEdit.newline(line: "- ", lineStart: 4, caretInLine: 2, info: info(src, line: 1))!
        XCTAssertEqual(apply(src, e), "- a\n")
    }

    func testNestedKeepsIndent() {
        let src = "- a\n  - b"
        let e = SmartEdit.newline(line: "  - b", lineStart: 4, caretInLine: 5, info: info(src, line: 1))!
        XCTAssertEqual(apply(src, e), "- a\n  - b\n  - ")
    }

    func testQuoteContinues() {
        let src = "> q"
        let e = SmartEdit.newline(line: "> q", lineStart: 0, caretInLine: 3, info: info(src, line: 0))!
        XCTAssertEqual(apply(src, e), "> q\n> ")
    }

    func testQuoteListContinues() {
        let src = "> - q"
        let e = SmartEdit.newline(line: "> - q", lineStart: 0, caretInLine: 5, info: info(src, line: 0))!
        XCTAssertEqual(apply(src, e), "> - q\n> - ")
    }

    func testPlainParagraphIsNil() {
        XCTAssertNil(SmartEdit.newline(line: "hello", lineStart: 0, caretInLine: 5, info: info("hello", line: 0)))
    }

    func testCodeKeepsIndent() {
        let src = "```\n    x\n```"
        let e = SmartEdit.newline(line: "    x", lineStart: 4, caretInLine: 5, info: info(src, line: 1))!
        XCTAssertEqual(apply(src, e), "```\n    x\n    \n```")
    }

    func testWrapUnwrap() {
        let t = "hello world" as NSString
        let w = SmartEdit.toggleWrap(text: t, selection: NSRange(location: 0, length: 5), delimiter: "**")
        XCTAssertEqual(apply(t as String, w), "**hello** world")
        let t2 = "**hello** world" as NSString
        let u = SmartEdit.toggleWrap(text: t2, selection: NSRange(location: 2, length: 5), delimiter: "**")
        XCTAssertEqual(apply(t2 as String, u), "hello world")
        let u2 = SmartEdit.toggleWrap(text: t2, selection: NSRange(location: 0, length: 9), delimiter: "**")
        XCTAssertEqual(apply(t2 as String, u2), "hello world")
        let empty = SmartEdit.toggleWrap(text: t, selection: NSRange(location: 5, length: 0), delimiter: "_")
        XCTAssertEqual(apply(t as String, empty), "hello__ world"); XCTAssertEqual(empty.caret, 6)
    }

    func testHeadingShift() {
        let up = SmartEdit.shiftHeading(line: "## T", lineStart: 0, caret: 4, up: true)!
        XCTAssertEqual(apply("## T", up), "### T"); XCTAssertEqual(up.caret, 5)
        let down = SmartEdit.shiftHeading(line: "# T", lineStart: 0, caret: 3, up: false)!
        XCTAssertEqual(apply("# T", down), "T"); XCTAssertEqual(down.caret, 1)
        let make = SmartEdit.shiftHeading(line: "T", lineStart: 0, caret: 1, up: true)!
        XCTAssertEqual(apply("T", make), "# T")
        XCTAssertNil(SmartEdit.shiftHeading(line: "###### T", lineStart: 0, caret: 0, up: true))
    }

    func testToggleTask() {
        XCTAssertEqual(apply("- [ ] a", SmartEdit.toggleTask(line: "- [ ] a", lineStart: 0, caret: 7)), "- [x] a")
        XCTAssertEqual(apply("- [x] a", SmartEdit.toggleTask(line: "- [x] a", lineStart: 0, caret: 7)), "- [ ] a")
        XCTAssertEqual(apply("- a", SmartEdit.toggleTask(line: "- a", lineStart: 0, caret: 3)), "- [ ] a")
        XCTAssertEqual(apply("a", SmartEdit.toggleTask(line: "a", lineStart: 0, caret: 1)), "- [ ] a")
    }

    func testMoveLines() {
        let t = "a\nb\nc" as NSString
        let (down, sel) = SmartEdit.moveLines(text: t, selection: NSRange(location: 0, length: 0), up: false)!
        XCTAssertEqual(apply(t as String, down), "b\na\nc"); XCTAssertEqual(sel.location, 2)
        let (up, sel2) = SmartEdit.moveLines(text: t, selection: NSRange(location: 4, length: 0), up: true)!
        XCTAssertEqual(apply(t as String, up), "a\nc\nb"); XCTAssertEqual(sel2.location, 2)
        XCTAssertNil(SmartEdit.moveLines(text: t, selection: NSRange(location: 0, length: 0), up: true))
    }

    func testLink() {
        let e = SmartEdit.link(text: "spec" as NSString, selection: NSRange(location: 0, length: 4), clipboardURL: nil)
        XCTAssertEqual(apply("spec", e), "[spec]()"); XCTAssertEqual(e.caret, 7)
        let e2 = SmartEdit.link(text: "spec" as NSString, selection: NSRange(location: 0, length: 4), clipboardURL: "https://x.y")
        XCTAssertEqual(apply("spec", e2), "[spec](https://x.y)")
    }
}

final class BlockFormatTests: XCTestCase {
    func apply(_ t: String, _ e: SmartEdit.Edit) -> String { (t as NSString).replacingCharacters(in: e.range, with: e.replacement) }

    func testBulletOnAndOff() {
        let t = "a\nb\nc"
        let (e, sel) = SmartEdit.toggleBlock(text: t as NSString, selection: NSRange(location: 0, length: 3), kind: .bullet)
        XCTAssertEqual(apply(t, e), "- a\n- b\nc"); XCTAssertEqual(sel, NSRange(location: 0, length: 7))
        let t2 = "- a\n- b"
        let (e2, _) = SmartEdit.toggleBlock(text: t2 as NSString, selection: NSRange(location: 0, length: 7), kind: .bullet)
        XCTAssertEqual(apply(t2, e2), "a\nb")
    }

    func testNumberReplacesBullets() {
        let t = "- a\n- b\n"
        let (e, _) = SmartEdit.toggleBlock(text: t as NSString, selection: NSRange(location: 0, length: 7), kind: .number)
        XCTAssertEqual(apply(t, e), "1. a\n2. b\n")
    }

    func testTaskAndHeading() {
        let (e, _) = SmartEdit.toggleBlock(text: "x" as NSString, selection: NSRange(location: 0, length: 1), kind: .task)
        XCTAssertEqual(apply("x", e), "- [ ] x")
        let (h, _) = SmartEdit.toggleBlock(text: "- x" as NSString, selection: NSRange(location: 0, length: 3), kind: .heading(2))
        XCTAssertEqual(apply("- x", h), "## x")
        let (h2, _) = SmartEdit.toggleBlock(text: "## x" as NSString, selection: NSRange(location: 0, length: 4), kind: .heading(2))
        XCTAssertEqual(apply("## x", h2), "x")
    }

    func testQuoteWrapsAndUnwraps() {
        let (q, _) = SmartEdit.toggleBlock(text: "- a" as NSString, selection: NSRange(location: 0, length: 3), kind: .quote)
        XCTAssertEqual(apply("- a", q), "> - a")
        let (u, _) = SmartEdit.toggleBlock(text: "> - a" as NSString, selection: NSRange(location: 0, length: 5), kind: .quote)
        XCTAssertEqual(apply("> - a", u), "- a")
    }
}
