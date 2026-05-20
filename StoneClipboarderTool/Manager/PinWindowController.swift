//
//  PinWindowController.swift
//  StoneClipboarderTool
//
//  Owns one floating NSPanel that renders a pinned clipboard item. The
//  controller bridges the SwiftUI PinContentView (which mutates the
//  PinnedItemConfig) with AppKit (NSPanel chrome, resize/move/lock).
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

@MainActor
final class PinWindowController: NSObject, NSWindowDelegate, ObservableObject {
    let config: PinnedItemConfig
    weak var settingsManager: SettingsManager?
    weak var pinManager: PinManager?

    private(set) var panel: PinPanel!
    private var saveDebounce: DispatchWorkItem?
    private var settingsObserver: AnyCancellable?

    init(
        config: PinnedItemConfig,
        settingsManager: SettingsManager,
        pinManager: PinManager
    ) {
        self.config = config
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
        applyClickThroughFlag(to: panel)
        applyCollectionBehavior(to: panel)
        panel.alphaValue = config.opacity
        panel.minSize = NSSize(width: 160, height: 60)

        let host = NSHostingView(rootView: makeRootView())
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel

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
                config: config,
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
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Public actions (called from SwiftUI chrome)

    func dismissByUser() {
        pinManager?.unpin(configId: config.id)
    }

    func copyToClipboard() {
        guard let vm = pinManager?.viewModel else { return }
        // Reconstruct a transient CBItem-like copy. Reuse the existing
        // pasteboard path on ClipboardManager via a temporary CBItem isn't
        // worth it — write the snapshot directly.
        let pb = NSPasteboard.general
        pb.clearContents()
        switch config.itemType {
        case .text, .combined:
            if let s = config.content { pb.setString(s, forType: .string) }
            if config.itemType == .combined,
               let data = config.imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        case .image:
            if let data = config.imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        case .file:
            if let data = config.fileData, let name = config.fileName {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                do {
                    try data.write(to: tmp)
                    pb.writeObjects([tmp as NSURL])
                } catch {
                    // Non-fatal; fall back to text representation if available.
                    if let s = config.content { pb.setString(s, forType: .string) }
                }
            }
        }
        _ = vm // silence unused-warning when no callbacks use vm
    }

    func toggleCollapsed() {
        if config.isCollapsed {
            // Restore expanded height.
            config.isCollapsed = false
            config.height = config.expandedHeight
            var frame = panel.frame
            frame.size.height = CGFloat(config.height)
            panel.setFrame(frame, display: true, animate: true)
        } else {
            config.expandedHeight = config.height
            config.isCollapsed = true
            // Header height (~28pt) — keep title bar visible only.
            config.height = 32
            var frame = panel.frame
            frame.size.height = CGFloat(config.height)
            panel.setFrame(frame, display: true, animate: true)
        }
        scheduleSave()
    }

    func setLocked(_ locked: Bool) {
        config.isLocked = locked
        applyMovableFlag(to: panel)
        scheduleSave()
    }

    func setClickThrough(_ clickThrough: Bool) {
        config.isClickThrough = clickThrough
        applyClickThroughFlag(to: panel)
        scheduleSave()
    }

    func setOpacity(_ opacity: Double) {
        let clamped = max(0.2, min(1.0, opacity))
        config.opacity = clamped
        panel.alphaValue = clamped
        scheduleSave()
    }

    func setImageZoom(_ zoom: Double) {
        config.imageZoom = max(0.25, min(8.0, zoom))
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
        panel.ignoresMouseEvents = config.isClickThrough
        panel.allowKey = !config.isClickThrough
        if config.isClickThrough, panel.isKeyWindow {
            panel.resignKey()
        }
    }

    private func applyCollectionBehavior(to panel: PinPanel) {
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle, .stationary]
        if settingsManager?.pinShowOnAllSpaces == true {
            behavior.insert(.canJoinAllSpaces)
        } else {
            behavior.insert(.moveToActiveSpace)
        }
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
}
