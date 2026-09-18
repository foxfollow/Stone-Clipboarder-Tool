//
//  HotkeySettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import SwiftData
import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @Environment(\.modelContext) private var modelContext
    @State private var showingConflictAlert = false
    @State private var conflictMessage = ""
    @State private var currentlyRecordingID: UUID? = nil

    var body: some View {
        Form {
            Section("General Hotkey Settings") {
                Toggle("Enable Global Hotkeys", isOn: $settingsManager.enableHotkeys)
                    .help("Enable or disable all global hotkeys")

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
                if let mainPanelConfig = hotkeyManager.hotkeyConfigs.first(where: {
                    $0.hotkeyAction == .mainPanel
                }) {
                    HotkeyConfigRow(
                        config: mainPanelConfig, currentlyRecordingID: $currentlyRecordingID)
                }
            }

            Section("Pins") {
                if let pinConfig = hotkeyManager.hotkeyConfigs.first(where: {
                    $0.hotkeyAction == .togglePinLastItem
                }) {
                    HotkeyConfigRow(config: pinConfig, currentlyRecordingID: $currentlyRecordingID)
                }
                if let dismissConfig = hotkeyManager.hotkeyConfigs.first(where: {
                    $0.hotkeyAction == .dismissAllPins
                }) {
                    HotkeyConfigRow(config: dismissConfig, currentlyRecordingID: $currentlyRecordingID)
                }
            }

            Section("Last Items Hotkeys") {
                ForEach(lastItemConfigs, id: \.id) { config in
                    HotkeyConfigRow(config: config, currentlyRecordingID: $currentlyRecordingID)
                }
            }

            Section("Favorite Items Hotkeys") {
                ForEach(favoriteItemConfigs, id: \.id) { config in
                    HotkeyConfigRow(config: config, currentlyRecordingID: $currentlyRecordingID)
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
            Button("OK") { /* No action needed for acknowledgement */ }
        } message: {
            Text(conflictMessage)
        }
        .onChange(of: settingsManager.maxLastItems) { _, _ in
            hotkeyManager.refreshHotkeyRegistrations()
        }
        .onChange(of: settingsManager.maxFavoriteItems) { _, _ in
            hotkeyManager.refreshHotkeyRegistrations()
        }
    }

    private var lastItemConfigs: [HotkeyConfig] {
        hotkeyManager.hotkeyConfigs
            .filter { $0.hotkeyAction?.isLastAction == true }
            .sorted { config1, config2 in
                (config1.hotkeyAction?.index ?? 0) < (config2.hotkeyAction?.index ?? 0)
            }
            .prefix(settingsManager.maxLastItems)
            .map { $0 }
    }

    private var favoriteItemConfigs: [HotkeyConfig] {
        hotkeyManager.hotkeyConfigs
            .filter { $0.hotkeyAction?.isFavoriteAction == true }
            .sorted { config1, config2 in
                (config1.hotkeyAction?.index ?? 0) < (config2.hotkeyAction?.index ?? 0)
            }
            .prefix(settingsManager.maxFavoriteItems)
            .map { $0 }
    }

    private func resetToDefaults() {
        settingsManager.maxLastItems = 10
        settingsManager.maxFavoriteItems = 10
        settingsManager.enableHotkeys = true

        for config in hotkeyManager.hotkeyConfigs {
            if let action = config.hotkeyAction {
                config.shortcutKeys = action.defaultShortcut
                config.isEnabled = true
                config.timestamp = Date()
            }
        }

        do {
            try modelContext.save()
            hotkeyManager.refreshHotkeyRegistrations()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to reset hotkeys to defaults", category: "SwiftData", error: error)
        }
    }
}

struct HotkeyConfigRow: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.modelContext) private var modelContext
    let config: HotkeyConfig
    @Binding var currentlyRecordingID: UUID?

    @State private var isRecording = false
    @State private var recordedShortcut = ""
    @State private var eventMonitor: Any?
    @State private var globalEventMonitor: Any?
    @State private var blockedShortcut = ""

    private var rowOpacity: Double {
        let recordingOther = currentlyRecordingID != nil && currentlyRecordingID != config.id
        let dimmedForRecording = recordingOther ? 0.4 : 1.0
        return settingsManager.enableHotkeys ? dimmedForRecording : 0.6
    }

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

            Toggle(
                "",
                isOn: Binding(
                    get: { config.isEnabled },
                    set: { enabled in
                        saveHotkeyChange(shortcut: config.shortcutKeys, enabled: enabled)
                    }
                )
            )
            .toggleStyle(.switch)
            .disabled(!settingsManager.enableHotkeys || currentlyRecordingID != nil)

            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Text(displayText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isRecording ? .white : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(backgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        isRecording ? Color.accentColor : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isRecording ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
            .disabled(
                !settingsManager.enableHotkeys
                    || (currentlyRecordingID != nil && currentlyRecordingID != config.id))
        }
        .opacity(rowOpacity)
        .onDisappear {
            stopRecording()
        }
        .onChange(of: currentlyRecordingID) { _, newValue in
            if newValue != config.id && isRecording {
                stopRecording()
            }
        }
    }

    private var displayText: String {
        guard isRecording else {
            let shortcut = config.shortcutKeys ?? ""
            return shortcut.isEmpty ? "None" : shortcut
        }
        
        if !blockedShortcut.isEmpty {
            return "\(blockedShortcut) (blocked)"
        } else if recordedShortcut.isEmpty {
            return "Press keys..."
        } else {
            // Show preview with first character highlighted
            let modifierChars: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
            let modifiers = String(recordedShortcut.filter { modifierChars.contains($0) })
            let keys = String(recordedShortcut.filter { !modifierChars.contains($0) })
            if !keys.isEmpty {
                let firstChar = String(keys.prefix(1))
                return "\(modifiers)\(firstChar)..."
            } else {
                return recordedShortcut
            }
        }
    }

    private var backgroundColor: Color {
        if isRecording, !blockedShortcut.isEmpty {
            return Color.red.opacity(0.3)
        } else if isRecording {
            return Color.accentColor.opacity(0.3)
        } else if currentlyRecordingID != nil && currentlyRecordingID != config.id {
            return Color.gray.opacity(0.05)
        } else {
            return Color.gray.opacity(0.1)
        }
    }

    private func startRecording() {
        guard !isRecording && currentlyRecordingID == nil else { return }

        isRecording = true
        currentlyRecordingID = config.id
        recordedShortcut = ""
        blockedShortcut = ""

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            event in
            handleKeyEvent(event)
            return nil  // Consume ALL events during recording
        }

        // Add global monitor to catch system shortcuts
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            if isRecording {
                handleKeyEvent(event)
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        currentlyRecordingID = nil

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        if let globalMonitor = globalEventMonitor {
            NSEvent.removeMonitor(globalMonitor)
            globalEventMonitor = nil
        }

        if let shortcut = HotkeyShortcut(recordedShortcut), !shortcut.isReservedBySystem {
            // A shortcut drives one action only: take it away from any other.
            // Compared structurally, so older stored spellings still match.
            for other in hotkeyManager.hotkeyConfigs
            where other.id != config.id && HotkeyShortcut(other.shortcutKeys) == shortcut {
                other.shortcutKeys = nil
                other.timestamp = Date()
            }

            saveHotkeyChange(shortcut: shortcut.stringValue, enabled: config.isEnabled)
        } else {
            // Invalid or empty shortcut, set to None
            saveHotkeyChange(shortcut: nil, enabled: config.isEnabled)
        }

        recordedShortcut = ""
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Modifier-only changes, presses without a modifier and keys global
        // hotkeys can't use are ignored; recording just continues.
        guard event.type == .keyDown,
              let shortcut = HotkeyShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        else { return }

        let text = shortcut.stringValue
        if shortcut.isReservedBySystem {
            blockedShortcut = text
            recordedShortcut = ""
            // Clear blocked message after 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if isRecording && blockedShortcut == text {
                    blockedShortcut = ""
                }
            }
            return
        }

        blockedShortcut = ""
        recordedShortcut = text

        // Auto-stop after capturing valid combination
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if isRecording && recordedShortcut == text {
                stopRecording()
            }
        }
    }

    private func saveHotkeyChange(shortcut: String?, enabled: Bool) {
        config.shortcutKeys = shortcut
        config.isEnabled = enabled
        config.timestamp = Date()

        do {
            try modelContext.save()
            hotkeyManager.refreshHotkeyRegistrations()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to save hotkey change", category: "SwiftData", error: error)
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
