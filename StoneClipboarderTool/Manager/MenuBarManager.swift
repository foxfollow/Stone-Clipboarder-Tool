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
    private var cbViewModel: CBViewModel?
    private var settingsManager: SettingsManager?

    func setupMenuBar(cbViewModel: CBViewModel, settingsManager: SettingsManager) {
        // Store references for refresh capability
        self.cbViewModel = cbViewModel
        self.settingsManager = settingsManager

        guard statusBarItem == nil else {
            refreshMenuBar()
            return
        }

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
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
        self.cbViewModel = nil
        self.settingsManager = nil
    }

    func refreshMenuBar() {
        guard let cbViewModel = cbViewModel,
            let settingsManager = settingsManager,
            let statusBarItem = statusBarItem
        else { return }

        // Refresh the button state
        if let button = statusBarItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.isEnabled = true
        }

        // Recreate popover with fresh content
        let menuBarView = MenuBarView()
            .environmentObject(cbViewModel)
            .environmentObject(settingsManager)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 350, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: menuBarView)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusBarItem?.button else {
            // Try to refresh if button is nil
            refreshMenuBar()
            return
        }

        if let popover = popover {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        } else {
            // Recreate popover if it's nil
            refreshMenuBar()
            // Try again after refresh
            if let popover = popover {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
}
