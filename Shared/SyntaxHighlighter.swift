//  SyntaxHighlighter.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import Foundation

enum FileFormat {
    case json, yaml, toml, xml, mobileconfig, shell, powershell, python, ruby, go, rust, javascript,
        markdown, hcl

    init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "json", "ndjson", "jsonl": self = .json
        case "yaml", "yml": self = .yaml
        case "toml", "lock": self = .toml
        case "xml", "recipe": self = .xml
        case "mobileconfig", "plist": self = .mobileconfig
        case "sh", "bash", "zsh", "ksh", "dash", "rc", "command": self = .shell
        case "ps1", "psm1", "psd1": self = .powershell
        case "py", "pyw", "pyi": self = .python
        case "rb", "gemspec", "rakefile": self = .ruby
        case "go": self = .go
        case "rs": self = .rust
        case "js", "jsx", "ts", "tsx", "mjs", "cjs": self = .javascript
        case "md", "markdown", "adoc": self = .markdown
        case "tf", "tfvars", "hcl": self = .hcl
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
        if format == .json, let data = source.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            isAppleConfigProfile(json)
        {
            if let html = renderJSONProfile(json, rawJSON: source, dark: darkMode) {
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
        case .python: tokens = tokenizePython(source)
        case .ruby: tokens = tokenizeRuby(source)
        case .go: tokens = tokenizeGo(source)
        case .rust: tokens = tokenizeRust(source)
        case .javascript: tokens = tokenizeJavaScript(source)
        case .markdown: return renderMarkdown(source, dark: darkMode)
        case .hcl: tokens = tokenizeHCL(source)
        }
        return wrapHTML(renderTokens(tokens), dark: darkMode)
    }

    // MARK: - Mobileconfig Renderer

    private static let payloadMetaKeys: Set<String> = [
        "PayloadType", "PayloadVersion", "PayloadUUID", "PayloadIdentifier",
        "PayloadDisplayName", "PayloadDescription",
        "PayloadOrganization", "PayloadScope", "PayloadRemovalDisallowed",
        "PayloadEnabled",
    ]

    /// Keys used as metadata in DDM declarations
    private static let ddmMetaKeys: Set<String> = [
        "Type", "Identifier",
    ]

    /// Extract effective settings, flattening ManagedClient.preferences nesting
    /// and handling DDM declaration "Payload" key
    static func extractSettings(_ payload: [String: Any]) -> [String: Any] {
        // DDM declaration: settings live under "Payload"
        if payload["Type"] as? String != nil,
            let ddmPayload = payload["Payload"] as? [String: Any]
        {
            return ddmPayload
        }
        let type = payload["PayloadType"] as? String ?? ""
        if type == "com.apple.ManagedClient.preferences",
            let content = payload["PayloadContent"] as? [String: Any]
        {
            for (_, domainVal) in content {
                if let domain = domainVal as? [String: Any],
                    let forced = domain["Forced"] as? [[String: Any]],
                    let first = forced.first,
                    let mcx = first["mcx_preference_settings"] as? [String: Any]
                {
                    return mcx
                }
            }
            return content
        }
        return payload.filter {
            !payloadMetaKeys.contains($0.key) && !ddmMetaKeys.contains($0.key)
                && $0.key != "PayloadContent" && $0.key != "Payload"
        }
    }

    /// Check if a value is simple (renders inline) vs complex (needs its own block)
    static func isSimple(_ value: Any) -> Bool {
        switch value {
        case is Bool, is NSNumber: return true
        case let s as String: return s.count < 120
        case let a as [Any]: return a.isEmpty
        case let d as [String: Any]: return d.isEmpty
        default: return true
        }
    }

    /// Check if a string value is "long" (should span full width)
    static func isLongString(_ value: Any) -> Bool {
        if let s = value as? String { return s.count > 60 }
        return false
    }

    // MARK: - Mobileconfig Renderer (HIG-style inset grouped)

    private static let pad = 16

    private struct Theme {
        let bg: String  // page background
        let cell: String  // card/cell background
        let sep: String  // separator
        let text: String  // primary text
        let key: String  // key labels in settings
        let label: String  // section headers, subtitles
        let muted: String  // timestamps, identifiers
        let accent: String  // numbers, badges
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
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else {
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
        case "System":
            scopeText = "Device Profile"
            scopeColor = t.scopeDevice
        case "User":
            scopeText = "User Profile"
            scopeColor = t.scopeUser
        default:
            scopeText = "Profile"
            scopeColor = t.muted
        }

        h +=
            "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"\(t.cell)\"><tr><td style=\"padding: 20px \(pad)px 16px \(pad)px;\">"
        h += "<font color=\"\(scopeColor)\" size=\"1\"><b>\(scopeText.uppercased())</b></font><br>"
        h +=
            "<font size=\"5\" face=\"-apple-system, Helvetica\" color=\"\(t.text)\"><b>\(esc(displayName))</b></font>"
        if let org = org { h += "<br><font size=\"2\" color=\"\(t.label)\">\(esc(org))</font>" }
        h += "<br><font size=\"1\" face=\"Menlo\" color=\"\(t.muted)\">\(esc(identifier))</font>"
        if let desc = desc, !desc.isEmpty {
            h += "<br><font size=\"2\" color=\"\(t.label)\">\(esc(desc))</font>"
        }

        if !payloadTypes.isEmpty {
            h += "<br><br>"
            for pt in payloadTypes {
                let short = pt.split(separator: ".").last.map(String.init) ?? pt
                h +=
                    "<font size=\"1\" face=\"Menlo\" color=\"\(t.accent)\"><b>\(esc(short))</b></font>"
                h += "<font color=\"\(t.muted)\"> &middot; </font>"
            }
        }

        h += "</td></tr></table>"

        // ── Payload Sections ──
        for (idx, payload) in payloads.enumerated() {
            let name =
                payload["PayloadDisplayName"] as? String
                ?? payload["PayloadType"] as? String ?? "Payload"
            let type = payload["PayloadType"] as? String ?? ""
            let payloadDesc = payload["PayloadDescription"] as? String

            h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">"
            h +=
                "<tr><td colspan=\"2\" style=\"padding: 28px \(pad)px 0 \(pad)px;\">\(thinLine(t))</td></tr>"
            h += "<tr><td style=\"padding: 12px \(pad)px 4px \(pad)px;\">"
            h += "<font size=\"1\" color=\"\(t.muted)\"><b>PAYLOAD \(idx + 1)</b></font><br>"
            h +=
                "<font size=\"3\" face=\"-apple-system, Helvetica\" color=\"\(t.text)\"><b>\(esc(name))</b></font>"
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
                    h += cellRow(
                        key, inlineValue(settings[key]!, key: key, t: t), t: t,
                        last: i == simpleKeys.count - 1)
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

        h +=
            "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(t.cell)\" style=\"padding: 12px \(pad)px;\">"
        let xmlTokens = tokenizeXML(rawXML)
        h +=
            "<pre style=\"font: 11px/1.6 Menlo, monospace; margin: 0; white-space: pre-wrap; word-wrap: break-word; color: \(t.key);\">\(renderTokens(xmlTokens))</pre>"
        h += "</td></tr></table>"

        return wrapMobileconfigHTML(h, t: t)
    }

    // MARK: - JSON Profile Detection & Renderer

    /// Check if a JSON dictionary looks like an Apple configuration profile
    static func isAppleConfigProfile(_ json: [String: Any]) -> Bool {
        // Top-level "Type": "com.apple.*"
        if let type = json["Type"] as? String, type.hasPrefix("com.apple.") {
            return true
        }
        // Has PayloadContent with PayloadType "com.apple.*"
        if let payloads = json["PayloadContent"] as? [[String: Any]] {
            return payloads.contains { payload in
                if let type = payload["PayloadType"] as? String, type.hasPrefix("com.apple.") {
                    return true
                }
                if let type = payload["Type"] as? String, type.hasPrefix("com.apple.") {
                    return true
                }
                return false
            }
        }
        return false
    }

    /// Render a JSON-based Apple config profile with the HIG two-fold view
    private static func renderJSONProfile(_ json: [String: Any], rawJSON: String, dark: Bool)
        -> String?
    {
        let t = dark ? Theme.dark : Theme.light
        var h = ""

        let topType = json["Type"] as? String
        let isDDM = topType != nil

        // Derive a friendly display name from the Type (e.g. "com.apple.configuration.passcode.settings" → "Passcode Settings")
        let derivedName: String = {
            guard let type = topType else { return "Untitled Profile" }
            let parts = type.split(separator: ".")
            // Drop common prefixes: com, apple, configuration
            let meaningful = parts.drop {
                ["com", "apple", "configuration"].contains($0.lowercased())
            }
            if meaningful.isEmpty { return type }
            return meaningful.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(
                separator: " ")
        }()

        let displayName =
            json["PayloadDisplayName"] as? String
            ?? json["DisplayName"] as? String
            ?? derivedName
        let identifier =
            json["PayloadIdentifier"] as? String
            ?? json["Identifier"] as? String ?? ""
        let org = json["PayloadOrganization"] as? String
        let desc = json["PayloadDescription"] as? String
        let scope = json["PayloadScope"] as? String

        // Determine payloads — either PayloadContent array or the top-level dict itself
        let payloads: [[String: Any]]
        if let content = json["PayloadContent"] as? [[String: Any]] {
            payloads = content
        } else if isDDM {
            payloads = [json]
        } else {
            payloads = []
        }

        let payloadTypes = payloads.compactMap {
            $0["PayloadType"] as? String ?? $0["Type"] as? String
        }

        let scopeText: String
        let scopeColor: String
        if isDDM {
            scopeText = "Declaration"
            scopeColor = t.accent
        } else {
            switch scope {
            case "System":
                scopeText = "Device Profile"
                scopeColor = t.scopeDevice
            case "User":
                scopeText = "User Profile"
                scopeColor = t.scopeUser
            default:
                scopeText = "JSON Profile"
                scopeColor = t.accent
            }
        }

        // Header
        h +=
            "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"\(t.cell)\"><tr><td style=\"padding: 20px \(pad)px 16px \(pad)px;\">"
        h += "<font color=\"\(scopeColor)\" size=\"1\"><b>\(scopeText.uppercased())</b></font><br>"
        h +=
            "<font size=\"5\" face=\"-apple-system, Helvetica\" color=\"\(t.text)\"><b>\(esc(displayName))</b></font>"
        if let org = org { h += "<br><font size=\"2\" color=\"\(t.label)\">\(esc(org))</font>" }
        if !identifier.isEmpty {
            h +=
                "<br><font size=\"1\" face=\"Menlo\" color=\"\(t.muted)\">\(esc(identifier))</font>"
        }
        if let desc = desc, !desc.isEmpty {
            h += "<br><font size=\"2\" color=\"\(t.label)\">\(esc(desc))</font>"
        }

        if !payloadTypes.isEmpty {
            h += "<br><br>"
            for pt in payloadTypes {
                let short = pt.split(separator: ".").last.map(String.init) ?? pt
                h +=
                    "<font size=\"1\" face=\"Menlo\" color=\"\(t.accent)\"><b>\(esc(short))</b></font>"
                h += "<font color=\"\(t.muted)\"> &middot; </font>"
            }
        }

        h += "</td></tr></table>"

        // Payload sections
        for (idx, payload) in payloads.enumerated() {
            let name =
                payload["PayloadDisplayName"] as? String
                ?? payload["DisplayName"] as? String
                ?? payload["PayloadType"] as? String
                ?? payload["Type"] as? String ?? "Payload"
            let type =
                payload["PayloadType"] as? String
                ?? payload["Type"] as? String ?? ""
            let payloadDesc = payload["PayloadDescription"] as? String

            let sectionLabel = isDDM ? "SETTINGS" : "PAYLOAD \(idx + 1)"

            h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">"
            h +=
                "<tr><td colspan=\"2\" style=\"padding: 28px \(pad)px 0 \(pad)px;\">\(thinLine(t))</td></tr>"
            h += "<tr><td style=\"padding: 12px \(pad)px 4px \(pad)px;\">"
            h += "<font size=\"1\" color=\"\(t.muted)\"><b>\(sectionLabel)</b></font><br>"
            h +=
                "<font size=\"3\" face=\"-apple-system, Helvetica\" color=\"\(t.text)\"><b>\(esc(name))</b></font>"
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
                    h += cellRow(
                        key, inlineValue(settings[key]!, key: key, t: t), t: t,
                        last: i == simpleKeys.count - 1)
                }
                h += groupEnd()
            }

            for key in complexKeys {
                h += sectionHeader(key, t: t)
                h += renderComplexValue(settings[key]!, t: t)
            }
        }

        // JSON Source
        h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">"
        h += "<tr><td style=\"padding: 28px \(pad)px 0 \(pad)px;\">\(thinLine(t))</td></tr>"
        h += "<tr><td style=\"padding: 8px \(pad)px 6px \(pad)px;\">"
        h += "<font size=\"1\" color=\"\(t.muted)\"><b>JSON SOURCE</b></font>"
        h += "</td></tr></table>"

        h +=
            "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(t.cell)\" style=\"padding: 12px \(pad)px;\">"
        let jsonTokens = tokenizeJSON(rawJSON)
        h +=
            "<pre style=\"font: 11px/1.6 Menlo, monospace; margin: 0; white-space: pre-wrap; word-wrap: break-word; color: \(t.key);\">\(renderTokens(jsonTokens))</pre>"
        h += "</td></tr></table>"

        return wrapMobileconfigHTML(h, t: t)
    }

    // MARK: - HIG Table Building Blocks

    private static func sectionHeader(_ title: String, t: Theme) -> String {
        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 16px \(pad)px 6px \(pad)px;\">"
            + "<font size=\"1\" color=\"\(t.label)\"><b>\(esc(title).uppercased())</b></font>"
            + "</td></tr></table>"
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

    private static func cellRow(_ key: String, _ value: String, t: Theme, last: Bool = false)
        -> String
    {
        var r =
            "<tr bgcolor=\"\(t.cell)\"><td valign=\"top\" style=\"padding: 9px \(pad)px; width: 38%;\">"
        r += "<font size=\"2\" color=\"\(t.key)\">\(esc(key))</font></td>"
        r += "<td valign=\"top\" style=\"padding: 9px \(pad)px;\">\(value)</td></tr>"
        if !last { r += thinSep(t) }
        return r
    }

    /// Keys whose integer values represent hours
    private static let hourKeys: Set<String> = [
        "gracePeriodInstallDelay", "gracePeriodLaunchDelay",
    ]

    /// Heuristic: does this key name suggest a time/duration value?
    static func isTimeKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let timeWords = [
            "time", "cycle", "delay", "interval", "timeout", "duration", "period", "refresh",
            "expir",
        ]
        return timeWords.contains { lower.contains($0) }
    }

    /// Format seconds into "Xd Xh Xm Xs"
    static func formatDuration(seconds: Int) -> String {
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
    static func formatHours(_ hours: Int) -> String {
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
                    result +=
                        " <font size=\"1\" color=\"\(t.muted)\">(\(formatHours(num.intValue)))</font>"
                } else if isTimeKey(key) {
                    result +=
                        " <font size=\"1\" color=\"\(t.muted)\">(\(formatDuration(seconds: num.intValue)))</font>"
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
                let label =
                    dict["_language"] as? String
                    ?? dict["identifier"] as? String
                    ?? dict["BundleIdentifier"] as? String
                    ?? dict["Identifier"] as? String
                    ?? dict["RuleValue"] as? String
                    ?? nil
                if let label = label {
                    h +=
                        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 10px \(pad)px 4px \(pad)px;\">"
                    h += "<font size=\"1\" color=\"\(t.label)\">\(esc(label))</font>"
                    h += "</td></tr></table>"
                } else if arr.count > 1 {
                    h +=
                        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 10px \(pad)px 4px \(pad)px;\">"
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
                        h +=
                            "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" style=\"padding: 9px \(pad)px 3px \(pad)px;\">"
                        h += "<font size=\"2\" color=\"\(t.key)\">\(esc(key))</font></td></tr>"
                        h +=
                            "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" style=\"padding: 0 \(pad)px 9px \(pad)px;\">"
                        h +=
                            "<font size=\"1\" face=\"Menlo\" color=\"\(t.label)\">\(esc(val as! String))</font></td></tr>"
                        if !isLast { h += thinSep(t) }
                    } else {
                        h +=
                            "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" valign=\"top\" style=\"padding: 9px \(pad)px 3px \(pad)px;\">"
                        h += "<font size=\"2\" color=\"\(t.key)\">\(esc(key))</font></td></tr>"
                        h +=
                            "<tr bgcolor=\"\(t.cell)\"><td colspan=\"2\" style=\"padding: 0 \(pad)px 9px \(pad + 8)px;\">"
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
                    h += cellRow(
                        key, inlineValue(dict[key]!, key: key, t: t), t: t,
                        last: i == simpleK.count - 1)
                }
                h += groupEnd()
            }
            for key in complexK {
                h +=
                    "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 12px \(pad)px 4px \(pad)px;\">"
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
            case plain, key, string, number, bool, comment, tag, attrName, attrValue, punctuation,
                plistKey, plistValue, variable, keyword, `operator`, command
        }
        let text: String
        let kind: Kind
    }

    // MARK: - JSON Tokenizer

    private static func tokenizeJSON(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"("(?:[^"\\]|\\.)*")\s*(:)|("(?:[^"\\]|\\.)*")|\b(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b|\b(true|false|null)\b"#
        )
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
        let regex = try! Regex(
            #"(?m)(#.*)$|^([\t ]*(?:- )?[A-Za-z_][\w.\-/]*)\s*(:)|("(?:[^"\\]|\\.)*"|'[^']*')|\b(true|false|yes|no|null|~)\b|\b(-?\d+(?:\.\d+)?)\b"#
        )
        let tokens = tokenize(src, regex: regex) { match in
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
        return embedSQLInYAML(tokens)
    }

    /// Re-tokenize plain text following `query:` keys as SQL
    private static func embedSQLInYAML(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var inSQL = false
        for token in tokens {
            if token.kind == .key
                && token.text.trimmingCharacters(in: .whitespaces).hasSuffix("query")
            {
                inSQL = true
                result.append(token)
                continue
            }
            if inSQL {
                if token.kind == .key {
                    // Hit the next YAML key — SQL region is over
                    inSQL = false
                    result.append(token)
                    continue
                }
                if token.kind == .plain {
                    let trimmed = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed == "|" || trimmed == ">" {
                        result.append(token)
                        continue
                    }
                    result.append(contentsOf: tokenizeSQL(token.text))
                    continue
                }
                // punctuation (:) after query key, or strings — pass through
                result.append(token)
                continue
            }
            result.append(token)
        }
        return result
    }

    // MARK: - SQL Tokenizer (for embedded osquery)

    private static func tokenizeSQL(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(?m)(--[^\n]*)"#  // 1: line comment
                + #"|('(?:[^'\\]|\\.)*')"#  // 2: single-quoted string
                + #"|("(?:[^"\\]|\\.)*")"#  // 3: double-quoted string
                + #"|\b(SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|ON|AND|OR|NOT|IN|LIKE|GLOB|AS|GROUP|ORDER|BY|HAVING|LIMIT|OFFSET|UNION|ALL|INSERT|INTO|UPDATE|DELETE|CREATE|DROP|ALTER|COUNT|SUM|AVG|MIN|MAX|DISTINCT|IS|NULL|BETWEEN|EXISTS|CASE|WHEN|THEN|ELSE|END|WITH|USING|COLLATE|ASC|DESC|SET|VALUES|TABLE|INDEX|VIEW|IF|REPLACE|CAST|COALESCE|RECURSIVE)\b"#  // 4: keyword (case-insensitive)
                + #"|\b(\d+(?:\.\d+)?)\b"#  // 5: number
                + #"|(\*|=|!=|<>|<=|>=|<|>|\|\|)"#  // 6: operator
        ).ignoresCase()
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[2] {
                return [Token(text: str, kind: .string)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let kw = match[4] {
                return [Token(text: kw, kind: .keyword)]
            } else if let num = match[5] {
                return [Token(text: num, kind: .number)]
            } else if let op = match[6] {
                return [Token(text: op, kind: .operator)]
            }
            return nil
        }
    }

    // MARK: - TOML Tokenizer

    private static func tokenizeTOML(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(?m)(#.*)$|(\[{1,2}[^\]]*\]{1,2})|^([\t ]*[A-Za-z_][\w.\-]*)\s*(=)|("(?:[^"\\]|\\.)*"|'[^']*'|"""[\s\S]*?"""|'''[\s\S]*?''')|\b(true|false)\b|\b(\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2})?)\b|\b(-?\d+(?:\.\d+)?)\b"#
        )
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
            #"(?m)(#!\/[^\n]*)"#  // 1: shebang
                + #"|(#[^\n]*)"#  // 2: comment
                + #"|('(?:[^'\\]|\\.)*')"#  // 3: single-quoted string
                + #"|("(?:[^"\\]|\\.)*")"#  // 4: double-quoted string
                + #"|(`[^`]*`)"#  // 5: backtick string
                + #"|(\$\{[^}]*\}|\$[A-Za-z_]\w*|\$[0-9@?#!$*\-])"#  // 6: variable
                + #"|\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|local|export|source|in|select|until)\b"#  // 7: keyword
                + #"|(\|\||&&|>>|>&|<<|<|>|;|\|)"#  // 8: operator
                + #"|\b(-?\d+(?:\.\d+)?)\b"#  // 9: number
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
            #"(<#[\s\S]*?#>)"#  // 1: block comment
                + #"|(?m)(#[^\n]*)"#  // 2: line comment
                + #"|('(?:[^'\\]|\\.)*')"#  // 3: single-quoted string
                + #"|("(?:[^"\\]|\\.)*")"#  // 4: double-quoted string
                + #"|(\$env:[A-Za-z_]\w*|\$\{[^}]*\}|\$[A-Za-z_]\w*)"#  // 5: variable
                + #"|\b(if|else|elseif|foreach|for|while|do|switch|function|param|return|try|catch|finally|throw|begin|process|end)\b"#  // 6: keyword
                + #"|([A-Z][a-z]+-[A-Z]\w*)"#  // 7: cmdlet (Verb-Noun)
                + #"|(-(?:eq|ne|gt|lt|ge|le|match|like|notmatch|notlike|contains|in|notin|replace|split|join|is|isnot|as|band|bor|bnot|bxor|shl|shr|and|or|not))\b"#  // 8: operator
                + #"|(\|\||&&|;|\|)"#  // 9: pipe/logical operator
                + #"|\b(-?\d+(?:\.\d+)?)\b"#  // 10: number
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

    // MARK: - Python Tokenizer

    private static func tokenizePython(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?''')"#  // 1: triple-quoted string
                + #"|(#[^\n]*)"#  // 2: comment
                + #"|(@[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)"#  // 3: decorator
                + #"|(f\"(?:[^\"\\]|\\.)*\"|f'(?:[^'\\]|\\.)*')"#  // 4: f-string
                + #"|('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")"#  // 5: string
                + #"|\b(def|class|if|elif|else|for|while|try|except|finally|with|as|import|from|return|yield|raise|pass|break|continue|and|or|not|is|in|lambda|global|nonlocal|assert|del|async|await|True|False|None)\b"#  // 6: keyword
                + #"|(\*\*|//|->|:=|==|!=|<=|>=|<<|>>|\+=|-=|\*=|/=|%=|&=|\|=|\^=|<|>)"#  // 7: operator
                + #"|\b(\d+(?:\.\d+)?(?:[eE][+-]?\d+)?j?|0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[bB][01]+)\b"#  // 8: number
        ).dotMatchesNewlines()
        return tokenize(src, regex: regex) { match in
            if let str = match[1] {
                return [Token(text: str, kind: .string)]
            } else if let comment = match[2] {
                return [Token(text: comment, kind: .comment)]
            } else if let deco = match[3] {
                return [Token(text: deco, kind: .attrName)]
            } else if let fstr = match[4] {
                return [Token(text: fstr, kind: .string)]
            } else if let str = match[5] {
                return [Token(text: str, kind: .string)]
            } else if let kw = match[6] {
                let boolish = ["True", "False", "None"].contains(kw)
                return [Token(text: kw, kind: boolish ? .bool : .keyword)]
            } else if let op = match[7] {
                return [Token(text: op, kind: .operator)]
            } else if let num = match[8] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - JavaScript/TypeScript Tokenizer

    private static func tokenizeJavaScript(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(//[^\n]*|/\*[\s\S]*?\*/)"#  // 1: comment
                + #"|(`(?:[^`\\]|\\.)*`)"#  // 2: template literal
                + #"|(\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')"#  // 3: string
                + #"|(/(?:[^/\\]|\\.)+/[gimsuy]*)"#  // 4: regex
                + #"|\b(const|let|var|function|return|if|else|for|while|do|switch|case|default|break|continue|class|extends|new|this|super|import|export|from|as|async|await|yield|try|catch|finally|throw|typeof|instanceof|in|of|void|delete|interface|type|enum|namespace|declare|abstract|implements|readonly|keyof|infer|never|unknown)\b"#  // 5: keyword
                + #"|\b(true|false|null|undefined|NaN|Infinity)\b"#  // 6: bool/literal
                + #"|(=>|===|!==|==|!=|<=|>=|&&|\|\||\?\?|\?\.|\.\.\.|\*\*|<<|>>|>>>)"#  // 7: operator
                + #"|\b(0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?n?)\b"#  // 8: number
        ).dotMatchesNewlines()
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[2] {
                return [Token(text: str, kind: .string)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let re = match[4] {
                return [Token(text: re, kind: .string)]
            } else if let kw = match[5] {
                return [Token(text: kw, kind: .keyword)]
            } else if let b = match[6] {
                return [Token(text: b, kind: .bool)]
            } else if let op = match[7] {
                return [Token(text: op, kind: .operator)]
            } else if let num = match[8] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - HCL / Terraform Tokenizer

    private static func tokenizeHCL(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(?m)(#[^\n]*|//[^\n]*)"#  // 1: line comment
                + #"|(/\*[\s\S]*?\*/)"#  // 2: block comment
                + #"|("(?:[^"\\]|\\.)*")"#  // 3: double-quoted string
                + #"|(<<-?\s*(\w+)\n[\s\S]*?\n\s*\5)"#  // 4: heredoc (5: delimiter)
                + #"|\b(variable|output|resource|data|provider|terraform|locals|module|moved|import|check|removed)\b"#  // 6: block type keyword
                + #"|\b(for_each|count|depends_on|lifecycle|source|version|required_providers|required_version|backend|cloud)\b"#  // 7: meta-argument / config keyword
                + #"|\b(for|in|if|else|endif|endfor)\b"#  // 8: expression keyword
                + #"|\b(true|false|null)\b"#  // 9: bool/null
                + #"|\b(\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#  // 10: number
                + #"|(\$\{[^}]*\})"#  // 11: interpolation ${}
                + #"|(%\{[^}]*\})"#  // 12: directive %{}
                + #"|([\w][\w\-]*)(\s*)(\{)"#  // 13: identifier before { (14: whitespace, 15: brace)
                + #"|([\w][\w\-]*)(\s*)(=)"#  // 16: key before = (17: whitespace, 18: equals)
        )
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let comment = match[2] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let heredoc = match[4] {
                return [Token(text: heredoc, kind: .string)]
            } else if let kw = match[6] {
                return [Token(text: kw, kind: .keyword)]
            } else if let kw = match[7] {
                return [Token(text: kw, kind: .keyword)]
            } else if let kw = match[8] {
                return [Token(text: kw, kind: .keyword)]
            } else if let b = match[9] {
                return [Token(text: b, kind: .bool)]
            } else if let num = match[10] {
                return [Token(text: num, kind: .number)]
            } else if let interp = match[11] {
                return [Token(text: interp, kind: .variable)]
            } else if let dir = match[12] {
                return [Token(text: dir, kind: .variable)]
            } else if let ident = match[13], let ws = match[14], let brace = match[15] {
                return [
                    Token(text: ident, kind: .tag), Token(text: ws, kind: .plain),
                    Token(text: brace, kind: .punctuation),
                ]
            } else if let key = match[16], let ws = match[17], let eq = match[18] {
                return [
                    Token(text: key, kind: .key), Token(text: ws, kind: .plain),
                    Token(text: eq, kind: .punctuation),
                ]
            }
            return nil
        }
    }

    // MARK: - Markdown Renderer

    private static func renderMarkdown(_ source: String, dark: Bool) -> String {
        let bg = dark ? "#1c1c1e" : "#ffffff"
        let fg = dark ? "#f5f5f7" : "#1d1d1f"
        let muted = dark ? "#98989d" : "#6e6e73"
        let accent = dark ? "#bf5af2" : "#6366f1"
        let codeBg = dark ? "#2c2c2e" : "#f4f4f5"
        let border = dark ? "#38383a" : "#e2e8f0"
        let link = dark ? "#0a84ff" : "#2563eb"

        var html = ""
        let lines = source.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBuffer = ""

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html +=
                        "<pre style=\"background:\(codeBg); padding:12px 16px; border-radius:6px; overflow-x:auto; font:12px/1.6 Menlo,monospace;\">\(escapeHTML(codeBuffer))</pre>"
                    codeBuffer = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                codeBuffer += (codeBuffer.isEmpty ? "" : "\n") + line
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                html += "<br>"
            } else if trimmed.hasPrefix("# ") {
                html +=
                    "<h1 style=\"font-size:28px; margin:24px 0 8px 0; border-bottom:1px solid \(border); padding-bottom:8px;\">\(inlineMarkdown(escapeHTML(String(trimmed.dropFirst(2)))))</h1>"
            } else if trimmed.hasPrefix("## ") {
                html +=
                    "<h2 style=\"font-size:22px; margin:20px 0 6px 0; border-bottom:1px solid \(border); padding-bottom:6px;\">\(inlineMarkdown(escapeHTML(String(trimmed.dropFirst(3)))))</h2>"
            } else if trimmed.hasPrefix("### ") {
                html +=
                    "<h3 style=\"font-size:18px; margin:16px 0 4px 0;\">\(inlineMarkdown(escapeHTML(String(trimmed.dropFirst(4)))))</h3>"
            } else if trimmed.hasPrefix("#### ") {
                html +=
                    "<h4 style=\"font-size:15px; margin:12px 0 4px 0; color:\(muted);\">\(inlineMarkdown(escapeHTML(String(trimmed.dropFirst(5)))))</h4>"
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                html +=
                    "<p style=\"margin:2px 0 2px 20px;\">&bull; \(inlineMarkdown(escapeHTML(String(trimmed.dropFirst(2)))))</p>"
            } else if trimmed.hasPrefix("> ") {
                html +=
                    "<blockquote style=\"margin:8px 0; padding:4px 16px; border-left:3px solid \(accent); color:\(muted);\">\(inlineMarkdown(escapeHTML(String(trimmed.dropFirst(2)))))</blockquote>"
            } else if trimmed.hasPrefix("---") || trimmed.hasPrefix("***")
                || trimmed.hasPrefix("___")
            {
                html += "<hr style=\"border:none; border-top:1px solid \(border); margin:16px 0;\">"
            } else if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                let content = trimmed.replacingOccurrences(
                    of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                html +=
                    "<p style=\"margin:2px 0 2px 20px;\">\(inlineMarkdown(escapeHTML(content)))</p>"
            } else {
                html += "<p style=\"margin:4px 0;\">\(inlineMarkdown(escapeHTML(trimmed)))</p>"
            }
        }

        if inCodeBlock {
            html +=
                "<pre style=\"background:\(codeBg); padding:12px 16px; border-radius:6px; font:12px/1.6 Menlo,monospace;\">\(escapeHTML(codeBuffer))</pre>"
        }

        return """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8">
            <style>
            body { font: 14px/1.7 -apple-system, Helvetica, sans-serif; margin: 0; padding: 20px 24px; background: \(bg); color: \(fg); }
            code { background: \(codeBg); padding: 2px 5px; border-radius: 3px; font: 12px Menlo, monospace; }
            a { color: \(link); text-decoration: none; }
            </style></head>
            <body>\(html)</body></html>
            """
    }

    /// Process inline markdown: **bold**, *italic*, `code`, [links](url)
    static func inlineMarkdown(_ text: String) -> String {
        var result = text
        // Bold
        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Italic
        result = result.replacingOccurrences(
            of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"_(.+?)_"#, with: "<em>$1</em>", options: .regularExpression)
        // Code
        result = result.replacingOccurrences(
            of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        // Links
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>",
            options: .regularExpression)
        return result
    }

    // MARK: - Ruby Tokenizer

    private static func tokenizeRuby(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(=begin[\s\S]*?=end)"#  // 1: block comment
                + #"|(?m)(#[^\n]*)"#  // 2: line comment
                + #"|(\"\"\"[\s\S]*?\"\"\"|'[^']*'|\"(?:[^\"\\]|\\.)*\")"#  // 3: string
                + #"|(/(?:[^/\\]|\\.)+/[imxo]*)"#  // 4: regex
                + #"|(@{1,2}[A-Za-z_]\w*)"#  // 5: instance/class var
                + #"|(\$[A-Za-z_]\w*|\$[0-9!@&+`'=~/\\,;.<>*$?:\"])"#  // 6: global var
                + #"|(:[A-Za-z_]\w*[!?]?)"#  // 7: symbol
                + #"|\b(def|class|module|end|if|elsif|else|unless|case|when|while|until|for|do|begin|rescue|ensure|raise|return|yield|block_given\?|require|require_relative|include|extend|attr_accessor|attr_reader|attr_writer|self|super|nil|true|false|and|or|not|in|then|puts|print|lambda|proc)\b"#  // 8: keyword
                + #"|(<=>|=>|&&|\|\||<<|>>|[!=<>]=|[-+*/%&|^~<>]=?|\.\.\.|\.\.)"#  // 9: operator
                + #"|\b(\d+(?:\.\d+)?(?:e[+-]?\d+)?|0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+)\b"#  // 10: number
        ).dotMatchesNewlines()
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let comment = match[2] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let re = match[4] {
                return [Token(text: re, kind: .string)]
            } else if let v = match[5] {
                return [Token(text: v, kind: .variable)]
            } else if let v = match[6] {
                return [Token(text: v, kind: .variable)]
            } else if let sym = match[7] {
                return [Token(text: sym, kind: .attrName)]
            } else if let kw = match[8] {
                return [
                    Token(text: kw, kind: ["nil", "true", "false"].contains(kw) ? .bool : .keyword)
                ]
            } else if let op = match[9] {
                return [Token(text: op, kind: .operator)]
            } else if let num = match[10] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - Go Tokenizer

    private static func tokenizeGo(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(//[^\n]*|/\*[\s\S]*?\*/)"#  // 1: comment
                + #"|(\"(?:[^\"\\]|\\.)*\"|`[^`]*`)"#  // 2: string
                + #"|\b(package|import|func|return|var|const|type|struct|interface|map|chan|go|defer|if|else|for|range|switch|case|default|break|continue|fallthrough|select|make|new|append|len|cap|copy|delete|close|panic|recover|nil|true|false|iota)\b"#  // 3: keyword
                + #"|\b(int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|string|bool|byte|rune|error|any)\b"#  // 4: type
                + #"|(:=|<-|&&|\|\||<<|>>|[!=<>]=|[-+*/%&|^~<>]=?|\.\.\.)\"?"#  // 5: operator
                + #"|\b(0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?)\b"#  // 6: number
        ).dotMatchesNewlines()
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[2] {
                return [Token(text: str, kind: .string)]
            } else if let kw = match[3] {
                return [
                    Token(
                        text: kw,
                        kind: ["nil", "true", "false", "iota"].contains(kw) ? .bool : .keyword)
                ]
            } else if let tp = match[4] {
                return [Token(text: tp, kind: .tag)]
            } else if let op = match[5] {
                return [Token(text: op, kind: .operator)]
            } else if let num = match[6] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - Rust Tokenizer

    private static func tokenizeRust(_ src: String) -> [Token] {
        let regex = try! Regex(
            #"(//[^\n]*|/\*[\s\S]*?\*/)"#  // 1: comment
                + #"|(r"[^"]*"|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)')"#  // 2: string/char
                + ##"|(#\[[\w:()=, "]*\]|#!\[[\w:()=, "]*\])"##  // 3: attribute
                + #"|\b(fn|let|mut|const|static|struct|enum|impl|trait|type|pub|crate|mod|use|as|self|super|Self|if|else|match|for|while|loop|in|break|continue|return|where|async|await|move|unsafe|extern|ref|dyn|macro_rules)\b"#  // 4: keyword
                + #"|\b(i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc|Some|None|Ok|Err)\b"#  // 5: type
                + #"|\b(true|false)\b"#  // 6: bool
                + #"|(=>|->|&&|\|\||<<|>>|[!=<>]=|[-+*/%&|^~<>]=?|\.\.\.|\.\.=?)"#  // 7: operator
                + #"|\b(0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?(?:_?(?:i|u|f)(?:8|16|32|64|128|size))?)\b"#  // 8: number
        ).dotMatchesNewlines()
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let str = match[2] {
                return [Token(text: str, kind: .string)]
            } else if let attr = match[3] {
                return [Token(text: attr, kind: .attrName)]
            } else if let kw = match[4] {
                return [Token(text: kw, kind: .keyword)]
            } else if let tp = match[5] {
                return [
                    Token(
                        text: tp,
                        kind: ["Some", "None", "Ok", "Err"].contains(tp) ? .keyword : .tag)
                ]
            } else if let b = match[6] {
                return [Token(text: b, kind: .bool)]
            } else if let op = match[7] {
                return [Token(text: op, kind: .operator)]
            } else if let num = match[8] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - XML Tokenizer

    private static func tokenizeXML(_ src: String) -> [Token] {
        // Match Payload key+value pairs, then general XML
        let mainRegex = try! Regex(
            #"(<!--[\s\S]*?-->)"#  // 1: comment
                + #"|(<!\[CDATA\[[\s\S]*?\]\]>)"#  // 2: CDATA
                + #"|(<key>)(Payload\w+)(</key>\s*)(<(?:string|integer)>)([^<]*)(</(?:string|integer)>)"#  // 3-8: Payload key + value
                + #"|(<key>)(Payload\w+)(</key>)"#  // 9-11: Payload key without simple value
                + #"|(<\/?[A-Za-z_][\w:\-.]*)(\s[^>]*)?(\/?>)"#  // 12-14: general tag
                + #"|("[^"]*"|'[^']*')"#  // 15: quoted string
        ).dotMatchesNewlines()
        return tokenize(src, regex: mainRegex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let cdata = match[2] {
                return [Token(text: cdata, kind: .string)]
            } else if let open = match[3], let keyText = match[4], let mid = match[5],
                let valOpen = match[6], let valText = match[7], let valClose = match[8]
            {
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
                tokens.append(
                    Token(text: String(src[searchStart..<match.range.lowerBound]), kind: .plain))
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

    static func escapeHTML(_ text: String) -> String {
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
