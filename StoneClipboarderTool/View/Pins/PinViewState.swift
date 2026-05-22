//
//  PinViewState.swift
//  StoneClipboarderTool
//
//  Plain, context-free snapshot of a pinned item used for rendering.
//
//  Why this exists: PinnedItemConfig is a SwiftData @Model whose content
//  fields (`content`, `imageData`, `fileData`) use @Attribute(.externalStorage).
//  Reading those off the live model during a SwiftUI body evaluation crashes
//  ("backing data was detached from a context without resolving attribute
//  faults") whenever the object faults or its context churns. We therefore
//  read every external-storage value exactly once — at creation, while the
//  context is valid — copy it into plain Swift values here, and render only
//  from this object. The model is then used solely to persist small scalar
//  fields (frame, opacity, flags).
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PinViewState: ObservableObject {
    // Immutable content snapshot (no SwiftData dependency after init).
    let itemType: CBItemType
    let content: String?
    let imageData: Data?
    let fileData: Data?
    let fileName: String?
    let fileUTI: String?
    /// Pre-decoded image for display (covers .image / .combined and image files).
    let displayImage: NSImage?

    // Mutable UI state — mirrored to PinnedItemConfig for persistence.
    @Published var opacity: Double
    @Published var isLocked: Bool
    @Published var isClickThrough: Bool
    @Published var isCollapsed: Bool
    @Published var imageZoom: Double
    @Published var editedText: String

    init(config: PinnedItemConfig) {
        let type = config.itemType
        self.itemType = type

        // One-time reads of external-storage properties (context still valid).
        let contentSnapshot = config.content
        let imageSnapshot = config.imageData
        let fileSnapshot = config.fileData

        self.content = contentSnapshot
        self.imageData = imageSnapshot
        self.fileData = fileSnapshot
        self.fileName = config.fileName
        self.fileUTI = config.fileUTI

        switch type {
        case .image, .combined:
            self.displayImage = imageSnapshot.flatMap { NSImage(data: $0) }
        case .file:
            // Only decode image-type files for preview.
            if let uti = config.fileUTI,
               UTTypeIsImage(uti),
               let data = fileSnapshot {
                self.displayImage = NSImage(data: data)
            } else {
                self.displayImage = nil
            }
        case .text:
            self.displayImage = nil
        }

        self.opacity = config.opacity
        self.isLocked = config.isLocked
        self.isClickThrough = config.isClickThrough
        self.isCollapsed = config.isCollapsed
        self.imageZoom = config.imageZoom
        self.editedText = contentSnapshot ?? ""
    }
}

private func UTTypeIsImage(_ uti: String) -> Bool {
    UTType(uti)?.conforms(to: .image) ?? false
}
