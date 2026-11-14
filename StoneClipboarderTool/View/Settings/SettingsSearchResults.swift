//
//  SettingsSearchResults.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The sidebar while the Settings search has text: matching settings,
/// grouped by page. A click opens the page on that row.
struct SettingsSearchResults: View {
    let results: [SettingsSearchEntry]
    let onPick: (SettingsSearchEntry) -> Void

    /// Pages in sidebar order, each with its results in rank order.
    private var groups: [(section: SettingsSection, entries: [SettingsSearchEntry])] {
        SettingsSection.allCases.compactMap { section in
            let entries = results.filter { $0.section == section }
            return entries.isEmpty ? nil : (section, entries)
        }
    }

    var body: some View {
        if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No settings found")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(groups, id: \.section) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            Button { onPick(entry) } label: { row(entry) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Label(group.section.title, systemImage: group.section.systemImage)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func row(_ entry: SettingsSearchEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .lineLimit(2)
            Text([entry.group, entry.note].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
