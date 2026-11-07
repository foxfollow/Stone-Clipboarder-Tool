//
//  CategoryIconPicker.swift
//  StoneClipboarderTool
//

import AppKit
import SwiftUI

/// Picks a category icon: an SF Symbol (from a short list or by name) or a
/// single emoji.
struct CategoryIconPicker: View {
    @Binding var icon: CategoryIcon
    let color: Color

    private enum Mode: String, CaseIterable, Identifiable {
        case symbol = "SF Symbol"
        case emoji = "Emoji"
        var id: Self { self }
    }

    @State private var mode: Mode = .symbol
    @State private var symbolName = ""
    @State private var emojiText = ""

    static let suggestedSymbols = [
        "tag", "link", "envelope", "phone", "mappin.and.ellipse", "calendar",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "terminal", "folder", "globe",
        "doc.text", "number", "creditcard", "banknote", "key", "lock", "person", "person.2",
        "building.2", "briefcase", "cart", "house", "airplane", "car", "star", "flag", "bookmark",
        "bubble.left", "quote.bubble", "photo", "music.note", "heart", "bolt", "paperclip",
        "list.bullet", "hammer", "checkmark.seal", "exclamationmark.triangle", "app.badge",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Icon", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .symbol: symbolPicker
            case .emoji: emojiPicker
            }
        }
        .onAppear {
            switch icon {
            case .symbol(let name):
                mode = .symbol
                symbolName = name
            case .emoji(let emoji):
                mode = .emoji
                emojiText = emoji
            }
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 4)], spacing: 4) {
                ForEach(Self.suggestedSymbols, id: \.self) { name in
                    Button {
                        symbolName = name
                        icon = .symbol(name)
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 13))
                            .foregroundStyle(color)
                            .frame(width: 28, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(icon == .symbol(name) ? color.opacity(0.2) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(icon == .symbol(name) ? color : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }

            HStack {
                TextField("Any SF Symbol name", text: $symbolName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: symbolName) { _, name in
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if CategoryIconView.isKnownSymbol(trimmed) {
                            icon = .symbol(trimmed)
                        }
                    }
                if !symbolName.isEmpty && !CategoryIconView.isKnownSymbol(symbolName.trimmingCharacters(in: .whitespaces)) {
                    Text("Unknown symbol")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var emojiPicker: some View {
        HStack(spacing: 8) {
            TextField("One emoji", text: $emojiText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onChange(of: emojiText) { _, text in
                    // Keep the newest character, so typing or picking
                    // another emoji replaces the old one.
                    guard let last = text.last.map(String.init) else { return }
                    if ItemCategory.isSingleEmoji(last) {
                        if text != last { emojiText = last }
                        icon = .emoji(last)
                    }
                }
            Button("Emoji & Symbols…") {
                NSApp.orderFrontCharacterPalette(nil)
            }
            if !emojiText.isEmpty && !ItemCategory.isSingleEmoji(emojiText) {
                Text("Not an emoji")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
