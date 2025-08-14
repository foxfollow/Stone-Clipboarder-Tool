//
//  QuickPickerWindowManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import AppKit
import SwiftUI

class QuickPickerHostingView: NSHostingView<QuickPickerView> {
    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        return result
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class KeyCapturingPanel: NSPanel {
    weak var quickPickerDelegate: QuickPickerWindowManager?

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        self.makeKey()
    }

    override func mouseDown(with event: NSEvent) {
        self.performDrag(with: event)
    }
}

@MainActor
class QuickPickerWindowManager: NSObject, ObservableObject, QuickPickerDelegate {
    private var window: NSPanel?
    private weak var cbViewModel: CBViewModel?
    private var eventMonitor: Any?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var isDragging = false
    private var dragOffset: NSPoint = NSPoint.zero

    func setCBViewModel(_ viewModel: CBViewModel) {
        self.cbViewModel = viewModel
        // Reset position flag on app start for fresh center positioning
        UserDefaults.standard.set(false, forKey: "QuickPickerHasValidPosition")
    }

    func showQuickPicker() {
        // If already visible, hide it (toggle behavior)
        if window?.isVisible == true {
            hideQuickPicker()
            return
        }

        guard let cbViewModel = cbViewModel else {
            print("CBViewModel is nil")
            return
        }

        // Store the currently active app so we can return focus to it later
        previousApp = NSWorkspace.shared.frontmostApplication

        // Create a panel with high priority level to capture focus
        let panel = KeyCapturingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.quickPickerDelegate = self

        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.worksWhenModal = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Create content view
        let contentView = QuickPickerView(viewModel: cbViewModel) { [weak self] in
            self?.hideQuickPicker()
        }

        let hostingView = QuickPickerHostingView(rootView: contentView)
        panel.contentView = hostingView

        // Set position (saved position or center)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let savedPosition = getSavedWindowPosition()

            let origin: NSPoint
            if isPositionValid(savedPosition, screenFrame: screenFrame) {
                origin = savedPosition
            } else {
                // Default to center
                origin = NSPoint(
                    x: screenFrame.midX - 250,
                    y: screenFrame.midY - 200
                )
            }
            panel.setFrameOrigin(origin)
        }

        // Temporarily activate app to capture focus, then show panel
        let wasActive = NSApp.isActive
        if !wasActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        panel.orderFrontRegardless()
        panel.makeKey()

        // Simple focus setup without interfering with text input
        DispatchQueue.main.async {
            // If we activated the app, hide all other windows immediately
            if !wasActive {
                for window in NSApp.windows {
                    if window !== panel && window.isVisible {
                        window.orderOut(nil)
                    }
                }
            }
        }

        self.window = panel

        // Setup click-outside monitoring and key monitoring
        setupEventMonitoring()
        setupKeyMonitoring()
    }

    func hideQuickPicker() {
        removeEventMonitoring()
        removeKeyMonitoring()

        if let window = window {
            // Save window position before closing
            saveWindowPosition(window.frame.origin)
            window.orderOut(nil)
            window.close()
        }

        self.window = nil

        // Return focus to the previous app immediately
        if let previousApp = previousApp, previousApp.isActive == false {
            DispatchQueue.main.async {
                previousApp.activate(options: [])
            }
        }
        previousApp = nil
    }

    func handleKeyEvent(_ event: NSEvent) {
        // This method is no longer used - key handling moved to local monitor
    }

    func isQuickPickerVisible() -> Bool {
        return window?.isVisible == true
    }

    private func setupEventMonitoring() {
        removeEventMonitoring()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            guard let self = self,
                let window = self.window,
                window.isVisible
            else { return }

            let clickLocation = NSEvent.mouseLocation
            if !window.frame.contains(clickLocation) {
                self.hideQuickPicker()
            }
        }
    }

    private func removeEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func setupKeyMonitoring() {
        removeKeyMonitoring()

        // Only monitor escape key globally, let SwiftUI handle everything else
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self,
                let window = self.window,
                window.isVisible,
                event.keyCode == 53  // Only handle escape key
            else { return }

            self.hideQuickPicker()
        }
    }

    private func removeKeyMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Window Position Management

    private func saveWindowPosition(_ position: NSPoint) {
        UserDefaults.standard.set(position.x, forKey: "QuickPickerWindowX")
        UserDefaults.standard.set(position.y, forKey: "QuickPickerWindowY")
        UserDefaults.standard.set(true, forKey: "QuickPickerHasValidPosition")
    }

    private func getSavedWindowPosition() -> NSPoint {
        let x = UserDefaults.standard.double(forKey: "QuickPickerWindowX")
        let y = UserDefaults.standard.double(forKey: "QuickPickerWindowY")
        return NSPoint(x: x, y: y)
    }

    private func isPositionValid(_ position: NSPoint, screenFrame: NSRect) -> Bool {
        // On app relaunch, always reset to center (fresh start)
        let hasValidPosition = UserDefaults.standard.bool(forKey: "QuickPickerHasValidPosition")
        if !hasValidPosition {
            return false
        }

        // Check if saved position exists (not 0,0 default)
        guard position.x != 0 || position.y != 0 else { return false }

        // Check if position is completely within screen bounds (no corner hanging)
        let windowSize = NSSize(width: 500, height: 400)
        let windowRect = NSRect(origin: position, size: windowSize)

        return screenFrame.contains(windowRect)
    }

    deinit {
        // Clean up on deinit
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
