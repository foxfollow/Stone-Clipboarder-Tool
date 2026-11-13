//
//  PasswordsSettingsSection.swift
//  StoneClipboarderTool
//

import SwiftUI

/// Quick Picker settings for the Passwords tab: auto-lock, clipboard
/// clearing, Lock Now and Delete All.
struct PasswordsSettingsSection: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var vaultManager: VaultManager
    @State private var isConfirmingDeleteAll = false
    @State private var passwordSheet: VaultPasswordSheet.Mode?

    private static let clearChoices = [0, 15, 30, 60, 120]

    var body: some View {
        Section("Passwords") {
            Text("In the Quick Picker, ⌥E then ⌥K moves an item into Passwords: it is encrypted on this Mac with a key kept in your Keychain and removed from the history. The tab unlocks with Touch ID or your password.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Show the Passwords tab", isOn: $settingsManager.showPasswordsTab)
                .settingsAnchor("passwords.show")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Password")
                    Text(settingsManager.vaultUsesPassword
                         ? "Passwords unlock with your password instead of Touch ID."
                         : "Off: Passwords unlock with Touch ID.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if settingsManager.vaultUsesPassword {
                    Button("Change…") { passwordSheet = .change }
                    Button("Remove…") { passwordSheet = .remove }
                } else {
                    Button("Require a Password…") { passwordSheet = .set }
                }
            }
            .settingsAnchor("passwords.password")

            Picker("Lock again after", selection: $settingsManager.vaultRelockMinutes) {
                ForEach(relockChoices, id: \.self) { minutes in
                    Text(relockLabel(minutes)).tag(minutes)
                }
            }
            .pickerStyle(.menu)
            .help("Passwords stay unlocked this long after you last used them. Locking the screen or sleep locks them at once.")
            .settingsAnchor("passwords.relock")

            Picker("Clear the clipboard after pasting", selection: $settingsManager.vaultClipboardClearSeconds) {
                ForEach(clearChoices, id: \.self) { seconds in
                    Text(seconds == 0 ? "Never" : "\(seconds) seconds").tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .help("Only if the clipboard still holds the pasted password.")
            .settingsAnchor("passwords.clearClipboard")

            HStack {
                Label(
                    vaultManager.isUnlocked ? "Unlocked" : "Locked",
                    systemImage: vaultManager.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Lock Now") { vaultManager.lock() }
                    .disabled(!vaultManager.isUnlocked)
                Button("Delete All Passwords…", role: .destructive) { isConfirmingDeleteAll = true }
            }
            .settingsAnchor("passwords.actions")
        }
        .sheet(item: $passwordSheet) { mode in
            VaultPasswordSheet(mode: mode)
                .environmentObject(vaultManager)
                .environmentObject(settingsManager)
        }
        .confirmationDialog(
            "Delete all saved passwords?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { vaultManager.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every entry, its Keychain key and the Passwords password are removed. This can't be undone.")
        }
    }

    /// The offered choices, plus a stored value that isn't one of them.
    private var relockChoices: [Int] {
        let choices = VaultLockPolicy.timeoutChoices
        let current = settingsManager.vaultRelockMinutes
        return choices.contains(current) ? choices : (choices + [current]).sorted()
    }

    private var clearChoices: [Int] {
        let current = settingsManager.vaultClipboardClearSeconds
        return Self.clearChoices.contains(current) ? Self.clearChoices : (Self.clearChoices + [current]).sorted()
    }

    private func relockLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) minutes"
    }
}
