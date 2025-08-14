//
//  MenuBarItemView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.08.2025.
//

import SwiftUI

struct MenuBarItemView: View {
    let item: CBItem
    
    private var contentPreview: String {
        let display = item.displayContent
        return display.count > 50 ? String(display.prefix(50)) + "..." : display
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contentPreview)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let image = item.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 100)
                        .cornerRadius(4)
                } else if let fileImage = item.filePreviewImage, item.fileData != nil {
                    Image(nsImage: fileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: item.isImageFile ? 100 : 36)
                        .cornerRadius(4)
                }
                
                Text(item.timestamp, format: Date.FormatStyle(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: item.itemType.sfSybmolName)
                .foregroundStyle(item.itemType.sybmolColor)
                .imageScale(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .background(
            Rectangle()
                .fill(Color.blue.opacity(0.1))
                .opacity(0)
        )
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                // Visual feedback handled by system
            }
        }
    }
}

