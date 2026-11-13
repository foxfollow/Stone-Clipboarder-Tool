//
//  SettingsSidebar.swift
//  StoneClipboarderTool
//

import SwiftUI

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection
    let accessibilityGranted: Bool
    let appVersion: String
    /// Non-nil while searching: shown instead of the pages.
    var searchResults: [SettingsSearchEntry]? = nil
    var onPickResult: (SettingsSearchEntry) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if let searchResults {
                SettingsSearchResults(results: searchResults, onPick: onPickResult)
            } else {
                List(selection: $selectedSection) {
                    ForEach(SettingsGroup.allCases) { group in
                        Section(group.title) {
                            ForEach(group.sections) { section in
                                SettingsSidebarRow(
                                    section: section,
                                    accessibilityGranted: accessibilityGranted
                                )
                                .tag(section)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            SettingsSidebarFooter(appVersion: appVersion)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }
}

private struct SettingsSidebarFooter: View {
    let appVersion: String

    var body: some View {
        HStack {
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
