//
//  HotkeyManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import Foundation
import Carbon
import AppKit
import SwiftData

@MainActor
class HotkeyManager: ObservableObject {
    @Published var hotkeyConfigs: [HotkeyConfig] = []

    private var registeredHotkeys: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var cbViewModel: CBViewModel?
    private var modelContext: ModelContext?

    weak var quickPickerDelegate: QuickPickerDelegate?

    init() {
        setupEventHandler()
    }

    deinit {
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
        registeredHotkeys.removeAll()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadHotkeyConfigs()
    }

    func setCBViewModel(_ viewModel: CBViewModel) {
        self.cbViewModel = viewModel
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let callback: EventHandlerProcPtr = { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData,
                  let theEvent = theEvent else {
                print("Invalid event handler parameters")
                return noErr
            }

            do {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    theEvent,
                    OSType(kEventParamDirectObject),
                    OSType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                if status == noErr {
                    Task { @MainActor in
                        manager.handleHotkeyPressed(hotkeyID.id)
                    }
                } else {
                    print("Failed to get hotkey ID from event: \(status)")
                }
            } catch {
                print("Error in hotkey callback: \(error)")
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &eventHandler)

        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }

    private func handleHotkeyPressed(_ hotkeyID: UInt32) {
        guard let action = registeredHotkeys[hotkeyID] else {
            print("No action found for hotkey ID: \(hotkeyID)")
            return
        }

        do {
            action()
        } catch {
            print("Error executing hotkey action: \(error)")
        }
    }

    // MARK: - Public Methods

    func registerDefaultHotkeys() {
        // Quick picker
        registerHotkey(keyCode: 49, modifiers: [.control, .option]) { [weak self] in
            self?.showQuickPicker()
        }

        // Last items (Ctrl+Option+1-0)
        registerLastItemHotkeys()

        // Favorites (Ctrl+Shift+1-0)
        registerFavoriteHotkeys()
    }

    private func registerLastItemHotkeys() {
        let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] // 1-9,0

        for (index, keyCode) in keyCodes.enumerated() {
            registerHotkey(keyCode: keyCode, modifiers: [.control, .option]) { [weak self] in
                self?.executeLastItemAction(index: index)
            }
        }
    }

    private func registerFavoriteHotkeys() {
        let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] // 1-9,0

        for (index, keyCode) in keyCodes.enumerated() {
            registerHotkey(keyCode: keyCode, modifiers: [.control, .shift]) { [weak self] in
                self?.executeFavoriteAction(index: index)
            }
        }
    }

    private func registerHotkey(keyCode: UInt32, modifiers: [KeyModifier], action: @escaping () -> Void) {
        let modifierFlags = modifiers.reduce(0) { result, modifier in
            result | modifier.carbonFlag
        }

        let hotkeyID = generateHotkeyID(keyCode: keyCode, modifiers: modifierFlags)
        var eventHotKeyRef: EventHotKeyRef?

        let eventHotkeyID = EventHotKeyID(signature: OSType(fourCharCodeFrom("SCBT")), id: hotkeyID)

        let status = RegisterEventHotKey(
            keyCode,
            modifierFlags,
            eventHotkeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )

        if status == noErr {
            registeredHotkeys[hotkeyID] = action
            print("Registered hotkey: keyCode=\(keyCode), modifiers=\(modifierFlags), id=\(hotkeyID)")
        } else {
            print("Failed to register hotkey: keyCode=\(keyCode), status=\(status)")
        }
    }

    private func generateHotkeyID(keyCode: UInt32, modifiers: UInt32) -> UInt32 {
        // Simple ID generation: combine keyCode and modifiers
        return (modifiers << 16) | keyCode
    }

    // MARK: - Actions

    private func showQuickPicker() {
        print("Showing quick picker...")
        quickPickerDelegate?.showQuickPicker()
    }

    private func executeLastItemAction(index: Int) {
        guard let cbViewModel = cbViewModel else {
            print("CBViewModel not available")
            return
        }

        guard index >= 0 && index < 10 else {
            print("Invalid index \(index) for last item action")
            return
        }

        let items = cbViewModel.recentItems
        guard index < items.count else {
            print("Index \(index) out of bounds for \(items.count) items")
            return
        }

        let item = items[index]
        print("Executing last item action for index \(index): \(item.displayContent)")

        Task { @MainActor in
            pasteItemToActiveApplication(item)
        }
    }

    private func executeFavoriteAction(index: Int) {
        guard let cbViewModel = cbViewModel else {
            print("CBViewModel not available")
            return
        }

        guard index >= 0 && index < 10 else {
            print("Invalid index \(index) for favorite action")
            return
        }

        let favoriteItems = cbViewModel.favoriteItems
        guard index < favoriteItems.count else {
            print("Index \(index) out of bounds for \(favoriteItems.count) favorite items")
            return
        }

        let item = favoriteItems[index]
        print("Executing favorite action for index \(index): \(item.displayContent)")

        Task { @MainActor in
            pasteItemToActiveApplication(item)
        }
    }

    @MainActor
    private func pasteItemToActiveApplication(_ item: CBItem) {
        guard let cbViewModel = cbViewModel else {
            print("CBViewModel not available for pasting")
            return
        }

        // Validate item
        guard !item.displayContent.isEmpty else {
            print("Item has no valid content to paste")
            return
        }

        do {
            // Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            var copySuccessful = false

            switch item.itemType {
            case .text:
                if let content = item.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pasteboard.setString(content, forType: .string)
                    copySuccessful = true
                    print("Copied text to clipboard: \(content.prefix(50))...")
                } else {
                    print("No valid text content to paste")
                    return
                }
            case .image:
                if let imageData = item.imageData,
                   !imageData.isEmpty,
                   let image = NSImage(data: imageData) {
                    pasteboard.writeObjects([image])
                    copySuccessful = true
                    print("Copied image to clipboard")
                } else {
                    print("No valid image data to paste")
                    return
                }
            case .file:
                if let fileData = item.fileData,
                   !fileData.isEmpty,
                   let fileName = item.fileName,
                   !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Create temporary file and add to pasteboard
                    let tempDir = FileManager.default.temporaryDirectory
                    let tempFile = tempDir.appendingPathComponent(fileName)
                    do {
                        try fileData.write(to: tempFile)
                        pasteboard.writeObjects([tempFile as NSURL])
                        copySuccessful = true
                        print("Copied file to clipboard: \(fileName)")
                    } catch {
                        print("Failed to write temp file: \(error)")
                        return
                    }
                } else {
                    print("No valid file data to paste")
                    return
                }
            }

            // Only simulate paste if copy was successful
            if copySuccessful {
                // Simulate Cmd+V to paste
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.simulatePasteKeyPress()
                }

                // Update item timestamp safely
                Task { @MainActor in
                    guard let viewModel = self.cbViewModel else { return }
                    viewModel.copyAndUpdateItem(item)
                }
            }
        } catch {
            print("Error pasting item: \(error)")
        }
    }

    private func simulatePasteKeyPress() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("Failed to create CGEventSource for paste simulation")
            return
        }

        // Create Cmd+V key events
        guard let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            print("Failed to create key events for paste simulation")
            return
        }

        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand

        // Post key down
        keyDownEvent.post(tap: .cghidEventTap)

        // Small delay before key up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyUpEvent.post(tap: .cghidEventTap)
        }

        print("Simulated Cmd+V paste sequence")
    }

    // MARK: - Configuration Loading

    func loadHotkeyConfigs() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<HotkeyConfig>(sortBy: [
            SortDescriptor(\.timestamp, order: .forward)
        ])

        do {
            hotkeyConfigs = try modelContext.fetch(descriptor)

            if hotkeyConfigs.isEmpty {
                createDefaultHotkeyConfigs()
            }

            // Register all hotkeys
            registerDefaultHotkeys()

        } catch {
            print("Failed to load hotkey configs: \(error)")
            createDefaultHotkeyConfigs()
            registerDefaultHotkeys()
        }
    }

    private func createDefaultHotkeyConfigs() {
        guard let modelContext = modelContext else { return }

        for action in HotkeyAction.allCases {
            let config = HotkeyConfig(action: action)
            modelContext.insert(config)
            hotkeyConfigs.append(config)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to create default hotkey configs: \(error)")
        }
    }

    func updateHotkeyConfig(_ config: HotkeyConfig, shortcutKeys: String?, isEnabled: Bool) {
        guard let modelContext = modelContext else { return }

        config.shortcutKeys = shortcutKeys
        config.isEnabled = isEnabled
        config.timestamp = Date()

        do {
            try modelContext.save()

            if let index = hotkeyConfigs.firstIndex(where: { $0.id == config.id }) {
                hotkeyConfigs[index] = config
            }
        } catch {
            print("Failed to update hotkey config: \(error)")
        }
    }

    // MARK: - Helper Methods

    private func fourCharCodeFrom(_ string: String) -> FourCharCode {
        guard !string.isEmpty else {
            print("Warning: Empty string for fourCharCode, using default")
            return OSType(0x53434254) // "SCBT"
        }

        let utf8 = string.utf8
        var bytes = Array(utf8.prefix(4))
        while bytes.count < 4 {
            bytes.append(0)
        }
        return bytes.withUnsafeBytes { ptr in
            ptr.load(as: FourCharCode.self)
        }
    }
}

// MARK: - Key Modifier Enum

enum KeyModifier {
    case control
    case option
    case shift
    case command

    var carbonFlag: UInt32 {
        switch self {
        case .control: return UInt32(controlKey)
        case .option: return UInt32(optionKey)
        case .shift: return UInt32(shiftKey)
        case .command: return UInt32(cmdKey)
        }
    }
}

// MARK: - Protocol

@MainActor
protocol QuickPickerDelegate: AnyObject {
    func showQuickPicker()
}
