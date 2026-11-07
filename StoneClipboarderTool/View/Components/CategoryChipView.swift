//
//  CategoryChipView.swift
//  StoneClipboarderTool
//

import SwiftUI

/// One chip in the Quick Picker's category bar: icon, name, count. The
/// active chip is filled with the category's color.
struct CategoryChipView: View {
    let chip: QPCategoryChip
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            CategoryIconView(icon: chip.icon, color: isActive ? .white : chip.color, size: 9)
            Text(chip.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Text("\(chip.count)")
                .font(.system(size: 9))
                .foregroundStyle(isActive ? Color.white.opacity(0.85) : Color.secondary)
        }
        .fixedSize()
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(isActive ? chip.color : Color.clear))
        .overlay(
            Capsule().stroke(isActive ? Color.clear : chip.color.opacity(0.45), lineWidth: 1)
        )
        .contentShape(Capsule())
    }
}
