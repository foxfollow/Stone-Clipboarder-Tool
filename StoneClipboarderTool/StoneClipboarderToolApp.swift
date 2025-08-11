//
//  StoneClipboarderToolApp.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Sparkle
import SwiftData
import SwiftUI

@main
struct StoneClipboarderToolApp: App {
    @StateObject private var cbViewModel = CBViewModel()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var menuBarManager = MenuBarManager()

    private let updaterController: SPUStandardUpdaterController

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CBItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        WindowGroup("Clipboard History") {
            ContentView(updater: updaterController.updater)
                .environmentObject(cbViewModel)
                .environmentObject(settingsManager)
                .onAppear {
                    setupApp()
                }
                .onChange(of: settingsManager.showInMenubar) { _, newValue in
                    updateMenuBarVisibility()
                }
                .onChange(of: settingsManager.showMainWindow) { _, newValue in
                    updateWindowVisibility()
                }
        }
        .modelContainer(sharedModelContainer)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environmentObject(settingsManager)
        }
    }

    private func setupApp() {
        cbViewModel.setModelContext(sharedModelContainer.mainContext)
        cbViewModel.startClipboardMonitoring()

        updateMenuBarVisibility()
        updateWindowVisibility()
    }

    private func updateMenuBarVisibility() {
        if settingsManager.showInMenubar {
            menuBarManager.setupMenuBar(cbViewModel: cbViewModel, settingsManager: settingsManager)
        } else {
            menuBarManager.hideMenuBar()
        }
    }

    private func updateWindowVisibility() {
        if settingsManager.showMainWindow {
            NSApp.setActivationPolicy(.regular)

            // Configure main window to automatically follow across desktops
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    if window.title == "Clipboard History"
                        || window.contentView?.subviews.first is NSHostingView<ContentView>
                    {
                        // Set window to automatically move to active space
                        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
                        break
                    }
                }
            }
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
