//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftUI

struct BarNavigationCellView: View {
    let item: CBItem
    
    var contentPreview: String {
        return item.displayContent
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(contentPreview)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack {
                    Image(systemName: item.itemType.sfSybmolName)
                        .foregroundStyle(item.itemType.sybmolColor)
                        .imageScale(.small)
                    Text(item.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if item.itemType == .image, let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 40, maxHeight: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
            } else if item.itemType == .file && item.isImageFile, let image = item.filePreviewImage {
                //                if  {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 40, maxHeight: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
