//
//  StoneClipboarderToolApp.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Sparkle
import SwiftData
import SwiftUI

// MARK: - AppDelegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Store references to managers for background initialization
    var cbViewModel: CBViewModel?
    var settingsManager: SettingsManager?
    var menuBarManager: MenuBarManager?
    var hotkeyManager: HotkeyManager?
    var quickPickerManager: QuickPickerWindowManager?
    var sharedModelContainer: ModelContainer?

    private var isInitialized = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize app in background, even if no window appears
        // If managers aren't ready yet, this will be called again after registration
        performSetup()
    }

    func performSetup() {
        guard !isInitialized,
            let cbViewModel,
            let settingsManager,
            let menuBarManager,
            let hotkeyManager,
            let quickPickerManager,
            let sharedModelContainer
        else {
            return
        }

        isInitialized = true

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

        updateMenuBarVisibility(
            settingsManager: settingsManager, menuBarManager: menuBarManager,
            cbViewModel: cbViewModel)
        updateWindowVisibility(settingsManager: settingsManager)
    }

    private func updateMenuBarVisibility(
        settingsManager: SettingsManager, menuBarManager: MenuBarManager, cbViewModel: CBViewModel
    ) {
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

    private func updateWindowVisibility(settingsManager: SettingsManager) {
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

// MARK: - App
@main
struct StoneClipboarderToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
            ExcludedApp.self,
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
        // Register managers with AppDelegate immediately when body is evaluated
        // This happens before any window appears
        let _ = registerWithAppDelegate()

        return Group {
            WindowGroup("Clipboard History") {
                ContentView()
                    .environmentObject(cbViewModel)
                    .environmentObject(settingsManager)
                    .environmentObject(hotkeyManager)
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
                    .environmentObject(cbViewModel)
                    .frame(width: 500, height: 500)
            }
            .modelContainer(sharedModelContainer)
            .windowResizability(.contentSize)
            .windowStyle(.automatic)

            Settings {
                SettingsView(updater: updaterController.updater)
                    .environmentObject(settingsManager)
                    .environmentObject(hotkeyManager)
                    .environmentObject(cbViewModel)
            }
            .modelContainer(sharedModelContainer)
        }
    }

    @MainActor
    private func registerWithAppDelegate() {
        // Provide references to AppDelegate
        appDelegate.cbViewModel = cbViewModel
        appDelegate.settingsManager = settingsManager
        appDelegate.menuBarManager = menuBarManager
        appDelegate.hotkeyManager = hotkeyManager
        appDelegate.quickPickerManager = quickPickerManager
        appDelegate.sharedModelContainer = sharedModelContainer

        // Trigger setup (will only run once)
        appDelegate.performSetup()
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
