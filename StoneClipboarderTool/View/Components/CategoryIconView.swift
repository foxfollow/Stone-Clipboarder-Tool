//
//  CategoryIconView.swift
//  StoneClipboarderTool
//

import AppKit
import SwiftUI

/// A category's SF Symbol in its color, or its emoji. An unknown symbol
/// name (typed by hand) falls back to a tag.
struct CategoryIconView: View {
    let icon: CategoryIcon
    let color: Color
    var size: CGFloat = 11

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: Self.isKnownSymbol(name) ? name : "tag")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: size))
        }
    }

    static func isKnownSymbol(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
