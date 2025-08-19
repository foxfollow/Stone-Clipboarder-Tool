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

                HStack {
                    Text(item.timestamp, style: .relative)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
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
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: item.itemType.sfSybmolName)
                .font(.title2)
                .foregroundStyle(item.itemType.sybmolColor)
                .frame(width: 40, height: 40)
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
