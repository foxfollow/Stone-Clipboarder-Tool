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
            Button("OK") {}
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
        .opacity(
            settingsManager.enableHotkeys
                ? (currentlyRecordingID != nil && currentlyRecordingID != config.id ? 0.4 : 1.0)
                : 0.6
        )
        .animation(.easeInOut(duration: 0.2), value: currentlyRecordingID)
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
        if isRecording {
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
        } else {
            let shortcut = config.shortcutKeys ?? ""
            return shortcut.isEmpty ? "None" : shortcut
        }
    }

    private var backgroundColor: Color {
        if isRecording {
            if !blockedShortcut.isEmpty {
                return Color.red.opacity(0.3)
            } else {
                return Color.accentColor.opacity(0.3)
            }
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

        switch keyCode {
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 49: return "Space"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        case 36: return "Return"
        case 53: return "Escape"
        case 51: return "Delete"
        case 48: return "Tab"
        case 76: return "Enter"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:

            // Fallback: try to get character from key code
            return getCharacterFromKeyCode(keyCode)
        }
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
