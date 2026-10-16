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

    nonisolated(unsafe) private var registeredHotkeys: [UInt32: EventHotKeyRef] = [:]
    nonisolated(unsafe) private var hotkeyActions: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private var cbViewModel: CBViewModel?
    private var modelContext: ModelContext?
    private var settingsManager: SettingsManager?
    private weak var pinManager: PinManager?

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

    func setPinManager(_ manager: PinManager) {
        self.pinManager = manager
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
            ErrorLogger.shared.log("Failed to install hotkey event handler (OSStatus \(status))", category: "Hotkeys")
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
            } else {
                // Migrate: on upgrades, ensure every HotkeyAction has a row.
                // New actions (e.g. pin shortcuts added in a later version)
                // wouldn't otherwise be registerable.
                ensureMissingHotkeyConfigs()
            }
            clearUnusableShortcuts()

            refreshHotkeyRegistrations()

        } catch {
            ErrorLogger.shared.log("Failed to load hotkey configs", category: "SwiftData", error: error)
            createDefaultHotkeyConfigs()
        }
    }

    private func ensureMissingHotkeyConfigs() {
        guard let modelContext = modelContext else { return }
        let existingActions = Set(hotkeyConfigs.compactMap { $0.hotkeyAction })
        let missing = HotkeyAction.allCases.filter { !existingActions.contains($0) }
        guard !missing.isEmpty else { return }

        for action in missing {
            let config = HotkeyConfig(action: action)
            modelContext.insert(config)
            hotkeyConfigs.append(config)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to add missing hotkey configs", category: "SwiftData", error: error)
        }
    }

    /// Stored shortcuts that can't be registered — e.g. keys recorded by older
    /// versions whose recorder accepted more keys than registration knew, or
    /// the legacy "None" string — become nil, which the UI shows as "None".
    /// Done once at load so registration never has to touch the model.
    private func clearUnusableShortcuts() {
        guard let modelContext = modelContext else { return }
        let unusable = hotkeyConfigs.filter { config in
            config.shortcutKeys != nil && HotkeyShortcut(config.shortcutKeys) == nil
        }
        guard !unusable.isEmpty else { return }

        for config in unusable {
            if let keys = config.shortcutKeys, !keys.isEmpty, keys != "None" {
                ErrorLogger.shared.log(
                    "Cleared unusable shortcut \(keys) for \(config.action)", category: "Hotkeys")
            }
            config.shortcutKeys = nil
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to clear unusable shortcuts", category: "SwiftData", error: error)
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to create default hotkey configs", category: "SwiftData", error: error)
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
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to update hotkey config", category: "SwiftData", error: error)
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
                let shortcut = HotkeyShortcut(config.shortcutKeys)
            else {
                continue
            }

            registerHotkey(shortcut, for: action)
        }
    }

    private func registerHotkey(_ shortcut: HotkeyShortcut, for action: HotkeyAction) {
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
        case .togglePinLastItem:
            actionClosure = { [weak self] in
                self?.pinManager?.togglePinForLastItem()
            }
        case .dismissAllPins:
            actionClosure = { [weak self] in
                self?.pinManager?.dismissAll()
            }
        }

        let keyCode = UInt32(shortcut.keyCode)
        let modifierFlags = shortcut.carbonModifiers
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
            hotkeyActions[hotkeyID] = actionClosure
        } else {
            ErrorLogger.shared.log(
                "Failed to register hotkey \(shortcut.stringValue) (OSStatus \(status))", category: "Hotkeys")
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

        pasteItemToActiveApplication(items[index])
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

        pasteItemToActiveApplication(favoriteItems[index])
    }

    private func pasteItemToActiveApplication(_ item: CBItem) {
        // Through the view model → ClipboardManager, which records the new
        // pasteboard change count so the monitor doesn't capture our own write
        // (an image written here used to come back as a duplicate item). It
        // also moves the item to the top of the history.
        guard let cbViewModel, cbViewModel.copyAndUpdateItem(item) else { return }
        PasteSimulator.paste()
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

// MARK: - Protocol

@MainActor
protocol QuickPickerDelegate: AnyObject {
    func showQuickPicker()
}
