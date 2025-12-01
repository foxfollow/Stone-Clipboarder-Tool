//
//  SearchBarView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 30.11.2025.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if #available(macOS 26.0, *) {
                // Liquid Glass container shape
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular)
            } else {
                // Fallback for older macOS versions
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

#Preview {
    @Previewable @State var searchText = ""

    VStack {
        SearchBarView(searchText: $searchText)

        Text("Search: '\(searchText)'")
            .foregroundStyle(.secondary)
            .padding()
    }
    .frame(width: 300)
    .padding()
}
