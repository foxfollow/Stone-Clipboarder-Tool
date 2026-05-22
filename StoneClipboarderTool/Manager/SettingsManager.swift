//
//  SettingsManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Foundation
import ServiceManagement

class SettingsManager: ObservableObject {
    @Published var showInMenubar: Bool {
        didSet {
            // Invariant: at least one of showInMenubar / showMainWindow must stay true,
            // otherwise the app becomes inaccessible (no menubar icon, no Dock icon, no Cmd+Tab).
            if !showInMenubar && !showMainWindow {
                showMainWindow = true
            }
            UserDefaults.standard.set(showInMenubar, forKey: "showInMenubar")
        }
    }

    @Published var showMainWindow: Bool {
        didSet {
            if !showMainWindow && !showInMenubar {
                showInMenubar = true
            }
            UserDefaults.standard.set(showMainWindow, forKey: "showMainWindow")
        }
    }

    @Published var confirmQuitOnCmdQ: Bool {
        didSet {
            UserDefaults.standard.set(confirmQuitOnCmdQ, forKey: "confirmQuitOnCmdQ")
        }
    }

    @Published var closeOtherWindowsOnQuickPicker: Bool {
        didSet {
            UserDefaults.standard.set(closeOtherWindowsOnQuickPicker, forKey: "closeOtherWindowsOnQuickPicker")
        }
    }

    @Published var maxLastItems: Int {
        didSet {
            UserDefaults.standard.set(maxLastItems, forKey: "maxLastItems")
        }
    }

    @Published var maxFavoriteItems: Int {
        didSet {
            UserDefaults.standard.set(maxFavoriteItems, forKey: "maxFavoriteItems")
        }
    }

    @Published var enableHotkeys: Bool {
        didSet {
            UserDefaults.standard.set(enableHotkeys, forKey: "enableHotkeys")
        }
    }

    @Published var enableAutoCleanup: Bool {
        didSet {
            UserDefaults.standard.set(enableAutoCleanup, forKey: "enableAutoCleanup")
        }
    }

    @Published var maxItemsToKeep: Int {
        didSet {
            UserDefaults.standard.set(maxItemsToKeep, forKey: "maxItemsToKeep")
        }
    }

    @Published var menuBarDisplayLimit: Int {
        didSet {
            UserDefaults.standard.set(menuBarDisplayLimit, forKey: "menuBarDisplayLimit")
        }
    }

    @Published var enableMemoryCleanup: Bool {
        didSet {
            UserDefaults.standard.set(enableMemoryCleanup, forKey: "enableMemoryCleanup")
        }
    }

    @Published var memoryCleanupInterval: Int {
        didSet {
            UserDefaults.standard.set(memoryCleanupInterval, forKey: "memoryCleanupInterval")
        }
    }

    @Published var maxInactiveTime: Int {
        didSet {
            UserDefaults.standard.set(maxInactiveTime, forKey: "maxInactiveTime")
        }
    }

    @Published var clipboardCaptureMode: ClipboardCaptureMode {
        didSet {
            UserDefaults.standard.set(clipboardCaptureMode.rawValue, forKey: "clipboardCaptureMode")
        }
    }

    @Published var enableAppExclusion: Bool {
        didSet {
            UserDefaults.standard.set(enableAppExclusion, forKey: "enableAppExclusion")
        }
    }

    @Published var lastPauseDuration: Int {
        didSet {
            UserDefaults.standard.set(lastPauseDuration, forKey: "lastPauseDuration")
        }
    }

    @Published var enableErrorFileLogging: Bool {
        didSet {
            UserDefaults.standard.set(enableErrorFileLogging, forKey: ErrorLogger.enableFileLoggingKey)
        }
    }

    @Published var quickLookMode: QuickLookMode {
        didSet {
            UserDefaults.standard.set(quickLookMode.rawValue, forKey: "quickLookMode")
        }
    }

    @Published var quickLookTriggerKey: QuickLookTriggerKey {
        didSet {
            UserDefaults.standard.set(quickLookTriggerKey.rawValue, forKey: "quickLookTriggerKey")
        }
    }

    @Published var enableOCROptionKey: Bool {
        didSet {
            UserDefaults.standard.set(enableOCROptionKey, forKey: "enableOCROptionKey")
        }
    }

    @Published var startAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
            updateLoginItem()
        }
    }

    @Published var hasShownAutoStartPrompt: Bool {
        didSet {
            UserDefaults.standard.set(hasShownAutoStartPrompt, forKey: "hasShownAutoStartPrompt")
        }
    }

    // MARK: - Pin settings
    // Defaults are applied at pin-creation time. Per-pin state (opacity, lock,
    // click-through, size, etc.) is then stored on the PinnedItemConfig so
    // toggling a global default doesn't yank already-open pins around.

    @Published var pinPersistAcrossLaunches: Bool {
        didSet { UserDefaults.standard.set(pinPersistAcrossLaunches, forKey: "pinPersistAcrossLaunches") }
    }

    @Published var pinAlwaysShowChrome: Bool {
        didSet { UserDefaults.standard.set(pinAlwaysShowChrome, forKey: "pinAlwaysShowChrome") }
    }

    @Published var pinShowOverFullscreen: Bool {
        didSet {
            UserDefaults.standard.set(pinShowOverFullscreen, forKey: "pinShowOverFullscreen")
            NotificationCenter.default.post(name: .pinBehaviorSettingsChanged, object: nil)
        }
    }

    @Published var pinSnapToScreenEdges: Bool {
        didSet { UserDefaults.standard.set(pinSnapToScreenEdges, forKey: "pinSnapToScreenEdges") }
    }

    @Published var pinShadowEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pinShadowEnabled, forKey: "pinShadowEnabled")
            NotificationCenter.default.post(name: .pinBehaviorSettingsChanged, object: nil)
        }
    }

    @Published var pinMaxConcurrent: Int {
        didSet {
            if pinMaxConcurrent < 0 {
                pinMaxConcurrent = 0  // re-enters didSet once, then persists
                return
            }
            UserDefaults.standard.set(pinMaxConcurrent, forKey: "pinMaxConcurrent")
        }
    }

    @Published var pinCornerRadius: Double {
        didSet {
            UserDefaults.standard.set(pinCornerRadius, forKey: "pinCornerRadius")
            NotificationCenter.default.post(name: .pinBehaviorSettingsChanged, object: nil)
        }
    }

    @Published var pinDefaultOpacity: Double {
        didSet { UserDefaults.standard.set(pinDefaultOpacity, forKey: "pinDefaultOpacity") }
    }

    @Published var pinDefaultTextWidth: Double {
        didSet { UserDefaults.standard.set(pinDefaultTextWidth, forKey: "pinDefaultTextWidth") }
    }

    @Published var pinDefaultTextHeight: Double {
        didSet { UserDefaults.standard.set(pinDefaultTextHeight, forKey: "pinDefaultTextHeight") }
    }

    @Published var pinDefaultImageWidth: Double {
        didSet { UserDefaults.standard.set(pinDefaultImageWidth, forKey: "pinDefaultImageWidth") }
    }

    @Published var pinDefaultImageHeight: Double {
        didSet { UserDefaults.standard.set(pinDefaultImageHeight, forKey: "pinDefaultImageHeight") }
    }

    @Published var pinDefaultFileWidth: Double {
        didSet { UserDefaults.standard.set(pinDefaultFileWidth, forKey: "pinDefaultFileWidth") }
    }

    @Published var pinDefaultFileHeight: Double {
        didSet { UserDefaults.standard.set(pinDefaultFileHeight, forKey: "pinDefaultFileHeight") }
    }

    @Published var pinAllowTextEdit: Bool {
        didSet { UserDefaults.standard.set(pinAllowTextEdit, forKey: "pinAllowTextEdit") }
    }

    @Published var pinDismissAllConfirm: Bool {
        didSet { UserDefaults.standard.set(pinDismissAllConfirm, forKey: "pinDismissAllConfirm") }
    }

    /// When true, opening the Quick Picker also hides pinned windows. Default
    /// false so pins survive the picker (they're meant to stay on top).
    @Published var pinQuickPickerDismissesPins: Bool {
        didSet { UserDefaults.standard.set(pinQuickPickerDismissesPins, forKey: "pinQuickPickerDismissesPins") }
    }

    func updateLoginItem() {
        do {
            if startAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error.localizedDescription)")
        }
    }

    var loginItemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    init() {
        self.showInMenubar = UserDefaults.standard.bool(forKey: "showInMenubar")
        self.showMainWindow = UserDefaults.standard.bool(forKey: "showMainWindow")
        self.confirmQuitOnCmdQ = UserDefaults.standard.object(forKey: "confirmQuitOnCmdQ") as? Bool ?? false
        self.closeOtherWindowsOnQuickPicker = UserDefaults.standard.object(forKey: "closeOtherWindowsOnQuickPicker") as? Bool ?? true
        self.maxLastItems = UserDefaults.standard.object(forKey: "maxLastItems") as? Int ?? 10
        self.maxFavoriteItems =
            UserDefaults.standard.object(forKey: "maxFavoriteItems") as? Int ?? 10
        self.enableHotkeys = UserDefaults.standard.object(forKey: "enableHotkeys") as? Bool ?? true
        self.enableAutoCleanup =
            UserDefaults.standard.object(forKey: "enableAutoCleanup") as? Bool ?? true
        self.maxItemsToKeep = UserDefaults.standard.object(forKey: "maxItemsToKeep") as? Int ?? 300
        self.menuBarDisplayLimit =
            UserDefaults.standard.object(forKey: "menuBarDisplayLimit") as? Int ?? 10
        self.enableMemoryCleanup =
            UserDefaults.standard.object(forKey: "enableMemoryCleanup") as? Bool ?? true
        self.memoryCleanupInterval =
            UserDefaults.standard.object(forKey: "memoryCleanupInterval") as? Int ?? 5
        self.maxInactiveTime =
            UserDefaults.standard.object(forKey: "maxInactiveTime") as? Int ?? 30
        self.enableAppExclusion = UserDefaults.standard.object(forKey: "enableAppExclusion") as? Bool ?? false
        self.lastPauseDuration = UserDefaults.standard.object(forKey: "lastPauseDuration") as? Int ?? 300 // Default 5 minutes
        self.enableErrorFileLogging = UserDefaults.standard.bool(forKey: ErrorLogger.enableFileLoggingKey) // Default false

        if let savedQLMode = UserDefaults.standard.string(forKey: "quickLookMode"),
           let mode = QuickLookMode(rawValue: savedQLMode) {
            self.quickLookMode = mode
        } else {
            self.quickLookMode = .native
        }

        if let savedTrigger = UserDefaults.standard.string(forKey: "quickLookTriggerKey"),
           let trigger = QuickLookTriggerKey(rawValue: savedTrigger) {
            self.quickLookTriggerKey = trigger
        } else {
            self.quickLookTriggerKey = .space
        }

        self.enableOCROptionKey = UserDefaults.standard.object(forKey: "enableOCROptionKey") as? Bool ?? true
        self.startAtLogin = UserDefaults.standard.object(forKey: "startAtLogin") as? Bool ?? false
        self.hasShownAutoStartPrompt = UserDefaults.standard.object(forKey: "hasShownAutoStartPrompt") as? Bool ?? false

        // Pin settings
        self.pinPersistAcrossLaunches = UserDefaults.standard.object(forKey: "pinPersistAcrossLaunches") as? Bool ?? true
        self.pinAlwaysShowChrome = UserDefaults.standard.object(forKey: "pinAlwaysShowChrome") as? Bool ?? false
        self.pinShowOverFullscreen = UserDefaults.standard.object(forKey: "pinShowOverFullscreen") as? Bool ?? true
        self.pinSnapToScreenEdges = UserDefaults.standard.object(forKey: "pinSnapToScreenEdges") as? Bool ?? false
        self.pinShadowEnabled = UserDefaults.standard.object(forKey: "pinShadowEnabled") as? Bool ?? true
        self.pinMaxConcurrent = UserDefaults.standard.object(forKey: "pinMaxConcurrent") as? Int ?? 10
        self.pinCornerRadius = UserDefaults.standard.object(forKey: "pinCornerRadius") as? Double ?? 10
        self.pinDefaultOpacity = UserDefaults.standard.object(forKey: "pinDefaultOpacity") as? Double ?? 1.0
        self.pinDefaultTextWidth = UserDefaults.standard.object(forKey: "pinDefaultTextWidth") as? Double ?? 360
        self.pinDefaultTextHeight = UserDefaults.standard.object(forKey: "pinDefaultTextHeight") as? Double ?? 240
        self.pinDefaultImageWidth = UserDefaults.standard.object(forKey: "pinDefaultImageWidth") as? Double ?? 500
        self.pinDefaultImageHeight = UserDefaults.standard.object(forKey: "pinDefaultImageHeight") as? Double ?? 500
        self.pinDefaultFileWidth = UserDefaults.standard.object(forKey: "pinDefaultFileWidth") as? Double ?? 280
        self.pinDefaultFileHeight = UserDefaults.standard.object(forKey: "pinDefaultFileHeight") as? Double ?? 120
        self.pinAllowTextEdit = UserDefaults.standard.object(forKey: "pinAllowTextEdit") as? Bool ?? false
        self.pinDismissAllConfirm = UserDefaults.standard.object(forKey: "pinDismissAllConfirm") as? Bool ?? false
        self.pinQuickPickerDismissesPins = UserDefaults.standard.object(forKey: "pinQuickPickerDismissesPins") as? Bool ?? false

        // Migrate from old preferTextOverImage setting to new clipboardCaptureMode
        if let savedModeString = UserDefaults.standard.string(forKey: "clipboardCaptureMode"),
           let savedMode = ClipboardCaptureMode(rawValue: savedModeString) {
            self.clipboardCaptureMode = savedMode
        } else if let oldPreference = UserDefaults.standard.object(forKey: "preferTextOverImage") as? Bool {
            // Migrate old boolean setting: true = textOnly, false = imageOnly
            self.clipboardCaptureMode = oldPreference ? .textOnly : .imageOnly
            UserDefaults.standard.set(self.clipboardCaptureMode.rawValue, forKey: "clipboardCaptureMode")
            UserDefaults.standard.removeObject(forKey: "preferTextOverImage")
        } else {
            // Default to textOnly for new installations
            self.clipboardCaptureMode = .textOnly
        }

        //        self.autoSelectOnPaste = UserDefaults.standard.object(forKey: "autoSelectOnPaste") as? Bool ?? true

        // Default to showing menubar if first launch
        if UserDefaults.standard.object(forKey: "showInMenubar") == nil {
            self.showInMenubar = true
        }

        // Default to showing main window if first launch
        if UserDefaults.standard.object(forKey: "showMainWindow") == nil {
            self.showMainWindow = true
        }

        // Invariant repair: if persisted state has both disabled (e.g. manual defaults edit),
        // restore main-window visibility so the app stays reachable.
        if !self.showInMenubar && !self.showMainWindow {
            self.showMainWindow = true
        }
    }
}

extension Notification.Name {
    /// Posted when a pin behavior setting that needs to propagate to live
    /// NSPanels changes (collection behavior, shadow, corner radius).
    static let pinBehaviorSettingsChanged = Notification.Name("StoneClipboarder.pinBehaviorSettingsChanged")

    /// Posted with `object` = `PersistentIdentifier` of a CBItem that just got
    /// deleted from the clipboard history. PinManager listens and closes any
    /// pin referencing it. (Posting `nil` means "all items wiped".)
    static let clipboardItemDeleted = Notification.Name("StoneClipboarder.clipboardItemDeleted")
}
