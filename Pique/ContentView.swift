//  ContentView.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let formats: [(String, String, Color)] = [
        ("JSON", "doc.text", Color.orange),
        ("YAML", "doc.text", Color.purple),
        ("TOML", "doc.text", Color.blue),
        ("XML", "doc.text", Color.green),
        ("mobileconfig", "lock.doc", Color.red),
        ("VPP token", "key.fill", Color.yellow),
        ("AutoPkg", "shippingbox", Color.brown),
        ("Shell", "terminal", Color.mint),
        ("PowerShell", "terminal", Color.blue),
        ("Python", "chevron.left.forwardslash.chevron.right", Color.cyan),
        ("JavaScript / TS", "chevron.left.forwardslash.chevron.right", Color.yellow),
        ("HCL", "doc.text", Color.indigo),
        ("Markdown", "doc.richtext", Color.gray),
        ("Env / Config", "slider.horizontal.3", Color.teal),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "eye.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.breathe.plain, options: .speed(0.5), isActive: !reduceMotion)

            Text("Pique")
                .font(.largeTitle.bold())

            Text("QuickLook previews for config files")
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                formatChipsRow(formats.prefix(5))
                formatChipsRow(formats.dropFirst(5).prefix(4))
                formatChipsRow(formats.dropFirst(9))
            }

            Text("Select a supported file in Finder and press Space to preview.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(48)
        .frame(minWidth: 700, minHeight: 300)
        .overlay(alignment: .bottomTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .padding(16)
            .help("Appearance Settings (⌘,)")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private func formatChipsRow<S: Sequence>(_ entries: S) -> some View
    where S.Element == (String, String, Color) {
        HStack(spacing: 12) {
            ForEach(Array(entries), id: \.0) { name, icon, color in
                Label(name, systemImage: icon)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(color)
            }
        }
    }
}

#Preview {
    ContentView()
}
