//
//  MainWindow.swift
//  StoneClipboarderTool
//
//  Finding and showing the "Clipboard History" window (the WindowGroup's
//  window). With "Show Main Window" off it is ordered out, never closed, so
//  it can always be found here and shown again.
//

import AppKit
import SwiftData
import SwiftUI

@MainActor
enum MainWindow {
    static let title = "Clipboard History"

    /// Moves to whichever Space is active when shown; can go full screen.
    static let collectionBehavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]

    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.title == title || window.contentView?.subviews.first is NSHostingView<ContentView>
    }

    static func find() -> NSWindow? {
        NSApp.windows.first(where: isMainWindow)
    }

    /// Brings the window to the front on the current Space, turning "Show
    /// Main Window" (Dock + ⌘Tab) on if it was off, and optionally selects
    /// an item once the window is up.
    static func show(settingsManager: SettingsManager, selecting item: CBItem? = nil) {
        let itemID = item?.persistentModelID
        settingsManager.showMainWindow = true

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard let window = find() else { return }
        window.collectionBehavior = collectionBehavior
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // Briefly raise it above everything: an accessory app that just
        // turned regular can otherwise open its window behind other apps.
        let originalLevel = window.level
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        DispatchQueue.main.async {
            // Center on the current screen.
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = window.frame
                window.setFrameOrigin(NSPoint(
                    x: screenFrame.midX - windowFrame.width / 2,
                    y: screenFrame.midY - windowFrame.height / 2))
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            window.level = originalLevel
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            guard let itemID else { return }
            // Select once the window's content is up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .selectClipboardItem, object: itemID)
            }
        }
    }
}
