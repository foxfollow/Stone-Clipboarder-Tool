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
    var clipboardContainer: ModelContainer?
    var settingsContainer: ModelContainer?

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
            let clipboardContainer,
            let settingsContainer
        else {
            return
        }

        isInitialized = true

        cbViewModel.setModelContext(clipboardContainer.mainContext)
        cbViewModel.setSettingsManager(settingsManager)

        // Ensure recent items are loaded immediately
        cbViewModel.fetchItems(reset: true)

        cbViewModel.startClipboardMonitoring()

        // HotkeyManager uses the settings container (HotkeyConfig lives there)
        hotkeyManager.setModelContext(settingsContainer.mainContext)
        hotkeyManager.setCBViewModel(cbViewModel)
        hotkeyManager.setSettingsManager(settingsManager)
        quickPickerManager.setCBViewModel(cbViewModel)
        hotkeyManager.quickPickerDelegate = quickPickerManager

        // Give ClipboardManager a separate context from the settings container for ExcludedApp queries
        cbViewModel.getClipboardManager().setSettingsModelContext(settingsContainer.mainContext)

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
            menuBarManager.setupMenuBar(cbViewModel: cbViewModel, settingsManager: settingsManager, clipboardManager: cbViewModel.getClipboardManager())

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

// MARK: - Container Factory
/// Creates separate ModelContainers for clipboard history and settings.
/// Clipboard data is high-churn and corruption-prone; settings are low-churn and must persist.
/// Separating them prevents clipboard DB corruption from wiping settings.
enum ModelContainerFactory {
    private static let logger = ErrorLogger.shared

    /// Clipboard container: stores CBItem only
    static func makeClipboardContainer() -> ModelContainer {
        let schema = Schema([CBItem.self])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport
            .appendingPathComponent("StoneClipboarderTool")
            .appendingPathComponent("ClipboardHistory.store")

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let config = ModelConfiguration("ClipboardHistory", schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.log("Clipboard container creation failed, attempting recovery", category: "SwiftData", error: error)

            // Recovery: delete corrupted DB and retry
            do {
                // Remove the main store file and its WAL/SHM companions
                let storeDir = storeURL.deletingLastPathComponent()
                let storeName = storeURL.lastPathComponent
                let fm = FileManager.default
                if let files = try? fm.contentsOfDirectory(atPath: storeDir.path) {
                    for file in files where file.hasPrefix(storeName) {
                        try? fm.removeItem(at: storeDir.appendingPathComponent(file))
                    }
                }

                logger.log("Deleted corrupted clipboard DB, creating fresh container", category: "SwiftData")
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                logger.log("CRITICAL: Cannot create clipboard container even after recovery", category: "SwiftData", error: error)
                // Last resort: in-memory container so the app doesn't crash
                let memConfig = ModelConfiguration("ClipboardHistoryMemory", schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memConfig])
                } catch {
                    // This should never happen but we absolutely must not crash
                    fatalError("Cannot create even in-memory clipboard container: \(error)")
                }
            }
        }
    }

    /// Settings container: stores HotkeyConfig and ExcludedApp
    static func makeSettingsContainer() -> ModelContainer {
        let schema = Schema([HotkeyConfig.self, ExcludedApp.self])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport
            .appendingPathComponent("StoneClipboarderTool")
            .appendingPathComponent("Settings.store")

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let config = ModelConfiguration("Settings", schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.log("Settings container creation failed, attempting recovery", category: "SwiftData", error: error)

            // Recovery: delete and retry
            do {
                let storeDir = storeURL.deletingLastPathComponent()
                let storeName = storeURL.lastPathComponent
                let fm = FileManager.default
                if let files = try? fm.contentsOfDirectory(atPath: storeDir.path) {
                    for file in files where file.hasPrefix(storeName) {
                        try? fm.removeItem(at: storeDir.appendingPathComponent(file))
                    }
                }

                logger.log("Deleted corrupted settings DB, creating fresh container", category: "SwiftData")
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                logger.log("CRITICAL: Cannot create settings container even after recovery", category: "SwiftData", error: error)
                let memConfig = ModelConfiguration("SettingsMemory", schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memConfig])
                } catch {
                    fatalError("Cannot create even in-memory settings container: \(error)")
                }
            }
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

    /// Clipboard history container (CBItem only — high churn, safe to reset on corruption)
    var clipboardContainer: ModelContainer = ModelContainerFactory.makeClipboardContainer()

    /// Settings container (HotkeyConfig + ExcludedApp — low churn, must persist)
    var settingsContainer: ModelContainer = ModelContainerFactory.makeSettingsContainer()

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
            .modelContainer(clipboardContainer)
            .windowResizability(.contentSize)
            .defaultSize(width: 800, height: 600)
            .commands {
                CommandGroup(after: .appInfo) {
                    CheckForUpdatesView(updater: updaterController.updater)
                }
            }

            // Custom Settings window with ID — uses settings container for ExcludedApp + HotkeyConfig
            WindowGroup("Settings", id: "settings") {
                SettingsView(updater: updaterController.updater)
                    .environmentObject(settingsManager)
                    .environmentObject(hotkeyManager)
                    .environmentObject(cbViewModel)
                    .frame(width: 500, height: 500)
            }
            .modelContainer(settingsContainer)
            .windowResizability(.contentSize)
            .windowStyle(.automatic)

            Settings {
                SettingsView(updater: updaterController.updater)
                    .environmentObject(settingsManager)
                    .environmentObject(hotkeyManager)
                    .environmentObject(cbViewModel)
            }
            .modelContainer(settingsContainer)
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
        appDelegate.clipboardContainer = clipboardContainer
        appDelegate.settingsContainer = settingsContainer

        // Trigger setup (will only run once)
        appDelegate.performSetup()
    }

    private func updateMenuBarVisibility() {
        if settingsManager.showInMenubar {
            menuBarManager.setupMenuBar(cbViewModel: cbViewModel, settingsManager: settingsManager, clipboardManager: cbViewModel.getClipboardManager())

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
