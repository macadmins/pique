//  ContentView.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import SwiftUI

struct ContentView: View {
    private let formats = [
        ("JSON", "doc.text", Color.orange),
        ("YAML", "doc.text", Color.purple),
        ("TOML", "doc.text", Color.blue),
        ("XML", "doc.text", Color.green),
        ("mobileconfig", "lock.doc", Color.red),
        ("Shell", "terminal", Color.mint),
        ("Python", "chevron.left.forwardslash.chevron.right", Color.cyan),
        ("HCL", "doc.text", Color.indigo),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "eye.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Pique")
                .font(.largeTitle.bold())

            Text("QuickLook previews for config files")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ForEach(formats, id: \.0) { name, icon, color in
                    Label(name, systemImage: icon)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(color)
                }
            }

            Text("Select a supported file in Finder and press Space to preview.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(48)
        .frame(minWidth: 700, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
