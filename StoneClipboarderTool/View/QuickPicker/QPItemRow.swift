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

    private var typeLabel: String {
        switch item.itemType {
        case .text: return "Text"
        case .image: return "Image"
        case .file: return "File"
        case .combined: return "Combined"
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
                }
            }

            Spacer()

            // Paste hint on selected row
            if isSelected {
                Text("⏎")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
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
