//
//  PinImageView.swift
//  StoneClipboarderTool
//
//  Zoomable / pannable image renderer for pinned windows, backed by an
//  AppKit NSScrollView so we get native scrollbars, trackpad pinch-zoom, and
//  click-drag panning.
//
//  Window-move interplay: the pin panel is movable by dragging its
//  background. We want a *zoomed-in* image to pan on drag instead of moving
//  the window, but a fit (un-zoomed) image to still move the window — and the
//  chrome bar always moves the window. We do this by toggling
//  `mouseDownCanMoveWindow` on the scroll view based on whether the image is
//  currently pannable (magnified beyond fit).
//
//  `zoom` is a multiplier on top of the fit scale: 1.0 == fit-to-window,
//  2.0 == twice as large, etc. Double-click resets to fit.
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
        scrollView.allowsMagnification = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.black.withAlphaComponent(0.04)

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

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.liveMagnifyEnded(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

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
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        let zoom: Binding<Double>
        weak var scrollView: PinScrollView?
        weak var imageView: NSImageView?
        var image: NSImage?
        var fitMagnification: CGFloat = 1.0
        // The fit baseline is applied exactly once. After that the user's
        // pinch owns the magnification — we never reprogram it from SwiftUI
        // updates or layout passes (that was what snapped the zoom back to
        // fit on every re-render / focus change).
        private var didInitialFit = false

        init(zoom: Binding<Double>) {
            self.zoom = zoom
        }

        /// Keep the document sized to the image and the fit baseline current.
        /// Applies the persisted zoom only on first valid layout; afterward it
        /// leaves the live magnification untouched.
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
            fitMagnification = fit

            scrollView.minMagnification = fit * 0.25
            scrollView.maxMagnification = fit * 8.0

            if !didInitialFit {
                // First real layout: honor the persisted zoom (1.0 == fit).
                scrollView.magnification = fit * CGFloat(zoom.wrappedValue)
                didInitialFit = true
            }
            updatePannable()
        }

        private func updatePannable() {
            guard let scrollView = scrollView else { return }
            scrollView.isPannable = scrollView.magnification > fitMagnification * 1.001
        }

        @objc nonisolated func liveMagnifyEnded(_ note: Notification) {
            MainActor.assumeIsolated {
                guard let scrollView = scrollView, fitMagnification > 0 else { return }
                // Persist the new zoom (relative to fit) without reprogramming
                // the magnification — it's already where the user left it.
                let newZoom = Double(scrollView.magnification / fitMagnification)
                zoom.wrappedValue = max(0.25, min(8.0, newZoom))
                updatePannable()
            }
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

    override var mouseDownCanMoveWindow: Bool { !isPannable }

    override func layout() {
        super.layout()
        onLayout?()
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

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        guard isPannable else {
            super.mouseDown(with: event)
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
