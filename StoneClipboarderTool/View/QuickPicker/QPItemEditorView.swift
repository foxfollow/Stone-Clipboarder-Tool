//
//  QPItemEditorView.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The ⌥E card over the Quick Picker: name the item, add it to or remove it
/// from the favorites, move it within the favorites.
///
/// Keys reach it through `TabKeyInterceptor`'s editor mode (⏎ save, Esc
/// cancel, ⌥↑ / ⌥↓ move, ⌥F favorite, ⌥K Move to Passwords), matched by key code so they work on
/// any keyboard layout and never type into the title field. Favorite changes
/// apply at once; only the title waits for ⏎.
struct QPItemEditorView: View {
    @ObservedObject var model: QPItemEditorModel
    let onSave: () -> Void
    let onCancel: () -> Void
    /// Nil hides the Passwords section (the tab is turned off).
    var onMoveToVault: (() -> Void)?

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack {
            // Dims the list; a click on it cancels like Esc.
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            card
                .padding(.horizontal, 36)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            // Next turn: the search field gives up focus first.
            DispatchQueue.main.async { isTitleFocused = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            titleField
            Divider()
            favoriteSection
            if onMoveToVault != nil {
                Divider()
                vaultSection
            }
            Divider()
            deleteSection
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.typeSymbol)
                .font(.system(size: 14))
                .foregroundStyle(model.typeColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.typeColor.opacity(0.12))
                )
            Text(model.preview)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Title", systemImage: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Reply to the bank", text: $model.title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
            Text("Shown above the content in the Quick Picker, menu bar and main window. Leave empty to remove.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var favoriteSection: some View {
        if model.isConfirmingUnfavorite {
            HStack(spacing: 8) {
                Image(systemName: "heart.slash")
                    .foregroundStyle(.red)
                Text("Remove from Favorites?")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Cancel") { model.isConfirmingUnfavorite = false }
                    .focusable(false)
                Button("Remove", role: .destructive) { model.confirmUnfavorite() }
                    .focusable(false)
            }
            .controlSize(.small)
        } else if model.isFavorite {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                if let position = model.favoritePosition {
                    Text("Favorite \(position + 1) of \(model.favoriteCount)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
                Spacer()
                Button { model.moveFavorite(by: -1) } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!model.canMoveUp)
                .help("Move up (⌥↑)")
                .focusable(false)
                Button { model.moveFavorite(by: 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(!model.canMoveDown)
                .help("Move down (⌥↓)")
                .focusable(false)
                Button("Remove…") { model.requestFavoriteToggle() }
                    .help("Remove from Favorites (⌥F)")
                    .focusable(false)
            }
            .controlSize(.small)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "heart")
                    .foregroundStyle(.secondary)
                Text("Not in Favorites")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add to Favorites") { model.requestFavoriteToggle() }
                    .help("Add to Favorites (⌥F)")
                    .focusable(false)
            }
            .controlSize(.small)
        }
    }

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Encrypt it and remove it from the history")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Move to Passwords") { onMoveToVault?() }
                    .help("Move to Passwords (⌥K)")
                    .focusable(false)
                    .disabled(model.isMovingToVault || model.isConfirmingUnfavorite)
            }
            .controlSize(.small)
            if let message = model.vaultMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Delete from the history, after confirming (⌃⌥⌫, ⏎ confirms).
    @ViewBuilder
    private var deleteSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .foregroundStyle(model.isConfirmingDelete ? Color.red : Color.secondary)
            Text(model.isConfirmingDelete ? "Delete this item from the history?" : "Delete from the history")
                .font(.system(size: 12, weight: model.isConfirmingDelete ? .medium : .regular))
                .foregroundStyle(model.isConfirmingDelete ? Color.primary : Color.secondary)
            Spacer()
            if model.isConfirmingDelete {
                Button("Cancel") { model.isConfirmingDelete = false }
                    .focusable(false)
                Button("Delete", role: .destructive) { model.confirmDelete() }
                    .focusable(false)
            } else {
                Button("Delete…", role: .destructive) { model.requestDelete() }
                    .help("Delete from the history (⌃⌥⌫)")
                    .focusable(false)
                    .disabled(model.isConfirmingUnfavorite)
            }
        }
        .controlSize(.small)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isConfirmingDelete {
                keyHint("⏎", "Delete")
                keyHint("ESC", "Keep")
            } else if model.isConfirmingUnfavorite {
                keyHint("⏎", "Remove")
                keyHint("ESC", "Keep")
            } else {
                keyHint("⏎", "Save")
                keyHint("ESC", "Cancel")
                keyHint("⌥F", model.isFavorite ? "Unfavorite" : "Favorite")
                if onMoveToVault != nil {
                    keyHint("⌥K", "Passwords")
                }
                if model.isFavorite {
                    keyHint("⌥↑↓", "Move")
                }
            }
            Spacer()
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
                .focusable(false)
                .disabled(model.isConfirmingUnfavorite || model.isConfirmingDelete)
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
