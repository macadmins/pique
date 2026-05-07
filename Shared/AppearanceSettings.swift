//  AppearanceSettings.swift
//  Pique
//
//  Shared between the main app and the QuickLook extension via an App Group.

import Foundation

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

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Whether to show line numbers in code previews.
    static var showLineNumbers: Bool {
        get { defaults.bool(forKey: lineNumbersKey) }
        set { defaults.set(newValue, forKey: lineNumbersKey) }
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
