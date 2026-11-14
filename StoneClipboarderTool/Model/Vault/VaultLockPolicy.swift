//
//  VaultLockPolicy.swift
//  StoneClipboarderTool
//
//  When an unlocked vault locks again by itself.
//

import Foundation

/// A sliding unlock window: every use of the vault (opening the Passwords
/// tab, pasting, editing) restarts it. Screen lock, sleep and the Lock button
/// end it at once through `reset()`.
struct VaultLockPolicy: Equatable {
    /// Choices offered in Settings, in minutes.
    static let timeoutChoices = [15, 60, 240]
    static let defaultTimeoutMinutes = 60

    var timeout: TimeInterval
    private(set) var lastUse: Date?

    init(timeoutMinutes: Int = VaultLockPolicy.defaultTimeoutMinutes) {
        timeout = TimeInterval(max(1, timeoutMinutes) * 60)
    }

    /// Whether the vault may stay unlocked at `now`. A clock that went back
    /// before the last use counts as expired.
    func isOpen(at now: Date) -> Bool {
        guard let lastUse else { return false }
        let elapsed = now.timeIntervalSince(lastUse)
        return elapsed >= 0 && elapsed < timeout
    }

    mutating func touch(at now: Date) {
        lastUse = now
    }

    mutating func reset() {
        lastUse = nil
    }
}
