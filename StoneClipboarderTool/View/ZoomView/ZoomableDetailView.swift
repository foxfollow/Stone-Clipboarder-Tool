//
//  ZoomableDetailView.swift
//  StoneClipboarderTool
//
//  Created by Assistant on 09.08.2025.
//

import SwiftUI
import AppKit

struct ZoomableDetailView: View {
    @EnvironmentObject var cbViewModel: CBViewModel
    let item: CBItem
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var isEditing = false
    @State private var editedText: String = ""
    @State private var hasChanges = false
    @State private var shouldFitToWindow = false
    
    private var itemTypeDisplayName: String {
        switch item.itemType {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .combined:
            return "Text + Image"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with timestamp and controls
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Copied: \(item.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Type: \(itemTypeDisplayName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Zoom controls (show for images, combined items, and image files)
                if item.itemType == .image || item.itemType == .combined || (item.itemType == .file && item.isImageFile) {
                    ZoomControllsView(
                        zoomScale: $zoomScale,
                        onFitToWindow: {
                            shouldFitToWindow.toggle()
                        }
                    )
                }
                
            }
            
            Divider()
            Group {
                switch item.itemType {
                case .text:
                    ScrollView {
                        textContentView
                    }
                case .image:
                    // Main content area with two-finger zoom support
                    ZoomableScrollView(
                        zoomLevel: $zoomScale,
                        shouldFitToWindow: $shouldFitToWindow
                    ) {
                        imageContentView
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .onAppear {
                        // Reset zoom when image item appears
                        zoomScale = 1.0
                        shouldFitToWindow = true
                    }
                    .onChange(of: item.id) { _, _ in
                        // Reset zoom when changing items
                        zoomScale = 1.0
                        shouldFitToWindow = true
                    }
                case .combined:
                    // Display both text and image for combined items
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Text section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Text Content")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                Text(item.content ?? "No text content")
                                    .textSelection(.enabled)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(12)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                            }

                            Divider()

                            // Image section with zoom support
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Image Content")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                ZoomableScrollView(
                                    zoomLevel: $zoomScale,
                                    shouldFitToWindow: $shouldFitToWindow
                                ) {
                                    imageContentView
                                }
                                .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                                .clipped()
                            }
                        }
                    }
                    .onAppear {
                        zoomScale = 1.0
                        shouldFitToWindow = true
                    }
                    .onChange(of: item.id) { _, _ in
                        zoomScale = 1.0
                        shouldFitToWindow = true
                    }
                case .file:
                    if item.isImageFile {
                        // Display image files with zoom support
                        ZoomableScrollView(
                            zoomLevel: $zoomScale,
                            shouldFitToWindow: $shouldFitToWindow
                        ) {
                            fileImageContentView
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                        .onAppear {
                            zoomScale = 1.0
                            shouldFitToWindow = true
                        }
                        .onChange(of: item.id) { _, _ in
                            zoomScale = 1.0
                            shouldFitToWindow = true
                        }
                    } else {
                        ScrollView {
                            fileContentView
                        }
                    }
                }
            }
        
            Divider()
            
            // Action buttons
            ActionsBottomButtonView(
                item: item,
                editedText: $editedText,
                isEditing: $isEditing,
                hasChanges: $hasChanges
            )
        }
        .padding()
        .navigationTitle("Clipboard Item")
        .onAppear {
            editedText = item.content ?? ""
        }
        .onChange(of: item.id) { _, _ in
            // Reset zoom and other states when item changes
            zoomScale = 1.0
            shouldFitToWindow = true
            editedText = item.content ?? ""
            isEditing = false
            hasChanges = false
        }
    }
    
    @ViewBuilder
    private var textContentView: some View {
        if isEditing {
            TextEditor(text: $editedText)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                )
                .frame(minWidth: 400, minHeight: 200)
                .onChange(of: editedText) { oldValue, newValue in
                    hasChanges = newValue != (item.content ?? "")
                }
        } else {
            Text(item.content ?? "No content")
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var fileContentView: some View {
        VStack(spacing: 16) {
            // File icon and info
            HStack {
                if let fileIcon = item.fileIcon {
                    Image(nsImage: fileIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName ?? "Unknown File")
                        .font(.headline)
                        .textSelection(.enabled)
                    
                    if let uti = item.fileUTI {
                        Text("Type: \(uti)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(item.displayContent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Action buttons for files
            HStack {
                Button("Save File...") {
                    saveFileToLocation()
                }
                .buttonStyle(.bordered)
                                
                Spacer()
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var fileImageContentView: some View {
        if let image = item.filePreviewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contextMenu {
                    Button("Save File...") {
                        saveFileToLocation()
                    }
                    Button("Copy to Clipboard") {
                        copyFileToClipboard()
                    }
                }
        } else {
            VStack {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                
                Text("Cannot preview image file")
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, maxHeight: 200, alignment: .topLeading)
        }
    }
    
    @ViewBuilder
    private var imageContentView: some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contextMenu {
                    Button("Save Image...") {
                        saveImageToFile(image: image)
                    }
                    
                    Button("Copy Image") {
                        copyImageToClipboard(image: image)
                    }
                }
        } else {
            VStack {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                
                Text("Image data corrupted")
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, maxHeight: 200, alignment: .topLeading)
        }
    }
    

    
    private func saveImageToFile(image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "clipboard_image"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData) {
                    
                    let imageData: Data?
                    if url.pathExtension.lowercased() == "png" {
                        imageData = bitmapRep.representation(using: .png, properties: [:])
                    } else {
                        imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    }
                    
                    if let data = imageData {
                        try? data.write(to: url)
                    }
                }
            }
        }
    }
    
    private func copyImageToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    private func saveFileToLocation() {
        cbViewModel.saveItemToFile(item)
    }
    
    private func copyFileToClipboard() {
        cbViewModel.copyItem(item)
    }
}

