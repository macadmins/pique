import XCTest
@testable import Pique

final class FileReaderTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiqueTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Happy path

    func testReadUTF8File() throws {
        let file = tempDir.appendingPathComponent("test.txt")
        let content = "Hello, Pique!\nLine 2"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let result = try FileReader.read(url: file)
        XCTAssertEqual(result, content)
    }

    func testReadEmptyFile() throws {
        let file = tempDir.appendingPathComponent("empty.txt")
        try Data().write(to: file)

        let result = try FileReader.read(url: file)
        XCTAssertEqual(result, "")
    }

    func testReadISOLatin1File() throws {
        let file = tempDir.appendingPathComponent("latin1.txt")
        // Write bytes that are valid ISO Latin-1 but invalid UTF-8
        let latin1String = "caf\u{00E9}" // cafe with accent
        let data = latin1String.data(using: .isoLatin1)!
        try data.write(to: file)

        let result = try FileReader.read(url: file)
        XCTAssertTrue(result.contains("caf"))
    }

    // MARK: - Size limit

    func testFileTooLargeThrows() throws {
        let file = tempDir.appendingPathComponent("large.bin")
        // Create a file just over the 10MB limit
        let size = Int(FileReader.maxFileSize) + 1
        let data = Data(count: size)
        try data.write(to: file)

        XCTAssertThrowsError(try FileReader.read(url: file)) { error in
            guard let readerError = error as? FileReader.FileReaderError else {
                XCTFail("Expected FileReaderError, got \(type(of: error))")
                return
            }
            if case .fileTooLarge(let reportedSize) = readerError {
                XCTAssertEqual(reportedSize, UInt64(size))
            } else {
                XCTFail("Expected fileTooLarge case")
            }
        }
    }

    func testErrorDescriptionFormatsMB() throws {
        let error = FileReader.FileReaderError.fileTooLarge(15_500_000)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("15.5 MB"), "Expected '15.5 MB' in: \(desc)")
        XCTAssertTrue(desc.contains("10 MB"), "Expected '10 MB' in: \(desc)")
    }

    func testNonExistentFileThrows() {
        let bogus = tempDir.appendingPathComponent("does-not-exist.txt")
        XCTAssertThrowsError(try FileReader.read(url: bogus))
    }

    func testFileAtExactLimitSucceeds() throws {
        let file = tempDir.appendingPathComponent("exact.bin")
        let data = Data(count: Int(FileReader.maxFileSize))
        try data.write(to: file)

        // Should not throw
        _ = try FileReader.read(url: file)
    }
}
