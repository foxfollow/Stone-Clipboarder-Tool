//
//  ClipboardContent.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026. (moved date)
//

import Foundation

/// One capture from the pasteboard, handed from ClipboardManager to CBViewModel.
enum ClipboardContent: Sendable {
    case text(String)
    case image(Data)               // encoded image bytes (PNG, TIFF, …) as provided
    case file(URL, String, Data)   // URL, UTI, Data
    case combined(String, Data)    // Text + image bytes together
}
