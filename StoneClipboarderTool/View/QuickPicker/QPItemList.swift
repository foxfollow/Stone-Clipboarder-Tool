//
//  QPItemList.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 14.08.2025.
//

import SwiftUI

struct QPItemList: View {
    var filteredItems: [CBItem]
    @Binding var selectedIndex: Int
    @Binding var searchText: String
    let performAction: () -> Void

    var body: some View {
        if filteredItems.isEmpty {
            VStack {
                Spacer()
                Text("No items found")
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredItems.enumerated()), id: \.offset) {
                            index, item in
                            QPItemRow(item: item, isSelected: index == selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    performAction()
                                }
                                .id("\(searchText)-\(item.id)-\(index)")
                        }
                    }
                    .padding(.vertical, 4)
                    .id("list-\(searchText)-\(filteredItems.count)")
                }
                .scrollIndicators(.visible)
                .onAppear {
                    if !filteredItems.isEmpty {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onChange(of: filteredItems) { _, newItems in
                    if !newItems.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(0, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}
