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
            let format = FileFormat(pathExtension: url.pathExtension) ?? .json

            // Step 1: Strip CMS signature from signed mobileconfig files
            if format == .mobileconfig, FileReader.isCMSEnvelope(data),
               let inner = FileReader.stripCMSSignature(from: data) {
                data = inner
            }

            // Step 2: Convert binary plist to XML text
            let text: String
            if FileReader.isBinaryPlist(data),
               let xml = FileReader.convertBinaryPlistToXMLString(data) {
                text = xml
            } else {
                text = FileReader.decodeToString(data)
            }

            let formatName = PreviewProvider.formatName(for: url.pathExtension)
            let isDark: Bool
            switch AppearanceSettings.override(forFormat: formatName) {
            case .system:
                isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            case .light:
                isDark = false
            case .dark:
                isDark = true
            }
            let html = SyntaxHighlighter.highlight(text, format: format, darkMode: isDark)

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

    /// Maps a file extension to a format group name matching AppearanceSettings keys.
    private static func formatName(for ext: String) -> String {
        switch ext.lowercased() {
        case "json", "ndjson", "jsonl":                            return "JSON"
        case "yaml", "yml":                                      return "YAML"
        case "toml", "lock":                                     return "TOML"
        case "xml", "recipe":                                    return "XML"
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
