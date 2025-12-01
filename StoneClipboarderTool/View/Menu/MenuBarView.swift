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
                    Toggle("Show Main Window", isOn: $settingsManager.showMainWindow)
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
        Task {
            do {
                try await cbViewModel.openInPreview(item: item)
            } catch {
                print("Failed to open in Preview: \(error)")
            }
        }
    }

    private func showMainWindow() {
        settingsManager.showMainWindow = true

        // First activate the app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find the main window
        var foundWindow: NSWindow?
        for window in NSApp.windows {
            if window.title == "Clipboard History"
                || window.contentView?.subviews.first is NSHostingView<ContentView>
            {
                foundWindow = window
                break
            }
        }

        guard let window = foundWindow else { return }

        // Force the window to appear on current space
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]

        // If window is minimized, restore it
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // Multiple strategies to ensure window appears

        // Strategy 1: Use very high window level temporarily to appear above everything
        let originalLevel = window.level
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Strategy 2: Force window center and visibility
        DispatchQueue.main.async {
            // Center window on current screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = window.frame
                let x = screenFrame.midX - windowFrame.width / 2
                let y = screenFrame.midY - windowFrame.height / 2
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            // Make sure it's visible
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        // Strategy 3: Reset window level after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            window.level = originalLevel
            window.makeKeyAndOrderFront(nil)

            // Final activation to ensure focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showMainWindowAndSelectItem(_ item: CBItem) {
        settingsManager.showMainWindow = true

        // First activate the app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find the main window
        var foundWindow: NSWindow?
        for window in NSApp.windows {
            if window.title == "Clipboard History"
                || window.contentView?.subviews.first is NSHostingView<ContentView>
            {
                foundWindow = window
                break
            }
        }

        guard let window = foundWindow else { return }

        // Force the window to appear on current space
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]

        // If window is minimized, restore it
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // Multiple strategies to ensure window appears

        // Strategy 1: Use very high window level temporarily to appear above everything
        let originalLevel = window.level
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Strategy 2: Force window center and visibility
        DispatchQueue.main.async {
            // Center window on current screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = window.frame
                let x = screenFrame.midX - windowFrame.width / 2
                let y = screenFrame.midY - windowFrame.height / 2
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            // Make sure it's visible
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        // Strategy 3: Reset window level after a delay and select item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            window.level = originalLevel
            window.makeKeyAndOrderFront(nil)

            // Final activation to ensure focus
            NSApp.activate(ignoringOtherApps: true)

            // Select the item after window is properly shown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SelectClipboardItem"),
                    object: "\(item.id)"
                )
            }
        }
    }
}
