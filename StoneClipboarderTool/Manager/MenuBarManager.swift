//
//  MenuBarManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import AppKit
import SwiftUI

class MenuBarManager: ObservableObject {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    
    func setupMenuBar(cbViewModel: CBViewModel, settingsManager: SettingsManager) {
        guard statusBarItem == nil else { return }
        
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        let menuBarView = MenuBarView()
            .environmentObject(cbViewModel)
            .environmentObject(settingsManager)
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 350, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: menuBarView)
    }
    
    func hideMenuBar() {
        guard let statusBarItem = statusBarItem else { return }
        NSStatusBar.system.removeStatusItem(statusBarItem)
        self.statusBarItem = nil
        self.popover = nil
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusBarItem?.button else { return }
        
        if let popover = popover {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
}
