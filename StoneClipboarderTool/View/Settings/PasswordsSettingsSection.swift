//
//  PasswordsSettingsSection.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The Passwords page: the tab, the optional password, auto-lock,
/// clipboard clearing, Lock Now and Delete All.
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

            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not your main password manager")
                        .font(.callout.weight(.semibold))
                    Text("Keep a copy of every password somewhere else too. Passwords are stored only on this Mac and are never synced or backed up by this app. They can be lost when the app is deleted or reinstalled, when you switch between builds (a release, a Homebrew or a self-built copy use different Keychain access and data folders), when you move to another Mac, or when the Keychain item is removed or conflicts. Clearing or cleaning up the clipboard history never touches them.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .settingsAnchor("passwords.notice")

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

            VStack(alignment: .leading, spacing: 4) {
                Picker("Keep copies of saved passwords out of the history", selection: $settingsManager.vaultCopyDetection) {
                    ForEach(VaultCopyDetection.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Text(copyDetectionNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsAnchor("passwords.copyDetection")
            .onChange(of: settingsManager.vaultCopyDetection) { _, mode in
                if mode == .always {
                    Task { await vaultManager.prepareCopyDetection() }
                }
            }

            Toggle("Remove history copies of saved passwords", isOn: $settingsManager.vaultRemoveHistoryCopies)
                .help("Every copy of a saved password in the history is deleted when Passwords unlocks and after you paste or type that password from Passwords.")
                .settingsAnchor("passwords.removeCopies")

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

    private var copyDetectionNote: String {
        switch settingsManager.vaultCopyDetection {
        case .off:
            return "Copying a saved password elsewhere adds it to the history like anything else."
        case .whileUnlocked:
            return "While Passwords is locked it answers nothing: copies then reach the history, and leave it at the next unlock or paste from Passwords if the option below is on."
        case .always:
            return "Also while locked. Someone at your unlocked Mac could copy guesses and see which ones stay out of the history."
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
