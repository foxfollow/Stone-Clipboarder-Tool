//
//  VaultPasswordRules.swift
//  StoneClipboarderTool
//

import Foundation

/// Checks a new Passwords password before it wraps the vault key.
enum VaultPasswordRules {
    static let minimumLength = 6

    /// Why the password can't be used yet, or nil when it can.
    static func problem(password: String, confirmation: String, hint: String, acknowledged: Bool) -> String? {
        if password.count < minimumLength {
            return "Use at least \(minimumLength) characters."
        }
        if password != confirmation {
            return "The passwords don't match."
        }
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty, trimmedHint.localizedCaseInsensitiveContains(password) {
            return "The hint must not contain the password."
        }
        if !acknowledged {
            return "Confirm that you understand a forgotten password can't be recovered."
        }
        return nil
    }
}
