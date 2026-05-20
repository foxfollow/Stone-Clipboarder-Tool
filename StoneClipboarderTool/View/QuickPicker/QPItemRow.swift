//
//  QPItemRow.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.08.2025.
//

import SwiftData
import SwiftUI

struct QPItemRow: View {
    let item: CBItem
    let isSelected: Bool
    // True when this row is part of a Shift+Arrow range but is not the
    // current cursor row (the cursor row uses `isSelected`).
    var isInMultiSelection: Bool = false
    var showOCRHint: Bool = false
    var isPinned: Bool = false

    private var typeLabel: String {
        switch item.itemType {
        case .text: return "Text"
        case .image: return "Image"
        case .file: return "File"
        case .combined: return "Combined"
        }
    }

    // OCR is only meaningful on image content.
    private var isImageLike: Bool {
        switch item.itemType {
        case .image, .combined:
            return true
        case .file:
            return item.isImageFile
        case .text:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon or thumbnail
            iconView

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayContent)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(item.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(typeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Spacer()

            // Inline action hints on the selected row: ⌥⏎ OCR (image-like
            // items only, when enabled in settings), then ⏎ Paste.
            if isSelected {
                HStack(spacing: 4) {
                    if showOCRHint && isImageLike {
                        Text("OCR:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        rowKeyBadge("⌥⏎", help: "Extract text (OCR)")
                    }
                    rowKeyBadge("⏎", help: "Paste")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderStroke, lineWidth: 1)
        )
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.2) }
        if isInMultiSelection { return Color.accentColor.opacity(0.1) }
        return Color.clear
    }

    private var borderStroke: Color {
        if isSelected { return Color.accentColor.opacity(0.5) }
        if isInMultiSelection { return Color.accentColor.opacity(0.25) }
        return Color.clear
    }

    private func rowKeyBadge(_ key: String, help: String) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
            )
            .help(help)
    }

    @ViewBuilder
    private var iconView: some View {
        if item.itemType == .image || (item.itemType == .file && item.isImageFile) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: item.itemType.sfSybmolName)
                        .font(.title2)
                        .foregroundStyle(item.itemType.sybmolColor)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        } else {
            Image(systemName: item.itemType.sfSybmolName)
                .font(.system(size: 18))
                .foregroundStyle(item.itemType.sybmolColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.itemType.sybmolColor.opacity(0.12))
                )
        }
    }
}

#Preview {
    let sampleImageData = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8//8/AwAI/wP+z4kAAAAASUVORK5CYII="
    )
    QPItemRow(
        item: CBItem(
            timestamp: Date(), content: nil, imageData: sampleImageData, fileData: nil,
            fileName: nil, fileUTI: nil, itemType: .image, isFavorite: false, orderIndex: 0),
        isSelected: false)
}
