//
//  ActionsBottomButtonView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 09.08.2025.

import SwiftUI
import AppKit

struct ActionsBottomButtonView: View {
    @EnvironmentObject var cbViewModel: CBViewModel

    var item: CBItem
    @Binding var editedText: String
    @Binding var isEditing: Bool
    @Binding var hasChanges: Bool
    @Binding var selectedItem: CBItem?

    // Guards against accessing properties on a SwiftData model whose backing
    // data was detached (e.g. by auto-cleanup deleting it from the context).
    // Without this, SwiftData crashes with "backing data detached from context".
    private var isItemDeleted: Bool {
        item.modelContext == nil
    }

    // Decided from the item type alone: decoding the image on every render
    // just to hide the button for an undecodable one isn't worth it.
    private var shouldShowPreviewButton: Bool {
        guard !isItemDeleted else { return false }
        switch item.itemType {
        case .image, .combined:
            return true
        case .file:
            return item.isImageFile
        case .text:
            return false
        }
    }

    private var shouldShowOCRButton: Bool {
        guard !isItemDeleted else { return false }
        switch item.itemType {
        case .image:
            return true
        case .file:
            return item.isImageFile
        case .combined, .text:
            return false
        }
    }

    var body: some View {
        if isItemDeleted {
            EmptyView()
                .onAppear { selectedItem = nil }
        } else {
            actionsContent
        }
    }

    @ViewBuilder
    private var actionsContent: some View {
        HStack {
            Button("Copy to Clipboard") {
                if hasChanges && isEditing {
                    // Save changes first, then copy
                    saveTextChanges()
                }
//                cbViewModel.copyItem(item)
                cbViewModel.copyAndUpdateItem(item)
            }
            .buttonStyle(.bordered)
            
            // Preview button for images and image files
            if shouldShowPreviewButton {
                Button("Open in Preview") {
                    openInPreview()
                }
                .buttonStyle(.bordered)
            }

            // OCR button for extracting text from images
            if shouldShowOCRButton {
                Button("Extract Text (Apple Vision)") {
                    extractTextFromImage()
                }
                .buttonStyle(.bordered)
            }

            if item.itemType == .text, isEditing {
                Button("Save Changes") {
                    saveTextChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
                
                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(.bordered)
            } else if item.itemType == .text {
                // TODO: if it is link add "Open Link" button
                Button("Edit Text") {
                    startEditing()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            Button("Delete", role: .destructive) {
                withAnimation {
                    selectedItem = nil
                    cbViewModel.deleteItem(item)
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func saveTextChanges() {
        cbViewModel.updateItemContent(item, newContent: editedText)
        isEditing = false
        hasChanges = false
    }
    
    private func startEditing() {
        editedText = item.content ?? ""
        isEditing = true
        hasChanges = false
    }
    
    private func cancelEditing() {
        editedText = item.content ?? ""
        isEditing = false
        hasChanges = false
    }
    
    private func openInPreview() {
        cbViewModel.openInPreview(item)
    }

    /// OCR the image into a new text item (on-device, see TextRecognizer).
    private func extractTextFromImage() {
        let imageToProcess: NSImage?
        switch item.itemType {
        case .image:
            imageToProcess = item.image
        case .file where item.isImageFile:
            imageToProcess = item.filePreviewImage
        default:
            imageToProcess = nil
        }

        guard let image = imageToProcess, let cgImage = TextRecognizer.cgImage(from: image) else {
            ErrorLogger.shared.log("Failed to get image for OCR", category: "OCR")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let recognizedText = TextRecognizer.recognizeText(in: cgImage)
            DispatchQueue.main.async {
                guard let recognizedText else {
                    ErrorLogger.shared.debug("No text found in image", category: "OCR")
                    return
                }
                cbViewModel.addTextItem(content: recognizedText)
                ErrorLogger.shared.debug("Extracted \(recognizedText.count) characters from image", category: "OCR")
            }
        }
    }
}
