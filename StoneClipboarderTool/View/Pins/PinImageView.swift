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
//  Window-move interplay: a *zoomed-in* image pans on drag (and doesn't move
//  the window); a fit image still moves the window; the chrome bar always
//  moves the window. Driven by `mouseDownCanMoveWindow` + `isPannable`.
//
//  `zoom` is a multiplier on top of the fit scale: 1.0 == fit-to-window.
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
        private var scrollProbe: Any?

        init(zoom: Binding<Double>) {
            self.zoom = zoom
        }

        // MARK: Magnify monitor

        func startMagnifyMonitor() {
            guard magnifyMonitor == nil else { return }
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                self?.handleMagnify(event)
                return event
            }
            // Diagnostic: also watch scroll wheel so we can tell whether ANY
            // trackpad events reach our app over the pin window.
            scrollProbe = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.probeScroll(event)
                return event
            }
            PinZoomLog.log("startMagnifyMonitor: installed local .magnify monitor")
        }

        func stopMagnifyMonitor() {
            if let m = magnifyMonitor {
                NSEvent.removeMonitor(m)
                magnifyMonitor = nil
            }
            if let m = scrollProbe {
                NSEvent.removeMonitor(m)
                scrollProbe = nil
            }
        }

        private func probeScroll(_ event: NSEvent) {
            guard let win = scrollView?.window else { return }
            let mine = event.window === win
            PinZoomLog.log("scrollWheel: eventWindow=\(Self.desc(event.window)) myWindow=\(Self.desc(win)) mine=\(mine)")
        }

        private func handleMagnify(_ event: NSEvent) {
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
                return
            }
            guard fitMagnification > 0 else {
                PinZoomLog.log("magnify SKIP: fitMagnification not ready (\(fitMagnification))")
                return
            }

            let minMag = fitMagnification * 0.25
            let maxMag = fitMagnification * 8.0
            let factor = 1 + event.magnification
            let oldMag = scrollView.magnification
            let newMag = max(minMag, min(maxMag, oldMag * factor))

            // Zoom toward the cursor for a natural feel.
            let pointInClip = scrollView.contentView.convert(event.locationInWindow, from: nil)
            scrollView.setMagnification(newMag, centeredAt: pointInClip)

            zoom.wrappedValue = max(0.25, min(8.0, Double(newMag / fitMagnification)))
            updatePannable()
            PinZoomLog.log(
                "magnify APPLY: \(String(format: "%.4f", oldMag)) -> \(String(format: "%.4f", newMag)) "
                + "(after set: \(String(format: "%.4f", scrollView.magnification))) zoom=\(String(format: "%.3f", zoom.wrappedValue))"
            )
        }

        private static func desc(_ window: NSWindow?) -> String {
            guard let window else { return "nil" }
            return "\(type(of: window))#\(UInt(bitPattern: ObjectIdentifier(window).hashValue) % 10000)"
        }

        // MARK: Layout

        /// Keep the document sized to the image and the fit baseline current.
        /// Applies the persisted zoom only on first valid layout; afterward it
        /// leaves the magnification alone (the monitor / user own it).
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

            if !didInitialFit {
                scrollView.magnification = fit * CGFloat(zoom.wrappedValue)
                didInitialFit = true
                PinZoomLog.log(
                    "applyLayout INITIAL FIT: clip=\(Int(clip.width))x\(Int(clip.height)) "
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

// MARK: - Debug logging
//
// Temporary diagnostics for pin-image zoom. Prints to stdout (visible in the
// Xcode console) with a "[PinZoom]" prefix so it's easy to filter and copy.
enum PinZoomLog {
    static func log(_ message: String) {
        // DEBUG if needed: uncomment to trace pin-image zoom in the console.
        // let ts = Self.formatter.string(from: Date())
        // print("[PinZoom \(ts)] \(message)")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
