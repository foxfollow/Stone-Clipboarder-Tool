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

    @State private var selectedSection: SettingsSection
    @State private var showAutoStartPrompt = false
    @State private var accessibilityGranted = AccessibilityAlertHelper.isAccessibilityGranted
    /// The sidebar's search field.
    @State private var searchText = ""
    /// Rows the last picked search result points at.
    @State private var highlight = SettingsHighlight()

    /// `initialSection` opens another page first (the landing screenshots).
    init(updater: SPUUpdater?, initialSection: SettingsSection = .general) {
        self.updater = updater
        _selectedSection = State(initialValue: initialSection)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selectedSection: $selectedSection,
                accessibilityGranted: accessibilityGranted,
                appVersion: appVersion,
                searchResults: searchResults,
                onPickResult: pick
            )
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetail(
                section: selectedSection,
                updater: updater,
                accessibilityGranted: $accessibilityGranted,
                highlight: highlight
            )
            .navigationTitle(selectedSection.title)
            .toolbar(removing: .sidebarToggle)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")
        .onSubmit(of: .search) {
            if let first = searchResults?.first { pick(first) }
        }
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

    /// nil while the search field is empty: the sidebar lists the pages.
    private var searchResults: [SettingsSearchEntry]? {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let entries = SettingsSearchIndex.entries(categories: settingsManager.itemCategories)
        return SettingsSearchIndex.search(searchText, in: entries)
    }

    /// Opens the result's page, scrolls to its row and lights it up for a
    /// moment. The search text stays, so the next result is one click away.
    private func pick(_ entry: SettingsSearchEntry) {
        selectedSection = entry.section
        let targets = [entry.parentAnchor, entry.anchor].compactMap { $0 }
        let picked = SettingsHighlight(anchors: Set(targets), scrollTargets: targets)
        highlight = picked
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if highlight.token == picked.token {
                highlight = SettingsHighlight()
            }
        }
    }
}
