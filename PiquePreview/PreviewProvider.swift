//  PreviewProvider.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import Cocoa
import QuickLookUI
import UniformTypeIdentifiers
import OSLog

@objc(PreviewProvider)
class PreviewProvider: NSViewController, QLPreviewingController {
    private let logger = Logger(subsystem: "io.macadmins.pique", category: "preview")

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        view = scrollView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            var data = try FileReader.readData(url: url)
            let extLower = url.pathExtension.lowercased()
            let nameLower = url.lastPathComponent.lowercased()
            // .recipe (XML), .recipe.plist (override), and .recipe.yaml (YAML recipe)
            // all flow through the structured renderer. Pathological extensions like
            // .yaml/.plist alone are NOT treated as recipes — the suffix matters.
            let isAutoPkgRecipe = extLower == "recipe"
                || nameLower.hasSuffix(".recipe.plist")
                || nameLower.hasSuffix(".recipe.yaml")
            let format: FileFormat = isAutoPkgRecipe
                ? .recipe
                : (FileFormat(pathExtension: url.pathExtension) ?? .json)

            // Step 1: Strip CMS signature from signed mobileconfig files
            if format == .mobileconfig, FileReader.isCMSEnvelope(data),
               let inner = FileReader.stripCMSSignature(from: data) {
                data = inner
            }

            // Step 2: Convert source bytes to displayable text
            let text: String
            if extLower == "vpptoken",
               let json = FileReader.decodeVPPToken(data) {
                text = json
            } else if FileReader.isBinaryPlist(data),
                      let xml = FileReader.convertBinaryPlistToXMLString(data) {
                text = xml
            } else {
                text = FileReader.decodeToString(data)
            }

            let formatName = isAutoPkgRecipe
                ? "AutoPkg"
                : PreviewProvider.formatName(for: url.pathExtension)
            let isDark: Bool
            switch AppearanceSettings.override(forFormat: formatName) {
            case .system:
                isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            case .light:
                isDark = false
            case .dark:
                isDark = true
            }
            var html = SyntaxHighlighter.highlight(text, format: format, darkMode: isDark)
            if url.pathExtension.lowercased() == "vpptoken",
               let info = FileReader.vppTokenInfo(data) {
                let banner = PreviewProvider.vppTokenBanner(info: info, dark: isDark)
                html = html.replacingOccurrences(of: "<body>", with: "<body>\(banner)")
            }

            logger.info("Preview for \(url.lastPathComponent, privacy: .public)")

            guard let htmlData = html.data(using: .utf8),
                  let attrString = NSAttributedString(
                      html: htmlData,
                      documentAttributes: nil
                  ) else {
                handler(nil)
                return
            }

            if let scrollView = view as? NSScrollView,
               let textView = scrollView.documentView as? NSTextView {
                textView.textStorage?.setAttributedString(attrString)
                let bg: NSColor = isDark ? NSColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1) : .white
                textView.backgroundColor = bg
                scrollView.backgroundColor = bg
            }

            handler(nil)
        } catch {
            logger.error("Preview failed: \(error.localizedDescription, privacy: .public)")
            handler(error)
        }
    }

    /// Builds an HTML expiration banner for a VPP token, colour-coded by remaining days.
    /// Expired → red, ≤30 days → amber, otherwise green. Org name is included when present.
    private static func vppTokenBanner(info: FileReader.VPPTokenInfo, dark: Bool) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = TimeZone(secondsFromGMT: 0)

        let title: String
        let bg: String
        let fg: String
        if let exp = info.expDate {
            let cal = Calendar(identifier: .gregorian)
            let today = cal.startOfDay(for: Date())
            let expDay = cal.startOfDay(for: exp)
            let days = cal.dateComponents([.day], from: today, to: expDay).day ?? 0
            let dateStr = dateFmt.string(from: exp)
            if days < 0 {
                title = "EXPIRED \(-days) day\(-days == 1 ? "" : "s") ago — \(dateStr)"
                bg = dark ? "#5a1a1a" : "#fde2e2"; fg = dark ? "#ffb4b4" : "#8a1a1a"
            } else if days == 0 {
                title = "Expires today — \(dateStr)"
                bg = dark ? "#5a1a1a" : "#fde2e2"; fg = dark ? "#ffb4b4" : "#8a1a1a"
            } else if days <= 30 {
                title = "Expires in \(days) day\(days == 1 ? "" : "s") — \(dateStr)"
                bg = dark ? "#5a4a1a" : "#fff4d6"; fg = dark ? "#ffd98a" : "#8a5a00"
            } else {
                title = "Expires in \(days) days — \(dateStr)"
                bg = dark ? "#1a4a2a" : "#dff5e1"; fg = dark ? "#a8e6b8" : "#1a5a2a"
            }
        } else {
            title = "Expiration date not readable"
            bg = dark ? "#3a3a3c" : "#eeeeee"; fg = dark ? "#d0d0d0" : "#555555"
        }

        let org = (info.orgName?.isEmpty == false) ? " · \(info.orgName!)" : ""
        return """
            <div style="background:\(bg);color:\(fg);font:600 13px/1.4 -apple-system,system-ui,sans-serif;padding:10px 14px;margin:0 0 12px 0;border-radius:6px;">\(title)\(org)</div>
            """
    }

    /// Maps a file extension to a format group name matching AppearanceSettings keys.
    private static func formatName(for ext: String) -> String {
        switch ext.lowercased() {
        case "json", "ndjson", "jsonl", "vpptoken":              return "JSON"
        case "yaml", "yml", "recipe":                            return "YAML"
        case "toml", "lock":                                     return "TOML"
        case "xml":                                              return "XML"
        case "mobileconfig", "plist":                            return "mobileconfig"
        case "sh", "bash", "zsh", "ksh", "dash", "rc", "command": return "Shell"
        case "ps1", "psm1", "psd1":                              return "PowerShell"
        case "py", "pyw", "pyi":                                 return "Python"
        case "rb":                                               return "Ruby"
        case "go":                                               return "Go"
        case "rs":                                               return "Rust"
        case "js", "jsx", "ts", "tsx", "mjs", "cjs":            return "JavaScript"
        case "md", "markdown", "adoc":                           return "Markdown"
        case "tf", "tfvars", "hcl":                              return "HCL"
        default:                                                  return ext
        }
    }
}
