import XCTest
@testable import Pique

final class HighlightIntegrationTests: XCTestCase {

    /// Extract the inner HTML body from a full highlight() result, stripping
    /// the wrapping <!DOCTYPE>, <style>, etc. so assertions target token output only.
    private func body(_ html: String) -> String {
        guard let start = html.range(of: "<body>"),
              let end = html.range(of: "</body>") else { return html }
        return String(html[start.upperBound..<end.lowerBound])
    }

    /// Count occurrences of a substring
    private func count(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    // MARK: - JSON: exact token content

    func testJSONKeysGetCorrectSpans() {
        let html = body(SyntaxHighlighter.highlight(#"{"name": "val", "age": 30}"#, format: .json))
        XCTAssertTrue(html.contains(#"<span class="key">&quot;name&quot;</span>"#))
        XCTAssertTrue(html.contains(#"<span class="key">&quot;age&quot;</span>"#))
        XCTAssertEqual(count(of: #"class="key""#, in: html), 2, "Expected exactly 2 key spans")
    }

    func testJSONStringValueNotTaggedAsKey() {
        let html = body(SyntaxHighlighter.highlight(#"{"k": "v"}"#, format: .json))
        XCTAssertTrue(html.contains(#"<span class="string">&quot;v&quot;</span>"#))
        XCTAssertFalse(html.contains(#"<span class="key">&quot;v&quot;</span>"#))
    }

    func testJSONNumberAndBool() {
        let html = body(SyntaxHighlighter.highlight(#"{"n": 42, "b": true, "c": null}"#, format: .json))
        XCTAssertTrue(html.contains(#"<span class="number">42</span>"#))
        XCTAssertTrue(html.contains(#"<span class="bool">true</span>"#))
        XCTAssertTrue(html.contains(#"<span class="bool">null</span>"#))
    }

    func testJSONEscapedStringContent() {
        let html = body(SyntaxHighlighter.highlight(#"{"msg": "hello \"world\""}"#, format: .json))
        // Verify the escaped string is inside a string span (not just loose in the HTML)
        XCTAssertTrue(html.contains(#"<span class="string">"#), "Should contain a string span")
        // Extract string spans and verify one contains "hello"
        let stringSpanPattern = #"<span class="string">[^<]*hello[^<]*</span>"#
        let regex = try! NSRegularExpression(pattern: stringSpanPattern)
        let matches = regex.numberOfMatches(in: html, range: NSRange(html.startIndex..., in: html))
        XCTAssertGreaterThan(matches, 0, "Expected 'hello' inside a string span, got: \(html)")
    }

    func testJSONNestedKeysAllTagged() {
        let json = #"{"a": {"b": {"c": 1}}}"#
        let html = body(SyntaxHighlighter.highlight(json, format: .json))
        XCTAssertEqual(count(of: #"class="key""#, in: html), 3)
    }

    // MARK: - YAML: comments, keys, embedded SQL

    func testYAMLCommentAndKey() {
        let yaml = "# comment\nhost: localhost"
        let html = body(SyntaxHighlighter.highlight(yaml, format: .yaml))
        XCTAssertTrue(html.contains(#"<span class="comment"># comment</span>"#))
        XCTAssertTrue(html.contains(#"<span class="key">host</span>"#))
    }

    func testYAMLBoolVariants() {
        let yaml = "a: true\nb: false\nc: yes\nd: no"
        let html = body(SyntaxHighlighter.highlight(yaml, format: .yaml))
        for kw in ["true", "false", "yes", "no"] {
            XCTAssertTrue(html.contains("<span class=\"bool\">\(kw)</span>"), "Expected bool span for '\(kw)'")
        }
    }

    func testYAMLEmbeddedSQLKeywords() {
        let yaml = "query: SELECT name FROM users WHERE id = 1"
        let html = body(SyntaxHighlighter.highlight(yaml, format: .yaml))
        XCTAssertTrue(html.contains(#"<span class="keyword">SELECT</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">FROM</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">WHERE</span>"#))
    }

    // MARK: - Shell: variable vs keyword distinction

    func testShellVariablesAndKeywords() {
        let shell = "if [ -n \"$HOME\" ]; then\n  echo $PATH\nfi"
        let html = body(SyntaxHighlighter.highlight(shell, format: .shell))
        // $HOME is inside double quotes, so it's part of the string token
        XCTAssertTrue(html.contains(#"<span class="string">&quot;$HOME&quot;</span>"#))
        // $PATH is unquoted, so it's a standalone variable
        XCTAssertTrue(html.contains(#"<span class="variable">$PATH</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">if</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">then</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">fi</span>"#))
    }

    func testShellShebangIsComment() {
        let shell = "#!/bin/bash\necho hello"
        let html = body(SyntaxHighlighter.highlight(shell, format: .shell))
        XCTAssertTrue(html.contains(#"<span class="comment">#!/bin/bash</span>"#))
    }

    func testShellBraceVariable() {
        let shell = "echo ${USER}_home"
        let html = body(SyntaxHighlighter.highlight(shell, format: .shell))
        XCTAssertTrue(html.contains(#"<span class="variable">${USER}</span>"#))
    }

    // MARK: - Python: decorators, keywords, f-strings

    func testPythonDecoratorIsAttrName() {
        let py = "@property\ndef x(self): pass"
        let html = body(SyntaxHighlighter.highlight(py, format: .python))
        XCTAssertTrue(html.contains(#"<span class="attrName">@property</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">def</span>"#))
    }

    func testPythonTrueFalseNoneAreBool() {
        let py = "x = True\ny = False\nz = None"
        let html = body(SyntaxHighlighter.highlight(py, format: .python))
        XCTAssertTrue(html.contains(#"<span class="bool">True</span>"#))
        XCTAssertTrue(html.contains(#"<span class="bool">False</span>"#))
        XCTAssertTrue(html.contains(#"<span class="bool">None</span>"#))
    }

    func testPythonFStringIsString() {
        let py = #"msg = f"hello {name}""#
        let html = body(SyntaxHighlighter.highlight(py, format: .python))
        // Verify the f-string is rendered as a single string span with the f prefix intact
        XCTAssertTrue(html.contains(#"<span class="string">f&quot;hello {name}&quot;</span>"#),
                       "f-string should be a single string span with f prefix: \(html)")
    }

    // MARK: - JavaScript: template literals, keywords, bools

    func testJSTemplateLiteralIsString() {
        let js = "const x = `hello`"
        let html = body(SyntaxHighlighter.highlight(js, format: .javascript))
        XCTAssertTrue(html.contains(#"<span class="string">`hello`</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">const</span>"#))
    }

    func testJSUndefinedAndNullAreBool() {
        let js = "let a = null\nlet b = undefined"
        let html = body(SyntaxHighlighter.highlight(js, format: .javascript))
        XCTAssertTrue(html.contains(#"<span class="bool">null</span>"#))
        XCTAssertTrue(html.contains(#"<span class="bool">undefined</span>"#))
    }

    // MARK: - Rust / Go: type spans

    func testRustBoolAndKeyword() {
        let rs = "let x: bool = true;\nlet mut y = false;"
        let html = body(SyntaxHighlighter.highlight(rs, format: .rust))
        XCTAssertTrue(html.contains(#"<span class="bool">true</span>"#))
        XCTAssertTrue(html.contains(#"<span class="bool">false</span>"#))
        XCTAssertTrue(html.contains(#"<span class="keyword">let</span>"#))
    }

    func testGoTypesAreTagSpans() {
        let go = "var x int = 42\nvar s string"
        let html = body(SyntaxHighlighter.highlight(go, format: .go))
        XCTAssertTrue(html.contains(#"<span class="tag">int</span>"#))
        XCTAssertTrue(html.contains(#"<span class="tag">string</span>"#))
    }

    // MARK: - XML: tag structure, attributes

    func testXMLTagAndAttributeSpans() {
        let xml = #"<item name="test">val</item>"#
        let html = body(SyntaxHighlighter.highlight(xml, format: .xml))
        XCTAssertTrue(html.contains(#"<span class="tag">&lt;item</span>"#))
        XCTAssertTrue(html.contains(#"<span class="attrName">name</span>"#))
        XCTAssertTrue(html.contains(#"<span class="attrValue">&quot;test&quot;</span>"#))
        XCTAssertTrue(html.contains(#"<span class="tag">&lt;/item</span>"#))
    }

    func testXMLCommentSpan() {
        let xml = "<!-- todo --><root/>"
        let html = body(SyntaxHighlighter.highlight(xml, format: .xml))
        XCTAssertTrue(html.contains(#"<span class="comment">&lt;!-- todo --&gt;</span>"#))
    }

    func testXMLPlistKeyHighlighting() {
        let xml = "<key>PayloadIdentifier</key><string>com.example</string>"
        let html = body(SyntaxHighlighter.highlight(xml, format: .xml))
        XCTAssertTrue(html.contains(#"<span class="plistKey">PayloadIdentifier</span>"#))
        XCTAssertTrue(html.contains(#"<span class="plistValue">com.example</span>"#))
    }

    // MARK: - Markdown: block-level rendering

    func testMarkdownHeadingsAndCode() {
        let md = "# Title\n\nSome `inline` text\n\n> quote"
        let html = SyntaxHighlighter.highlight(md, format: .markdown)
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("Title"))
        XCTAssertTrue(html.contains("<code>inline</code>"))
        XCTAssertTrue(html.contains("<blockquote"))
    }

    func testMarkdownCodeBlock() {
        let md = "```\nlet x = 1\n```"
        let html = SyntaxHighlighter.highlight(md, format: .markdown)
        XCTAssertTrue(html.contains("<pre"))
        XCTAssertTrue(html.contains("let x = 1"))
        // Code inside fenced block should be escaped, not rendered as markdown
        XCTAssertFalse(html.contains("<h1"))
    }

    func testMarkdownH2H3AndOrderedList() {
        let md = "## Second\n\n### Third\n\n1. first\n2. second"
        let html = SyntaxHighlighter.highlight(md, format: .markdown)
        XCTAssertTrue(html.contains("<h2"), "Should render h2 for ##")
        XCTAssertTrue(html.contains("Second"))
        XCTAssertTrue(html.contains("<h3"), "Should render h3 for ###")
        XCTAssertTrue(html.contains("Third"))
        // Ordered list items are rendered as <p> tags (not <ol>), verify content is present
        XCTAssertTrue(html.contains("first"), "Should render ordered list item content")
        XCTAssertTrue(html.contains("second"), "Should render ordered list item content")
    }

    func testMarkdownHorizontalRule() {
        let md = "above\n\n---\n\nbelow"
        let html = SyntaxHighlighter.highlight(md, format: .markdown)
        XCTAssertTrue(html.contains("<hr"), "Should render horizontal rule for ---")
    }

    // MARK: - Profile rendering (two-fold view)

    func testJSONProfileDDMShowsSettingsAndSource() {
        let json = #"{"Type": "com.apple.configuration.passcode.settings", "Identifier": "test-id", "Payload": {"minLength": 6}}"#
        let html = SyntaxHighlighter.highlight(json, format: .json)
        XCTAssertTrue(html.contains("JSON SOURCE"), "Should have raw JSON section")
        XCTAssertTrue(html.contains("Passcode Settings") || html.contains("passcode"), "Should derive name from type")
        XCTAssertTrue(html.contains("minLength"), "Should render the setting key")
    }

    // MARK: - Dark mode applies different color scheme

    func testDarkModeUsesDistinctColors() {
        let json = #"{"k": "v"}"#
        let light = SyntaxHighlighter.highlight(json, format: .json, darkMode: false)
        let dark = SyntaxHighlighter.highlight(json, format: .json, darkMode: true)
        // Light uses #ffffff bg, dark uses #1c1c1e
        XCTAssertTrue(light.contains("#ffffff"))
        XCTAssertTrue(dark.contains("#1c1c1e"))
        XCTAssertFalse(light.contains("#1c1c1e"))
        XCTAssertFalse(dark.contains("#ffffff"))
    }

    // MARK: - Edge cases that break tokenizers

    func testJSONTrailingCommaDoesNotCrash() {
        // Invalid JSON but should not crash the tokenizer
        let json = #"{"a": 1, "b": 2,}"#
        let html = body(SyntaxHighlighter.highlight(json, format: .json))
        XCTAssertEqual(count(of: #"class="key""#, in: html), 2)
    }

    func testJSONEmptyInput() {
        let html = body(SyntaxHighlighter.highlight("", format: .json))
        // Should produce a valid page with no token spans
        XCTAssertEqual(count(of: #"class="#, in: html), 0)
    }

    func testShellUnclosedDoubleQuote() {
        // Unclosed string — tokenizer should not hang or crash
        let shell = "echo \"hello world"
        let html = body(SyntaxHighlighter.highlight(shell, format: .shell))
        XCTAssertTrue(html.contains("hello"))
    }

    func testYAMLMultilineValueDoesNotSwallowKeys() {
        let yaml = "first: value1\nsecond: value2\nthird: value3"
        let html = body(SyntaxHighlighter.highlight(yaml, format: .yaml))
        XCTAssertEqual(count(of: #"class="key""#, in: html), 3, "All three YAML keys should be tagged")
    }

    func testPowerShellCmdletAndVariable() {
        let ps = "$name = Get-Process\nWrite-Host $name"
        let html = body(SyntaxHighlighter.highlight(ps, format: .powershell))
        XCTAssertTrue(html.contains(#"<span class="variable">$name</span>"#))
        XCTAssertTrue(html.contains(#"<span class="command">Get-Process</span>"#))
        XCTAssertTrue(html.contains(#"<span class="command">Write-Host</span>"#))
    }

    func testTOMLTableHeaderAndKeyValue() {
        let toml = "[package]\nname = \"pique\"\nversion = \"0.1.0\""
        let html = body(SyntaxHighlighter.highlight(toml, format: .toml))
        XCTAssertTrue(html.contains(#"<span class="tag">[package]</span>"#))
        XCTAssertTrue(html.contains(#"<span class="key">name</span>"#))
        XCTAssertTrue(html.contains(#"<span class="string">&quot;pique&quot;</span>"#))
    }

    func testRubySymbolAndGlobalVar() {
        let rb = "$stdout.puts :hello"
        let html = body(SyntaxHighlighter.highlight(rb, format: .ruby))
        XCTAssertTrue(html.contains(#"<span class="variable">$stdout</span>"#))
        XCTAssertTrue(html.contains(#"<span class="attrName">:hello</span>"#))
    }

    // MARK: - HCL / Terraform

    func testHCLResourceBlock() {
        let hcl = #"resource "aws_instance" "web" {\n  ami = "abc-123"\n}"#
        let html = body(SyntaxHighlighter.highlight(hcl, format: .hcl))
        XCTAssertTrue(html.contains(#"<span class="keyword">resource</span>"#))
        XCTAssertTrue(html.contains(#"class="string""#))
    }

    func testHCLKeyValueAssignment() {
        let hcl = "instance_type = \"t3.micro\""
        let html = body(SyntaxHighlighter.highlight(hcl, format: .hcl))
        XCTAssertTrue(html.contains(#"<span class="key">instance_type</span>"#))
        XCTAssertTrue(html.contains(#"<span class="string">&quot;t3.micro&quot;</span>"#))
    }

    func testHCLComments() {
        let hcl = "# This is a comment\n// Another comment\n/* block */"
        let html = body(SyntaxHighlighter.highlight(hcl, format: .hcl))
        XCTAssertEqual(count(of: #"class="comment""#, in: html), 3)
    }

    func testHCLBoolAndNumber() {
        let hcl = "enabled = true\ncount = 3"
        let html = body(SyntaxHighlighter.highlight(hcl, format: .hcl))
        XCTAssertTrue(html.contains(#"<span class="bool">true</span>"#))
        XCTAssertTrue(html.contains(#"<span class="number">3</span>"#))
    }

    func testHCLInterpolation() {
        let hcl = #"name = "${var.prefix}-web""#
        let html = body(SyntaxHighlighter.highlight(hcl, format: .hcl))
        XCTAssertTrue(html.contains(#"class="string""#))
    }
}
