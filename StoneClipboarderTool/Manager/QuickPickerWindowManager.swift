//
//  QuickPickerWindowManager.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import AppKit
import QuickLookUI
import SwiftUI

class QuickPickerHostingView: NSHostingView<QuickPickerView> {
    override var acceptsFirstResponder: Bool {
        return true
    }

    // No becomeFirstResponder override here. A previous version re-asserted
    // self as first responder on the next runloop tick, which fired *after*
    // SwiftUI's @FocusState routed focus to the search TextField's field
    // editor — kicking the cursor out of the search box. SwiftUI's onKeyPress
    // handlers fire on the parent view regardless of which child is focused,
    // so we don't need to force the hosting view to stay first responder.

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class KeyCapturingPanel: NSPanel {
    weak var quickPickerDelegate: QuickPickerWindowManager?

    override var canBecomeKey: Bool {
        return true
    }
    // canBecomeMain intentionally not overridden — NSPanel's default is false,
    // which is what we want so .nonactivatingPanel + canJoinAllSpaces can
    // render over another app's fullscreen Space without triggering activation.

    override var acceptsFirstResponder: Bool {
        return canBecomeKey
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        return result
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)

        // Force focus for any keyboard events
        if (event.type == .keyDown || event.type == .keyUp), !self.isKeyWindow {
            self.makeKey()
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
    // Debounced dismiss used when QL panel is open — avoids frame-check fragility
    // and double-scheduling when the user clicks twice on the QL panel.
    nonisolated(unsafe) private var pendingQLDismiss: DispatchWorkItem?
    // Observes app resign-active so QuickPicker closes when an external app activates
    // (e.g. "Open with TextEdit" in QL, whether TextEdit was already running or not).
    private var resignActiveObserver: NSObjectProtocol?

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

        // Hide our other windows so the QuickPicker is the only one visible.
        // orderOut on its own does NOT trigger a Space switch — only NSApp.activate
        // and activation-policy changes do. Safe to do this in any context.
        for window in NSApp.windows {
            window.orderOut(nil)
        }

        // Create a borderless non-activating panel. .nonactivatingPanel is
        // required for the picker to render over another app's fullscreen
        // Space without forcing a Space switch; SwiftUI @FocusState is
        // unreliable in this configuration, so focusSearchField() below
        // pushes the cursor into the search field directly via the
        // responder chain instead of relying on @FocusState.
        let panel = KeyCapturingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.quickPickerDelegate = self

        panel.isFloatingPanel = true
        // Keep .floating so QuickLook (which uses ~floating level) can render
        // above the picker when the user previews an item. A higher level like
        // .popUpMenu would shove QL behind the picker.
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.worksWhenModal = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        // canJoinAllSpaces + fullScreenAuxiliary lets the panel render on top
        // of another app's fullscreen Space without triggering a Space switch.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
            .transient
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

        // Show the panel and activate our app so it becomes the OS-level
        // active app. macOS routes key events to the active app first, so
        // without this the trigger key (space / →) for QuickLook leaks
        // through to whichever app was frontmost before the picker opened
        // and types the literal character there.
        //
        // We deliberately do NOT toggle activation policy
        // (.regular ↔ .accessory) — that's what previously caused a Space
        // switch out of another app's fullscreen Space. NSApp.activate by
        // itself is safe here because the orderOut() loop above already
        // hid every other window of ours, and the panel itself lives on the
        // current Space (canJoinAllSpaces + fullScreenAuxiliary), so macOS
        // has nothing to switch Spaces *to*.
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        // Push the cursor straight into the search TextField. SwiftUI renders
        // the TextField as an NSTextField inside the hosting view; we walk
        // the subview tree to find it and make it first responder. The small
        // delay lets SwiftUI finish its initial render so the NSTextField
        // actually exists. Doing this via the AppKit responder chain works
        // reliably even when @FocusState misfires (which it does inside a
        // borderless .nonactivatingPanel).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusSearchField()
        }

        self.window = panel

        // Setup click-outside monitoring and key monitoring
        setupEventMonitoring()
        setupKeyMonitoring()
        setupLocalKeyMonitoring()
        setupResignActiveObserver()
    }

    func hideQuickPicker() {
        pendingQLDismiss?.cancel()
        pendingQLDismiss = nil
        removeResignActiveObserver()
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
            // QLPreviewPanel.orderOut leaves first responder unset, so arrow
            // keys / trigger key would do nothing in the picker afterwards.
            // Re-key our panel so the search field regains the cursor and
            // SwiftUI's onKeyPress handlers wake up again.
            reclaimKeyFocus()
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
        // Re-take key focus on our QuickPicker panel after showing the preview.
        // QLPreviewPanel.makeKeyAndOrderFront steals key, and with
        // .nonactivatingPanel our app is not "active", so without this the
        // trigger key (space / →) and escape would be delivered to whichever
        // app was frontmost before the picker opened — typing the literal
        // character there instead of toggling the preview off.
        reclaimKeyFocus()
    }

    private func reclaimKeyFocus() {
        // Re-take key on our panel after QuickLook steals it and put the
        // cursor back into the search field. Without this, arrow keys and
        // the trigger key go nowhere after closing QL.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            window.makeKey()
            self?.focusSearchField()
        }
    }

    /// Walk the hosting view's subview tree to find the search NSTextField
    /// (rendered by SwiftUI's TextField) and make it first responder so the
    /// cursor lands in it. Falls back to the hosting view if no field is
    /// found yet (rare — would mean SwiftUI hasn't rendered).
    private func focusSearchField() {
        guard let window = window, let contentView = window.contentView else { return }
        if let textField = Self.findFirstTextField(in: contentView) {
            window.makeFirstResponder(textField)
        } else {
            window.makeFirstResponder(contentView)
        }
    }

    private static func findFirstTextField(in view: NSView) -> NSView? {
        if view is NSTextField {
            return view
        }
        // SwiftUI on macOS sometimes wraps text input in a private subclass
        // whose class name contains "TextField" — match by name as a fallback
        // so we don't miss it on future macOS versions.
        let className = String(describing: type(of: view))
        if className.contains("TextField"), view.acceptsFirstResponder {
            return view
        }
        for subview in view.subviews {
            if let found = findFirstTextField(in: subview) {
                return found
            }
        }
        return nil
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

            // Never dismiss for clicks inside the QuickPicker window itself
            if window.frame.contains(clickLocation) {
                return
            }

            // When native QL is visible, ANY click outside the QuickPicker could be on
            // the QL panel body OR its detached toolbar/HUD ("Open with" button lives there).
            // Frame-checking is unreliable because that button is in a separate NSWindow.
            // Instead, debounce: cancel any previous pending dismiss and schedule a new one
            // so the button's mouseUp action fires before we tear everything down.
            if self.isPreviewPanelVisible() {
                self.pendingQLDismiss?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.pendingQLDismiss = nil
                    self?.hideQuickPicker()
                }
                self.pendingQLDismiss = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
                return
            }

            // Don't dismiss for clicks inside the custom preview panel
            if self.customPreviewManager.isPreviewVisible {
                return
            }

            self.hideQuickPicker()
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

    // MARK: - Resign Active Observer

    private func setupResignActiveObserver() {
        removeResignActiveObserver()
        // Delay registration briefly so the NSApp.activate() call in showQuickPicker
        // doesn't immediately fire the observer on app launch / re-show.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                guard self.window?.isVisible == true else { return }
                self.resignActiveObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.willResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self = self, self.window?.isVisible == true else { return }
                        // Delay slightly so "Open with" button action fires and temp files survive
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.hideQuickPicker()
                        }
                    }
                }
            }
        }
    }

    private func removeResignActiveObserver() {
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            resignActiveObserver = nil
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
        let windowSize = NSSize(width: 500, height: 430)
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
