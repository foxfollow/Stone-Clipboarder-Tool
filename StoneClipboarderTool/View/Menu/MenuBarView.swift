//
//  MenuBarView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var cbViewModel: CBViewModel
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var clipboardManager: ClipboardManager

    @Environment(\.dismiss) private var dismiss
    private var recentItems: [CBItem] {
        Array(cbViewModel.items.prefix(settingsManager.menuBarDisplayLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: clipboardManager.isPaused ? "arrow.trianglehead.2.clockwise.rotate.90.page.on.clipboard" : "doc.on.clipboard")
                    .foregroundStyle(clipboardManager.isPaused ? .orange : .blue)
                Text("Clipboard History")
                    .font(.headline)

                Spacer()

                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Pause Timer Section
            PauseTimerView()
                .environmentObject(clipboardManager)
                .environmentObject(settingsManager)

            if recentItems.isEmpty {
                Text("No clipboard history")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(recentItems) { item in
                            SwipeableRow(
                                item: item,
                                onDelete: {
                                    withAnimation {
                                        cbViewModel.deleteItem(item)
                                    }
                                },
                                onPreview: { item in
                                    // Open image in Preview app
                                    openInPreview(item: item)
                                },
                                onOpenMain: { item in
                                    // Show main window and select this item
                                    showMainWindowAndSelectItem(item)
                                }
                            ) {
                                Button {
                                    cbViewModel.copyAndUpdateItem(item)
                                } label: {
                                    MenuBarItemView(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer with settings
            HStack {
                Button("Show Main Window") {
                    showMainWindow()
                }
                .buttonStyle(.borderless)

                Spacer()

                Menu("Settings") {
                    Toggle("Show in Menu Bar", isOn: $settingsManager.showInMenubar)
                        .disabled(!settingsManager.showMainWindow)
                    Toggle("Show Main Window (in Dock & Cmd+Tab)", isOn: $settingsManager.showMainWindow)
                        .disabled(!settingsManager.showInMenubar)
                    Divider()
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 350)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            cbViewModel.deleteItems(at: offsets, from: cbViewModel.items)
        }
    }

    private func openInPreview(item: CBItem) {
        cbViewModel.openInPreview(item)
    }

    private func showMainWindow() {
        MainWindow.show(settingsManager: settingsManager)
    }

    private func showMainWindowAndSelectItem(_ item: CBItem) {
        MainWindow.show(settingsManager: settingsManager, selecting: item)
    }
}
