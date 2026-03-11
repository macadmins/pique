import XCTest
@testable import Pique

final class FileFormatTests: XCTestCase {

    // MARK: - Known extensions

    func testJSON() {
        XCTAssertEqual(FileFormat(pathExtension: "json"), .json)
    }

    func testYAML() {
        XCTAssertEqual(FileFormat(pathExtension: "yaml"), .yaml)
        XCTAssertEqual(FileFormat(pathExtension: "yml"), .yaml)
    }

    func testTOML() {
        XCTAssertEqual(FileFormat(pathExtension: "toml"), .toml)
        XCTAssertEqual(FileFormat(pathExtension: "lock"), .toml)
    }

    func testXML() {
        XCTAssertEqual(FileFormat(pathExtension: "xml"), .xml)
        XCTAssertEqual(FileFormat(pathExtension: "recipe"), .xml)
    }

    func testMobileconfig() {
        XCTAssertEqual(FileFormat(pathExtension: "mobileconfig"), .mobileconfig)
        XCTAssertEqual(FileFormat(pathExtension: "plist"), .mobileconfig)
    }

    func testShell() {
        for ext in ["sh", "bash", "zsh", "ksh", "dash", "rc"] {
            XCTAssertEqual(FileFormat(pathExtension: ext), .shell, "Expected .shell for .\(ext)")
        }
    }

    func testPowerShell() {
        for ext in ["ps1", "psm1", "psd1"] {
            XCTAssertEqual(FileFormat(pathExtension: ext), .powershell, "Expected .powershell for .\(ext)")
        }
    }

    func testPython() {
        for ext in ["py", "pyw", "pyi"] {
            XCTAssertEqual(FileFormat(pathExtension: ext), .python, "Expected .python for .\(ext)")
        }
    }

    func testRuby() {
        XCTAssertEqual(FileFormat(pathExtension: "rb"), .ruby)
        XCTAssertEqual(FileFormat(pathExtension: "gemspec"), .ruby)
        XCTAssertEqual(FileFormat(pathExtension: "rakefile"), .ruby)
    }

    func testGo() {
        XCTAssertEqual(FileFormat(pathExtension: "go"), .go)
    }

    func testRust() {
        XCTAssertEqual(FileFormat(pathExtension: "rs"), .rust)
    }

    func testJavaScript() {
        for ext in ["js", "jsx", "ts", "tsx", "mjs", "cjs"] {
            XCTAssertEqual(FileFormat(pathExtension: ext), .javascript, "Expected .javascript for .\(ext)")
        }
    }

    func testMarkdown() {
        XCTAssertEqual(FileFormat(pathExtension: "md"), .markdown)
        XCTAssertEqual(FileFormat(pathExtension: "markdown"), .markdown)
        XCTAssertEqual(FileFormat(pathExtension: "adoc"), .markdown)
    }

    func testHCL() {
        for ext in ["tf", "tfvars", "hcl"] {
            XCTAssertEqual(FileFormat(pathExtension: ext), .hcl, "Expected .hcl for .\(ext)")
        }
    }

    // MARK: - Case insensitivity

    func testCaseInsensitive() {
        XCTAssertEqual(FileFormat(pathExtension: "JSON"), .json)
        XCTAssertEqual(FileFormat(pathExtension: "YAML"), .yaml)
        XCTAssertEqual(FileFormat(pathExtension: "Toml"), .toml)
        XCTAssertEqual(FileFormat(pathExtension: "SH"), .shell)
    }

    // MARK: - Unknown / empty

    func testUnknownExtension() {
        XCTAssertNil(FileFormat(pathExtension: "docx"))
        XCTAssertNil(FileFormat(pathExtension: "pdf"))
        XCTAssertNil(FileFormat(pathExtension: "exe"))
    }

    func testEmptyExtension() {
        XCTAssertNil(FileFormat(pathExtension: ""))
    }
}
