//
//  HotkeySettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import SwiftUI
import SwiftData

struct HotkeySettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @State private var showingConflictAlert = false
    @State private var conflictMessage = ""

    var body: some View {
        Form {
            Section("General Hotkey Settings") {
                Toggle("Enable Global Hotkeys", isOn: $settingsManager.enableHotkeys)
                    .help("Enable or disable all global hotkeys")

                Toggle("Auto-select items on paste", isOn: $settingsManager.autoSelectOnPaste)
                    .help("Automatically select items in the main window when pasted via hotkey")

                HStack {
                    Text("Max Last Items")
                    Spacer()
                    Stepper(value: $settingsManager.maxLastItems, in: 1...10) {
                        Text("\(settingsManager.maxLastItems)")
                    }
                }
                .help("Maximum number of last items to show hotkeys for")

                HStack {
                    Text("Max Favorite Items")
                    Spacer()
                    Stepper(value: $settingsManager.maxFavoriteItems, in: 1...10) {
                        Text("\(settingsManager.maxFavoriteItems)")
                    }
                }
                .help("Maximum number of favorite items to show hotkeys for")
            }

            Section("Quick Picker") {
                if let mainPanelConfig = hotkeyManager.hotkeyConfigs.first(where: { $0.hotkeyAction == .mainPanel }) {
                    HotkeyConfigRow(config: mainPanelConfig)
                }
            }

            Section("Last Items Hotkeys") {
                ForEach(lastItemConfigs, id: \.id) { config in
                    HotkeyConfigRow(config: config)
                }
            }

            Section("Favorite Items Hotkeys") {
                ForEach(favoriteItemConfigs, id: \.id) { config in
                    HotkeyConfigRow(config: config)
                }
            }

            Section {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hotkey Settings")
        .alert("Hotkey Conflict", isPresented: $showingConflictAlert) {
            Button("OK") {}
        } message: {
            Text(conflictMessage)
        }
    }

    private var lastItemConfigs: [HotkeyConfig] {
        hotkeyManager.hotkeyConfigs
            .filter { $0.hotkeyAction?.isLastAction == true }
            .sorted { config1, config2 in
                (config1.hotkeyAction?.index ?? 0) < (config2.hotkeyAction?.index ?? 0)
            }
    }

    private var favoriteItemConfigs: [HotkeyConfig] {
        hotkeyManager.hotkeyConfigs
            .filter { $0.hotkeyAction?.isFavoriteAction == true }
            .sorted { config1, config2 in
                (config1.hotkeyAction?.index ?? 0) < (config2.hotkeyAction?.index ?? 0)
            }
    }

    private func resetToDefaults() {
        for config in hotkeyManager.hotkeyConfigs {
            if let action = config.hotkeyAction {
                hotkeyManager.updateHotkeyConfig(
                    config,
                    shortcutKeys: action.defaultShortcut,
                    isEnabled: true
                )
            }
        }
    }
}

struct HotkeyConfigRow: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var settingsManager: SettingsManager
    let config: HotkeyConfig
    @State private var isRecording = false
    @State private var currentKeys = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.hotkeyAction?.displayName ?? "Unknown")
                    .font(.system(size: 14, weight: .medium))

                if !config.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { config.isEnabled && settingsManager.enableHotkeys },
                set: { enabled in
                    hotkeyManager.updateHotkeyConfig(
                        config,
                        shortcutKeys: config.shortcutKeys,
                        isEnabled: enabled
                    )
                }
            ))
            .toggleStyle(.switch)
            .disabled(!settingsManager.enableHotkeys)

            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Text(isRecording ? "Recording..." : (config.shortcutKeys ?? "None"))
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!settingsManager.enableHotkeys)
        }
        .opacity(settingsManager.enableHotkeys ? 1.0 : 0.6)
    }

    private func startRecording() {
        isRecording = true
        currentKeys = ""

        // TODO: Implement actual key recording logic
        // For now, we'll simulate it
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            stopRecording()
        }
    }

    private func stopRecording() {
        isRecording = false

        // If we recorded keys, update the config
        if !currentKeys.isEmpty {
            hotkeyManager.updateHotkeyConfig(
                config,
                shortcutKeys: currentKeys,
                isEnabled: config.isEnabled
            )
        }
    }
}

#Preview {
    let hotkeyManager = HotkeyManager()
    let settingsManager = SettingsManager()

    NavigationView {
        HotkeySettingsView()
            .environmentObject(hotkeyManager)
            .environmentObject(settingsManager)
    }
}
