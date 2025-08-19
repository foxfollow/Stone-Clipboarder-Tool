//
//  HotkeyConfig.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 13.08.2025.
//

import Foundation
import SwiftData

enum HotkeyAction: String, Codable, CaseIterable {
    case last1 = "last_1"
    case last2 = "last_2"
    case last3 = "last_3"
    case last4 = "last_4"
    case last5 = "last_5"
    case last6 = "last_6"
    case last7 = "last_7"
    case last8 = "last_8"
    case last9 = "last_9"
    case last0 = "last_0"

    case fav1 = "fav_1"
    case fav2 = "fav_2"
    case fav3 = "fav_3"
    case fav4 = "fav_4"
    case fav5 = "fav_5"
    case fav6 = "fav_6"
    case fav7 = "fav_7"
    case fav8 = "fav_8"
    case fav9 = "fav_9"
    case fav0 = "fav_0"

    case mainPanel = "main_panel"

    var displayName: String {
        switch self {
        case .last1: return "Last Item 1"
        case .last2: return "Last Item 2"
        case .last3: return "Last Item 3"
        case .last4: return "Last Item 4"
        case .last5: return "Last Item 5"
        case .last6: return "Last Item 6"
        case .last7: return "Last Item 7"
        case .last8: return "Last Item 8"
        case .last9: return "Last Item 9"
        case .last0: return "Last Item 10"
        case .fav1: return "Favorite 1"
        case .fav2: return "Favorite 2"
        case .fav3: return "Favorite 3"
        case .fav4: return "Favorite 4"
        case .fav5: return "Favorite 5"
        case .fav6: return "Favorite 6"
        case .fav7: return "Favorite 7"
        case .fav8: return "Favorite 8"
        case .fav9: return "Favorite 9"
        case .fav0: return "Favorite 10"
        case .mainPanel: return "Quick Picker"
        }
    }

    var defaultShortcut: String {
        switch self {
        case .last1: return "⌃⌥1"
        case .last2: return "⌃⌥2"
        case .last3: return "⌃⌥3"
        case .last4: return "⌃⌥4"
        case .last5: return "⌃⌥5"
        case .last6: return "⌃⌥6"
        case .last7: return "⌃⌥7"
        case .last8: return "⌃⌥8"
        case .last9: return "⌃⌥9"
        case .last0: return "⌃⌥0"
        case .fav1: return "⌃⇧1"
        case .fav2: return "⌃⇧2"
        case .fav3: return "⌃⇧3"
        case .fav4: return "⌃⇧4"
        case .fav5: return "⌃⇧5"
        case .fav6: return "⌃⇧6"
        case .fav7: return "⌃⇧7"
        case .fav8: return "⌃⇧8"
        case .fav9: return "⌃⇧9"
        case .fav0: return "⌃⇧0"
        case .mainPanel: return "⌃⌥Space"
        }
    }

    var isLastAction: Bool {
        switch self {
        case .last1, .last2, .last3, .last4, .last5, .last6, .last7, .last8, .last9, .last0:
            return true
        default:
            return false
        }
    }

    var isFavoriteAction: Bool {
        switch self {
        case .fav1, .fav2, .fav3, .fav4, .fav5, .fav6, .fav7, .fav8, .fav9, .fav0:
            return true
        default:
            return false
        }
    }

    var index: Int {
        switch self {
        case .last1, .fav1: return 0
        case .last2, .fav2: return 1
        case .last3, .fav3: return 2
        case .last4, .fav4: return 3
        case .last5, .fav5: return 4
        case .last6, .fav6: return 5
        case .last7, .fav7: return 6
        case .last8, .fav8: return 7
        case .last9, .fav9: return 8
        case .last0, .fav0: return 9
        case .mainPanel: return -1
        }
    }
}

@Model
final class HotkeyConfig {
    var id: UUID
    var action: String
    var shortcutKeys: String?
    var isEnabled: Bool
    var timestamp: Date

    init(action: HotkeyAction, shortcutKeys: String? = nil, isEnabled: Bool = true) {
        self.id = UUID()
        self.action = action.rawValue
        self.shortcutKeys = shortcutKeys ?? action.defaultShortcut
        self.isEnabled = isEnabled
        self.timestamp = Date()
    }

    var hotkeyAction: HotkeyAction? {
        return HotkeyAction(rawValue: action)
    }
}
