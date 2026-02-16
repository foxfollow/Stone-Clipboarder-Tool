//
//  SettingsManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Foundation

class SettingsManager: ObservableObject {
    @Published var showInMenubar: Bool {
        didSet {
            UserDefaults.standard.set(showInMenubar, forKey: "showInMenubar")
        }
    }

    @Published var showMainWindow: Bool {
        didSet {
            UserDefaults.standard.set(showMainWindow, forKey: "showMainWindow")
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

    init() {
        self.showInMenubar = UserDefaults.standard.bool(forKey: "showInMenubar")
        self.showMainWindow = UserDefaults.standard.bool(forKey: "showMainWindow")
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
    }
}
