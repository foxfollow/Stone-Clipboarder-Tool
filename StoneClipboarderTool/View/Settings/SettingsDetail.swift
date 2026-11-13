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
    var highlight = SettingsHighlight()

    var body: some View {
        SettingsDetailContainer(subtitle: section.subtitle, highlight: highlight) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .general:       GeneralSettingsView()
        case .hotkeys:       HotkeySettingsView()
        case .quickPicker:   QuickPickerSettingsView()
        case .categories:    CategoriesSettingsView()
        case .pins:          PinSettingsView()
        case .excludedApps:  ExcludedAppsSettingsView()
        case .accessibility: AccessibilitySettingsView(accessibilityGranted: $accessibilityGranted)
        case .about:         AboutSettingsView(updater: updater)
        }
    }
}
