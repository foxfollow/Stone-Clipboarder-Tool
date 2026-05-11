//
//  SettingsDetail.swift
//  StoneClipboarderTool
//

import Sparkle
import SwiftUI

struct SettingsDetail: View {
    let section: SettingsSection
    let updater: SPUUpdater?
    @Binding var accessibilityGranted: Bool

    var body: some View {
        SettingsDetailContainer(subtitle: section.subtitle) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .general:       GeneralSettingsView()
        case .hotkeys:       HotkeySettingsView()
        case .excludedApps:  ExcludedAppsSettingsView()
        case .accessibility: AccessibilitySettingsView(accessibilityGranted: $accessibilityGranted)
        case .about:         AboutSettingsView(updater: updater)
        }
    }
}
