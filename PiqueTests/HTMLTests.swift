import XCTest
@testable import Pique

final class HTMLTests: XCTestCase {

    // MARK: - escapeHTML

    func testEscapeHTMLScriptTag() {
        XCTAssertEqual(SyntaxHighlighter.escapeHTML("<script>"), "&lt;script&gt;")
    }

    func testEscapeHTMLAllSpecialChars() {
        XCTAssertEqual(
            SyntaxHighlighter.escapeHTML("<div class=\"test\">&value</div>"),
            "&lt;div class=&quot;test&quot;&gt;&amp;value&lt;/div&gt;"
        )
    }

    func testEscapeHTMLPlainText() {
        let plain = "Hello World 123"
        XCTAssertEqual(SyntaxHighlighter.escapeHTML(plain), plain)
    }

    func testEscapeHTMLEmptyString() {
        XCTAssertEqual(SyntaxHighlighter.escapeHTML(""), "")
    }

    // MARK: - inlineMarkdown

    func testInlineMarkdownBold() {
        XCTAssertEqual(SyntaxHighlighter.inlineMarkdown("**bold**"), "<strong>bold</strong>")
    }

    func testInlineMarkdownItalic() {
        XCTAssertEqual(SyntaxHighlighter.inlineMarkdown("*italic*"), "<em>italic</em>")
    }

    func testInlineMarkdownCode() {
        XCTAssertEqual(SyntaxHighlighter.inlineMarkdown("`code`"), "<code>code</code>")
    }

    func testInlineMarkdownLink() {
        let result = SyntaxHighlighter.inlineMarkdown("[text](https://example.com)")
        XCTAssertEqual(result, "<a href=\"https://example.com\">text</a>")
    }

    func testInlineMarkdownMixed() {
        XCTAssertEqual(
            SyntaxHighlighter.inlineMarkdown("**bold** and *italic* and `code`"),
            "<strong>bold</strong> and <em>italic</em> and <code>code</code>"
        )
    }

    func testInlineMarkdownPlainTextUnchanged() {
        let plain = "just plain text"
        XCTAssertEqual(SyntaxHighlighter.inlineMarkdown(plain), plain)
    }

    func testInlineMarkdownUnderscoreBold() {
        XCTAssertEqual(SyntaxHighlighter.inlineMarkdown("__bold__"), "<strong>bold</strong>")
    }

    func testInlineMarkdownUnderscoreItalic() {
        XCTAssertEqual(SyntaxHighlighter.inlineMarkdown("_italic_"), "<em>italic</em>")
    }
}
