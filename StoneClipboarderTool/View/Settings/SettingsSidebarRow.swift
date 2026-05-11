//
//  SettingsSidebarRow.swift
//  StoneClipboarderTool
//

import SwiftUI

struct SettingsSidebarRow: View {
    let section: SettingsSection
    let accessibilityGranted: Bool

    var body: some View {
        Label(section.title, systemImage: iconName)
    }

    private var iconName: String {
        if section == .accessibility {
            return accessibilityGranted ? "checkmark.shield" : "xmark.shield"
        }
        return section.systemImage
    }
}
