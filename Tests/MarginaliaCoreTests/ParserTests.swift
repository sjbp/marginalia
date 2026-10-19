import XCTest
@testable import MarginaliaCore

final class ParserTests: XCTestCase {
    func testSourceMapUnicode() {
        let m = SourceMap("á b\nc😀d\ne")
        XCTAssertEqual(m.lineCount, 3)
        XCTAssertEqual(m.utf16Offset(line: 1, column: 1), 0)
        XCTAssertEqual(m.utf16Offset(line: 1, column: 3), 1)   // after á (2 bytes)
        XCTAssertEqual(m.utf16Offset(line: 2, column: 1), 4)
        XCTAssertEqual(m.utf16Offset(line: 2, column: 6), 7)   // after c + 😀 (4 bytes, 2 units)
        XCTAssertEqual(m.lineRange(1), NSRange(location: 4, length: 4))
        XCTAssertEqual(m.lineRange(2), NSRange(location: 9, length: 1))
    }

    func testLineKindsAndPrefixes() {
        let src = """
        ---
        title: x
        ---
        # Título

        Para **b** _i_.

        - item one
          continues
          - nested
        10. num
        - [ ] task

        > quote

        ```swift
        let x = 1
        ```

        | a | bb |
        |---|---|
        | ccc | d |
        """
        let m = MarkdownParser.parse(src)
        let kinds = m.lines.map { $0.kind }
        XCTAssertEqual(Array(kinds[0...2]), [.frontmatter, .frontmatter, .frontmatter])
        XCTAssertEqual(kinds[3], .heading); XCTAssertEqual(m.lines[3].prefixLength, 2); XCTAssertEqual(m.lines[3].headingLevel, 1)
        XCTAssertEqual(kinds[5], .text)
        XCTAssertEqual(kinds[7], .listItem); XCTAssertEqual(m.lines[7].prefixLength, 2); XCTAssertEqual(m.lines[7].listDepth, 1)
        XCTAssertEqual(kinds[8], .listContinuation); XCTAssertEqual(m.lines[8].prefixLength, 2)
        XCTAssertEqual(kinds[9], .listItem); XCTAssertEqual(m.lines[9].prefixLength, 4); XCTAssertEqual(m.lines[9].listDepth, 2)
        XCTAssertEqual(kinds[10], .listItem); XCTAssertEqual(m.lines[10].prefixLength, 4); XCTAssertTrue(m.lines[10].ordered)
        XCTAssertEqual(kinds[11], .listItem); XCTAssertEqual(m.lines[11].prefixLength, 6); XCTAssertEqual(m.lines[11].checkbox, 1)
        XCTAssertEqual(kinds[13], .text); XCTAssertEqual(m.lines[13].quoteDepth, 1); XCTAssertEqual(m.lines[13].prefixLength, 2)
        XCTAssertEqual(kinds[15], .codeFence); XCTAssertEqual(kinds[16], .code); XCTAssertEqual(kinds[17], .codeFence)
        XCTAssertEqual(m.codeBlocks.first?.language, "swift")
        XCTAssertEqual(kinds[19], .table); XCTAssertEqual(kinds[20], .tableSeparator); XCTAssertEqual(kinds[21], .table)
        XCTAssertEqual(m.headings.count, 1)
        let line5 = m.lines[5].range
        let spans = m.inlines.filter { NSIntersectionRange($0.range, line5).length > 0 }
        XCTAssertTrue(spans.contains { $0.kind == .strong && (src as NSString).substring(with: $0.range) == "b" })
        XCTAssertTrue(spans.contains { $0.kind == .emphasis && (src as NSString).substring(with: $0.range) == "i" })
        XCTAssertEqual(spans.filter { $0.kind == .marker }.count, 4)
        let t = m.tables[0]
        XCTAssertEqual(t.lines.count, 3)
        // first row: " a " (3) vs " ccc " (5) → pad 2 ; " bb " (4) is the widest in col 2
        XCTAssertEqual(t.lines[0].pads.map { $0.chars }, [2])
        XCTAssertEqual(t.lines[2].pads.map { $0.chars }, [1])
    }

    func testCriticMarkup() {
        let src = "A {==word==}{>>@sebo: hmm<<}{>>@claude: ok<<} B {>>loose<<} {++new++} {--old--} {~~a~>b~~}"
        let m = MarkdownParser.parse(src)
        XCTAssertEqual(m.comments.count, 3)
        XCTAssertEqual(m.comments[0].author, "sebo"); XCTAssertEqual(m.comments[0].text, "hmm")
        XCTAssertEqual((src as NSString).substring(with: m.comments[0].anchorRange!), "word")
        XCTAssertEqual(m.comments[1].author, "claude")
        XCTAssertEqual((src as NSString).substring(with: m.comments[1].anchorRange!), "word")
        XCTAssertNil(m.comments[2].author); XCTAssertNil(m.comments[2].anchorRange)
        XCTAssertTrue(m.inlines.contains { $0.kind == .criticAdd })
        XCTAssertTrue(m.inlines.contains { $0.kind == .criticSubstNew && (src as NSString).substring(with: $0.range) == "b" })
    }

    func testLinksAndCode() {
        let src = "see [spec](SPEC.md \"t\") and <https://a.b> and `x` and ![i](p.png) and note[^1]"
        let m = MarkdownParser.parse(src)
        let ns = src as NSString
        func texts(_ k: InlineKind) -> [String] { m.inlines.filter { $0.kind == k }.map { ns.substring(with: $0.range) } }
        XCTAssertEqual(texts(.linkText), ["spec"])
        XCTAssertEqual(texts(.linkURL), ["SPEC.md \"t\"", "p.png"])
        XCTAssertEqual(texts(.autolink), ["https://a.b"])
        XCTAssertEqual(texts(.code), ["x"])
        XCTAssertEqual(texts(.imageAlt), ["i"])
        XCTAssertEqual(texts(.footnoteRef), ["[^1]"])
    }

    func testLargeParses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/large.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let t0 = CFAbsoluteTimeGetCurrent()
        let m = MarkdownParser.parse(text)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("large.md parse_ms=\(ms) lines=\(m.lines.count) inlines=\(m.inlines.count) comments=\(m.comments.count)")
        XCTAssertGreaterThan(m.headings.count, 100)
    }
}
