//
//  QuickLookTriggerKey.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026.
//

import Foundation

enum QuickLookTriggerKey: String, Codable, CaseIterable {
    case space = "space"
    case arrowRight = "arrowRight"

    var displayName: String {
        switch self {
        case .space: return "Space"
        case .arrowRight: return "Arrow Right (→)"
        }
    }
}
