//
//  QPVaultPane.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The Passwords tab's body: the lock screen, or the decrypted entries.
/// Keys are handled by QuickPickerView; this view only shows state and
/// takes clicks.
struct QPVaultPane: View {
    @ObservedObject var vaultManager: VaultManager
    let entries: [VaultPayload]
    @Binding var selectedIndex: Int
    let revealedID: UUID?
    let searchText: String
    let onUnlock: () -> Void
    let onPaste: () -> Void
    let onEdit: (VaultPayload) -> Void
    /// The row's eye: show or hide its content.
    var onToggleReveal: (VaultPayload) -> Void = { _ in }

    var body: some View {
        if vaultManager.isUnlocked {
            if entries.isEmpty {
                emptyState
            } else {
                list
            }
        } else {
            lockScreen
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 14) {
            Image(systemName: vaultManager.isAuthenticating ? "touchid" : "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Passwords are locked")
                .font(.headline)
            Button(action: onUnlock) {
                Label("Unlock with Touch ID", systemImage: "touchid")
            }
            .controlSize(.large)
            .disabled(vaultManager.isAuthenticating)
            .focusable(false)
            Text("⏎ to unlock. They lock again when the screen locks or after a while unused.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let message = vaultManager.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            if searchText.isEmpty {
                Text("No passwords yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Select an item on another tab, press ⌥E and choose Move to Passwords (⌥K).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text("No passwords found")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if vaultManager.unreadableCount > 0 {
                unreadableNote
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unreadableNote: some View {
        Text("\(vaultManager.unreadableCount) saved item(s) can't be opened with the current key.")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        QPVaultRow(
                            entry: entry, isSelected: index == selectedIndex, isRevealed: entry.id == revealedID,
                            onToggleReveal: { onToggleReveal(entry) })
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = index
                                onPaste()
                            }
                            .contextMenu {
                                Button("Paste") {
                                    selectedIndex = index
                                    onPaste()
                                }
                                Button(entry.id == revealedID ? "Hide  ⌥R" : "Show  ⌥R") {
                                    onToggleReveal(entry)
                                }
                                Button("Rename, Reorder or Delete…  ⌥E") {
                                    selectedIndex = index
                                    onEdit(entry)
                                }
                            }
                    }
                    if vaultManager.unreadableCount > 0 {
                        unreadableNote
                            .padding(.vertical, 8)
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                guard entries.indices.contains(newIndex) else { return }
                let entry = entries[newIndex]
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(entry.id, anchor: .center)
                }
            }
        }
    }
}
