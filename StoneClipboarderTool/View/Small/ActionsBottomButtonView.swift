//
//  ActionsBottomButtonView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 09.08.2025.

import SwiftUI
import AppKit
import Vision

struct ActionsBottomButtonView: View {
    @EnvironmentObject var cbViewModel: CBViewModel
    
    var item: CBItem
    @Binding var editedText: String
    @Binding var isEditing: Bool
    @Binding var hasChanges: Bool
    
    // Computed property to determine if Preview button should be shown
    private var shouldShowPreviewButton: Bool {
        switch item.itemType {
        case .image, .combined:
            return item.image != nil
        case .file:
            return item.isImageFile && item.filePreviewImage != nil
        case .text:
            return false
        }
    }

    // Computed property to determine if OCR button should be shown
    private var shouldShowOCRButton: Bool {
        switch item.itemType {
        case .image:
            return item.image != nil
        case .file:
            return item.isImageFile && item.filePreviewImage != nil
        case .combined, .text:
            return false
        }
    }
    
    var body: some View {
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

            if item.itemType == .text {
                if isEditing {
                    Button("Save Changes") {
                        saveTextChanges()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
                    
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .buttonStyle(.bordered)
                } else {
                    // TODO: if it is link add "Open Link" button
                    Button("Edit Text") {
                        startEditing()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
            
            Button("Delete", role: .destructive) {
                withAnimation {
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
        switch item.itemType {
        case .image, .combined:
            openImageInPreview()
        case .file:
            if item.isImageFile {
                openImageFileInPreview()
            }
        case .text:
            break // No preview for text
        }
    }
    
    private func openImageInPreview() {
        guard let image = item.image else { return }
        
        // Create temporary file for the image
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "clipboard_image_\(UUID().uuidString).png"
        let tempFile = tempDir.appendingPathComponent(fileName)
        
        do {
            // Convert image to PNG data
            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                print("Failed to convert image to PNG")
                return
            }
            
            // Write to temporary file
            try pngData.write(to: tempFile)
            
            // Open in Preview.app
            NSWorkspace.shared.open(tempFile)
            
            // Clean up temp file after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                try? FileManager.default.removeItem(at: tempFile)
            }
            
        } catch {
            print("Error creating temp file for Preview: \(error.localizedDescription)")
        }
    }
    
    private func openImageFileInPreview() {
        guard let fileData = item.fileData,
              let fileName = item.fileName else { return }
        
        // Create temporary file with original extension
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = "clipboard_file_\(UUID().uuidString)_\(fileName)"
        let tempFile = tempDir.appendingPathComponent(tempFileName)
        
        do {
            // Write file data to temporary file
            try fileData.write(to: tempFile)
            
            // Open in Preview.app
            NSWorkspace.shared.open(tempFile)
            
            // Clean up temp file after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                try? FileManager.default.removeItem(at: tempFile)
            }
            
        } catch {
            print("Error creating temp file for Preview: \(error.localizedDescription)")
        }
    }

    private func extractTextFromImage() {
        // Get the image based on item type
        let imageToProcess: NSImage?
        switch item.itemType {
        case .image:
            imageToProcess = item.image
        case .file where item.isImageFile:
            imageToProcess = item.filePreviewImage
        default:
            imageToProcess = nil
        }

        guard let image = imageToProcess,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to get image for OCR")
            return
        }

        // Create Vision request
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("OCR error: \(error.localizedDescription)")
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("No text recognized")
                return
            }

            // Extract all recognized text
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")

            if recognizedText.isEmpty {
                print("No text found in image")
                return
            }

            // Create a new text item with extracted text on main thread
            DispatchQueue.main.async {
                cbViewModel.addTextItem(content: recognizedText)
                print("Extracted \(recognizedText.count) characters from image")
            }
        }

        // Configure request for best accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Perform OCR
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("Failed to perform OCR: \(error.localizedDescription)")
            }
        }
    }

}
