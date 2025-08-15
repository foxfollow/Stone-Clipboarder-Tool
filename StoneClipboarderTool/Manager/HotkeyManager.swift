//
//  HotkeyManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import AppKit
import Carbon
import Foundation
import SwiftData

@MainActor
class HotkeyManager: ObservableObject {
    @Published var hotkeyConfigs: [HotkeyConfig] = []

    private var registeredHotkeys: [UInt32: EventHotKeyRef] = [:]
    private var hotkeyActions: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var cbViewModel: CBViewModel?
    private var modelContext: ModelContext?
    private var settingsManager: SettingsManager?

    weak var quickPickerDelegate: QuickPickerDelegate?

    init() {
        setupEventHandler()
    }

    deinit {
        // Unregister hotkeys synchronously in deinit
        for (_, hotKeyRef) in registeredHotkeys {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotkeys.removeAll()
        hotkeyActions.removeAll()

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setCBViewModel(_ viewModel: CBViewModel) {
        self.cbViewModel = viewModel
    }

    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let callback: EventHandlerProcPtr = { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData,
                let theEvent = theEvent
            else {
                return noErr
            }

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
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &eventHandler)

        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }

    private func handleHotkeyPressed(_ hotkeyID: UInt32) {
        guard let settingsManager = settingsManager,
            settingsManager.enableHotkeys
        else {
            return
        }

        guard let action = hotkeyActions[hotkeyID] else {
            return
        }

        action()
    }

    // MARK: - Configuration Management

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

            refreshHotkeyRegistrations()

        } catch {
            print("Failed to load hotkey configs: \(error)")
            createDefaultHotkeyConfigs()
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
            refreshHotkeyRegistrations()
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
            let descriptor = FetchDescriptor<HotkeyConfig>(sortBy: [
                SortDescriptor(\.timestamp, order: .forward)
            ])
            hotkeyConfigs = try modelContext.fetch(descriptor)
            refreshHotkeyRegistrations()
        } catch {
            print("Failed to update hotkey config: \(error)")
        }
    }

    // MARK: - Hotkey Registration

    @MainActor
    func refreshHotkeyRegistrations() {
        unregisterAllHotkeys()

        guard let settingsManager = settingsManager,
            settingsManager.enableHotkeys
        else {
            return
        }

        for config in hotkeyConfigs {
            guard config.isEnabled,
                let action = config.hotkeyAction,
                let shortcut = config.shortcutKeys,
                !shortcut.isEmpty,
                shortcut != "None"
            else {
                continue
            }

            registerHotkeyFromConfig(config: config, action: action, shortcut: shortcut)
        }
    }

    @MainActor
    private func registerHotkeyFromConfig(
        config: HotkeyConfig, action: HotkeyAction, shortcut: String
    ) {
        guard let (keyCode, modifiers) = parseShortcut(shortcut) else {
            print("Failed to parse shortcut: \(shortcut), setting to None")
            // Set invalid shortcuts to None
            config.shortcutKeys = "None"
            return
        }

        let actionClosure: () -> Void

        switch action {
        case .mainPanel:
            actionClosure = { [weak self] in
                self?.showQuickPicker()
            }
        case .last1, .last2, .last3, .last4, .last5, .last6, .last7, .last8, .last9, .last0:
            let index = action.index
            actionClosure = { [weak self] in
                self?.executeLastItemAction(index: index)
            }
        case .fav1, .fav2, .fav3, .fav4, .fav5, .fav6, .fav7, .fav8, .fav9, .fav0:
            let index = action.index
            actionClosure = { [weak self] in
                self?.executeFavoriteAction(index: index)
            }
        }

        registerHotkey(keyCode: keyCode, modifiers: modifiers, action: actionClosure)
    }

    @MainActor
    private func registerHotkey(
        keyCode: UInt32, modifiers: [KeyModifier], action: @escaping () -> Void
    ) {
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

        if status == noErr, let hotKeyRef = eventHotKeyRef {
            registeredHotkeys[hotkeyID] = hotKeyRef
            hotkeyActions[hotkeyID] = action
        } else {
            print("Failed to register hotkey: keyCode=\(keyCode), status=\(status)")
        }
    }

    @MainActor
    private func unregisterAllHotkeys() {
        for (_, hotKeyRef) in registeredHotkeys {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotkeys.removeAll()
        hotkeyActions.removeAll()
    }

    private func generateHotkeyID(keyCode: UInt32, modifiers: UInt32) -> UInt32 {
        return (modifiers << 16) | keyCode
    }

    // MARK: - Shortcut Parsing

    private func parseShortcut(_ shortcut: String) -> (keyCode: UInt32, modifiers: [KeyModifier])? {
        let components = shortcut.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .joined()

        var modifiers: [KeyModifier] = []
        var keyChar = ""

        for char in components {
            switch char {
            case "⌃":
                modifiers.append(.control)
            case "⌥":
                modifiers.append(.option)
            case "⇧":
                modifiers.append(.shift)
            case "⌘":
                modifiers.append(.command)
            default:
                keyChar.append(char)
            }
        }

        // Must have both modifiers and a key character
        guard !modifiers.isEmpty, !keyChar.isEmpty, let keyCode = keyCodeForCharacter(keyChar)
        else {
            return nil
        }

        return (keyCode, modifiers)
    }

    private func keyCodeForCharacter(_ character: String) -> UInt32? {
        switch character.lowercased() {
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "0": return 29
        case "space": return 49
        case "a": return 0
        case "b": return 11
        case "c": return 8
        case "d": return 2
        case "e": return 14
        case "f": return 3
        case "g": return 5
        case "h": return 4
        case "i": return 34
        case "j": return 38
        case "k": return 40
        case "l": return 37
        case "m": return 46
        case "n": return 45
        case "o": return 31
        case "p": return 35
        case "q": return 12
        case "r": return 15
        case "s": return 1
        case "t": return 17
        case "u": return 32
        case "v": return 9
        case "w": return 13
        case "x": return 7
        case "y": return 16
        case "z": return 6
        default: return nil
        }
    }

    // MARK: - Actions

    private func showQuickPicker() {
        quickPickerDelegate?.showQuickPicker()
    }

    private func executeLastItemAction(index: Int) {
        guard let cbViewModel = cbViewModel,
            let settingsManager = settingsManager
        else {
            return
        }

        guard index >= 0 && index < settingsManager.maxLastItems else {
            return
        }

        let items = cbViewModel.recentItems
        guard index < items.count else {
            return
        }

        let item = items[index]
        Task { @MainActor in
            pasteItemToActiveApplication(item)
        }
    }

    private func executeFavoriteAction(index: Int) {
        guard let cbViewModel = cbViewModel,
            let settingsManager = settingsManager
        else {
            return
        }

        guard index >= 0 && index < settingsManager.maxFavoriteItems else {
            return
        }

        let favoriteItems = cbViewModel.favoriteItems
        guard index < favoriteItems.count else {
            return
        }

        let item = favoriteItems[index]
        Task { @MainActor in
            pasteItemToActiveApplication(item)
        }
    }

    @MainActor
    private func pasteItemToActiveApplication(_ item: CBItem) {
        guard let cbViewModel = cbViewModel else {
            return
        }

        guard !item.displayContent.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var copySuccessful = false

        switch item.itemType {
        case .text:
            if let content = item.content,
                !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                pasteboard.setString(content, forType: .string)
                copySuccessful = true
            }
        case .image:
            if let imageData = item.imageData,
                !imageData.isEmpty,
                let image = NSImage(data: imageData)
            {
                pasteboard.writeObjects([image])
                copySuccessful = true
            }
        case .file:
            if let fileData = item.fileData,
                !fileData.isEmpty,
                let fileName = item.fileName,
                !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(fileName)
                do {
                    try fileData.write(to: tempFile)
                    pasteboard.writeObjects([tempFile as NSURL])
                    copySuccessful = true
                } catch {
                    print("Failed to write temp file: \(error)")
                }
            }
        }

        if copySuccessful {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.simulatePasteKeyPress()
            }

            Task { @MainActor in
                guard let viewModel = self.cbViewModel else { return }
                viewModel.copyAndUpdateItem(item)

            }
        }
    }

    private func simulatePasteKeyPress() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        guard
            let keyDownEvent = CGEvent(
                keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return
        }

        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand

        keyDownEvent.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyUpEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Helper Methods

    private func fourCharCodeFrom(_ string: String) -> FourCharCode {
        guard !string.isEmpty else {
            return OSType(0x5343_4254)
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
