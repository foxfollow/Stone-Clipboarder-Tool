//
//  QPItemRow.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.08.2025.
//

import SwiftUI

struct QPItemRow: View {
    let item: CBItem
    let isSelected: Bool
    
    private var displayText: String {
        return item.displayContent
    }
    
    private var icon: String {
        return item.itemType.sfSybmolName
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: item.itemType.sfSybmolName)
                    .foregroundColor(item.itemType.sybmolColor)
                    .imageScale(.small)
                
                Text(displayText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if item.itemType == .image, let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
            } else if item.itemType == .file && item.isImageFile, let image = item.filePreviewImage {
                //                if  {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            //            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
//        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    let sampleImageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8//8/AwAI/wP+z4kAAAAASUVORK5CYII=")
    QPItemRow(item: CBItem(timestamp: Date(), content: nil, imageData: sampleImageData, fileData: nil, fileName: nil, fileUTI: nil, itemType: .image, isFavorite: false, orderIndex: 0),
              isSelected: false)
}
