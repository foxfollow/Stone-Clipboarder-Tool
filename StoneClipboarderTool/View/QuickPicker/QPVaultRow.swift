//
//  QPVaultRow.swift
//  StoneClipboarderTool
//

import SwiftUI

/// One entry on the Quick Picker's Passwords tab. Text stays masked and an
/// image shows only its icon until the eye button (or ⌥R) reveals the row.
struct QPVaultRow: View {
    let entry: VaultPayload
    let isSelected: Bool
    let isRevealed: Bool
    var onToggleReveal: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            iconView

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: entry.title == nil ? "key.fill" : "tag.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text(entry.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                secondLine
            }

            Spacer()

            Button(action: onToggleReveal) {
                QPEyeIcon(isRevealed: isRevealed, size: 14)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(isRevealed ? "Hide (⌥R)" : "Show (⌥R)")

            if isSelected {
                HStack(spacing: 4) {
                    rowKeyBadge("⌥E", help: "Rename, reorder or delete")
                    rowKeyBadge("⏎", help: "Paste")
                }
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
    private var secondLine: some View {
        switch entry.itemType {
        case .text, .combined:
            if isRevealed, let content = entry.content {
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.disabled)
            } else {
                Text(entry.itemType == .combined ? "•••••••• + image" : "••••••••")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        case .image:
            Text(isRevealed ? "Image" : "Hidden image")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .file:
            Text(entry.fileData.map { ByteCountFormatter.string(fromByteCount: Int64($0.count), countStyle: .file) }
                 ?? "File")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// The entry's own color, else its type's.
    private var iconColor: Color {
        entry.colorHex.flatMap(ItemCategory.nsColor(hex:)).map { Color(nsColor: $0) } ?? entry.itemType.sybmolColor
    }

    @ViewBuilder
    private var iconView: some View {
        if isRevealed, let data = entry.imageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let icon = entry.icon {
            CategoryIconView(icon: icon, color: iconColor, size: 18)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.12))
                )
        } else {
            Image(systemName: entry.itemType == .text ? "key.horizontal.fill" : entry.itemType.sfSybmolName)
                .font(.system(size: 18))
                .foregroundStyle(entry.itemType.sybmolColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(entry.itemType.sybmolColor.opacity(0.12))
                )
        }
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
}
