//
//  PinLiveText.swift
//  StoneClipboarderTool
//
//  Live Text for image pins: VisionKit finds the text in the image (on the
//  Mac, like Preview and Photos) and a toggle at the bottom right turns
//  selecting it on and off.
//
//  VisionKit's ImageAnalysisOverlayView takes every click over the image,
//  which would end panning and moving the pin by dragging the image. So it
//  sits in a container that lets clicks through until Live Text is on, and
//  the pin draws its own toggle instead of VisionKit's (which also sits at
//  the top right, over the chrome).
//
//  The analysis runs once, the first time the pointer enters the pin, and
//  only in memory. Nothing it finds is stored or logged.
//

import AppKit
import VisionKit

@MainActor
final class PinLiveText: NSObject, ImageAnalysisOverlayViewDelegate {
    let container = PinLiveTextContainer()
    let overlay = ImageAnalysisOverlayView()
    let button = PinLiveTextButton()
    /// The image's view inside the scroll view; the overlay follows it.
    weak var imageView: NSView?
    /// Live Text turned on or off (the pin shows a hint).
    var onActiveChange: ((Bool) -> Void)?

    private(set) var isActive = false
    private var image: NSImage?
    private var analyzedImage: NSImage?
    private var analysisTask: Task<Void, Never>?

    override init() {
        super.init()
        overlay.delegate = self
        overlay.preferredInteractionTypes = .automaticTextOnly
        overlay.isSupplementaryInterfaceHidden = true
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)
        button.isHidden = true
        button.target = self
        button.action = #selector(toggle)
    }

    deinit {
        analysisTask?.cancel()
    }

    /// The image changed: forget the old analysis; the next hover analyzes.
    func setImage(_ newImage: NSImage?) {
        guard newImage !== image else { return }
        image = newImage
        analysisTask?.cancel()
        analyzedImage = nil
        overlay.analysis = nil
        button.isHidden = true
        setActive(false)
    }

    /// Analyzes the image once (the first hover). The toggle appears only
    /// when there is text to select.
    func analyzeIfNeeded() {
        guard ImageAnalyzer.isSupported, let image, analyzedImage !== image else { return }
        analyzedImage = image
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
            let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: configuration)
            guard let self, !Task.isCancelled, self.image === image else { return }
            self.overlay.analysis = analysis
            self.overlay.setContentsRectNeedsUpdate()
            self.button.isHidden = !(analysis?.hasResults(for: .text) ?? false)
        }
    }

    /// Scroll, zoom or resize moved the image.
    func contentsMoved() {
        guard overlay.analysis != nil else { return }
        overlay.setContentsRectNeedsUpdate()
    }

    @objc private func toggle() {
        setActive(!isActive)
        onActiveChange?(isActive)
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        container.isActive = active
        button.isOn = active
        overlay.selectableItemsHighlighted = active
        if !active {
            overlay.resetSelection()
        }
    }

    /// ⌘C with text selected in the image: copies that text. False when
    /// nothing is selected, so ⌘C copies the whole pin as before.
    func copySelection() -> Bool {
        guard isActive, overlay.hasActiveTextSelection else { return false }
        let text = overlay.selectedText
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    // MARK: ImageAnalysisOverlayViewDelegate

    /// Where the image is inside the overlay, in unit coordinates of the
    /// overlay's own (unflipped) space. It moves with scrolling and zoom.
    func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
        guard let imageView, overlayView.bounds.width > 0, overlayView.bounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let rect = overlayView.convert(imageView.bounds, from: imageView)
        let bounds = overlayView.bounds
        return CGRect(
            x: (rect.minX - bounds.minX) / bounds.width,
            y: (rect.minY - bounds.minY) / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        )
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        shouldBeginAt point: CGPoint,
        forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes
    ) -> Bool {
        isActive
    }
}

/// Holds the overlay; clicks pass through to the image until Live Text is on.
final class PinLiveTextContainer: NSView {
    var isActive = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isActive ? super.hitTest(point) : nil
    }
}

/// The round Live Text toggle at the bottom right of an image pin.
final class PinLiveTextButton: NSButton {
    static let size: CGFloat = 28

    var isOn = false {
        didSet { updateLook() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Live Text")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        wantsLayer = true
        layer?.cornerRadius = Self.size / 2
        toolTip = "Live Text: select and copy the text in this image"
        setAccessibilityLabel("Live Text")
        updateLook()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func updateLook() {
        layer?.backgroundColor = (isOn
            ? NSColor.controlAccentColor
            : NSColor.black.withAlphaComponent(0.55)).cgColor
        contentTintColor = .white
        setAccessibilityValue(isOn ? "On" : "Off")
    }
}
