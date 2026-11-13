//
//  QPVaultEditorView.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The ⌥E card on the Passwords tab: name the entry, move it, delete it.
/// Keys arrive through `TabKeyInterceptor`'s editor mode: ⏎ save, Esc
/// cancel, ⌥↑ / ⌥↓ move, ⌘⌫ delete (only ⏎ confirms), ⌥R show or hide the
/// content (the eye).
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
            if model.isRevealed {
                revealedContent
            }
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
            CategoryIconView(icon: model.iconForPicker, color: model.color, size: 14)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.color.opacity(0.12))
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
            Button { model.isRevealed.toggle() } label: {
                QPEyeIcon(isRevealed: model.isRevealed, size: 15)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(model.isRevealed ? "Hide (⌥R)" : "Show (⌥R)")
        }
    }

    /// The content behind the eye: text (no selection, so it can't be
    /// copied into the history by accident) and the image.
    @ViewBuilder
    private var revealedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = model.revealText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            }
            if let data = model.revealImageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 120)
            }
            if (model.revealText ?? "").isEmpty && model.revealImageData == nil {
                Text("A file: ⎵ previews it, ⏎ pastes it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
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
            appearanceRow
        }
    }

    /// The row's icon (SF Symbol or emoji, in a popover) and its color.
    private var appearanceRow: some View {
        HStack(spacing: 8) {
            Text("Icon")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Button { model.isPickingIcon = true } label: {
                CategoryIconView(icon: model.iconForPicker, color: model.color, size: 14)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Choose an SF Symbol or an emoji")
            .popover(isPresented: $model.isPickingIcon, arrowEdge: .bottom) {
                CategoryIconPicker(
                    icon: Binding(get: { model.iconForPicker }, set: { model.icon = $0 }),
                    color: model.color
                )
                .padding(12)
                .frame(width: 300)
            }
            ColorPicker(
                "Color",
                selection: Binding(
                    get: { model.color },
                    set: { newColor in
                        model.color = newColor
                        // A color needs an icon to show on.
                        if model.icon == nil { model.icon = model.iconForPicker }
                    }),
                supportsOpacity: false
            )
            .labelsHidden()
            .help("Icon color")
            if model.icon != nil {
                Button("Default") { model.resetAppearance() }
                    .controlSize(.small)
                    .focusable(false)
                    .help("Back to the type's icon and color")
            }
            Spacer()
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
                    .help("Delete (⌘⌫)")
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
                keyHint("⌘⌫", "Delete")
                keyHint("⌥R", model.isRevealed ? "Hide" : "Show")
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
