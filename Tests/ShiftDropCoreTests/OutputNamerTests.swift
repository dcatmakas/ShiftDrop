import XCTest
@testable import ShiftDropCore

final class OutputNamerTests: XCTestCase {
    func testAddsSuffixAndAvoidsCollisions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("Page 001.pdf")
        let first = OutputNamer.url(for: source, ext: "jpg")
        XCTAssertEqual(first.lastPathComponent, "Page 001.jpg")

        FileManager.default.createFile(atPath: first.path, contents: Data())
        XCTAssertEqual(OutputNamer.url(for: source, ext: "jpg").lastPathComponent, "Page 001 2.jpg")
        XCTAssertEqual(OutputNamer.url(for: source, suffix: "Cropped", ext: "jpg").lastPathComponent, "Page 001 Cropped.jpg")
    }
}
