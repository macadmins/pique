//  ContentView.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false

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

            FlowLayout(spacing: 12, rowSpacing: 10) {
                ForEach(formats, id: \.0) { name, icon, color in
                    Label(name, systemImage: icon)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(color)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)

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
            .padding(16)
            .help("Appearance Settings")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

/// Wraps subviews onto multiple rows when they don't fit on one line.
/// Each subview keeps its natural width; rows wrap on overflow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.map { $0.height }.reduce(0, +)
            + CGFloat(max(0, rows.count - 1)) * rowSpacing
        let widest = rows.map { $0.width }.max() ?? 0
        return CGSize(width: min(widest, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            let xStart = bounds.minX + (bounds.width - row.width) / 2
            var x = xStart
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    private func computeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(indices: [], width: 0, height: 0)
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width
            if projected > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [i], width: size.width, height: size.height)
            } else {
                current.indices.append(i)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview {
    ContentView()
}
