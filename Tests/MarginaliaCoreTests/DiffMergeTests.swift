import XCTest
@testable import MarginaliaCore

final class DiffMergeTests: XCTestCase {
    func testDiffMarksChangedLines() {
        let r = LineDiff.diff(old: "a\nb\nc\n", new: "a\nB\nc\nd\n")
        XCTAssertEqual(r.changedNewLines, [1, 3])
        XCTAssertEqual(r.oldToNew[0], 0); XCTAssertEqual(r.oldToNew[2], 2)
        XCTAssertEqual(LineDiff.mapLine(1, r, oldCount: 3), 1)
    }

    func testDiffRemoval() {
        let r = LineDiff.diff(old: "a\nb\nc\n", new: "a\nc\n")
        XCTAssertEqual(r.removedBefore, [1])
        XCTAssertEqual(r.oldToNew[2], 1)
    }

    func testMergeDisjoint() {
        let base = "1\n2\n3\n4\n5\n"
        let ours = "1\nX\n3\n4\n5\n"
        let theirs = "1\n2\n3\n4\nY\n"
        let m = ThreeWayMerge.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(m.text, "1\nX\n3\n4\nY\n")
        XCTAssertFalse(m.hadConflict)
    }

    func testMergeTheirsOnly() {
        let m = ThreeWayMerge.merge(base: "a\nb\n", ours: "a\nb\n", theirs: "a\nb\nc\n")
        XCTAssertEqual(m.text, "a\nb\nc\n")
    }

    func testMergeConflictKeepsOurs() {
        let m = ThreeWayMerge.merge(base: "1\n2\n3\n", ours: "1\nours\n3\n", theirs: "1\ntheirs\n3\n")
        XCTAssertEqual(m.text, "1\nours\n3\n")
        XCTAssertEqual(m.conflictLines, [1])
    }

    func testMergeInsertAtEndBothSides() {
        let m = ThreeWayMerge.merge(base: "a\n", ours: "a\nb\n", theirs: "a\nc\n")
        XCTAssertTrue(m.hadConflict)
        XCTAssertEqual(m.text, "a\nb\n")
    }

    func testMergeTheirsAppendOursEditTop() {
        let base = "# T\n\npara\n"
        let ours = "# Title\n\npara\n"
        let theirs = "# T\n\npara\n\nnew paragraph\n"
        let m = ThreeWayMerge.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(m.text, "# Title\n\npara\n\nnew paragraph\n")
        XCTAssertFalse(m.hadConflict)
    }
}
