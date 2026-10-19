import XCTest
@testable import MarginaliaCore

final class DocumentTests: XCTestCase {
    func testReadsUTF8() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t.md")
        try "# Hola\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try Document(url: url).text, "# Hola\n")
    }
}
