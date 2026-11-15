//
//  VaultPreviewMode.swift
//  StoneClipboarderTool
//

import Foundation

/// How Space / → previews a Passwords entry. Raw values are stored: never
/// rename them. "Preview mode: Disabled" in the Quick Picker settings turns
/// this preview off too.
enum VaultPreviewMode: String, Codable, CaseIterable {
    /// Apple's Quick Look panel (the default). It only reads files, so the
    /// entry is decrypted into an owner-only `Secret_` folder that goes as
    /// soon as the preview closes. Its "Open with…" button can hand that
    /// file to another app.
    case quickLook = "quickLook"
    /// The app's own preview panel, drawn from memory: no file on disk.
    case custom = "custom"

    var displayName: String {
        switch self {
        case .quickLook: return "Apple Quick Look"
        case .custom: return "Custom Preview"
        }
    }
}
