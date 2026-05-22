//
//  PinWindowController.swift
//  StoneClipboarderTool
//
//  Owns one floating NSPanel that renders a pinned clipboard item. The
//  controller bridges the SwiftUI PinContentView (which mutates PinViewState)
//  with AppKit (NSPanel chrome, resize/move/lock) and persists scalar state
//  back to PinnedItemConfig.
//

import AppKit
import Combine
import SwiftUI

/// Custom NSPanel for pins. Key behavior is conditional: when a pin is in
/// click-through mode it must NOT accept keystrokes (otherwise our ESC
/// handler would fire while the user "thinks" they're working in the app
/// beneath the pin).
final class PinPanel: NSPanel {
    var allowKey: Bool = true

    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { allowKey }

    override func cancelOperation(_ sender: Any?) {
        // ESC closes the pin (only fires when the pin is key).
        if let controller = delegate as? PinWindowController {
            controller.dismissByUser()
        }
    }
}

/// Hosting view that accepts the first mouse click so a control can be hit
/// without first activating the (nonactivating) pin — needed for ⌘-hold
/// interaction with a click-through pin.
final class PinHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PinWindowController: NSObject, NSWindowDelegate, ObservableObject {
    let config: PinnedItemConfig
    let state: PinViewState
    weak var settingsManager: SettingsManager?
    weak var pinManager: PinManager?

    private(set) var panel: PinPanel!
    private var saveDebounce: DispatchWorkItem?
    private var settingsObserver: AnyCancellable?

    // ⌘-hold interaction support for click-through pins.
    private var clickThroughFlagsMonitorLocal: Any?
    private var clickThroughFlagsMonitorGlobal: Any?

    init(
        config: PinnedItemConfig,
        settingsManager: SettingsManager,
        pinManager: PinManager
    ) {
        self.config = config
        self.state = PinViewState(config: config)
        self.settingsManager = settingsManager
        self.pinManager = pinManager
        super.init()
        buildPanel()
    }

    // MARK: - Panel setup

    private func buildPanel() {
        let panel = PinPanel(
            contentRect: config.frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = settingsManager?.pinShadowEnabled ?? true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.worksWhenModal = true
        panel.delegate = self

        applyMovableFlag(to: panel)
        applyCollectionBehavior(to: panel)
        panel.alphaValue = config.opacity
        panel.minSize = NSSize(width: 160, height: 60)

        let host = PinHostingView(rootView: makeRootView())
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel

        // Apply click-through last so the ⌘-hold monitor can attach.
        applyClickThroughFlag(to: panel)

        // Re-apply behavior settings when the user toggles them.
        settingsObserver = NotificationCenter.default
            .publisher(for: .pinBehaviorSettingsChanged)
            .sink { [weak self] _ in
                self?.applyBehaviorSettings()
            }
    }

    private func makeRootView() -> AnyView {
        guard let settings = settingsManager else {
            return AnyView(EmptyView())
        }
        return AnyView(
            PinContentView(
                state: state,
                controller: self,
                settings: settings
            )
        )
    }

    func showWindow() {
        panel.orderFrontRegardless()
    }

    func close() {
        settingsObserver?.cancel()
        settingsObserver = nil
        removeClickThroughMonitors()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Public actions (called from SwiftUI chrome)

    func dismissByUser() {
        pinManager?.unpin(configId: config.id)
    }

    func copyToClipboard() {
        // Read from the context-free snapshot, never the SwiftData model.
        let pb = NSPasteboard.general
        pb.clearContents()
        switch state.itemType {
        case .text, .combined:
            // Use the live (possibly edited) text, not the original snapshot.
            pb.setString(state.editedText, forType: .string)
            if state.itemType == .combined,
               let data = state.imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        case .image:
            if let data = state.imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        case .file:
            if let data = state.fileData, let name = state.fileName {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                do {
                    try data.write(to: tmp)
                    pb.writeObjects([tmp as NSURL])
                } catch {
                    if let s = state.content { pb.setString(s, forType: .string) }
                }
            }
        }
    }

    /// Open the pinned item in the system's default app — the same UX as
    /// "Open with Preview / TextEdit" elsewhere in the app. Works off the
    /// context-free snapshot so it's safe regardless of the model's state.
    func openInDefaultApp() {
        let tempDir = FileManager.default.temporaryDirectory

        switch state.itemType {
        case .text, .combined:
            let text = state.editedText
            if !text.isEmpty {
                let url = tempDir.appendingPathComponent("pinned_text_\(UUID().uuidString).txt")
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    openInTextEditOrDefault(url)
                    scheduleTempCleanup(url)
                } catch { /* best-effort */ }
                return
            }
            // Combined with no text → fall through to the image.
            if state.itemType == .combined, let data = state.imageData {
                openImageData(data, in: tempDir)
            }
        case .image:
            if let data = state.imageData {
                openImageData(data, in: tempDir)
            }
        case .file:
            if let data = state.fileData, let name = state.fileName {
                let url = tempDir.appendingPathComponent("pinned_\(UUID().uuidString)_\(name)")
                do {
                    try data.write(to: url)
                    NSWorkspace.shared.open(url)
                    scheduleTempCleanup(url)
                } catch { /* best-effort */ }
            }
        }
    }

    private func openImageData(_ data: Data, in tempDir: URL) {
        // Normalize to PNG so Preview opens it cleanly regardless of source
        // representation (clipboard images are often TIFF).
        let url = tempDir.appendingPathComponent("pinned_image_\(UUID().uuidString).png")
        let pngData: Data?
        if let rep = NSBitmapImageRep(data: data) {
            pngData = rep.representation(using: .png, properties: [:])
        } else if let img = NSImage(data: data), let png = img.pngRepresentation {
            pngData = png
        } else {
            pngData = nil
        }
        guard let pngData else { return }
        do {
            try pngData.write(to: url)
            NSWorkspace.shared.open(url)
            scheduleTempCleanup(url)
        } catch { /* best-effort */ }
    }

    private func openInTextEditOrDefault(_ url: URL) {
        if let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: textEditURL, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func scheduleTempCleanup(_ url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func toggleCollapsed() {
        if state.isCollapsed {
            state.isCollapsed = false
            config.isCollapsed = false
            config.height = config.expandedHeight
            var frame = panel.frame
            frame.size.height = CGFloat(config.height)
            panel.setFrame(frame, display: true, animate: true)
        } else {
            config.expandedHeight = config.height
            state.isCollapsed = true
            config.isCollapsed = true
            config.height = 32
            var frame = panel.frame
            frame.size.height = CGFloat(config.height)
            panel.setFrame(frame, display: true, animate: true)
        }
        scheduleSave()
    }

    func setLocked(_ locked: Bool) {
        state.isLocked = locked
        config.isLocked = locked
        applyMovableFlag(to: panel)
        scheduleSave()
    }

    func setClickThrough(_ clickThrough: Bool) {
        state.isClickThrough = clickThrough
        config.isClickThrough = clickThrough
        applyClickThroughFlag(to: panel)
        scheduleSave()

        if clickThrough {
            pinManager?.showHUDMessage("Click-through on — hold ⌘ to interact, then click the hand icon to turn it off")
        }
    }

    func setOpacity(_ opacity: Double) {
        let clamped = max(0.2, min(1.0, opacity))
        state.opacity = clamped
        config.opacity = clamped
        panel.alphaValue = clamped
        scheduleSave()
    }

    /// Persist an in-pin text edit. Only writes to the managed object when
    /// it's still attached to a context (avoids touching detached/external
    /// storage). No-op when persistence is off.
    func commitTextEdit(_ text: String) {
        guard state.itemType == .text || state.itemType == .combined else { return }
        guard config.modelContext != nil else { return }
        config.content = text
        scheduleSave()
    }

    func setImageZoom(_ zoom: Double) {
        let clamped = max(0.25, min(8.0, zoom))
        state.imageZoom = clamped
        config.imageZoom = clamped
        scheduleSave()
    }

    func applyBehaviorSettings() {
        guard let settings = settingsManager else { return }
        panel.hasShadow = settings.pinShadowEnabled
        applyCollectionBehavior(to: panel)
        // Corner radius is read inside PinContentView from the live
        // SettingsManager binding, so SwiftUI re-renders automatically.
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !config.isLocked else { return }
        let frame = panel.frame
        config.x = Double(frame.origin.x)
        config.y = Double(frame.origin.y)
        if settingsManager?.pinSnapToScreenEdges == true {
            snapToEdgesIfNeeded()
        }
        scheduleSave()
    }

    func windowDidResize(_ notification: Notification) {
        guard !config.isLocked else { return }
        let frame = panel.frame
        config.width = Double(frame.size.width)
        config.height = Double(frame.size.height)
        if !config.isCollapsed {
            config.expandedHeight = config.height
        }
        scheduleSave()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if config.isLocked {
            return panel.frame.size
        }
        return frameSize
    }

    // MARK: - Helpers

    private func applyMovableFlag(to panel: PinPanel) {
        panel.isMovableByWindowBackground = !config.isLocked
        panel.isMovable = !config.isLocked
    }

    private func applyClickThroughFlag(to panel: PinPanel) {
        let clickThrough = config.isClickThrough
        panel.ignoresMouseEvents = clickThrough
        panel.allowKey = !clickThrough
        if clickThrough {
            if panel.isKeyWindow { panel.resignKey() }
            installClickThroughMonitors()
        } else {
            removeClickThroughMonitors()
        }
    }

    /// While a click-through pin is active, holding ⌘ temporarily makes the
    /// panel interactive so the user can reach the chrome and turn click-
    /// through back off. Releasing ⌘ restores pass-through. We watch both the
    /// local (our app active) and global (another app active) flag streams
    /// because click-through pins are typically used over other apps.
    private func installClickThroughMonitors() {
        removeClickThroughMonitors()

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self, self.config.isClickThrough else { return }
            let commandHeld = event.modifierFlags.contains(.command)
            self.panel.ignoresMouseEvents = !commandHeld
            self.panel.allowKey = commandHeld
        }

        clickThroughFlagsMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
        clickThroughFlagsMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
        }
    }

    private func removeClickThroughMonitors() {
        if let m = clickThroughFlagsMonitorLocal {
            NSEvent.removeMonitor(m)
            clickThroughFlagsMonitorLocal = nil
        }
        if let m = clickThroughFlagsMonitorGlobal {
            NSEvent.removeMonitor(m)
            clickThroughFlagsMonitorGlobal = nil
        }
    }

    private func applyCollectionBehavior(to panel: PinPanel) {
        // Pins always join all Spaces (matches the rest of the app).
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
        if settingsManager?.pinShowOverFullscreen == true {
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior
    }

    private func snapToEdgesIfNeeded() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let snapDistance: CGFloat = 12
        var origin = panel.frame.origin
        let size = panel.frame.size

        if abs(origin.x - visible.minX) < snapDistance { origin.x = visible.minX }
        if abs((origin.x + size.width) - visible.maxX) < snapDistance {
            origin.x = visible.maxX - size.width
        }
        if abs(origin.y - visible.minY) < snapDistance { origin.y = visible.minY }
        if abs((origin.y + size.height) - visible.maxY) < snapDistance {
            origin.y = visible.maxY - size.height
        }

        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
            config.x = Double(origin.x)
            config.y = Double(origin.y)
        }
    }

    /// Debounced disk write so dragging doesn't hammer SwiftData.
    private func scheduleSave() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pinManager?.saveConfig(self.config)
        }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    deinit {
        if let m = clickThroughFlagsMonitorLocal { NSEvent.removeMonitor(m) }
        if let m = clickThroughFlagsMonitorGlobal { NSEvent.removeMonitor(m) }
    }
}
