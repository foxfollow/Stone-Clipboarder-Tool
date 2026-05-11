//
//  SettingsSidebar.swift
//  StoneClipboarderTool
//

import SwiftUI

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection
    let accessibilityGranted: Bool
    let appVersion: String

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarRow(
                        section: section,
                        accessibilityGranted: accessibilityGranted
                    )
                    .tag(section)
                }
            }
            .listStyle(.sidebar)

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
