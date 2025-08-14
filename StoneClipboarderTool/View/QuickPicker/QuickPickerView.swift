//
//  QuickPickerView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import AppKit
import SwiftUI

struct QuickPickerView: View {
    @ObservedObject var viewModel: CBViewModel
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    let onClose: () -> Void

    init(viewModel: CBViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    private var filteredItems: [CBItem] {
        let items = viewModel.items.sorted { $0.timestamp > $1.timestamp }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(items)
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return items.filter { item in
            switch item.itemType {
            case .text:
                if let content = item.content {
                    return content.localizedCaseInsensitiveContains(trimmedSearch)
                }
                return false
            case .image, .file:
                return item.displayContent.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            QPItemList(
                filteredItems: filteredItems,
                selectedIndex: $selectedIndex,
                searchText: $searchText
            ) {
                performAction()
            }
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(radius: 10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            performAction()
            return .handled
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: filteredItems) { _, newItems in
            if selectedIndex >= newItems.count {
                selectedIndex = max(0, newItems.count - 1)
            }
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit {
                    performAction()
                }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    //    @ViewBuilder
    //    private var itemsList: some View {
    //
    //    }

    private func performAction() {
        guard selectedIndex < filteredItems.count else { return }

        let item = filteredItems[selectedIndex]
        copyToPasteboard(item)

        // Close immediately without activating main app
        onClose()

        // Paste after a longer delay to ensure target app is active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            simulatePaste()
        }
    }

    private func copyToPasteboard(_ item: CBItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.itemType {
        case .text:
            if let content = item.content {
                pasteboard.setString(content, forType: .string)
            }
        case .image:
            if let imageData = item.imageData,
                let image = NSImage(data: imageData)
            {
                pasteboard.writeObjects([image])
            }
        case .file:
            if let fileData = item.fileData,
                let fileName = item.fileName
            {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                    fileName)
                try? fileData.write(to: tempURL)
                pasteboard.writeObjects([tempURL as NSURL])
            }
        }
    }

    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // Create Cmd+V key events
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}

#Preview {
    QuickPickerView(viewModel: CBViewModel()) {
        print("Closed")
    }
}
