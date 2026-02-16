//
//  QuickLookMode.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026.
//

import Foundation

enum QuickLookMode: String, Codable, CaseIterable {
    case native = "native"
    case custom = "custom"
    case disabled = "disabled"

    var displayName: String {
        switch self {
        case .native: return "Apple Quick Look"
        case .custom: return "Custom Preview"
        case .disabled: return "Disabled"
        }
    }
}
