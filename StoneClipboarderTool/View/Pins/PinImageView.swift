//
//  PinImageView.swift
//  StoneClipboarderTool
//
//  Zoomable / pannable image renderer for pinned windows, backed by an
//  AppKit NSScrollView (native scrollbars + click-drag panning).
//
//  Zoom is handled by a dedicated `.magnify` event monitor rather than
//  NSScrollView's built-in magnification gesture. A pin is a non-activating
//  panel, so whether the built-in gesture reaches the scroll view through the
//  responder chain is unreliable (it depends on key/focus state) — that was
//  why pinch-zoom worked only sometimes. The monitor catches magnify events
//  for the pin's window directly and applies the magnification ourselves, so
//  it works whether or not the pin is the key window.
//
//  Magnify events that reach the scroll view through the responder chain
//  (`magnify(with:)`) are handled too; the monitor consumes the ones it
//  applies, so a gesture is never applied twice.
//
//  Window-move interplay: a *zoomed-in* image pans on drag (and doesn't move
//  the window); a fit image moves the window via `performDrag` (SwiftUI's
//  hosting view defeats `isMovableByWindowBackground`); the chrome bar always
//  moves the window (PinDragArea). A locked pin never moves.
//
//  `zoom` is a multiplier on top of the fit scale: 1.0 == fit-to-window.
//  Resizing the pin keeps the multiplier, so a fit image grows and shrinks
//  with the window. ⌘-scroll zooms too (for a mouse without pinch).
//  Double-click resets to fit.
//

import AppKit
import SwiftUI

struct PinImageView: NSViewRepresentable {
    let image: NSImage?
    @Binding var zoom: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(zoom: $zoom)
    }

    func makeNSView(context: Context) -> PinScrollView {
        let scrollView = PinScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        // We drive magnification ourselves via the event monitor below, so the
        // built-in gesture (unreliable in a non-key panel) stays off.
        scrollView.allowsMagnification = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.black.withAlphaComponent(0.04)

        // Centers the image while it is smaller than the viewport; the default
        // clip view pins it to the bottom-left corner.
        scrollView.contentView = PinCenteringClipView()

        let imageView = PinDraggableImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = image
        imageView.onDoubleClick = { [weak coordinator = context.coordinator] in
            coordinator?.resetZoom()
        }
        scrollView.documentView = imageView

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.image = image

        // Re-fit whenever the scroll view lays out (initial sizing + resize).
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.applyLayout()
        }
        scrollView.onCommandScroll = { [weak coordinator = context.coordinator] event in
            coordinator?.handleCommandScroll(event)
        }
        scrollView.onMagnify = { [weak coordinator = context.coordinator] event in
            coordinator?.handleMagnify(event)
        }

        context.coordinator.startMagnifyMonitor()
        PinZoomLog.log("makeNSView: image=\(image.map { "\($0.size.width)x\($0.size.height)" } ?? "nil")")

        return scrollView
    }

    func updateNSView(_ scrollView: PinScrollView, context: Context) {
        context.coordinator.image = image
        if let imageView = scrollView.documentView as? NSImageView,
           imageView.image !== image {
            imageView.image = image
        }
        context.coordinator.applyLayout()
    }

    static func dismantleNSView(_ nsView: PinScrollView, coordinator: Coordinator) {
        coordinator.stopMagnifyMonitor()
    }

    @MainActor
    final class Coordinator: NSObject {
        let zoom: Binding<Double>
        weak var scrollView: PinScrollView?
        weak var imageView: NSImageView?
        var image: NSImage?
        var fitMagnification: CGFloat = 1.0
        private var didInitialFit = false
        private var magnifyMonitor: Any?

        init(zoom: Binding<Double>) {
            self.zoom = zoom
        }

        // MARK: Magnify monitor

        func startMagnifyMonitor() {
            guard magnifyMonitor == nil else { return }
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, self.handleMagnify(event) else { return event }
                return nil
            }
            PinZoomLog.log("startMagnifyMonitor: installed local .magnify monitor")
        }

        func stopMagnifyMonitor() {
            if let m = magnifyMonitor {
                NSEvent.removeMonitor(m)
                magnifyMonitor = nil
            }
        }

        /// Returns true when the gesture was for this pin and was applied.
        @discardableResult
        func handleMagnify(_ event: NSEvent) -> Bool {
            let win = scrollView?.window
            PinZoomLog.log(
                "magnify recv: delta=\(String(format: "%.4f", event.magnification)) "
                + "eventWindow=\(Self.desc(event.window)) myWindow=\(Self.desc(win)) "
                + "match=\(event.window === win) fit=\(String(format: "%.4f", fitMagnification))"
            )

            guard let scrollView = scrollView,
                  let window = scrollView.window,
                  event.window === window else {
                PinZoomLog.log("magnify SKIP: window mismatch or no scrollView")
                return false
            }
            guard fitMagnification > 0 else {
                PinZoomLog.log("magnify SKIP: fitMagnification not ready (\(fitMagnification))")
                return false
            }

            zoom(by: 1 + event.magnification, at: event.locationInWindow)
            return true
        }

        /// ⌘-scroll zoom. Trackpads send many small precise deltas, wheels
        /// send a few coarse lines.
        func handleCommandScroll(_ event: NSEvent) {
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            let factor = max(0.5, min(1.5, 1 + event.scrollingDeltaY * step))
            zoom(by: factor, at: event.locationInWindow)
        }

        private func zoom(by factor: CGFloat, at locationInWindow: NSPoint) {
            guard let scrollView = scrollView, fitMagnification > 0 else { return }
            let minMag = fitMagnification * 0.25
            let maxMag = fitMagnification * 8.0
            let oldMag = scrollView.magnification
            let newMag = max(minMag, min(maxMag, oldMag * factor))

            // Zoom toward the cursor for a natural feel.
            let pointInClip = scrollView.contentView.convert(locationInWindow, from: nil)
            scrollView.setMagnification(newMag, centeredAt: pointInClip)

            zoom.wrappedValue = max(0.25, min(8.0, Double(scrollView.magnification / fitMagnification)))
            updatePannable()
            PinZoomLog.log(
                "zoom APPLY: \(String(format: "%.4f", oldMag)) -> \(String(format: "%.4f", scrollView.magnification)) "
                + "zoom=\(String(format: "%.3f", zoom.wrappedValue))"
            )
        }

        private static func desc(_ window: NSWindow?) -> String {
            guard let window else { return "nil" }
            return "\(type(of: window))#\(UInt(bitPattern: ObjectIdentifier(window).hashValue) % 10000)"
        }

        // MARK: Layout

        /// Keep the document sized to the image and the fit baseline current.
        /// When the fit changes (first layout, window resize) the magnification
        /// follows it at the current zoom multiplier.
        func applyLayout() {
            guard let scrollView = scrollView,
                  let imageView = imageView,
                  let image = image,
                  image.size.width > 0, image.size.height > 0 else { return }

            let natural = image.size
            if imageView.frame.size != natural {
                imageView.frame = NSRect(origin: .zero, size: natural)
            }

            let clip = scrollView.contentSize
            guard clip.width > 0, clip.height > 0 else { return }

            let fit = min(clip.width / natural.width, clip.height / natural.height)
            let fitChanged = abs(fit - fitMagnification) > fit * 0.0001
            fitMagnification = fit

            // NSScrollView clamps to 0.25…4.0 by default, which cuts zoom off
            // early for large or small images.
            scrollView.minMagnification = fit * 0.25
            scrollView.maxMagnification = fit * 8.0

            if !didInitialFit || fitChanged {
                scrollView.magnification = fit * CGFloat(zoom.wrappedValue)
                didInitialFit = true
                PinZoomLog.log(
                    "applyLayout FIT: clip=\(Int(clip.width))x\(Int(clip.height)) "
                    + "natural=\(Int(natural.width))x\(Int(natural.height)) fit=\(String(format: "%.4f", fit)) "
                    + "magnification=\(String(format: "%.4f", scrollView.magnification))"
                )
            }
            updatePannable()
        }

        private func updatePannable() {
            guard let scrollView = scrollView else { return }
            scrollView.isPannable = scrollView.magnification > fitMagnification * 1.001
        }

        func resetZoom() {
            guard let scrollView = scrollView else { return }
            scrollView.animator().magnification = fitMagnification
            zoom.wrappedValue = 1.0
            updatePannable()
        }
    }
}

/// NSScrollView that only lets a background drag move the window when the
/// image is not pannable (fit / un-zoomed). When zoomed in, drags pan instead.
final class PinScrollView: NSScrollView {
    var isPannable: Bool = false
    var onLayout: (() -> Void)?
    var onCommandScroll: ((NSEvent) -> Void)?
    var onMagnify: ((NSEvent) -> Void)?

    override var mouseDownCanMoveWindow: Bool { !isPannable }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks on the letterbox around a fit image move the pin.
    override func mouseDown(with event: NSEvent) {
        if isPannable {
            super.mouseDown(with: event)
        } else {
            PinDragAreaView.dragWindow(of: self, with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let onCommandScroll {
            onCommandScroll(event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// Clip view that keeps a document smaller than the viewport centered.
final class PinCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let doc = documentView.frame
        if rect.width > doc.width {
            rect.origin.x = doc.midX - rect.width / 2
        }
        if rect.height > doc.height {
            rect.origin.y = doc.midY - rect.height / 2
        }
        return rect
    }
}

/// NSImageView document view that pans the enclosing scroll view on left-drag
/// when zoomed, and resets zoom on double-click. Opts out of window-move while
/// pannable so the drag pans rather than relocating the pin.
final class PinDraggableImageView: NSImageView {
    var onDoubleClick: (() -> Void)?
    private var lastWindowPoint: NSPoint?

    private var isPannable: Bool {
        (enclosingScrollView as? PinScrollView)?.isPannable ?? false
    }

    override var mouseDownCanMoveWindow: Bool { !isPannable }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        guard isPannable else {
            PinDragAreaView.dragWindow(of: self, with: event)
            return
        }
        lastWindowPoint = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPannable,
              let scrollView = enclosingScrollView,
              let last = lastWindowPoint else {
            super.mouseDragged(with: event)
            return
        }
        let now = event.locationInWindow
        // Window coordinates are stable across scrolling, unlike view coords.
        let dx = now.x - last.x
        let dy = now.y - last.y
        lastWindowPoint = now

        let mag = max(scrollView.magnification, 0.0001)
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        // Hand-tool panning: content follows the cursor (opposite of origin).
        origin.x -= dx / mag
        origin.y -= dy / mag
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    override func mouseUp(with event: NSEvent) {
        if lastWindowPoint != nil {
            lastWindowPoint = nil
            NSCursor.pop()
        }
        super.mouseUp(with: event)
    }
}

// MARK: - Debug logging
//
// Diagnostics for pin-image zoom, at debug level in the unified log
// (category "PinZoom"); free when debug logging is off.
enum PinZoomLog {
    static func log(_ message: @autoclosure () -> String) {
        ErrorLogger.shared.debug(message(), category: "PinZoom")
    }
}
