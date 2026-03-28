//  SettingsView.swift
//  Pique
//
//  Settings sheet for configuring per-format appearance overrides.

import SwiftUI

struct SettingsView: View {
    private let formatGroups: [(name: String, icon: String, color: Color)] = [
        ("JSON",         "doc.text",                               .orange),
        ("YAML",         "doc.text",                               .purple),
        ("TOML",         "doc.text",                               .blue),
        ("XML",          "doc.text",                               .green),
        ("mobileconfig", "lock.doc",                               .red),
        ("Shell",        "terminal",                               .mint),
        ("PowerShell",   "terminal",                               .blue),
        ("Python",       "chevron.left.forwardslash.chevron.right", .cyan),
        ("Ruby",         "chevron.left.forwardslash.chevron.right", .red),
        ("Go",           "chevron.left.forwardslash.chevron.right", .teal),
        ("Rust",         "chevron.left.forwardslash.chevron.right", .orange),
        ("JavaScript",   "chevron.left.forwardslash.chevron.right", .yellow),
        ("Markdown",     "doc.richtext",                           .gray),
        ("HCL",          "doc.text",                               .indigo),
        ("Log",          "doc.text.below.ecg",                     .gray),
    ]

    @State private var overrides: [String: AppearanceOverride] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Appearance Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Text("Override the preview appearance for specific file types, independent of the macOS system appearance.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 12)

            // One row per format group
            List {
                ForEach(formatGroups, id: \.name) { group in
                    FormatRow(
                        name: group.name,
                        icon: group.icon,
                        color: group.color,
                        override: binding(for: group.name)
                    )
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 480, height: 540)
        .onAppear { loadOverrides() }
    }

    private func binding(for format: String) -> Binding<AppearanceOverride> {
        Binding(
            get: { overrides[format] ?? .system },
            set: { newValue in
                overrides[format] = newValue
                AppearanceSettings.setOverride(newValue, forFormat: format)
            }
        )
    }

    private func loadOverrides() {
        var loaded: [String: AppearanceOverride] = [:]
        for group in formatGroups {
            let o = AppearanceSettings.override(forFormat: group.name)
            if o != .system { loaded[group.name] = o }
        }
        overrides = loaded
    }
}

private struct FormatRow: View {
    let name: String
    let icon: String
    let color: Color
    @Binding var override: AppearanceOverride

    var body: some View {
        HStack {
            Label(name, systemImage: icon)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(color)
            Spacer()
            Picker("", selection: $override) {
                ForEach(AppearanceOverride.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SettingsView()
}
