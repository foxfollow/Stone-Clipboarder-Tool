//
//  SettingsSection.swift
//  StoneClipboarderTool
//

import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case hotkeys
    case excludedApps
    case accessibility
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .hotkeys: return "Hotkeys"
        case .excludedApps: return "Excluded Apps"
        case .accessibility: return "Accessibility"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Behavior, capture, and history retention."
        case .hotkeys: return "Global shortcuts for items, favorites, and the Quick Picker."
        case .excludedApps: return "Apps whose clipboard content is never saved."
        case .accessibility: return "Login behavior and macOS accessibility permission."
        case .about: return "Version, links, and feedback."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .excludedApps: return "lock.app.dashed"
        case .accessibility: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }
}
