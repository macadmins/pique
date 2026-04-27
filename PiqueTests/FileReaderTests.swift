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

    // MARK: - readData

    func testReadDataReturnsRawBytes() throws {
        let file = tempDir.appendingPathComponent("raw.bin")
        let bytes: [UInt8] = [0x00, 0x01, 0xFF, 0xFE, 0x42]
        let data = Data(bytes)
        try data.write(to: file)

        let result = try FileReader.readData(url: file)
        XCTAssertEqual(result, data)
    }

    func testReadDataTooLargeThrows() throws {
        let file = tempDir.appendingPathComponent("large2.bin")
        let size = Int(FileReader.maxFileSize) + 1
        try Data(count: size).write(to: file)

        XCTAssertThrowsError(try FileReader.readData(url: file)) { error in
            guard case FileReader.FileReaderError.fileTooLarge = error else {
                XCTFail("Expected fileTooLarge")
                return
            }
        }
    }

    // MARK: - decodeToString

    func testDecodeToStringUTF8() {
        let text = "Hello, world! 🌍"
        let data = text.data(using: .utf8)!
        XCTAssertEqual(FileReader.decodeToString(data), text)
    }

    func testDecodeToStringLatin1Fallback() {
        // 0xE9 is 'é' in Latin-1 but invalid as standalone UTF-8
        let data = Data([0x63, 0x61, 0x66, 0xE9]) // "café"
        let result = FileReader.decodeToString(data)
        XCTAssertEqual(result, "café")
    }

    // MARK: - Binary plist

    func testIsBinaryPlistDetectsHeader() {
        let bplist = Data([0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30])
        XCTAssertTrue(FileReader.isBinaryPlist(bplist))

        let xml = "<?xml version=\"1.0\"".data(using: .utf8)!
        XCTAssertFalse(FileReader.isBinaryPlist(xml))
    }

    func testConvertBinaryPlistToXML() throws {
        // Create a binary plist via PropertyListSerialization
        let dict: [String: Any] = ["PayloadDisplayName": "Test Profile", "PayloadVersion": 1]
        let binaryData = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .binary, options: 0
        )
        XCTAssertTrue(FileReader.isBinaryPlist(binaryData))

        let xmlString = FileReader.convertBinaryPlistToXMLString(binaryData)
        XCTAssertNotNil(xmlString)
        XCTAssertTrue(xmlString!.contains("PayloadDisplayName"))
        XCTAssertTrue(xmlString!.contains("Test Profile"))
        XCTAssertTrue(xmlString!.contains("<?xml"))
    }

    func testConvertBinaryPlistReturnsNilForInvalidData() {
        let garbage = Data([0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0xFF, 0xFF])
        XCTAssertNil(FileReader.convertBinaryPlistToXMLString(garbage))
    }

    // MARK: - CMS envelope detection

    func testIsCMSEnvelopeDetection() {
        // Bytes containing the PKCS#7 signedData OID
        var fakeEnvelope = Data(count: 5)
        fakeEnvelope.append(contentsOf: [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02])
        fakeEnvelope.append(Data(count: 10))
        XCTAssertTrue(FileReader.isCMSEnvelope(fakeEnvelope))

        let plainXML = "<?xml version=\"1.0\"?>".data(using: .utf8)!
        XCTAssertFalse(FileReader.isCMSEnvelope(plainXML))
    }

    func testIsCMSEnvelopeTooShort() {
        let short = Data([0x06, 0x09, 0x2a])
        XCTAssertFalse(FileReader.isCMSEnvelope(short))
    }

    func testStripCMSSignatureReturnsNilForNonCMS() {
        let plainXML = "<?xml version=\"1.0\"?><plist></plist>".data(using: .utf8)!
        XCTAssertNil(FileReader.stripCMSSignature(from: plainXML))
    }

    // MARK: - Pipeline order (binary plist after CMS strip)

    func testBinaryPlistDetectedAfterCMSStrip() throws {
        // Simulate the pipeline: after CMS stripping, the inner content is a binary plist
        let dict: [String: Any] = ["PayloadType": "Configuration"]
        let binaryData = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .binary, options: 0
        )

        // Verify the pipeline steps work in sequence
        XCTAssertTrue(FileReader.isBinaryPlist(binaryData))
        let xmlString = FileReader.convertBinaryPlistToXMLString(binaryData)
        XCTAssertNotNil(xmlString)
        XCTAssertTrue(xmlString!.contains("PayloadType"))
        XCTAssertTrue(xmlString!.contains("Configuration"))
    }

    // MARK: - Recipe YAML parser

    func testRecipeYAMLParsesScalarsAndNestedMapping() {
        let yaml = """
            Identifier: com.example.foo
            Description: Hello world
            Input:
              NAME: Foo
            """
        let dict = RecipeYAMLParser.parse(yaml)
        XCTAssertEqual(dict?["Identifier"] as? String, "com.example.foo")
        XCTAssertEqual(dict?["Description"] as? String, "Hello world")
        XCTAssertEqual((dict?["Input"] as? [String: Any])?["NAME"] as? String, "Foo")
    }

    func testRecipeYAMLParsesSequenceAtSameIndentAsParent() {
        // recipe-robot emits Process: with `- ` at column 0; this is the bug
        // that existed in v1 of the parser.
        let yaml = """
            Process:
            - Processor: Alpha
            - Processor: Beta
            """
        let dict = RecipeYAMLParser.parse(yaml)
        let process = dict?["Process"] as? [Any]
        XCTAssertEqual(process?.count, 2)
        XCTAssertEqual((process?[0] as? [String: Any])?["Processor"] as? String, "Alpha")
        XCTAssertEqual((process?[1] as? [String: Any])?["Processor"] as? String, "Beta")
    }

    func testRecipeYAMLParsesProcessStepWithArguments() {
        let yaml = """
            Process:
            - Processor: AppPkgCreator
              Arguments:
                app_path: '%RECIPE_CACHE_DIR%/%NAME%.app'
            """
        let dict = RecipeYAMLParser.parse(yaml)
        let step = (dict?["Process"] as? [Any])?.first as? [String: Any]
        XCTAssertEqual(step?["Processor"] as? String, "AppPkgCreator")
        let args = step?["Arguments"] as? [String: Any]
        XCTAssertEqual(args?["app_path"] as? String, "%RECIPE_CACHE_DIR%/%NAME%.app")
    }

    func testRecipeYAMLSingleQuotedNumberStaysString() {
        let dict = RecipeYAMLParser.parse("MinimumVersion: '2.3'")
        // Single-quoted '2.3' must be preserved as a string, not converted to 2.3
        XCTAssertEqual(dict?["MinimumVersion"] as? String, "2.3")
    }

    func testRecipeYAMLBareNumberBecomesNumber() {
        let dict = RecipeYAMLParser.parse("MinimumVersion: 2.3")
        XCTAssertEqual(dict?["MinimumVersion"] as? Double, 2.3)
    }

    func testRecipeYAMLIgnoresLineComments() {
        let yaml = """
            # heading comment
            Identifier: com.example.foo  # trailing comment
            """
        let dict = RecipeYAMLParser.parse(yaml)
        XCTAssertEqual(dict?["Identifier"] as? String, "com.example.foo")
    }

    func testRecipeYAMLProcessStepWithoutArguments() {
        // Raycast.pkg.recipe.yaml has `- Processor: AppPkgCreator` with no Arguments
        let yaml = """
            Process:
            - Processor: AppPkgCreator
            """
        let dict = RecipeYAMLParser.parse(yaml)
        let step = (dict?["Process"] as? [Any])?.first as? [String: Any]
        XCTAssertEqual(step?["Processor"] as? String, "AppPkgCreator")
        XCTAssertNil(step?["Arguments"])
    }

}
