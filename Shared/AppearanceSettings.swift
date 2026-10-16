//  AppearanceSettings.swift
//  Pique
//
//  Shared between the main app and the QuickLook extension via an App Group.

import AppKit

/// The appearance to use when rendering a preview.
enum AppearanceOverride: String, CaseIterable {
    case system   // follow macOS system appearance (default)
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

enum AppearanceSettings {
    static let appGroupID = "group.io.macadmins.pique.apps"
    private static let key = "appearanceOverrides"
    private static let lineNumbersKey = "showLineNumbers"
    private static let finalNewlineKey = "showFinalNewline"
    private static let fontScaleKey = "fontScale"
    private static let codeFontKey = "codeFontFamily"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Whether to show line numbers in code previews.
    static var showLineNumbers: Bool {
        get { defaults.bool(forKey: lineNumbersKey) }
        set { defaults.set(newValue, forKey: lineNumbersKey) }
    }

    /// Whether to mark the file's final newline with a visible ↵.
    static var showFinalNewline: Bool {
        get { defaults.bool(forKey: finalNewlineKey) }
        set { defaults.set(newValue, forKey: finalNewlineKey) }
    }

    /// Multiplier applied to all preview text (1.0 = default size).
    static var fontScale: Double {
        get { let value = defaults.double(forKey: fontScaleKey); return value > 0 ? value : 1 }
        set { defaults.set(newValue, forKey: fontScaleKey) }
    }

    /// Font family for monospaced (code) text; empty keeps each renderer's default.
    static var codeFontFamily: String {
        get { defaults.string(forKey: codeFontKey) ?? "" }
        set { defaults.set(newValue, forKey: codeFontKey) }
    }

    /// Applies the text size and code font settings to a converted preview, after HTML
    /// conversion, so every renderer is covered without touching its hardcoded sizes.
    /// Proportional text (Markdown body, profile labels) keeps its family.
    static func applyFontSettings(to text: NSMutableAttributedString, scale: Double, codeFamily: String) {
        let full = NSRange(location: 0, length: text.length)
        let factor = CGFloat(scale)
        let manager = NSFontManager.shared
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let size = font.pointSize * factor
            var newFont = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
            if font.isFixedPitch, !codeFamily.isEmpty {
                if codeFamily == "SF Mono" {
                    // The system monospaced font has no public family name, so build it and re-apply traits.
                    let traits = manager.traits(of: font).intersection([.boldFontMask, .italicFontMask])
                    newFont = manager.convert(NSFont.monospacedSystemFont(ofSize: size, weight: .regular), toHaveTrait: traits)
                } else {
                    newFont = manager.convert(newFont, toFamily: codeFamily)
                }
            }
            text.addAttribute(.font, value: newFont, range: range)
        }
        guard factor != 1 else { return }
        text.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.paragraphSpacing *= factor
            style.paragraphSpacingBefore *= factor
            style.headIndent *= factor
            style.firstLineHeadIndent *= factor
            text.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }

    /// Returns the stored appearance override for a format group name, defaulting to `.system`.
    static func override(forFormat format: String) -> AppearanceOverride {
        let raw = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        guard let value = raw[format],
              let override = AppearanceOverride(rawValue: value) else {
            return .system
        }
        return override
    }

    /// Persists an appearance override for a format group name.
    /// Setting `.system` removes the entry entirely (returns to default behaviour).
    static func setOverride(_ value: AppearanceOverride, forFormat format: String) {
        var raw = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        if value == .system {
            raw.removeValue(forKey: format)
        } else {
            raw[format] = value.rawValue
        }
        defaults.set(raw, forKey: key)
    }
}
