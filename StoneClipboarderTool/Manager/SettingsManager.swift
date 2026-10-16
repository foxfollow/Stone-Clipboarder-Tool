//
//  SettingsManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Foundation
import ServiceManagement

@MainActor
final class SettingsManager: ObservableObject {
    /// Where every setting is persisted. `.standard` in the app; tests pass an
    /// isolated suite so they never touch the real preferences.
    private let defaults: UserDefaults

    @Published var showInMenubar: Bool {
        didSet {
            // Invariant: at least one of showInMenubar / showMainWindow must stay true,
            // otherwise the app becomes inaccessible (no menubar icon, no Dock icon, no Cmd+Tab).
            if !showInMenubar && !showMainWindow {
                showMainWindow = true
            }
            defaults.set(showInMenubar, forKey: "showInMenubar")
        }
    }

    @Published var showMainWindow: Bool {
        didSet {
            if !showMainWindow && !showInMenubar {
                showInMenubar = true
            }
            defaults.set(showMainWindow, forKey: "showMainWindow")
        }
    }

    @Published var confirmQuitOnCmdQ: Bool {
        didSet {
            defaults.set(confirmQuitOnCmdQ, forKey: "confirmQuitOnCmdQ")
        }
    }

    @Published var closeOtherWindowsOnQuickPicker: Bool {
        didSet {
            defaults.set(closeOtherWindowsOnQuickPicker, forKey: "closeOtherWindowsOnQuickPicker")
        }
    }

    @Published var maxLastItems: Int {
        didSet {
            defaults.set(maxLastItems, forKey: "maxLastItems")
        }
    }

    @Published var maxFavoriteItems: Int {
        didSet {
            defaults.set(maxFavoriteItems, forKey: "maxFavoriteItems")
        }
    }

    @Published var enableHotkeys: Bool {
        didSet {
            defaults.set(enableHotkeys, forKey: "enableHotkeys")
        }
    }

    @Published var enableAutoCleanup: Bool {
        didSet {
            defaults.set(enableAutoCleanup, forKey: "enableAutoCleanup")
        }
    }

    @Published var maxItemsToKeep: Int {
        didSet {
            defaults.set(maxItemsToKeep, forKey: "maxItemsToKeep")
        }
    }

    @Published var menuBarDisplayLimit: Int {
        didSet {
            defaults.set(menuBarDisplayLimit, forKey: "menuBarDisplayLimit")
        }
    }

    @Published var enableMemoryCleanup: Bool {
        didSet {
            defaults.set(enableMemoryCleanup, forKey: "enableMemoryCleanup")
        }
    }

    @Published var memoryCleanupInterval: Int {
        didSet {
            defaults.set(memoryCleanupInterval, forKey: "memoryCleanupInterval")
        }
    }

    @Published var maxInactiveTime: Int {
        didSet {
            defaults.set(maxInactiveTime, forKey: "maxInactiveTime")
        }
    }

    @Published var clipboardCaptureMode: ClipboardCaptureMode {
        didSet {
            defaults.set(clipboardCaptureMode.rawValue, forKey: "clipboardCaptureMode")
        }
    }

    @Published var enableAppExclusion: Bool {
        didSet {
            defaults.set(enableAppExclusion, forKey: "enableAppExclusion")
        }
    }

    @Published var lastPauseDuration: Int {
        didSet {
            defaults.set(lastPauseDuration, forKey: "lastPauseDuration")
        }
    }

    @Published var enableErrorFileLogging: Bool {
        didSet {
            defaults.set(enableErrorFileLogging, forKey: ErrorLogger.enableFileLoggingKey)
        }
    }

    @Published var quickLookMode: QuickLookMode {
        didSet {
            defaults.set(quickLookMode.rawValue, forKey: "quickLookMode")
        }
    }

    @Published var quickLookTriggerKey: QuickLookTriggerKey {
        didSet {
            defaults.set(quickLookTriggerKey.rawValue, forKey: "quickLookTriggerKey")
        }
    }

    @Published var enableOCROptionKey: Bool {
        didSet {
            defaults.set(enableOCROptionKey, forKey: "enableOCROptionKey")
        }
    }

    /// Delay in milliseconds between each synthetic keystroke when using the
    /// Quick Picker's type-out paste (⌘⇧Return). Higher = slower/steadier for
    /// text fields that drop characters; 0 = as fast as possible.
    @Published var typePasteCharDelayMs: Int {
        didSet {
            if typePasteCharDelayMs < 0 {
                typePasteCharDelayMs = 0  // re-enters didSet once, then persists
                return
            }
            defaults.set(typePasteCharDelayMs, forKey: "typePasteCharDelayMs")
        }
    }

    @Published var startAtLogin: Bool {
        didSet {
            defaults.set(startAtLogin, forKey: "startAtLogin")
            updateLoginItem()
        }
    }

    @Published var hasShownAutoStartPrompt: Bool {
        didSet {
            defaults.set(hasShownAutoStartPrompt, forKey: "hasShownAutoStartPrompt")
        }
    }

    // MARK: - Pin settings
    // Defaults are applied at pin-creation time. Per-pin state (opacity, lock,
    // click-through, size, etc.) is then stored on the PinnedItemConfig so
    // toggling a global default doesn't yank already-open pins around.

    @Published var pinPersistAcrossLaunches: Bool {
        didSet { defaults.set(pinPersistAcrossLaunches, forKey: "pinPersistAcrossLaunches") }
    }

    @Published var pinAlwaysShowChrome: Bool {
        didSet { defaults.set(pinAlwaysShowChrome, forKey: "pinAlwaysShowChrome") }
    }

    @Published var pinShowOverFullscreen: Bool {
        didSet {
            defaults.set(pinShowOverFullscreen, forKey: "pinShowOverFullscreen")
            NotificationCenter.default.post(name: .pinBehaviorSettingsChanged, object: nil)
        }
    }

    @Published var pinSnapToScreenEdges: Bool {
        didSet { defaults.set(pinSnapToScreenEdges, forKey: "pinSnapToScreenEdges") }
    }

    @Published var pinShadowEnabled: Bool {
        didSet {
            defaults.set(pinShadowEnabled, forKey: "pinShadowEnabled")
            NotificationCenter.default.post(name: .pinBehaviorSettingsChanged, object: nil)
        }
    }

    @Published var pinMaxConcurrent: Int {
        didSet {
            if pinMaxConcurrent < 0 {
                pinMaxConcurrent = 0  // re-enters didSet once, then persists
                return
            }
            defaults.set(pinMaxConcurrent, forKey: "pinMaxConcurrent")
        }
    }

    @Published var pinCornerRadius: Double {
        didSet {
            defaults.set(pinCornerRadius, forKey: "pinCornerRadius")
            NotificationCenter.default.post(name: .pinBehaviorSettingsChanged, object: nil)
        }
    }

    @Published var pinDefaultOpacity: Double {
        didSet { defaults.set(pinDefaultOpacity, forKey: "pinDefaultOpacity") }
    }

    @Published var pinDefaultTextWidth: Double {
        didSet { defaults.set(pinDefaultTextWidth, forKey: "pinDefaultTextWidth") }
    }

    @Published var pinDefaultTextHeight: Double {
        didSet { defaults.set(pinDefaultTextHeight, forKey: "pinDefaultTextHeight") }
    }

    @Published var pinDefaultImageWidth: Double {
        didSet { defaults.set(pinDefaultImageWidth, forKey: "pinDefaultImageWidth") }
    }

    @Published var pinDefaultImageHeight: Double {
        didSet { defaults.set(pinDefaultImageHeight, forKey: "pinDefaultImageHeight") }
    }

    @Published var pinDefaultFileWidth: Double {
        didSet { defaults.set(pinDefaultFileWidth, forKey: "pinDefaultFileWidth") }
    }

    @Published var pinDefaultFileHeight: Double {
        didSet { defaults.set(pinDefaultFileHeight, forKey: "pinDefaultFileHeight") }
    }

    @Published var pinAllowTextEdit: Bool {
        didSet { defaults.set(pinAllowTextEdit, forKey: "pinAllowTextEdit") }
    }

    @Published var pinDismissAllConfirm: Bool {
        didSet { defaults.set(pinDismissAllConfirm, forKey: "pinDismissAllConfirm") }
    }

    /// When true, opening the Quick Picker also hides pinned windows. Default
    /// false so pins survive the picker (they're meant to stay on top).
    @Published var pinQuickPickerDismissesPins: Bool {
        didSet { defaults.set(pinQuickPickerDismissesPins, forKey: "pinQuickPickerDismissesPins") }
    }

    func updateLoginItem() {
        do {
            if startAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            ErrorLogger.shared.log("Failed to update login item", category: "LoginItem", error: error)
        }
    }

    var loginItemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showInMenubar = defaults.bool(forKey: "showInMenubar")
        self.showMainWindow = defaults.bool(forKey: "showMainWindow")
        self.confirmQuitOnCmdQ = defaults.object(forKey: "confirmQuitOnCmdQ") as? Bool ?? false
        self.closeOtherWindowsOnQuickPicker = defaults.object(forKey: "closeOtherWindowsOnQuickPicker") as? Bool ?? true
        self.maxLastItems = defaults.object(forKey: "maxLastItems") as? Int ?? 10
        self.maxFavoriteItems =
            defaults.object(forKey: "maxFavoriteItems") as? Int ?? 10
        self.enableHotkeys = defaults.object(forKey: "enableHotkeys") as? Bool ?? true
        self.enableAutoCleanup =
            defaults.object(forKey: "enableAutoCleanup") as? Bool ?? true
        self.maxItemsToKeep = defaults.object(forKey: "maxItemsToKeep") as? Int ?? 300
        self.menuBarDisplayLimit =
            defaults.object(forKey: "menuBarDisplayLimit") as? Int ?? 10
        self.enableMemoryCleanup =
            defaults.object(forKey: "enableMemoryCleanup") as? Bool ?? true
        self.memoryCleanupInterval =
            defaults.object(forKey: "memoryCleanupInterval") as? Int ?? 5
        self.maxInactiveTime =
            defaults.object(forKey: "maxInactiveTime") as? Int ?? 30
        self.enableAppExclusion = defaults.object(forKey: "enableAppExclusion") as? Bool ?? false
        self.lastPauseDuration = defaults.object(forKey: "lastPauseDuration") as? Int ?? 300 // Default 5 minutes
        self.enableErrorFileLogging = defaults.bool(forKey: ErrorLogger.enableFileLoggingKey) // Default false

        if let savedQLMode = defaults.string(forKey: "quickLookMode"),
           let mode = QuickLookMode(rawValue: savedQLMode) {
            self.quickLookMode = mode
        } else {
            self.quickLookMode = .native
        }

        if let savedTrigger = defaults.string(forKey: "quickLookTriggerKey"),
           let trigger = QuickLookTriggerKey(rawValue: savedTrigger) {
            self.quickLookTriggerKey = trigger
        } else {
            self.quickLookTriggerKey = .space
        }

        self.enableOCROptionKey = defaults.object(forKey: "enableOCROptionKey") as? Bool ?? true
        self.typePasteCharDelayMs = defaults.object(forKey: "typePasteCharDelayMs") as? Int ?? 5
        self.startAtLogin = defaults.object(forKey: "startAtLogin") as? Bool ?? false
        self.hasShownAutoStartPrompt = defaults.object(forKey: "hasShownAutoStartPrompt") as? Bool ?? false

        // Pin settings
        self.pinPersistAcrossLaunches = defaults.object(forKey: "pinPersistAcrossLaunches") as? Bool ?? true
        self.pinAlwaysShowChrome = defaults.object(forKey: "pinAlwaysShowChrome") as? Bool ?? false
        self.pinShowOverFullscreen = defaults.object(forKey: "pinShowOverFullscreen") as? Bool ?? true
        self.pinSnapToScreenEdges = defaults.object(forKey: "pinSnapToScreenEdges") as? Bool ?? false
        self.pinShadowEnabled = defaults.object(forKey: "pinShadowEnabled") as? Bool ?? true
        self.pinMaxConcurrent = defaults.object(forKey: "pinMaxConcurrent") as? Int ?? 10
        self.pinCornerRadius = defaults.object(forKey: "pinCornerRadius") as? Double ?? 10
        self.pinDefaultOpacity = defaults.object(forKey: "pinDefaultOpacity") as? Double ?? 1.0
        self.pinDefaultTextWidth = defaults.object(forKey: "pinDefaultTextWidth") as? Double ?? 360
        self.pinDefaultTextHeight = defaults.object(forKey: "pinDefaultTextHeight") as? Double ?? 240
        self.pinDefaultImageWidth = defaults.object(forKey: "pinDefaultImageWidth") as? Double ?? 500
        self.pinDefaultImageHeight = defaults.object(forKey: "pinDefaultImageHeight") as? Double ?? 500
        self.pinDefaultFileWidth = defaults.object(forKey: "pinDefaultFileWidth") as? Double ?? 280
        self.pinDefaultFileHeight = defaults.object(forKey: "pinDefaultFileHeight") as? Double ?? 120
        self.pinAllowTextEdit = defaults.object(forKey: "pinAllowTextEdit") as? Bool ?? false
        self.pinDismissAllConfirm = defaults.object(forKey: "pinDismissAllConfirm") as? Bool ?? false
        self.pinQuickPickerDismissesPins = defaults.object(forKey: "pinQuickPickerDismissesPins") as? Bool ?? false

        // Migrate from old preferTextOverImage setting to new clipboardCaptureMode
        if let savedModeString = defaults.string(forKey: "clipboardCaptureMode"),
           let savedMode = ClipboardCaptureMode(rawValue: savedModeString) {
            self.clipboardCaptureMode = savedMode
        } else if let oldPreference = defaults.object(forKey: "preferTextOverImage") as? Bool {
            // Migrate old boolean setting: true = textOnly, false = imageOnly
            self.clipboardCaptureMode = oldPreference ? .textOnly : .imageOnly
            defaults.set(self.clipboardCaptureMode.rawValue, forKey: "clipboardCaptureMode")
            defaults.removeObject(forKey: "preferTextOverImage")
        } else {
            // Default to textOnly for new installations
            self.clipboardCaptureMode = .textOnly
        }

        // Default to showing menubar if first launch
        if defaults.object(forKey: "showInMenubar") == nil {
            self.showInMenubar = true
        }

        // Default to showing main window if first launch
        if defaults.object(forKey: "showMainWindow") == nil {
            self.showMainWindow = true
        }

        // The Quick Picker position was once written here although it only
        // lives for a session now (QuickPickerWindowManager.lastOrigin).
        for legacyKey in ["QuickPickerWindowX", "QuickPickerWindowY", "QuickPickerHasValidPosition"] {
            defaults.removeObject(forKey: legacyKey)
        }

        // Invariant repair: if persisted state has both disabled (e.g. manual defaults edit),
        // restore main-window visibility so the app stays reachable.
        if !self.showInMenubar && !self.showMainWindow {
            self.showMainWindow = true
        }
    }
}
