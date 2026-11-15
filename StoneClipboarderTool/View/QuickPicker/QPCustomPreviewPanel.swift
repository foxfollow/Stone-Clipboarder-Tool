//
//  QPCustomPreviewPanel.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Custom SwiftUI-based preview panel for clipboard items and Passwords
/// entries. Alternative to native QLPreviewPanel; renders from memory, so
/// nothing is written to disk (the Passwords tab relies on that).
struct QPCustomPreviewPanel: View {
    let item: QPPreviewContent
    var triggerKeyHint: String = "⎵ to close"
    var size = QPCustomPreviewManager.compactSize
    var isExpanded = false
    /// Nil hides the expand button.
    var onToggleExpanded: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            previewContent
        }
        .frame(width: size.width, height: size.height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Image(systemName: iconForType)
                .foregroundStyle(.secondary)
            Text(titleForType)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Text(triggerKeyHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let onToggleExpanded {
                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded
                          ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Smaller (⌥⎵)" : "Larger (⌥⎵)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.itemType {
        case .text:
            textPreview
        case .image:
            imagePreview(data: item.imageData)
        case .file:
            if item.isImageFile, let data = item.fileData {
                imagePreview(data: data)
            } else {
                filePreview
            }
        case .combined:
            combinedPreview
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        ScrollView {
            let text = item.content ?? "No content"
            let displayText = text.count > 10_000
                ? String(text.prefix(10_000)) + "\n\n... (\(text.count - 10_000) more characters)"
                : text
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func imagePreview(data: Data?) -> some View {
        if let data = data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        } else {
            ContentUnavailableView("Image unavailable", systemImage: "photo")
        }
    }

    @ViewBuilder
    private var filePreview: some View {
        VStack(spacing: 12) {
            Spacer()
            if let fileName = item.fileName {
                let url = URL(fileURLWithPath: fileName)
                let icon = NSWorkspace.shared.icon(for: .init(filenameExtension: url.pathExtension) ?? .data)
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
            Text(item.fileName ?? "Unknown File")
                .font(.headline)
                .lineLimit(2)
            if let data = item.fileData {
                Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    @ViewBuilder
    private var combinedPreview: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let content = item.content, !content.isEmpty {
                    let displayText = content.count > 10_000
                        ? String(content.prefix(10_000)) + "\n\n... (\(content.count - 10_000) more characters)"
                        : content
                    Text(displayText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let data = item.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    private var iconForType: String {
        switch item.itemType {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .combined: return "doc.richtext"
        }
    }

    private var titleForType: String {
        if let title = item.title { return title }
        switch item.itemType {
        case .text: return "Text"
        case .image: return "Image"
        case .file: return item.fileName ?? "File"
        case .combined: return "Text + Image"
        }
    }
}

/// What the preview shows, copied from a history item or a Passwords
/// entry so the panel never holds a model (or plaintext on disk).
struct QPPreviewContent {
    let itemType: CBItemType
    let title: String?
    let content: String?
    let imageData: Data?
    let fileData: Data?
    let fileName: String?
    let isImageFile: Bool

    init(item: CBItem) {
        itemType = item.itemType
        title = item.displayTitle
        content = item.content
        imageData = item.imageData
        fileData = item.fileData
        fileName = item.fileName
        isImageFile = item.isImageFile
    }

    init(entry: VaultPayload) {
        itemType = entry.itemType
        title = entry.title
        content = entry.content
        imageData = entry.imageData
        fileData = entry.fileData
        fileName = entry.fileName
        isImageFile = entry.fileUTI.flatMap { UTType($0) }?.conforms(to: .image) == true
    }
}

// MARK: - Custom Preview Window Manager

/// Manages the custom NSPanel-based preview window lifecycle.
@MainActor
class QPCustomPreviewManager {
    static let compactSize = CGSize(width: 420, height: 400)

    private var previewWindow: NSPanel?
    private weak var mainWindow: NSPanel?
    private var content: QPPreviewContent?
    var triggerKeyHint: String = "⎵ to close"
    /// Most of the screen instead of the panel beside the picker.
    private(set) var isExpanded = false
    /// Shows the expand button (the Passwords preview; Quick Look has its own).
    var allowsExpanding = false

    var isPreviewVisible: Bool {
        previewWindow?.isVisible == true
    }

    func showPreview(for item: CBItem, relativeTo mainWindow: NSPanel?) {
        showPreview(content: QPPreviewContent(item: item), relativeTo: mainWindow)
    }

    func showPreview(content: QPPreviewContent, relativeTo mainWindow: NSPanel?, expanded: Bool? = nil) {
        self.content = content
        self.mainWindow = mainWindow
        if let expanded { isExpanded = expanded }

        // If already visible, just update
        if let existing = previewWindow, existing.isVisible {
            render(in: existing)
            return
        }

        // .nonactivatingPanel is required so the preview can render alongside
        // another app's fullscreen Space without forcing a Space switch — the
        // QuickPicker panel uses the same flag for the same reason. Without
        // it, an activating borderless panel resolves to our app's home
        // Space instead of the user's current fullscreen Space.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]

        render(in: panel)
        panel.orderFrontRegardless()
        self.previewWindow = panel

        // Keep focus on main window
        DispatchQueue.main.async {
            mainWindow?.makeKey()
        }
    }

    /// Switches between the panel beside the picker and most of the screen.
    func toggleExpanded() {
        isExpanded.toggle()
        guard let panel = previewWindow, panel.isVisible else { return }
        render(in: panel)
    }

    func hidePreview() {
        previewWindow?.orderOut(nil)
        previewWindow?.close()
        previewWindow = nil
        content = nil
        isExpanded = false
    }

    private func render(in panel: NSPanel) {
        guard let content else { return }
        let frame = targetFrame()
        let view = QPCustomPreviewPanel(
            item: content, triggerKeyHint: triggerKeyHint, size: frame.size, isExpanded: isExpanded,
            onToggleExpanded: allowsExpanding ? { [weak self] in self?.toggleExpanded() } : nil)
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(frame, display: true)
    }

    /// Beside the picker (left if there's no room on the right), or 85 % of
    /// the picker's screen when expanded.
    private func targetFrame() -> NSRect {
        let screen = mainWindow?.screen ?? NSScreen.main
        if isExpanded, let visible = screen?.visibleFrame {
            let size = CGSize(width: visible.width * 0.85, height: visible.height * 0.85)
            return NSRect(
                origin: NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2), size: size)
        }
        let size = Self.compactSize
        guard let mainFrame = mainWindow?.frame else { return NSRect(origin: .zero, size: size) }
        var origin = NSPoint(x: mainFrame.maxX + 8, y: mainFrame.origin.y)
        if let screen, origin.x + size.width > screen.visibleFrame.maxX {
            origin.x = mainFrame.minX - size.width - 8
        }
        return NSRect(origin: origin, size: size)
    }
}
