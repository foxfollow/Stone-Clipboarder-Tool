//
//  PasswordsSettingsView.swift
//  StoneClipboarderTool
//

import SwiftUI

/// Settings → Security → Passwords.
struct PasswordsSettingsView: View {
    var body: some View {
        Form {
            PasswordsSettingsSection()
        }
        .formStyle(.grouped)
    }
}
