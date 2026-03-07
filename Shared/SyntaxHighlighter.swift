import Foundation

enum FileFormat {
    case json, yaml, toml, xml, mobileconfig, shell, powershell

    init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "json": self = .json
        case "yaml", "yml": self = .yaml
        case "toml": self = .toml
        case "xml": self = .xml
        case "mobileconfig", "plist": self = .mobileconfig
        case "sh", "bash", "zsh", "ksh", "dash": self = .shell
        case "ps1", "psm1", "psd1": self = .powershell
        default: return nil
        }
    }
}

enum SyntaxHighlighter {
    static func highlight(_ source: String, format: FileFormat, darkMode: Bool = false) -> String {
        if format == .mobileconfig, let data = source.data(using: .utf8) {
            if let html = renderMobileconfig(data, dark: darkMode) {
                return html
            }
        }
        let tokens: [Token]
        switch format {
        case .json: tokens = tokenizeJSON(source)
        case .yaml: tokens = tokenizeYAML(source)
        case .toml: tokens = tokenizeTOML(source)
        case .xml, .mobileconfig: tokens = tokenizeXML(source)
        case .shell: tokens = tokenizeShell(source)
        case .powershell: tokens = tokenizePowerShell(source)
        }
        return wrapHTML(renderTokens(tokens), dark: darkMode)
    }

    // MARK: - Mobileconfig Renderer

    private static let payloadMetaKeys: Set<String> = [
        "PayloadType", "PayloadVersion", "PayloadUUID", "PayloadIdentifier",
        "PayloadDisplayName", "PayloadDescription",
        "PayloadOrganization", "PayloadScope", "PayloadRemovalDisallowed",
        "PayloadEnabled"
    ]

    /// Extract effective settings, flattening ManagedClient.preferences nesting
    private static func extractSettings(_ payload: [String: Any]) -> [String: Any] {
        let type = payload["PayloadType"] as? String ?? ""
        if type == "com.apple.ManagedClient.preferences",
           let content = payload["PayloadContent"] as? [String: Any] {
            for (_, domainVal) in content {
                if let domain = domainVal as? [String: Any],
                   let forced = domain["Forced"] as? [[String: Any]],
                   let first = forced.first,
                   let mcx = first["mcx_preference_settings"] as? [String: Any] {
                    return mcx
                }
            }
            return content
        }
        return payload.filter { !payloadMetaKeys.contains($0.key) && $0.key != "PayloadContent" }
    }

    /// Check if a value is simple (renders inline) vs complex (needs its own block)
    private static func isSimple(_ value: Any) -> Bool {
        switch value {
        case is Bool, is NSNumber: return true
        case let s as String: return s.count < 120
        case let a as [Any]: return a.isEmpty
        case let d as [String: Any]: return d.isEmpty
        default: return true
        }
    }

    /// Check if a string value is "long" (should span full width)
    private static func isLongString(_ value: Any) -> Bool {
        if let s = value as? String { return s.count > 60 }
        return false
    }

    // MARK: - Mobileconfig Renderer (HIG-style inset grouped)

    private static let pad = 16

    private struct Theme {
        let bg: String        // page background
        let cell: String      // card/cell background
        let sep: String       // separator
        let text: String      // primary text
        let key: String       // key labels in settings
        let label: String     // section headers, subtitles
        let muted: String     // timestamps, identifiers
        let accent: String    // numbers, badges
        let boolYes: String
        let boolNo: String
        let scopeDevice: String
        let scopeUser: String

        // XML syntax colors
        let xmlKey: String
        let xmlString: String
        let xmlNumber: String
        let xmlBool: String
        let xmlComment: String
        let xmlTag: String
        let xmlAttrName: String
        let xmlAttrValue: String

        static let light = Theme(
            bg: "#f8fafc", cell: "#ffffff", sep: "#e2e8f0",
            text: "#0f172a", key: "#334155", label: "#64748b", muted: "#94a3b8",
            accent: "#6366f1", boolYes: "#059669", boolNo: "#dc2626",
            scopeDevice: "#ea580c", scopeUser: "#2563eb",
            xmlKey: "#0451a5", xmlString: "#c41a16", xmlNumber: "#1c00cf",
            xmlBool: "#0b4f79", xmlComment: "#94a3b8", xmlTag: "#9a3412",
            xmlAttrName: "#6366f1", xmlAttrValue: "#c41a16"
        )

        static let dark = Theme(
            bg: "#1c1c1e", cell: "#2c2c2e", sep: "#38383a",
            text: "#f5f5f7", key: "#d1d1d6", label: "#98989d", muted: "#636366",
            accent: "#bf5af2", boolYes: "#30d158", boolNo: "#ff453a",
            scopeDevice: "#ff9f0a", scopeUser: "#0a84ff",
            xmlKey: "#9cdcfe", xmlString: "#ce9178", xmlNumber: "#b5cea8",
            xmlBool: "#569cd6", xmlComment: "#6a9955", xmlTag: "#569cd6",
            xmlAttrName: "#c586c0", xmlAttrValue: "#ce9178"
        )
    }

    private static func renderMobileconfig(_ data: Data, dark: Bool) -> String? {
        guard let rawXML = String(data: data, encoding: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let t = dark ? Theme.dark : Theme.light
        var h = ""

        let displayName = plist["PayloadDisplayName"] as? String ?? "Untitled Profile"
        let identifier = plist["PayloadIdentifier"] as? String ?? ""
        let org = plist["PayloadOrganization"] as? String
        let desc = plist["PayloadDescription"] as? String
        let scope = plist["PayloadScope"] as? String
        let payloads = plist["PayloadContent"] as? [[String: Any]] ?? []
        let payloadTypes = payloads.compactMap { $0["PayloadType"] as? String }

        let scopeText: String
        let scopeColor: String
        switch scope {
        case "System": scopeText = "Device Profile"; scopeColor = t.scopeDevice
        case "User":   scopeText = "User Profile";   scopeColor = t.scopeUser
        default:       scopeText = "Profile";         scopeColor = t.muted
        }

        h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"\(t.cell)\"><tr><td style=\"padding: 20px \(pad)px 16px \(pad)px;\">"
        h += "<font color=\"\(scopeColor)\" size=\"1\"><b>\(scopeText.uppercased())</b></font><br>"
        h += "<font size=\"5\" face=\"-apple-system, Helvetica\" color=\"\(t.text)\"><b>\(esc(displayName))</b></font>"
        if let org = org { h += "<br><font size=\"2\" color=\"\(t.label)\">\(esc(org))</font>" }
        h += "<br><font size=\"1\" face=\"Menlo\" color=\"\(t.muted)\">\(esc(identifier))</font>"
        if let desc = desc, !desc.isEmpty {
            h += "<br><font size=\"2\" color=\"\(t.label)\">\(esc(desc))</font>"
        }

        if !payloadTypes.isEmpty {
            h += "<br><br>"
            for pt in payloadTypes {
                let short = pt.split(separator: ".").last.map(String.init) ?? pt
                h += "<font size=\"1\" face=\"Menlo\" color=\"\(t.accent)\"><b>\(esc(short))</b></font>"
                h += "<font color=\"\(t.muted)\"> &middot; </font>"
            }
        }

        h += "</td></tr></table>"

        // ── Payload Sections ──
        for (idx, payload) in payloads.enumerated() {
            let name = payload["PayloadDisplayName"] as? String
                ?? payload["PayloadType"] as? String ?? "Payload"
            let type = payload["PayloadType"] as? String ?? ""
            let payloadDesc = payload["PayloadDescription"] as? String

            h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">"
            h += "<tr><td colspan=\"2\" style=\"padding: 28px \(pad)px 0 \(pad)px;\">\(thinLine(t))</td></tr>"
            h += "<tr><td style=\"padding: 12px \(pad)px 4px \(pad)px;\">"
            h += "<font size=\"1\" color=\"\(t.muted)\"><b>PAYLOAD \(idx + 1)</b></font><br>"
            h += "<font size=\"3\" face=\"-apple-system, Helvetica\" color=\"\(t.text)\"><b>\(esc(name))</b></font>"
            if !type.isEmpty && type != name {
                h += "<br><font size=\"1\" face=\"Menlo\" color=\"\(t.muted)\">\(esc(type))</font>"
            }
            if let d = payloadDesc, !d.isEmpty {
                h += "<br><font size=\"2\" color=\"\(t.label)\">\(esc(d))</font>"
            }
            h += "</td></tr></table>"

            let settings = extractSettings(payload)
            guard !settings.isEmpty else { continue }

            let sorted = settings.keys.sorted()
            let simpleKeys = sorted.filter { isSimple(settings[$0]!) }
            let complexKeys = sorted.filter { !isSimple(settings[$0]!) }

            if !simpleKeys.isEmpty {
                h += groupStart(t)
                for (i, key) in simpleKeys.enumerated() {
                    h += cellRow(key, inlineValue(settings[key]!, key: key, t: t), t: t, last: i == simpleKeys.count - 1)
                }
                h += groupEnd()
            }

            for key in complexKeys {
                h += sectionHeader(key, t: t)
                h += renderComplexValue(settings[key]!, t: t)
            }
        }

        // ── XML Source ──
        h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">"
        h += "<tr><td style=\"padding: 28px \(pad)px 0 \(pad)px;\">\(thinLine(t))</td></tr>"
        h += "<tr><td style=\"padding: 8px \(pad)px 6px \(pad)px;\">"
        h += "<font size=\"1\" color=\"\(t.muted)\"><b>XML SOURCE</b></font>"
        h += "</td></tr></table>"

        h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(t.cell)\" style=\"padding: 12px \(pad)px;\">"
        let xmlTokens = tokenizeXML(rawXML)
        h += "<pre style=\"font: 11px/1.6 Menlo, monospace; margin: 0; white-space: pre-wrap; word-wrap: break-word; color: \(t.key);\">\(renderTokens(xmlTokens))</pre>"
        h += "</td></tr></table>"

        return wrapMobileconfigHTML(h, t: t)
    }

    // MARK: - HIG Table Building Blocks

    private static func sectionHeader(_ title: String, t: Theme) -> String {
        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 16px \(pad)px 6px \(pad)px;\">" +
        "<font size=\"1\" color=\"\(t.label)\"><b>\(esc(title).uppercased())</b></font>" +
        "</td></tr></table>"
    }

    private static func groupStart(_ t: Theme) -> String {
        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"\(t.cell)\">"
    }

    private static func groupEnd() -> String { "</table>" }

    /// 1px line spanning full width
    private static func thinLine(_ t: Theme) -> String {
        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(t.sep)\" style=\"font-size:1px; line-height:1px; height:1px;\">&nbsp;</td></tr></table>"
    }

    /// 1px separator row inside a table (inset from left)
    private static func thinSep(_ t: Theme) -> String {
        "<tr><td colspan=\"2\" style=\"padding: 0 0 0 \(pad)px;\">\(thinLine(t))</td></tr>"
    }

    private static func cellRow(_ key: String, _ value: String, t: Theme, last: Bool = false) -> String {
        var r = "<tr bgcolor=\"\(t.cell)\"><td valign=\"top\" style=\"padding: 9px \(pad)px; width: 38%;\">"
        r += "<font size=\"2\" color=\"\(t.key)\">\(esc(key))</font></td>"
        r += "<td valign=\"top\" style=\"padding: 9px \(pad)px;\">\(value)</td></tr>"
        if !last { r += thinSep(t) }
        return r
    }

    /// Keys whose integer values represent hours
    private static let hourKeys: Set<String> = [
        "gracePeriodInstallDelay", "gracePeriodLaunchDelay"
    ]

    /// Heuristic: does this key name suggest a time/duration value?
    private static func isTimeKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let timeWords = ["time", "cycle", "delay", "interval", "timeout", "duration", "period", "refresh", "expir"]
        return timeWords.contains { lower.contains($0) }
    }

    /// Format seconds into "Xd Xh Xm Xs"
    private static func formatDuration(seconds: Int) -> String {
        if seconds == 0 { return "0s" }
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 { parts.append("\(s)s") }
        return parts.joined(separator: " ")
    }

    /// Format hours into "Xd Xh"
    private static func formatHours(_ hours: Int) -> String {
        if hours == 0 { return "0h" }
        let d = hours / 24
        let h = hours % 24
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 { parts.append("\(h)h") }
        return parts.joined(separator: " ")
    }

    private static func inlineValue(_ value: Any, key: String? = nil, t: Theme = .light) -> String {
        switch value {
        case let bool as Bool:
            let color = bool ? t.boolYes : t.boolNo
            return "<font size=\"2\" color=\"\(color)\"><b>\(bool ? "Yes" : "No")</b></font>"
        case let num as NSNumber:
            var result = "<font size=\"2\" color=\"\(t.accent)\"><b>\(num)</b></font>"
            if let key = key, num.intValue > 0 {
                if hourKeys.contains(key) {
                    result += " <font size=\"1\" color=\"\(t.muted)\">(\(formatHours(num.intValue)))</font>"
                } else if isTimeKey(key) {
                    result += " <font size=\"1\" color=\"\(t.muted)\">(\(formatDuration(seconds: num.intValue)))</font>"
                }
            }
            return result
        case let str as String where str.isEmpty:
            return "<font size=\"2\" color=\"\(t.muted)\"><i>—</i></font>"
        case let str as String:
            return "<font size=\"2\" color=\"\(t.text)\">\(esc(str))</font>"
        default:
            return "<font size=\"2\" color=\"\(t.text)\">\(esc(String(describing: value)))</font>"
        }
    }

    private static func renderComplexValue(_ value: Any, t: Theme) -> String {
        var h = ""
        switch value {
        case let arr as [[String: Any]]:
            for (i, dict) in arr.enumerated() {
                let label = dict["_language"] as? String
                    ?? dict["identifier"] as? String
                    ?? dict["BundleIdentifier"] as? String
                    ?? dict["Identifier"] as? String
                    ?? dict["RuleValue"] as? String
                    ?? nil
                if let label = label {
                    h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 10px \(pad)px 4px \(pad)px;\">"
                    h += "<font size=\"1\" color=\"\(t.label)\">\(esc(label))</font>"
                    h += "</td></tr></table>"
                } else if arr.count > 1 {
                    h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 10px \(pad)px 4px \(pad)px;\">"
                    h += "<font size=\"1\" color=\"\(t.label)\">Item \(i + 1)</font>"
                    h += "</td></tr></table>"
                }
                h += groupStart(t)
                let keys = dict.keys.sorted()
                for (j, key) in keys.enumerated() {
                    let val = dict[key]!
                    let isLast = j == keys.count - 1
                    if isSimple(val) && !isLongString(val) {
                        h += cellRow(key, inlineValue(val, key: key, t: t), t: t, last: isLast)
                    } else if isLongString(val) {
                        h += "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" style=\"padding: 9px \(pad)px 3px \(pad)px;\">"
                        h += "<font size=\"2\" color=\"\(t.key)\">\(esc(key))</font></td></tr>"
                        h += "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" style=\"padding: 0 \(pad)px 9px \(pad)px;\">"
                        h += "<font size=\"1\" face=\"Menlo\" color=\"\(t.label)\">\(esc(val as! String))</font></td></tr>"
                        if !isLast { h += thinSep(t) }
                    } else {
                        h += "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" valign=\"top\" style=\"padding: 9px \(pad)px 3px \(pad)px;\">"
                        h += "<font size=\"2\" color=\"\(t.key)\">\(esc(key))</font></td></tr>"
                        h += "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" style=\"padding: 0 \(pad)px 9px \(pad + 8)px;\">"
                        h += renderNestedBlock(val, t: t)
                        h += "</td></tr>"
                        if !isLast { h += thinSep(t) }
                    }
                }
                h += groupEnd()
            }

        case let arr as [Any]:
            h += groupStart(t)
            for (i, item) in arr.enumerated() {
                h += cellRow("[\(i)]", inlineValue(item, t: t), t: t, last: i == arr.count - 1)
            }
            h += groupEnd()

        case let dict as [String: Any]:
            let keys = dict.keys.sorted()
            let simpleK = keys.filter { isSimple(dict[$0]!) }
            let complexK = keys.filter { !isSimple(dict[$0]!) }

            if !simpleK.isEmpty {
                h += groupStart(t)
                for (i, key) in simpleK.enumerated() {
                    h += cellRow(key, inlineValue(dict[key]!, key: key, t: t), t: t, last: i == simpleK.count - 1)
                }
                h += groupEnd()
            }
            for key in complexK {
                h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 12px \(pad)px 4px \(pad)px;\">"
                h += "<font size=\"1\" color=\"\(t.label)\"><b>\(esc(key).uppercased())</b></font>"
                h += "</td></tr></table>"
                h += renderComplexValue(dict[key]!, t: t)
            }

        default:
            h += groupStart(t)
            h += "<tr><td style=\"padding: 10px \(pad)px;\">\(inlineValue(value, t: t))</td></tr>"
            h += groupEnd()
        }
        return h
    }

    private static func renderNestedBlock(_ value: Any, t: Theme) -> String {
        switch value {
        case let arr as [[String: Any]]:
            var h = ""
            for (i, dict) in arr.enumerated() {
                if i > 0 { h += "<br>" }
                let label = dict["identifier"] as? String ?? dict["Identifier"] as? String
                if let label = label {
                    h += "<font size=\"1\" color=\"\(t.label)\">\(esc(label))</font><br>"
                }
                for key in dict.keys.sorted() {
                    h += "<font size=\"1\" face=\"Menlo\" color=\"\(t.muted)\">\(esc(key))</font> "
                    h += inlineValue(dict[key]!, t: t)
                    h += "<br>"
                }
            }
            return h
        case let arr as [Any]:
            return arr.map { inlineValue($0, t: t) }.joined(separator: ", ")
        case let dict as [String: Any]:
            var h = ""
            for key in dict.keys.sorted() {
                h += "<font size=\"1\" face=\"Menlo\" color=\"\(t.muted)\">\(esc(key))</font> "
                if isSimple(dict[key]!) {
                    h += inlineValue(dict[key]!, t: t)
                } else {
                    h += renderNestedBlock(dict[key]!, t: t)
                }
                h += "<br>"
            }
            return h
        default:
            return inlineValue(value, t: t)
        }
    }

    /// Short alias for escapeHTML
    private static func esc(_ s: String) -> String { escapeHTML(s) }

    private static func wrapMobileconfigHTML(_ body: String, t: Theme) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
        body {
            font: 13px/1.5 -apple-system, Helvetica, sans-serif;
            margin: 0; padding: 0;
            background: \(t.bg); color: \(t.text);
        }
        pre { margin: 0; }
        table { border-collapse: collapse; }
        .key       { color: \(t.xmlKey); }
        .string    { color: \(t.xmlString); }
        .number    { color: \(t.xmlNumber); }
        .bool      { color: \(t.xmlBool); }
        .comment   { color: \(t.xmlComment); font-style: italic; }
        .tag       { color: \(t.xmlTag); }
        .attrName  { color: \(t.xmlAttrName); }
        .attrValue { color: \(t.xmlString); }
        .plistKey  { color: \(t.xmlKey); font-weight: bold; }
        .plistValue { color: \(t.xmlString); font-weight: bold; }
        .variable  { color: \(t.xmlTag); }
        .keyword   { color: \(t.xmlBool); }
        .operator  { color: \(t.xmlComment); }
        .command   { color: \(t.xmlAttrName); }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    // MARK: - Token

    private struct Token {
        enum Kind: String {
            case plain, key, string, number, bool, comment, tag, attrName, attrValue, punctuation, plistKey, plistValue, variable, keyword, `operator`, command
        }
        let text: String
        let kind: Kind
    }

    // MARK: - JSON Tokenizer

    private static func tokenizeJSON(_ src: String) -> [Token] {
        let regex = try! Regex(#"("(?:[^"\\]|\\.)*")\s*(:)|("(?:[^"\\]|\\.)*")|\b(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b|\b(true|false|null)\b"#)
        return tokenize(src, regex: regex) { match in
            if let key = match[1], match[2] != nil {
                return [Token(text: key, kind: .key), Token(text: ":", kind: .punctuation)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let num = match[4] {
                return [Token(text: num, kind: .number)]
            } else if let b = match[5] {
                return [Token(text: b, kind: .bool)]
            }
            return nil
        }
    }

    // MARK: - YAML Tokenizer

    private static func tokenizeYAML(_ src: String) -> [Token] {
        let regex = try! Regex(#"(?m)(#.*)$|^([\t ]*(?:- )?[A-Za-z_][\w.\-/]*)\s*(:)|("(?:[^"\\]|\\.)*"|'[^']*')|\b(true|false|yes|no|null|~)\b|\b(-?\d+(?:\.\d+)?)\b"#)
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let key = match[2], match[3] != nil {
                return [Token(text: key, kind: .key), Token(text: ":", kind: .punctuation)]
            } else if let str = match[4] {
                return [Token(text: str, kind: .string)]
            } else if let b = match[5] {
                return [Token(text: b, kind: .bool)]
            } else if let num = match[6] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - TOML Tokenizer

    private static func tokenizeTOML(_ src: String) -> [Token] {
        let regex = try! Regex(#"(?m)(#.*)$|(\[{1,2}[^\]]*\]{1,2})|^([\t ]*[A-Za-z_][\w.\-]*)\s*(=)|("(?:[^"\\]|\\.)*"|'[^']*'|"""[\s\S]*?"""|'''[\s\S]*?''')|\b(true|false)\b|\b(\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2})?)\b|\b(-?\d+(?:\.\d+)?)\b"#)
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let header = match[2] {
                return [Token(text: header, kind: .tag)]
            } else if let key = match[3], match[4] != nil {
                return [Token(text: key, kind: .key), Token(text: "=", kind: .punctuation)]
            } else if let str = match[5] {
                return [Token(text: str, kind: .string)]
            } else if let b = match[6] {
                return [Token(text: b, kind: .bool)]
            } else if let date = match[7] {
                return [Token(text: date, kind: .attrValue)]
            } else if let num = match[8] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - Shell Tokenizer

    private static func tokenizeShell(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(?m)(#!\/[^\n]*)"# +                   // 1: shebang
            #"|(#[^\n]*)"# +                          // 2: comment
            #"|('(?:[^'\\]|\\.)*')"# +                // 3: single-quoted string
            #"|("(?:[^"\\]|\\.)*")"# +                // 4: double-quoted string
            #"|(`[^`]*`)"# +                          // 5: backtick string
            #"|(\$\{[^}]*\}|\$[A-Za-z_]\w*|\$[0-9@?#!$*\-])"# + // 6: variable
            #"|\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|local|export|source|in|select|until)\b"# + // 7: keyword
            #"|(\|\||&&|>>|>&|<<|<|>|;|\|)"# +       // 8: operator
            #"|\b(-?\d+(?:\.\d+)?)\b"#                // 9: number
        )
        return tokenize(src, regex: regex) { match in
            if let shebang = match[1] {
                return [Token(text: shebang, kind: .comment)]
            } else if let comment = match[2] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let str = match[4] {
                return [Token(text: str, kind: .string)]
            } else if let str = match[5] {
                return [Token(text: str, kind: .string)]
            } else if let v = match[6] {
                return [Token(text: v, kind: .variable)]
            } else if let kw = match[7] {
                return [Token(text: kw, kind: .keyword)]
            } else if let op = match[8] {
                return [Token(text: op, kind: .operator)]
            } else if let num = match[9] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - PowerShell Tokenizer

    private static func tokenizePowerShell(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(<#[\s\S]*?#>)"# +                     // 1: block comment
            #"|(?m)(#[^\n]*)"# +                      // 2: line comment
            #"|('(?:[^'\\]|\\.)*')"# +                // 3: single-quoted string
            #"|("(?:[^"\\]|\\.)*")"# +                // 4: double-quoted string
            #"|(\$env:[A-Za-z_]\w*|\$\{[^}]*\}|\$[A-Za-z_]\w*)"# + // 5: variable
            #"|\b(if|else|elseif|foreach|for|while|do|switch|function|param|return|try|catch|finally|throw|begin|process|end)\b"# + // 6: keyword
            #"|([A-Z][a-z]+-[A-Z]\w*)"# +             // 7: cmdlet (Verb-Noun)
            #"|(-(?:eq|ne|gt|lt|ge|le|match|like|notmatch|notlike|contains|in|notin|replace|split|join|is|isnot|as|band|bor|bnot|bxor|shl|shr|and|or|not))\b"# + // 8: operator
            #"|(\|\||&&|;|\|)"# +                     // 9: pipe/logical operator
            #"|\b(-?\d+(?:\.\d+)?)\b"#                // 10: number
        )
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let comment = match[2] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let str = match[4] {
                return [Token(text: str, kind: .string)]
            } else if let v = match[5] {
                return [Token(text: v, kind: .variable)]
            } else if let kw = match[6] {
                return [Token(text: kw, kind: .keyword)]
            } else if let cmd = match[7] {
                return [Token(text: cmd, kind: .command)]
            } else if let op = match[8] {
                return [Token(text: op, kind: .operator)]
            } else if let op = match[9] {
                return [Token(text: op, kind: .operator)]
            } else if let num = match[10] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - XML Tokenizer

    private static func tokenizeXML(_ src: String) -> [Token] {
        // Match Payload key+value pairs, then general XML
        let mainRegex = try! Regex(
            #"(<!--[\s\S]*?-->)"# +        // 1: comment
            #"|(<!\[CDATA\[[\s\S]*?\]\]>)"# + // 2: CDATA
            #"|(<key>)(Payload\w+)(</key>\s*)(<(?:string|integer)>)([^<]*)(</(?:string|integer)>)"# + // 3-8: Payload key + value
            #"|(<key>)(Payload\w+)(</key>)"# + // 9-11: Payload key without simple value
            #"|(<\/?[A-Za-z_][\w:\-.]*)(\s[^>]*)?(\/?>)"# + // 12-14: general tag
            #"|("[^"]*"|'[^']*')"#          // 15: quoted string
        ).dotMatchesNewlines()
        return tokenize(src, regex: mainRegex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let cdata = match[2] {
                return [Token(text: cdata, kind: .string)]
            } else if let open = match[3], let keyText = match[4], let mid = match[5],
                      let valOpen = match[6], let valText = match[7], let valClose = match[8] {
                // <key>PayloadIdentifier</key>\n<string>value</string> → both bold
                return [
                    Token(text: open, kind: .tag),
                    Token(text: keyText, kind: .plistKey),
                    Token(text: mid, kind: .tag),
                    Token(text: valOpen, kind: .tag),
                    Token(text: valText, kind: .plistValue),
                    Token(text: valClose, kind: .tag),
                ]
            } else if let open = match[9], let keyText = match[10], let close = match[11] {
                // <key>PayloadContent</key> (followed by array/dict, not simple value)
                return [
                    Token(text: open, kind: .tag),
                    Token(text: keyText, kind: .plistKey),
                    Token(text: close, kind: .tag),
                ]
            } else if let tagName = match[12] {
                var result = [Token(text: tagName, kind: .tag)]
                if let attrs = match[13] {
                    result.append(contentsOf: tokenizeXMLAttributes(attrs))
                }
                if let close = match[14] {
                    result.append(Token(text: close, kind: .tag))
                }
                return result
            } else if let str = match[15] {
                return [Token(text: str, kind: .attrValue)]
            }
            return nil
        }
    }

    private static func tokenizeXMLAttributes(_ attrs: String) -> [Token] {
        let regex = try! Regex(#"([A-Za-z_][\w:\-.]*)(\s*=\s*)("[^"]*"|'[^']*')"#)
        return tokenize(attrs, regex: regex) { match in
            if let name = match[1], let eq = match[2], let value = match[3] {
                return [
                    Token(text: name, kind: .attrName),
                    Token(text: eq, kind: .plain),
                    Token(text: value, kind: .attrValue),
                ]
            }
            return nil
        }
    }

    // MARK: - Regex Engine

    private static func tokenize(
        _ src: String,
        regex: Regex<AnyRegexOutput>,
        handler: (MatchResult) -> [Token]?
    ) -> [Token] {
        var tokens: [Token] = []
        var searchStart = src.startIndex

        while let match = try? regex.firstMatch(in: src[searchStart...]) {
            if match.range.lowerBound > searchStart {
                tokens.append(Token(text: String(src[searchStart..<match.range.lowerBound]), kind: .plain))
            }

            let result = MatchResult(match: match)
            if let produced = handler(result) {
                tokens.append(contentsOf: produced)
            } else {
                tokens.append(Token(text: String(src[match.range]), kind: .plain))
            }
            searchStart = match.range.upperBound
        }

        if searchStart < src.endIndex {
            tokens.append(Token(text: String(src[searchStart...]), kind: .plain))
        }

        return tokens
    }

    private struct MatchResult {
        let match: Regex<AnyRegexOutput>.Match

        subscript(index: Int) -> String? {
            guard index < match.output.count else { return nil }
            guard let substring = match.output[index].substring else { return nil }
            return String(substring)
        }
    }

    // MARK: - HTML Rendering

    private static func renderTokens(_ tokens: [Token]) -> String {
        tokens.map { token in
            let escaped = escapeHTML(token.text)
            switch token.kind {
            case .plain, .punctuation:
                return escaped
            default:
                return "<span class=\"\(token.kind.rawValue)\">\(escaped)</span>"
            }
        }.joined()
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func wrapHTML(_ body: String, dark: Bool) -> String {
        let bg = dark ? "#1c1c1e" : "#ffffff"
        let fg = dark ? "#f5f5f7" : "#1d1d1f"
        let colors: String
        if dark {
            colors = """
            .key       { color: #9cdcfe; }
            .string    { color: #ce9178; }
            .number    { color: #b5cea8; }
            .bool      { color: #569cd6; }
            .comment   { color: #6a9955; font-style: italic; }
            .tag       { color: #569cd6; }
            .attrName  { color: #c586c0; }
            .attrValue { color: #ce9178; }
            .plistKey  { color: #9cdcfe; font-weight: bold; }
            .plistValue { color: #ce9178; font-weight: bold; }
            .variable  { color: #d19a66; }
            .keyword   { color: #c586c0; }
            .operator  { color: #abb2bf; }
            .command   { color: #61afef; }
            """
        } else {
            colors = """
            .key       { color: #0451a5; }
            .string    { color: #a31515; }
            .number    { color: #098658; }
            .bool      { color: #0000ff; }
            .comment   { color: #6a9955; font-style: italic; }
            .tag       { color: #800000; }
            .attrName  { color: #e50000; }
            .attrValue { color: #0451a5; }
            .plistKey  { color: #0451a5; font-weight: bold; }
            .plistValue { color: #a31515; font-weight: bold; }
            .variable  { color: #e06c20; }
            .keyword   { color: #af00db; }
            .operator  { color: #383a42; }
            .command   { color: #4078f2; }
            """
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body {
            font: 13px/1.5 ui-monospace, "SF Mono", Menlo, monospace;
            margin: 0;
            padding: 16px 20px;
            background: \(bg);
            color: \(fg);
        }
        pre {
            margin: 0;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        \(colors)
        </style>
        </head>
        <body><pre>\(body)</pre></body>
        </html>
        """
    }
}
