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
        // Ensure the hosting view can receive keyboard events
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
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
        return true  // Allow it to become main to receive proper focus
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        return result
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)

        // Force focus for any keyboard events
        if event.type == .keyDown || event.type == .keyUp {
            if !self.isKeyWindow {
                self.makeKey()
            }
        }
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        self.makeKey()
    }

    override func mouseDown(with event: NSEvent) {
        self.makeKey()
        self.performDrag(with: event)
    }
}

@MainActor
class QuickPickerWindowManager: NSObject, ObservableObject, QuickPickerDelegate {
    private var window: NSPanel?
    private let quickLookCoordinator = QPQuickLookCoordinator()
    private let customPreviewManager = QPCustomPreviewManager()
    private weak var cbViewModel: CBViewModel?
    private weak var settingsManager: SettingsManager?
    nonisolated(unsafe) private var eventMonitor: Any?
    nonisolated(unsafe) private var keyMonitor: Any?
    nonisolated(unsafe) private var localKeyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var isDragging = false
    private var dragOffset: NSPoint = NSPoint.zero
    private var menuBarRefreshCallback: (() -> Void)?

    func setCBViewModel(_ viewModel: CBViewModel) {
        self.cbViewModel = viewModel
        // Reset position flag on app start for fresh center positioning
        UserDefaults.standard.set(false, forKey: "QuickPickerHasValidPosition")
    }

    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
    }

    func setMenuBarRefreshCallback(_ callback: @escaping () -> Void) {
        self.menuBarRefreshCallback = callback
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
        
        // Hide ALL other windows to ensure QuickPicker is the only one visible
        for window in NSApp.windows {
            window.orderOut(nil)
        }

        // Create a panel that captures focus without activating the main app
        let panel = KeyCapturingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.quickPickerDelegate = self

        panel.isFloatingPanel = true
        panel.level = .floating  // Use floating level instead of screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.worksWhenModal = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
            .transient  // Add transient to prevent it from becoming main
        ]

        // Create content view
        let contentView = QuickPickerView(
            viewModel: cbViewModel,
            settingsManager: settingsManager,
            onClose: { [weak self] in
                self?.hideQuickPicker()
            },
            onPreviewToggle: { [weak self] item in
                self?.togglePreviewPanel(for: item)
            },
            onPreviewUpdate: { [weak self] item in
                self?.updatePreviewPanel(for: item)
            },
            isPreviewVisible: { [weak self] in
                self?.isPreviewPanelVisible() ?? false
            }
        )

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

        // Store current activation policy
        let currentPolicy = NSApp.activationPolicy()
        
        // Temporarily set to accessory to prevent dock icon bounce
        if currentPolicy == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
        
        // Show panel without activating main app
        panel.orderFrontRegardless()
        panel.makeKey()
        
        // Activate the app to ensure we can receive keyboard events
        NSApp.activate(ignoringOtherApps: true)
        
        // Force keyboard focus to the panel
        DispatchQueue.main.async {
            panel.makeKey()
            panel.makeMain()
            if let contentView = panel.contentView {
                panel.makeFirstResponder(contentView)
                contentView.becomeFirstResponder()
            }
            
            // Restore activation policy after a short delay
            if currentPolicy == .regular {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.setActivationPolicy(currentPolicy)
                }
            }
        }

        self.window = panel

        // Setup click-outside monitoring and key monitoring
        setupEventMonitoring()
        setupKeyMonitoring()
        setupLocalKeyMonitoring()
    }

    func hideQuickPicker() {
        hidePreviewPanel()
        removeEventMonitoring()
        removeKeyMonitoring()
        removeLocalKeyMonitoring()

        if let window = window {
            // Save window position before closing
            saveWindowPosition(window.frame.origin)
            window.orderOut(nil)
            window.close()
        }

        self.window = nil

        // Return focus to the previous app if we had stored one
        if let previousApp = previousApp {
            previousApp.activate(options: [])
        }
        previousApp = nil

        // Refresh menubar after operations to fix any state issues
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.menuBarRefreshCallback?()
        }
    }

    // MARK: - Preview Panel Management

    private func togglePreviewPanel(for item: CBItem) {
        guard settingsManager?.quickLookMode != .disabled else { return }

        if isPreviewPanelVisible() {
            hidePreviewPanel()
        } else {
            showPreviewPanel(for: item)
        }
    }

    private func showPreviewPanel(for item: CBItem) {
        let mode = settingsManager?.quickLookMode ?? .native
        switch mode {
        case .native:
            guard quickLookCoordinator.prepareItem(item) else { return }
            quickLookCoordinator.showPreview()
        case .custom:
            let triggerKey = settingsManager?.quickLookTriggerKey ?? .space
            customPreviewManager.triggerKeyHint = triggerKey == .space ? "⎵ to close" : "→ to close"
            customPreviewManager.showPreview(for: item, relativeTo: window)
        case .disabled:
            break
        }
    }

    private func updatePreviewPanel(for item: CBItem) {
        guard isPreviewPanelVisible() else { return }
        showPreviewPanel(for: item)
    }

    func isPreviewPanelVisible() -> Bool {
        let mode = settingsManager?.quickLookMode ?? .native
        switch mode {
        case .native: return quickLookCoordinator.isPreviewVisible
        case .custom: return customPreviewManager.isPreviewVisible
        case .disabled: return false
        }
    }

    func hidePreviewPanel() {
        quickLookCoordinator.hidePreview()
        customPreviewManager.hidePreview()
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

    private func setupLocalKeyMonitoring() {
        removeLocalKeyMonitoring()

        // Local monitor to capture all keyboard events when panel is key
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) {
            [weak self] event in
            guard let self = self,
                let window = self.window,
                window.isKeyWindow
            else { return event }

            // Let SwiftUI handle navigation and text input
            return event
        }
    }

    private func removeLocalKeyMonitoring() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
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
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
