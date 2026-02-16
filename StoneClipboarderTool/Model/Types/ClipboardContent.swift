//
//  ClipboardContent.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026. (moved date)
//

import Foundation
import AppKit

enum ClipboardContent {
    case text(String)
    case image(NSImage)
    case file(URL, String, Data) // URL, UTI, Data
    case combined(String, NSImage) // Text + Image together
}
