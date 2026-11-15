//
//  VaultPasswordSheet.swift
//  StoneClipboarderTool
//

import SwiftUI

/// Sets, changes or removes the Passwords password. A locked vault is
/// unlocked first: with Touch ID, or with the current password.
struct VaultPasswordSheet: View {
    enum Mode: Identifiable {
        case set, change, remove
        var id: Self { self }
    }

    let mode: Mode
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var hint = ""
    @State private var acknowledged = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var title: String {
        switch mode {
        case .set: return "Require a Password for Passwords"
        case .change: return "Change the Passwords Password"
        case .remove: return "Remove the Passwords Password"
        }
    }

    private var problem: String? {
        guard mode != .remove else { return nil }
        return VaultPasswordRules.problem(
            password: password, confirmation: confirmation, hint: hint, acknowledged: acknowledged)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            if !vaultManager.isUnlocked {
                unlockStep
            } else if mode == .remove {
                Text("Passwords will unlock with Touch ID (or your Mac's login password) again. The key stays in your Keychain without a password.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                passwordFields
                warning
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if vaultManager.isUnlocked {
                    Button(mode == .remove ? "Remove Password" : "Save Password") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking || problem != nil)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await vaultManager.loadPasswordHint() }
    }

    /// The key is needed to (re)wrap it: unlock first.
    @ViewBuilder
    private var unlockStep: some View {
        Text("Unlock Passwords first.")
            .font(.callout)
            .foregroundStyle(.secondary)
        if settingsManager.vaultUsesPassword {
            SecureField("Current password", text: $currentPassword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { unlockWithPassword() }
            if !vaultManager.passwordHint.isEmpty {
                Text("Hint: \(vaultManager.passwordHint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Unlock") { unlockWithPassword() }
                .disabled(currentPassword.isEmpty || isWorking)
        } else {
            Button {
                Task {
                    isWorking = true
                    await vaultManager.unlock(reason: "change how your saved passwords are protected")
                    isWorking = false
                }
            } label: {
                Label("Unlock with Touch ID", systemImage: "touchid")
            }
            .disabled(isWorking)
        }
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("New password (at least \(VaultPasswordRules.minimumLength) characters)", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("Repeat the password", text: $confirmation)
                .textFieldStyle(.roundedBorder)
            TextField("Hint (optional, shown on the lock screen)", text: $hint)
                .textFieldStyle(.roundedBorder)
            Text("Touch ID won't open Passwords any more: this password will.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("If you forget this password, everything in Passwords is lost for good. Nobody can recover it — not this app, not Apple, not the developer. Only Delete All Passwords will let you start over.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            Toggle("I understand that a forgotten password can't be recovered", isOn: $acknowledged)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }

    private func unlockWithPassword() {
        guard !currentPassword.isEmpty else { return }
        Task {
            isWorking = true
            let unlocked = await vaultManager.unlock(password: currentPassword)
            isWorking = false
            currentPassword = ""
            errorMessage = unlocked ? nil : vaultManager.statusMessage
        }
    }

    private func save() {
        Task {
            isWorking = true
            let done: Bool
            if mode == .remove {
                done = await vaultManager.removePassword()
            } else {
                done = await vaultManager.setPassword(password, hint: hint)
            }
            isWorking = false
            if done {
                dismiss()
            } else {
                errorMessage = "Couldn't update the Keychain. Try again."
            }
        }
    }
}
