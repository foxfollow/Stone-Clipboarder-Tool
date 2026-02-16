//
//  QPCustomPreviewPanel.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026.
//

import AppKit
import SwiftUI

/// Custom SwiftUI-based preview panel for clipboard items.
/// Alternative to native QLPreviewPanel.
struct QPCustomPreviewPanel: View {
    let item: CBItem
    var triggerKeyHint: String = "⎵ to close"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            previewContent
        }
        .frame(width: 420, height: 400)
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
        .frame(maxHeight: 350)
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
        .frame(maxHeight: 350)
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
        switch item.itemType {
        case .text: return "Text"
        case .image: return "Image"
        case .file: return item.fileName ?? "File"
        case .combined: return "Text + Image"
        }
    }
}

// MARK: - Custom Preview Window Manager

/// Manages the custom NSPanel-based preview window lifecycle.
@MainActor
class QPCustomPreviewManager {
    private var previewWindow: NSPanel?
    var triggerKeyHint: String = "⎵ to close"

    var isPreviewVisible: Bool {
        previewWindow?.isVisible == true
    }

    func showPreview(for item: CBItem, relativeTo mainWindow: NSPanel?) {
        // If already visible, just update
        let hint = triggerKeyHint
        if let existing = previewWindow, existing.isVisible {
            let view = QPCustomPreviewPanel(item: item, triggerKeyHint: hint)
            existing.contentView = NSHostingView(rootView: view)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.borderless],
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

        let view = QPCustomPreviewPanel(item: item, triggerKeyHint: hint)
        panel.contentView = NSHostingView(rootView: view)

        // Position relative to main window
        if let mainWindow = mainWindow {
            let mainFrame = mainWindow.frame
            var origin = NSPoint(x: mainFrame.maxX + 8, y: mainFrame.origin.y)

            if let screen = NSScreen.main {
                if origin.x + 420 > screen.visibleFrame.maxX {
                    origin.x = mainFrame.minX - 420 - 8
                }
            }
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
        self.previewWindow = panel

        // Keep focus on main window
        DispatchQueue.main.async {
            mainWindow?.makeKey()
        }
    }

    func hidePreview() {
        previewWindow?.orderOut(nil)
        previewWindow?.close()
        previewWindow = nil
    }
}
