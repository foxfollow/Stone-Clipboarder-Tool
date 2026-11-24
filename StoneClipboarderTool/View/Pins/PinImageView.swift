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
//  with the window. ⌘-scroll zooms too (for a mouse without pinch), and
//  ⌘+ / ⌘− / ⌘0 zoom from the keyboard while the pin is key.
//  Double-click resets to fit; a two-finger double-tap toggles fit / 2×.
//  None of that is discoverable, so the pin says so: a tooltip, a hint the
//  first time the pointer enters each pin view, and a zoom badge on every change.
//
//  Smoothness: the image is a layer's contents, so magnifying scales a GPU
//  texture instead of redrawing (and resampling) the whole bitmap on every
//  gesture event. The zoom multiplier lives in the coordinator while a
//  gesture runs and reaches the `zoom` binding (SwiftUI state + persistence)
//  only once the gesture settles, so the pin's SwiftUI body isn't rebuilt
//  60 times a second.
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
        scrollView.onSmartMagnify = { [weak coordinator = context.coordinator] event in
            coordinator?.handleSmartMagnify(event)
        }

        scrollView.toolTip = PinScrollView.zoomHelp
        context.coordinator.startMagnifyMonitor()
        PinZoomLog.log("makeNSView: image=\(image.map { "\($0.size.width)x\($0.size.height)" } ?? "nil")")

        return scrollView
    }

    func updateNSView(_ scrollView: PinScrollView, context: Context) {
        context.coordinator.image = image
        if let imageView = scrollView.documentView as? PinDraggableImageView,
           imageView.image !== image {
            imageView.image = image
        }
        context.coordinator.syncExternalZoom(zoom)
        context.coordinator.applyLayout()
    }

    static func dismantleNSView(_ nsView: PinScrollView, coordinator: Coordinator) {
        coordinator.stopMagnifyMonitor()
        // Dismantling runs inside a SwiftUI update; publishing the zoom from
        // here would be a change during a view update.
        DispatchQueue.main.async { coordinator.flushZoom() }
    }

    @MainActor
    final class Coordinator: NSObject {
        let zoom: Binding<Double>
        weak var scrollView: PinScrollView?
        weak var imageView: PinDraggableImageView?
        var image: NSImage?
        var fitMagnification: CGFloat = 1.0
        private var didInitialFit = false
        nonisolated(unsafe) private var magnifyMonitor: Any?
        nonisolated(unsafe) private var commitWorkForDeinit: DispatchWorkItem?
        private var lastClipSize: NSSize = .zero
        /// Live zoom multiplier (1.0 == fit). Source of truth while a gesture
        /// runs; the binding catches up in `commitZoomSoon`.
        private var currentZoom: Double
        /// Last value written to (or read from) the binding.
        private var reportedZoom: Double
        private var commitWork: DispatchWorkItem?

        init(zoom: Binding<Double>) {
            self.zoom = zoom
            self.currentZoom = zoom.wrappedValue
            self.reportedZoom = zoom.wrappedValue
        }

        deinit {
            if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
            commitWorkForDeinit?.cancel()
        }

        /// Picks up a zoom change made outside this view (e.g. a restored
        /// config), ignoring the echo of our own commits.
        func syncExternalZoom(_ value: Double) {
            guard abs(value - reportedZoom) > 0.0001 else { return }
            reportedZoom = value
            currentZoom = value
            if let scrollView, fitMagnification > 0, didInitialFit {
                scrollView.magnification = fitMagnification * CGFloat(value)
                updatePannable()
            }
        }

        private func commitZoomSoon() {
            commitWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flushZoom() }
            commitWork = work
            commitWorkForDeinit = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        func flushZoom() {
            commitWork?.cancel()
            commitWork = nil
            guard abs(currentZoom - reportedZoom) > 0.0001 else { return }
            reportedZoom = currentZoom
            zoom.wrappedValue = currentZoom
        }

        // MARK: Magnify monitor

        func startMagnifyMonitor() {
            guard magnifyMonitor == nil else { return }
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.magnify, .smartMagnify, .keyDown]
            ) { [weak self] event in
                guard let self else { return event }
                let handled: Bool
                switch event.type {
                case .smartMagnify: handled = self.handleSmartMagnify(event)
                case .keyDown: handled = self.handleZoomKey(event)
                default: handled = self.handleMagnify(event)
                }
                return handled ? nil : event
            }
            PinZoomLog.log("startMagnifyMonitor: installed local magnify / smartMagnify / zoom-key monitor")
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
            if event.phase == .ended || event.phase == .cancelled {
                flushZoom()
            }
            return true
        }

        /// Two-finger double-tap: zoom to 2× at the pointer, or back to fit.
        @discardableResult
        func handleSmartMagnify(_ event: NSEvent) -> Bool {
            guard let scrollView, let window = scrollView.window,
                  event.window === window, fitMagnification > 0 else { return false }
            _ = scrollView
            if currentZoom > 1.01 {
                resetZoom()
            } else {
                zoom(by: 2 / max(CGFloat(currentZoom), 0.0001), at: event.locationInWindow, animated: true)
                flushZoom()
            }
            return true
        }

        /// ⌘+ / ⌘= zoom in, ⌘− zoom out, ⌘0 fit. Matched by the typed
        /// character (German `+` and AZERTY `-` sit on other keys than US),
        /// with the keypad and the US key positions as a fallback for
        /// layouts that type no Latin character there.
        func handleZoomKey(_ event: NSEvent) -> Bool {
            guard let scrollView, let window = scrollView.window,
                  event.window === window, fitMagnification > 0 else { return false }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard mods == .command || mods == [.command, .shift] else { return false }

            let clip = scrollView.contentView
            let center = clip.convert(NSPoint(x: clip.bounds.midX, y: clip.bounds.midY), to: nil)
            switch Self.zoomKey(for: event) {
            case .zoomIn: zoom(by: 1.25, at: center, animated: true)
            case .zoomOut: zoom(by: 0.8, at: center, animated: true)
            case .fit: resetZoom()
            case nil: return false
            }
            flushZoom()
            return true
        }

        private enum ZoomKey { case zoomIn, zoomOut, fit }

        private static func zoomKey(for event: NSEvent) -> ZoomKey? {
            switch event.keyCode {
            case 69: return .zoomIn   // keypad +
            case 78: return .zoomOut  // keypad -
            case 82: return .fit      // keypad 0
            default: break
            }
            let chars = event.charactersIgnoringModifiers ?? ""
            switch chars {
            case "+", "=": return .zoomIn
            case "-", "−": return .zoomOut
            case "0": return .fit
            default: break
            }
            // A layout that types something non-ASCII on these keys: fall
            // back to the US positions.
            guard chars.unicodeScalars.contains(where: { !$0.isASCII }) else { return nil }
            switch event.keyCode {
            case 24: return .zoomIn
            case 27: return .zoomOut
            case 29: return .fit
            default: return nil
            }
        }

        /// ⌘-scroll zoom. Trackpads send many small precise deltas, wheels
        /// send a few coarse lines; an exponential step keeps zoom-in and
        /// zoom-out symmetric.
        func handleCommandScroll(_ event: NSEvent) {
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.005 : 0.08
            let factor = max(0.5, min(2.0, exp(event.scrollingDeltaY * step)))
            zoom(by: factor, at: event.locationInWindow)
        }

        private func zoom(by factor: CGFloat, at locationInWindow: NSPoint, animated: Bool = false) {
            guard let scrollView = scrollView, fitMagnification > 0 else { return }
            let minMag = fitMagnification * 0.25
            let maxMag = fitMagnification * 8.0
            // Step from the target, not `scrollView.magnification`: while an
            // animated step runs that still holds an in-between value.
            let oldMag = fitMagnification * CGFloat(currentZoom)
            let newMag = max(minMag, min(maxMag, oldMag * factor))

            // Zoom toward the cursor for a natural feel.
            let pointInClip = scrollView.contentView.convert(locationInWindow, from: nil)
            if animated {
                scrollView.animator().setMagnification(newMag, centeredAt: pointInClip)
            } else {
                scrollView.setMagnification(newMag, centeredAt: pointInClip)
            }

            currentZoom = max(0.25, min(8.0, Double(newMag / fitMagnification)))
            commitZoomSoon()
            updatePannable(magnification: newMag)
            showZoomBadge()
            PinZoomLog.log(
                "zoom APPLY: \(String(format: "%.4f", oldMag)) -> \(String(format: "%.4f", newMag)) "
                + "zoom=\(String(format: "%.3f", currentZoom))"
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
            // Layout has already resized the clip around its old origin, so
            // work out the old center from the old clip size.
            let clipView = scrollView.contentView
            let oldMag = max(scrollView.magnification, 0.0001)
            let oldSize = lastClipSize == .zero ? clip : lastClipSize
            let center = NSPoint(
                x: clipView.bounds.minX + oldSize.width / oldMag / 2,
                y: clipView.bounds.minY + oldSize.height / oldMag / 2
            )
            lastClipSize = clip

            let fit = min(clip.width / natural.width, clip.height / natural.height)
            let fitChanged = abs(fit - fitMagnification) > fit * 0.0001
            fitMagnification = fit

            // NSScrollView clamps to 0.25…4.0 by default, which cuts zoom off
            // early for large or small images.
            scrollView.minMagnification = fit * 0.25
            scrollView.maxMagnification = fit * 8.0

            if !didInitialFit || fitChanged {
                // Keep whatever was in the middle of the pin in the middle
                // while the window resizes.
                scrollView.magnification = fit * CGFloat(currentZoom)
                if didInitialFit {
                    let b = clipView.bounds
                    clipView.scroll(to: NSPoint(x: center.x - b.width / 2, y: center.y - b.height / 2))
                    scrollView.reflectScrolledClipView(clipView)
                }
                didInitialFit = true
                PinZoomLog.log(
                    "applyLayout FIT: clip=\(Int(clip.width))x\(Int(clip.height)) "
                    + "natural=\(Int(natural.width))x\(Int(natural.height)) fit=\(String(format: "%.4f", fit)) "
                    + "magnification=\(String(format: "%.4f", scrollView.magnification))"
                )
            }
            updatePannable()
        }

        private func updatePannable(magnification: CGFloat? = nil) {
            guard let scrollView = scrollView else { return }
            let mag = magnification ?? scrollView.magnification
            scrollView.isPannable = mag > fitMagnification * 1.001
        }

        func resetZoom() {
            guard let scrollView = scrollView else { return }
            // The animator's value lags behind, so judge pannability by the
            // target rather than reading magnification back mid-animation.
            scrollView.animator().magnification = fitMagnification
            currentZoom = 1.0
            flushZoom()
            updatePannable(magnification: fitMagnification)
            showZoomBadge()
        }

        private func showZoomBadge() {
            let label = abs(currentZoom - 1) < 0.005
                ? "Fit"
                : "\(Int((currentZoom * 100).rounded()))%"
            scrollView?.showHint("\(label)   ⌘+  ⌘−  ⌘0 fit")
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
    var onSmartMagnify: ((NSEvent) -> Void)?

    static let zoomHelp = """
        Zoom: pinch, ⌘-scroll, or ⌘+ / ⌘−
        Fit: ⌘0 or double-click
        Two-finger double-tap: fit ↔ 2×
        Drag to pan when zoomed in
        """

    private let hintLabel = PinHintLabel()
    private var hintHide: DispatchWorkItem?
    private var didShowIntroHint = false
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(hintLabel)
    }

    /// Shows a small badge at the bottom of the pin, then fades it out.
    func showHint(_ text: String, duration: TimeInterval = 1.4) {
        hintLabel.stringValue = text
        positionHint()
        hintHide?.cancel()
        if hintLabel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                hintLabel.animator().alphaValue = 1
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.hintLabel.animator().alphaValue = 0
            }
        }
        hintHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func positionHint() {
        let size = hintLabel.fittingSize
        let width = min(size.width + 16, bounds.width - 12)
        hintLabel.frame = NSRect(
            x: (bounds.width - width) / 2,
            y: 8,
            width: max(width, 0),
            height: size.height + 6
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    /// The first time the pointer enters, say how to zoom.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard !didShowIntroHint else { return }
        didShowIntroHint = true
        showHint("Pinch or ⌘-scroll · ⌘+ ⌘− zoom · ⌘0 fit", duration: 2.5)
    }

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

    override func smartMagnify(with event: NSEvent) {
        if let onSmartMagnify {
            onSmartMagnify(event)
        } else {
            super.smartMagnify(with: event)
        }
    }

    override func layout() {
        super.layout()
        positionHint()
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

/// Rounded, click-through badge for zoom hints.
final class PinHintLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        lineBreakMode = .byTruncatingTail
        font = .systemFont(ofSize: 11, weight: .medium)
        textColor = .white
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = 7
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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

/// Layer-backed image document view. The image is the layer's contents, so
/// the scroll view's magnification scales a texture on the GPU instead of
/// redrawing the bitmap. Pans the enclosing scroll view on left-drag when
/// zoomed, and resets zoom on double-click. Opts out of window-move while
/// pannable so the drag pans rather than relocating the pin.
final class PinDraggableImageView: NSView {
    var onDoubleClick: (() -> Void)?
    private var lastWindowPoint: NSPoint?

    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.contentsGravity = .resizeAspect
        // Trilinear keeps big screenshots clean when shown smaller than
        // their natural size; linear is the smooth default when enlarged.
        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .linear
        let scale = window?.backingScaleFactor ?? 2
        layer.contents = image?.layerContents(forContentsScale: scale)
        layer.contentsScale = scale
    }

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
