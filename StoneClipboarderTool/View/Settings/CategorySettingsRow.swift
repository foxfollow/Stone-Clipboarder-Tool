//
//  CategorySettingsRow.swift
//  StoneClipboarderTool
//

import SwiftUI

/// One category in Settings → Categories: icon, name, what it matches, an
/// on/off switch, Edit and (custom ones) Delete.
struct CategorySettingsRow: View {
    let category: ItemCategory
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    var onDelete: (() -> Void)?

    private var detail: String {
        switch category.kind {
        case .builtIn:
            let base = Self.builtInDescription(category.builtIn)
            return category.supportsMatchMode && category.matchMode == .entireText ? base + " · entire text" : base
        case .regex:
            let mode = category.matchMode == .entireText ? " · entire text" : ""
            return category.pattern + (category.caseSensitive ? " · case sensitive" : "") + mode
        case .apps:
            return category.appNames.isEmpty ? "No apps" : category.appNames.joined(separator: ", ")
        }
    }

    static func builtInDescription(_ builtIn: ItemCategory.BuiltIn?) -> String {
        switch builtIn {
        case .link: return "Web links"
        case .email: return "Email addresses"
        case .phone: return "Phone numbers"
        case .address: return "Postal addresses"
        case .date: return "Dates and times"
        case .code: return "Source code and shell commands"
        case .json: return "Valid JSON objects and arrays"
        case .path: return "File paths: /Users/…, ~/…, C:\\…"
        case .language: return "One chip per detected language"
        case .ocr: return "Images with readable text (Vision)"
        case .barcode: return "Images with a QR code or barcode"
        case .face: return "Images with faces"
        case .transparent: return "Images with transparent areas: icons, logos, cut-outs"
        case nil: return ""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            CategoryIconView(icon: category.icon, color: category.color, size: 14)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name.isEmpty ? "Untitled" : category.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Edit…", action: onEdit)
                .controlSize(.small)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete \(category.name)")
            }
            Toggle("", isOn: Binding(get: { category.isEnabled }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(category.isEnabled ? "Shown in the Quick Picker" : "Hidden")
        }
        .opacity(category.isEnabled ? 1 : 0.6)
        .settingsAnchor(SettingsAnchor.category(category.id))
    }
}
