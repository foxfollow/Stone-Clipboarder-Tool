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

    @Published var autoSelectOnPaste: Bool {
        didSet {
            UserDefaults.standard.set(autoSelectOnPaste, forKey: "autoSelectOnPaste")
        }
    }

    init() {
        self.showInMenubar = UserDefaults.standard.bool(forKey: "showInMenubar")
        self.showMainWindow = UserDefaults.standard.bool(forKey: "showMainWindow")
        self.maxLastItems = UserDefaults.standard.object(forKey: "maxLastItems") as? Int ?? 10
        self.maxFavoriteItems = UserDefaults.standard.object(forKey: "maxFavoriteItems") as? Int ?? 10
        self.enableHotkeys = UserDefaults.standard.object(forKey: "enableHotkeys") as? Bool ?? true
        self.autoSelectOnPaste = UserDefaults.standard.object(forKey: "autoSelectOnPaste") as? Bool ?? true

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
