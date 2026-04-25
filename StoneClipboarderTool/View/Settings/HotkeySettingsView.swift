//
//  HotkeySettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import Carbon
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

        if !recordedShortcut.isEmpty && isValidShortcut(recordedShortcut) {
            // Check for duplicate shortcuts
            let existingShortcut = hotkeyManager.hotkeyConfigs.first { otherConfig in
                otherConfig.id != config.id && otherConfig.shortcutKeys == recordedShortcut
            }

            if let existing = existingShortcut {
                // Clear the existing conflicting shortcut
                existing.shortcutKeys = nil
                existing.timestamp = Date()
            }

            saveHotkeyChange(shortcut: recordedShortcut, enabled: config.isEnabled)
        } else {
            // Invalid or empty shortcut, set to None
            saveHotkeyChange(shortcut: nil, enabled: config.isEnabled)
        }

        recordedShortcut = ""
    }

    private func handleKeyEvent(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            // Don't update recordedShortcut for modifier-only changes
            break

        case .keyDown:
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if !modifiers.isEmpty, let keyString = keyStringForKeyCode(event.keyCode) {
                let shortcut = formatModifiers(modifiers) + keyString

                // Filter out common system shortcuts
                if isSystemShortcut(shortcut) {
                    blockedShortcut = shortcut
                    recordedShortcut = ""
                    // Clear blocked message after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if isRecording && blockedShortcut == shortcut {
                            blockedShortcut = ""
                        }
                    }
                    return
                }

                blockedShortcut = ""
                recordedShortcut = shortcut

                // Auto-stop after capturing valid combination
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isRecording && recordedShortcut == shortcut {
                        stopRecording()
                    }
                }
            }

        default:
            break
        }
    }

    private func formatModifiers(_ modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    private func keyStringForKeyCode(_ keyCode: UInt16) -> String? {
        // Static lookup table mapping key codes to display strings
        let keyCodeMap: [UInt16: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            49: "Space",
            0: "A",  11: "B", 8: "C",  2: "D",  14: "E",
            3: "F",  5: "G",  4: "H",  34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
            35: "P", 12: "Q", 15: "R", 1: "S",  17: "T",
            32: "U", 9: "V",  13: "W", 7: "X",  16: "Y",
            6: "Z",
            36: "Return", 53: "Escape", 51: "Delete",
            48: "Tab",    76: "Enter",
            123: "←",    124: "→",    125: "↓",  126: "↑",
        ]
        if let mapped = keyCodeMap[keyCode] {
            return mapped
        }
        // Fallback: try to get character from key code
        return getCharacterFromKeyCode(keyCode)
    }

    private func getCharacterFromKeyCode(_ keyCode: UInt16) -> String? {
        // Create a keyboard layout and try to get the character
        let inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard
            let layoutData = TISGetInputSourceProperty(
                inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let keyboardLayout = unsafeBitCast(
            CFDataGetBytePtr((layoutData.assumingMemoryBound(to: CFData.self) as! CFData)),
            to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualStringLength: Int = 0

        let result = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,  // no modifiers for character lookup
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &actualStringLength,
            &chars
        )

        if result == noErr && actualStringLength > 0 {
            let str = String(utf16CodeUnits: chars, count: actualStringLength).uppercased()
            return str
        }

        return nil
    }

    private func isSystemShortcut(_ shortcut: String) -> Bool {
        let systemShortcuts = [
            "⌘A", "⌘C", "⌘V", "⌘X", "⌘Z", "⌘Y", "⌘S", "⌘O", "⌘N", "⌘W", "⌘Q",
            "⌘T", "⌘R", "⌘P", "⌘F", "⌘G", "⌘H", "⌘M", "⌘,", "⌘Space",
            "⌘⇧Z", "⌘⇧T", "⌘⇧N", "⌘⇧W", "⌘⇧A", "⌘⇧S", "⌘⇧P",
            "⌃Space", "⌥Space", "⌘⌥Space", "⌘⌃Space",
            "⌘Tab", "⌘⇧Tab", "⌘`", "⌘⇧`",
        ]
        return systemShortcuts.contains(shortcut)
    }

    private func isValidShortcut(_ shortcut: String) -> Bool {
        let modifierChars: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let modifiers = shortcut.filter { modifierChars.contains($0) }
        let keys = shortcut.filter { !modifierChars.contains($0) }

        // Must have at least one modifier and one key, and not be a system shortcut
        return !modifiers.isEmpty && !keys.isEmpty && !isSystemShortcut(shortcut)
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
