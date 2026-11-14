//
//  VaultCopyDetection.swift
//  StoneClipboarderTool
//

import Foundation

/// When a copy of a saved Passwords entry is kept out of the history.
/// Raw values are stored: never rename them.
enum VaultCopyDetection: String, Codable, CaseIterable {
    /// Every copy goes into the history.
    case off = "off"
    /// Only while Passwords is unlocked (the default): a locked vault
    /// answers nothing about what it holds.
    case whileUnlocked = "whileUnlocked"
    /// Also while locked, through the fingerprints. Someone at the Mac
    /// could then copy guesses and see which ones stay out of the history.
    case always = "always"

    var displayName: String {
        switch self {
        case .off: return "Never"
        case .whileUnlocked: return "While Passwords is unlocked"
        case .always: return "Always, also while locked"
        }
    }
}
