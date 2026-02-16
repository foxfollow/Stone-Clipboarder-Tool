//
//  CBItemType.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026. (moved date)
//

 import SwiftUI

enum CBItemType: String, Codable, CaseIterable {
    case text = "text"
    case image = "image"
    case file = "file"
    case combined = "combined"  // Text + Image together

    var sfSybmolName: String {
        switch self {
        case .text: return "text.page"
        case .image: return "photo"
        case .file: return "document.badge.ellipsis"
        case .combined: return "text.and.photo"
        }
    }

    var sybmolColor: Color {
        switch self {
        case .text: return .blue
        case .image: return .orange
        case .file: return .pink
        case .combined: return .purple
        }
    }
}
