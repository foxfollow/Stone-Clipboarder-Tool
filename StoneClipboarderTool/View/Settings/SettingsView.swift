//
//  SettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Sparkle
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    let updater: SPUUpdater?

    @State private var selectedSection: SettingsSection = .general
    @State private var showAutoStartPrompt = false
    @State private var accessibilityGranted = AccessibilityAlertHelper.isAccessibilityGranted

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selectedSection: $selectedSection,
                accessibilityGranted: accessibilityGranted,
                appVersion: appVersion
            )
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetail(
                section: selectedSection,
                updater: updater,
                accessibilityGranted: $accessibilityGranted
            )
            .navigationTitle(selectedSection.title)
            .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 540)
        .onAppear {
            if !settingsManager.hasShownAutoStartPrompt {
                settingsManager.hasShownAutoStartPrompt = true
                showAutoStartPrompt = true
            }
        }
        .alert("Launch at Login", isPresented: $showAutoStartPrompt) {
            Button("Enable") { settingsManager.startAtLogin = true }
            Button("Not Now", role: .cancel) { /* No action needed for cancel */ }
        } message: {
            Text("Would you like StoneClipboarder to start automatically when you log in?\n\nYou can change this later in Settings > Accessibility or in macOS System Settings > Login Items.")
        }
    }
}
