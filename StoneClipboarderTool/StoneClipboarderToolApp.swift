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
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var quickPickerManager = QuickPickerWindowManager()

    private let updaterController: SPUStandardUpdaterController

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CBItem.self,
            HotkeyConfig.self,
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
            ContentView()
                .environmentObject(cbViewModel)
                .environmentObject(settingsManager)
                .environmentObject(hotkeyManager)
                .onAppear {
                    setupApp()
                }
                .onChange(of: settingsManager.showInMenubar) { _, newValue in
                    updateMenuBarVisibility()
                }
                .onChange(of: settingsManager.showMainWindow) { _, newValue in
                    updateWindowVisibility()
                }
                .onChange(of: settingsManager.enableHotkeys) { _, newValue in
                    hotkeyManager.refreshHotkeyRegistrations()
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

        // Custom Settings window with ID
        WindowGroup("Settings", id: "settings") {
            SettingsView(updater: updaterController.updater)
                .environmentObject(settingsManager)
                .environmentObject(hotkeyManager)
                .frame(width: 500, height: 500)
        }
        .windowResizability(.contentSize)
        .windowStyle(.automatic)

        Settings {
            SettingsView(updater: updaterController.updater)
                .environmentObject(settingsManager)
                .environmentObject(hotkeyManager)
        }

    }

    private func setupApp() {
        cbViewModel.setModelContext(sharedModelContainer.mainContext)
        cbViewModel.setSettingsManager(settingsManager)

        // Ensure recent items are loaded immediately
        cbViewModel.fetchItems(reset: true)

        cbViewModel.startClipboardMonitoring()

        hotkeyManager.setModelContext(sharedModelContainer.mainContext)
        hotkeyManager.setCBViewModel(cbViewModel)
        hotkeyManager.setSettingsManager(settingsManager)
        quickPickerManager.setCBViewModel(cbViewModel)
        hotkeyManager.quickPickerDelegate = quickPickerManager

        // Connect menubar refresh callback to fix state after QuickPicker operations
        quickPickerManager.setMenuBarRefreshCallback {
            menuBarManager.refreshMenuBar()
        }

        // Load and register hotkeys
        hotkeyManager.loadHotkeyConfigs()

        updateMenuBarVisibility()
        updateWindowVisibility()
    }

    private func updateMenuBarVisibility() {
        if settingsManager.showInMenubar {
            menuBarManager.setupMenuBar(cbViewModel: cbViewModel, settingsManager: settingsManager)

            // Monitor and refresh menubar state periodically to prevent corruption
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                menuBarManager.refreshMenuBar()
            }
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
