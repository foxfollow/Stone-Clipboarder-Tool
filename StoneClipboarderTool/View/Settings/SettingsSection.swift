//
//  SettingsSection.swift
//  StoneClipboarderTool
//

import Foundation

/// A heading in the Settings sidebar with its pages under it.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case general
    case quickPicker
    case security
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .quickPicker: return "Quick Picker"
        case .security: return "Security"
        case .about: return "About"
        }
    }

    /// Its pages, in sidebar order.
    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

/// A Settings page. Cases are in sidebar order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case hotkeys
    case accessibility
    case quickPicker
    case categories
    case pins
    case passwords
    case excludedApps
    case about

    var id: String { rawValue }

    var group: SettingsGroup {
        switch self {
        case .general, .hotkeys, .accessibility: return .general
        case .quickPicker, .categories, .pins: return .quickPicker
        case .passwords, .excludedApps: return .security
        case .about: return .about
        }
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .hotkeys: return "Hotkeys"
        case .quickPicker: return "Quick Picker"
        case .categories: return "Categories"
        case .pins: return "Pins"
        case .passwords: return "Passwords"
        case .excludedApps: return "Excluded Apps"
        case .accessibility: return "Accessibility"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Behavior, capture, and history retention."
        case .hotkeys: return "Global shortcuts for items, favorites, and the Quick Picker."
        case .quickPicker: return "Tab order, Quick Look preview and type-out paste in the Quick Picker."
        case .categories: return "Group items by what they contain, their language or the app they came from."
        case .pins: return "Floating clipboard windows that stay on top of every Space."
        case .passwords: return "Encrypted passwords in the Quick Picker: unlocking, auto-lock and an optional password."
        case .excludedApps: return "Apps whose clipboard content is never saved."
        case .accessibility: return "Login behavior and macOS accessibility permission."
        case .about: return "Version, links, and feedback."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .quickPicker: return "text.magnifyingglass"
        case .categories: return "square.grid.2x2"
        case .pins: return "pin.fill"
        case .passwords: return "key.fill"
        case .excludedApps: return "lock.app.dashed"
        case .accessibility: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }
}
