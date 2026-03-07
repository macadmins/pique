import XCTest
@testable import Pique

final class FormattingTests: XCTestCase {

    // MARK: - formatDuration

    func testFormatDurationZero() {
        XCTAssertEqual(SyntaxHighlighter.formatDuration(seconds: 0), "0s")
    }

    func testFormatDurationAllComponents() {
        // 1d 1h 1m 1s = 86400 + 3600 + 60 + 1 = 90061
        XCTAssertEqual(SyntaxHighlighter.formatDuration(seconds: 90061), "1d 1h 1m 1s")
    }

    func testFormatDurationExactHour() {
        XCTAssertEqual(SyntaxHighlighter.formatDuration(seconds: 3600), "1h")
    }

    func testFormatDurationMinutesAndSeconds() {
        XCTAssertEqual(SyntaxHighlighter.formatDuration(seconds: 90), "1m 30s")
    }

    func testFormatDurationDaysOnly() {
        XCTAssertEqual(SyntaxHighlighter.formatDuration(seconds: 172800), "2d")
    }

    // MARK: - formatHours

    func testFormatHoursZero() {
        XCTAssertEqual(SyntaxHighlighter.formatHours(0), "0h")
    }

    func testFormatHoursWithDays() {
        XCTAssertEqual(SyntaxHighlighter.formatHours(25), "1d 1h")
    }

    func testFormatHoursExactDay() {
        XCTAssertEqual(SyntaxHighlighter.formatHours(24), "1d")
    }

    func testFormatHoursSmall() {
        XCTAssertEqual(SyntaxHighlighter.formatHours(5), "5h")
    }

    // MARK: - isSimple

    func testIsSimpleBool() {
        XCTAssertTrue(SyntaxHighlighter.isSimple(true))
        XCTAssertTrue(SyntaxHighlighter.isSimple(false))
    }

    func testIsSimpleNumber() {
        XCTAssertTrue(SyntaxHighlighter.isSimple(42 as NSNumber))
        XCTAssertTrue(SyntaxHighlighter.isSimple(3.14 as NSNumber))
    }

    func testIsSimpleShortString() {
        XCTAssertTrue(SyntaxHighlighter.isSimple("hello"))
    }

    func testIsSimpleLongString() {
        let long = String(repeating: "a", count: 121)
        XCTAssertFalse(SyntaxHighlighter.isSimple(long))
    }

    func testIsSimpleEmptyCollections() {
        XCTAssertTrue(SyntaxHighlighter.isSimple([Any]()))
        XCTAssertTrue(SyntaxHighlighter.isSimple([String: Any]()))
    }

    func testIsSimpleNonEmptyArray() {
        XCTAssertFalse(SyntaxHighlighter.isSimple(["item"]))
    }

    // MARK: - isLongString

    func testIsLongStringTrue() {
        let s = String(repeating: "x", count: 61)
        XCTAssertTrue(SyntaxHighlighter.isLongString(s))
    }

    func testIsLongStringFalse() {
        let s = String(repeating: "x", count: 59)
        XCTAssertFalse(SyntaxHighlighter.isLongString(s))
    }

    func testIsLongStringNonString() {
        XCTAssertFalse(SyntaxHighlighter.isLongString(42))
    }

    // MARK: - isTimeKey

    // MARK: - Negative input behavior (documents silent empty-string return)

    func testFormatDurationNegativeReturnsEmpty() {
        XCTAssertEqual(SyntaxHighlighter.formatDuration(seconds: -100), "")
    }

    func testFormatHoursNegativeReturnsEmpty() {
        XCTAssertEqual(SyntaxHighlighter.formatHours(-5), "")
    }

    // MARK: - Boundary tests

    func testIsSimpleBoundary119And120() {
        let at119 = String(repeating: "a", count: 119)
        XCTAssertTrue(SyntaxHighlighter.isSimple(at119), "119 chars should be simple (< 120)")
        let at120 = String(repeating: "a", count: 120)
        XCTAssertFalse(SyntaxHighlighter.isSimple(at120), "120 chars should NOT be simple (not < 120)")
    }

    func testIsSimpleNonEmptyDict() {
        let dict: [String: Any] = ["k": "v"]
        XCTAssertFalse(SyntaxHighlighter.isSimple(dict))
    }

    func testIsLongStringBoundary60() {
        let at60 = String(repeating: "x", count: 60)
        XCTAssertFalse(SyntaxHighlighter.isLongString(at60), "Exactly 60 chars should NOT be long (> 60)")
    }

    // MARK: - isTimeKey

    func testIsTimeKeyPositive() {
        XCTAssertTrue(SyntaxHighlighter.isTimeKey("gracePeriodDelay"))
        XCTAssertTrue(SyntaxHighlighter.isTimeKey("connectionTimeout"))
        XCTAssertTrue(SyntaxHighlighter.isTimeKey("refreshInterval"))
        XCTAssertTrue(SyntaxHighlighter.isTimeKey("cacheDuration"))
        XCTAssertTrue(SyntaxHighlighter.isTimeKey("expirationPeriod"))
    }

    func testIsTimeKeyNegative() {
        XCTAssertFalse(SyntaxHighlighter.isTimeKey("username"))
        XCTAssertFalse(SyntaxHighlighter.isTimeKey("SSID"))
        XCTAssertFalse(SyntaxHighlighter.isTimeKey("password"))
    }
}
