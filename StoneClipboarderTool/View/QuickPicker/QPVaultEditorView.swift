//
//  QPVaultEditorView.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The ⌥E card on the Passwords tab: name the entry, move it, delete it.
/// Keys arrive through `TabKeyInterceptor`'s editor mode: ⏎ save, Esc
/// cancel, ⌥↑ / ⌥↓ move, ⌥⌫ delete (⏎ confirms).
struct QPVaultEditorView: View {
    @ObservedObject var model: QPVaultEditorModel
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            card
                .padding(.horizontal, 36)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            DispatchQueue.main.async { isTitleFocused = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            titleField
            Divider()
            orderAndDelete
            Divider()
            footer
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.typeSymbol)
                .font(.system(size: 14))
                .foregroundStyle(model.typeColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.typeColor.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Encrypted password")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.kindDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Title", systemImage: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Bank login", text: $model.title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
            Text("Shown instead of the hidden content. Leave empty to remove.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var orderAndDelete: some View {
        if model.isConfirmingDelete {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                Text("Delete this password for good?")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Cancel") { model.isConfirmingDelete = false }
                    .focusable(false)
                Button("Delete", role: .destructive, action: onDelete)
                    .focusable(false)
            }
            .controlSize(.small)
        } else {
            HStack(spacing: 8) {
                if let position = model.position {
                    Text("\(position + 1) of \(model.count)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
                Spacer()
                Button { model.move(by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(!model.canMoveUp)
                    .help("Move up (⌥↑)")
                    .focusable(false)
                Button { model.move(by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(!model.canMoveDown)
                    .help("Move down (⌥↓)")
                    .focusable(false)
                Button("Delete…", role: .destructive) { model.isConfirmingDelete = true }
                    .help("Delete (⌥⌫)")
                    .focusable(false)
            }
            .controlSize(.small)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isConfirmingDelete {
                keyHint("⏎", "Delete")
                keyHint("ESC", "Keep")
            } else {
                keyHint("⏎", "Save")
                keyHint("ESC", "Cancel")
                keyHint("⌥↑↓", "Move")
                keyHint("⌥⌫", "Delete")
            }
            Spacer()
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
                .focusable(false)
                .disabled(model.isConfirmingDelete)
        }
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundStyle(.tertiary)
    }
}
