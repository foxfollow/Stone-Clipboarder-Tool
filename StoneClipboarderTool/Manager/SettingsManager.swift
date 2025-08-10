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
    
    init() {
        self.showInMenubar = UserDefaults.standard.bool(forKey: "showInMenubar")
        self.showMainWindow = UserDefaults.standard.bool(forKey: "showMainWindow")
        
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
