//
//  PinDragArea.swift
//  StoneClipboarderTool
//
//  Transparent AppKit strip behind the pin chrome that moves the pin.
//  `isMovableByWindowBackground` doesn't work over SwiftUI content (the
//  hosting view swallows the mouse-down), so the drag is started explicitly
//  with `performDrag`. A locked pin (`isMovable == false`) doesn't move.
//

import AppKit
import SwiftUI

struct PinDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> PinDragAreaView {
        let view = PinDragAreaView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: PinDragAreaView, context: Context) {
        view.onDoubleClick = onDoubleClick
    }
}

final class PinDragAreaView: NSView {
    var onDoubleClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        Self.dragWindow(of: self, with: event)
    }

    /// Moves `view`'s window with the mouse unless the window is locked.
    static func dragWindow(of view: NSView, with event: NSEvent) {
        guard let window = view.window, window.isMovable else { return }
        window.performDrag(with: event)
    }
}
