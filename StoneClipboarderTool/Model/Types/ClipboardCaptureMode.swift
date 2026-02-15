//
//  ClipboardCaptureMode.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026. (moved date)
//

import Foundation

enum ClipboardCaptureMode: String, Codable, CaseIterable {
    case textOnly = "textOnly"
    case imageOnly = "imageOnly"
    case both = "both"
    case bothAsOne = "bothAsOne"

    var displayName: String {
        switch self {
        case .textOnly: return "Text Only"
        case .imageOnly: return "Image Only"
        case .both: return "Both Text and Image"
        case .bothAsOne: return "Both as One Item (BETA)"
        }
    }

    var description: String {
        switch self {
        case .textOnly:
            return "Prefer text when both available (e.g., Word), but still capture standalone images (screenshots)"
        case .imageOnly:
            return "Prefer images when both available, but still capture standalone text"
        case .both:
            return "Capture both text and image separately when both are available"
        case .bothAsOne:
            return "Capture text and image together as one combined item (see both in preview)"
        }
    }
}
