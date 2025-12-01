//
//  MenuBarManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import AppKit
import SwiftUI
import Combine

class MenuBarManager: ObservableObject {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private var cbViewModel: CBViewModel?
    private var settingsManager: SettingsManager?
    private var clipboardManager: ClipboardManager?
    private var cancellables = Set<AnyCancellable>()

    func setupMenuBar(cbViewModel: CBViewModel, settingsManager: SettingsManager, clipboardManager: ClipboardManager) {
        // Store references for refresh capability
        self.cbViewModel = cbViewModel
        self.settingsManager = settingsManager
        self.clipboardManager = clipboardManager

        // Observe pause state changes to update icon
        setupPauseStateObserver()

        guard statusBarItem == nil else {
            refreshMenuBar()
            return
        }

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            updateIcon()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        let menuBarView = MenuBarView()
            .environmentObject(cbViewModel)
            .environmentObject(settingsManager)
            .environmentObject(clipboardManager)

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
        self.clipboardManager = nil
    }

    func refreshMenuBar() {
        guard let cbViewModel = cbViewModel,
            let settingsManager = settingsManager,
            let clipboardManager = clipboardManager,
            let statusBarItem = statusBarItem
        else { return }

        // Refresh the button state
        if let button = statusBarItem.button {
            updateIcon()
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.isEnabled = true
        }

        // Recreate popover with fresh content
        let menuBarView = MenuBarView()
            .environmentObject(cbViewModel)
            .environmentObject(settingsManager)
            .environmentObject(clipboardManager)

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

    /// Update the menu bar icon based on pause state
    func updateIcon() {
        guard let button = statusBarItem?.button else { return }

        let isPaused = clipboardManager?.isPaused ?? false
        let iconName = isPaused ? "arrow.trianglehead.2.clockwise.rotate.90.page.on.clipboard" : "doc.on.clipboard"

        button.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: isPaused ? "Clipboard Monitoring Paused" : "Clipboard History"
        )
    }

    /// Setup observer to watch for pause state changes
    private func setupPauseStateObserver() {
        guard let clipboardManager = clipboardManager else { return }

        // Clear existing observers
        cancellables.removeAll()

        // Observe isPaused property changes
        clipboardManager.$isPaused
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateIcon()
                }
            }
            .store(in: &cancellables)
    }
}
