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
    var pinManager: PinManager?
    var clipboardContainer: ModelContainer?
    var settingsContainer: ModelContainer?

    private var isInitialized = false
    /// Watches the running-application record so a late reset of the activation
    /// policy can be undone — see `startGuardingActivationPolicy()`.
    private var activationPolicyObservation: NSKeyValueObservation?
    /// Held strongly on purpose: NSKeyValueObservation doesn't retain what it
    /// observes, and AppKit keeps delivering LaunchServices change callbacks to
    /// an observed NSRunningApplication. Letting it deallocate crashes the app
    /// (objc_msgSend in runningApplicationNotificationCallback) on the first
    /// policy change.
    private var observedRunningApplication: NSRunningApplication?
    private var quitKeyDownMonitor: Any?
    private var quitKeyUpMonitor: Any?
    private var quitTimer: Timer?
    private var quitDoubleTapTimer: Timer?
    private var awaitingSecondTap = false
    private var quitHUDWindow: NSWindow?
    private var quitHUDShownAt: Date?

    private let quitHoldDuration: TimeInterval = 1.0
    private let quitHUDMinDisplayDuration: TimeInterval = 0.8
    private let quitDoubleTapWindow: TimeInterval = 0.4

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize app in background, even if no window appears
        // If managers aren't ready yet, this will be called again after registration
        performSetup()
        guard !AppEnvironment.isRunningUnitTests else { return }

        // The activation policy MUST be (re)applied here, after the app has finished
        // launching. performSetup() usually already ran during SwiftUI body evaluation
        // (via registerWithAppDelegate), which is *before* this point — and a
        // setActivationPolicy(.accessory) call that early is reset by AppKit to the
        // Info.plist default (.regular) once launch completes. Because performSetup() is
        // guarded by isInitialized, it won't re-apply the policy here on its own, so the
        // app would stay in the Dock & Cmd+Tab after a cold launch (e.g. login-item
        // relaunch after a reboot) despite "Show Main Window" being off — until the user
        // toggled the setting off and on again. Re-applying here covers a normal launch;
        // startGuardingActivationPolicy() covers a slow login-item check-in that lands later.
        if let settingsManager {
            updateWindowVisibility(settingsManager: settingsManager)
        }
        startGuardingActivationPolicy()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !AppEnvironment.isRunningUnitTests else { return }
        // Quick Look copies of clipboard items shouldn't outlive the app.
        QPQuickLookCoordinator.removeAllPreviewSessions()
    }

    /// Keeps Dock / Cmd+Tab presence matching `showMainWindow` after launch.
    ///
    /// Re-applying the policy in applicationDidFinishLaunching is not enough on
    /// its own. LaunchServices check-in stamps the Info.plist default type
    /// (Foreground) onto the app, and check-in is asynchronous: on a normal launch
    /// it completes within milliseconds, before our re-apply, but for a login-item
    /// launch it was measured at 3.3 s — landing after the re-apply and putting
    /// the app back in the Dock. Nothing signals check-in completion, so correct
    /// drift whenever the running-application record changes, and re-check on a
    /// short schedule in case that change is never observed.
    private func startGuardingActivationPolicy() {
        let runningApplication = NSRunningApplication.current
        observedRunningApplication = runningApplication
        activationPolicyObservation = runningApplication.observe(\.activationPolicy) {
            [weak self] _, _ in
            Task { @MainActor in self?.correctActivationPolicyDrift() }
        }
        for delay in [1.0, 3.0, 6.0, 10.0, 20.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.correctActivationPolicyDrift()
            }
        }
    }

    /// Re-applies the policy the settings call for, if the system disagrees.
    /// A no-op when nothing drifted, so it's safe to call on every change —
    /// legitimate toggles update `showMainWindow` before the policy, never after.
    private func correctActivationPolicyDrift() {
        guard let settingsManager else { return }
        let wanted: NSApplication.ActivationPolicy = settingsManager.showMainWindow ? .regular : .accessory
        // NSRunningApplication reflects what LaunchServices — and so the Dock —
        // believes. NSApp.activationPolicy() can be a stale cache of our own
        // last call, which is exactly the value that got overwritten.
        let actual = NSRunningApplication.current.activationPolicy
        guard actual != wanted else { return }

        ErrorLogger.shared.log(
            "Activation policy drifted to \(actual.rawValue), expected \(wanted.rawValue); re-applying",
            category: "WindowVisibility")

        // If AppKit's cache already holds the target value, setting it again may
        // be skipped as a no-op and never reach LaunchServices. Sync the cache to
        // the real state first — the Dock already shows that state, so this step
        // is invisible.
        if NSApp.activationPolicy() == wanted, actual != .prohibited {
            NSApp.setActivationPolicy(actual)
        }
        updateWindowVisibility(settingsManager: settingsManager)
    }

    func performSetup() {
        guard !isInitialized,
            let cbViewModel,
            let settingsManager,
            let menuBarManager,
            let hotkeyManager,
            let quickPickerManager,
            let pinManager,
            let clipboardContainer,
            let settingsContainer
        else {
            return
        }

        isInitialized = true

        // When the app only hosts the unit-test bundle, stay inert: no
        // clipboard monitoring, global hotkeys, menu bar item, pins or ⌘Q
        // monitor. Tests build the objects they need themselves.
        if AppEnvironment.isRunningUnitTests { return }

        cbViewModel.setModelContext(clipboardContainer.mainContext)
        cbViewModel.setSettingsManager(settingsManager)

        // Load the first rows on the next turn: performSetup runs while
        // SwiftUI evaluates App.body, where publishing `items` isn't allowed.
        DispatchQueue.main.async {
            cbViewModel.fetchItems(reset: true)
        }

        cbViewModel.startClipboardMonitoring()

        // HotkeyManager uses the settings container (HotkeyConfig lives there)
        hotkeyManager.setModelContext(settingsContainer.mainContext)
        hotkeyManager.setCBViewModel(cbViewModel)
        hotkeyManager.setSettingsManager(settingsManager)
        hotkeyManager.setPinManager(pinManager)
        quickPickerManager.setCBViewModel(cbViewModel)
        quickPickerManager.setSettingsManager(settingsManager)
        quickPickerManager.setPinManager(pinManager)
        hotkeyManager.quickPickerDelegate = quickPickerManager

        // PinManager shares the settings container (PinnedItemConfig lives there)
        pinManager.viewModel = cbViewModel
        pinManager.settingsManager = settingsManager
        pinManager.modelContext = settingsContainer.mainContext
        pinManager.startObservingItemDeletes()
        pinManager.restorePersistedPins()

        // Give ClipboardManager a separate context from the settings container for ExcludedApp queries
        cbViewModel.getClipboardManager().setSettingsModelContext(settingsContainer.mainContext)

        // Connect menubar refresh callback to fix state after QuickPicker operations
        quickPickerManager.setMenuBarRefreshCallback {
            menuBarManager.refreshMenuBar()
        }

        // Clean up leftover preview session files from previous launches
        QPQuickLookCoordinator.cleanupOldPreviewSessions()

        // Load and register hotkeys
        hotkeyManager.loadHotkeyConfigs()

        updateMenuBarVisibility(
            settingsManager: settingsManager, menuBarManager: menuBarManager,
            cbViewModel: cbViewModel)
        updateWindowVisibility(settingsManager: settingsManager)
        startQuitKeyMonitor()
    }

    /// Applies `showInMenubar`. Called at setup and when the setting changes.
    func applyMenuBarVisibility() {
        guard let settingsManager, let menuBarManager, let cbViewModel else { return }
        updateMenuBarVisibility(settingsManager: settingsManager, menuBarManager: menuBarManager, cbViewModel: cbViewModel)
    }

    /// Applies `showMainWindow` (Dock / ⌘Tab presence and the main window).
    /// Called at setup, after launch and when the setting changes.
    func applyWindowVisibility() {
        guard let settingsManager else { return }
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

    private func startQuitKeyMonitor() {
        quitKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.settingsManager?.confirmQuitOnCmdQ == true,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.keyCode == 12, // Q
                  !event.isARepeat
            else { return event }
            if self.awaitingSecondTap {
                self.confirmQuit()
            } else {
                self.handleQuitKeyDown()
            }
            return nil // consume event, prevent default quit
        }
    }

    private func handleQuitKeyDown() {
        showQuitHUD()
        quitTimer = Timer.scheduledTimer(withTimeInterval: quitHoldDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.confirmQuit()
            }
        }
        quitKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 12 {
                DispatchQueue.main.async { self?.handleQuitKeyUp() }
            }
            return event
        }
    }

    private func handleQuitKeyUp() {
        quitTimer?.invalidate()
        quitTimer = nil
        if let monitor = quitKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            quitKeyUpMonitor = nil
        }
        // Start a window during which a second ⌘Q press will confirm quit
        awaitingSecondTap = true
        quitDoubleTapTimer = Timer.scheduledTimer(withTimeInterval: quitDoubleTapWindow, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.expireDoubleTapWindow() }
        }
    }

    private func expireDoubleTapWindow() {
        awaitingSecondTap = false
        quitDoubleTapTimer?.invalidate()
        quitDoubleTapTimer = nil
        // Keep HUD visible for minimum duration so the user can read it
        let elapsed = quitHUDShownAt.map { Date().timeIntervalSince($0) } ?? quitHUDMinDisplayDuration
        let remaining = quitHUDMinDisplayDuration - elapsed
        if remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.hideQuitHUD()
            }
        } else {
            hideQuitHUD()
        }
    }

    private func confirmQuit() {
        quitTimer?.invalidate()
        quitTimer = nil
        quitDoubleTapTimer?.invalidate()
        quitDoubleTapTimer = nil
        awaitingSecondTap = false
        if let monitor = quitKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            quitKeyUpMonitor = nil
        }
        hideQuitHUD()
        NSApp.terminate(nil)
    }

    private func showQuitHUD() {
        guard quitHUDWindow == nil else { return }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hud = NSHostingView(rootView: QuitHUDView())
        hud.frame = NSRect(origin: .zero, size: hud.fittingSize)
        panel.contentView = hud
        panel.setContentSize(hud.fittingSize)

        if let screen = NSScreen.main {
            let mid = screen.frame
            let sz = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: mid.midX - sz.width / 2, y: mid.midY - sz.height / 2))
        }
        panel.orderFront(nil)
        quitHUDWindow = panel
        quitHUDShownAt = Date()
    }

    private func hideQuitHUD() {
        quitHUDWindow?.orderOut(nil)
        quitHUDWindow = nil
        quitHUDShownAt = nil
    }

    private func updateWindowVisibility(settingsManager: SettingsManager) {
        if settingsManager.showMainWindow {
            NSApp.setActivationPolicy(.regular)

            // Configure main window to automatically follow across desktops
            DispatchQueue.main.async {
                MainWindow.find()?.collectionBehavior = MainWindow.collectionBehavior
            }
        } else {
            // Hide the auto-created "Clipboard History" WindowGroup window and drop to
            // accessory (no Dock icon / not in Cmd+Tab). See applicationDidFinishLaunching
            // for why this must also be re-applied after launch: an accessory policy set
            // too early (during SwiftUI body evaluation, before the app finishes launching)
            // is reset by AppKit to the Info.plist default (.regular).
            hideMainWindowAndDropToAccessory()
            // The WindowGroup window may not exist yet on the first tick; re-apply once
            // more after the runloop settles so it can't keep the app in the Dock.
            DispatchQueue.main.async { [weak self] in
                self?.hideMainWindowAndDropToAccessory()
            }
        }
    }

    /// Hides the main window (keeping the NSWindow object alive so MenuBarView's
    /// "Show Main Window" can re-show it later) and re-asserts the accessory policy.
    private func hideMainWindowAndDropToAccessory() {
        for window in NSApp.windows where MainWindow.isMainWindow(window) {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Quit HUD
private struct QuitHUDView: View {
    var body: some View {
        Text("Hold \u{2318}Q to Quit")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 36)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.18).opacity(0.95))
            )
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
        makeContainer(schema: Schema([CBItem.self]), storeName: "ClipboardHistory")
    }

    /// Settings container: stores HotkeyConfig, ExcludedApp, and PinnedItemConfig
    static func makeSettingsContainer() -> ModelContainer {
        makeContainer(
            schema: Schema([HotkeyConfig.self, ExcludedApp.self, PinnedItemConfig.self]),
            storeName: "Settings"
        )
    }

    /// Opens `Application Support/StoneClipboarderTool/<storeName>.store`.
    /// Recovery: if opening fails, delete the store and its WAL/SHM companions
    /// and retry; if that fails too, fall back to an in-memory container so the
    /// app still launches. A unit-test host always gets an in-memory container.
    private static func makeContainer(schema: Schema, storeName: String) -> ModelContainer {
        guard !AppEnvironment.isRunningUnitTests else {
            return makeInMemoryContainer(schema: schema, name: "\(storeName)Tests")
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport
            .appendingPathComponent("StoneClipboarderTool")
            .appendingPathComponent("\(storeName).store")

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let config = ModelConfiguration(storeName, schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.log("\(storeName) container creation failed, attempting recovery", category: "SwiftData", error: error)

            // Recovery: delete corrupted DB and retry
            do {
                // Remove the main store file and its WAL/SHM companions
                let storeDir = storeURL.deletingLastPathComponent()
                let storeFileName = storeURL.lastPathComponent
                let fm = FileManager.default
                if let files = try? fm.contentsOfDirectory(atPath: storeDir.path) {
                    for file in files where file.hasPrefix(storeFileName) {
                        try? fm.removeItem(at: storeDir.appendingPathComponent(file))
                    }
                }

                logger.log("Deleted corrupted \(storeName) DB, creating fresh container", category: "SwiftData")
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                logger.log("CRITICAL: Cannot create \(storeName) container even after recovery", category: "SwiftData", error: error)
                // Last resort: in-memory container so the app doesn't crash
                return makeInMemoryContainer(schema: schema, name: "\(storeName)Memory")
            }
        }
    }

    private static func makeInMemoryContainer(schema: Schema, name: String) -> ModelContainer {
        let config = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // The only sanctioned fatalError: without even an in-memory store
            // there is nothing the app can do.
            fatalError("Cannot create even an in-memory \(name) container: \(error)")
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
    @StateObject private var pinManager = PinManager()

    private let updaterController: SPUStandardUpdaterController

    /// Clipboard history container (CBItem only — high churn, safe to reset on corruption)
    var clipboardContainer: ModelContainer = ModelContainerFactory.makeClipboardContainer()

    /// Settings container (HotkeyConfig + ExcludedApp — low churn, must persist)
    var settingsContainer: ModelContainer = ModelContainerFactory.makeSettingsContainer()

    init() {
        // A unit-test host must not check for (or offer) updates.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !AppEnvironment.isRunningUnitTests,
            updaterDelegate: nil, userDriverDelegate: nil)
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
                    .environmentObject(pinManager)
                    .onChange(of: settingsManager.showInMenubar) { _, _ in
                        appDelegate.applyMenuBarVisibility()
                    }
                    .onChange(of: settingsManager.showMainWindow) { _, _ in
                        appDelegate.applyWindowVisibility()
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
                    .environmentObject(pinManager)
                    .frame(minWidth: 720, minHeight: 540)
            }
            .modelContainer(settingsContainer)
            .windowResizability(.contentSize)
            .windowStyle(.automatic)

            Settings {
                SettingsView(updater: updaterController.updater)
                    .environmentObject(settingsManager)
                    .environmentObject(hotkeyManager)
                    .environmentObject(cbViewModel)
                    .environmentObject(pinManager)
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
        appDelegate.pinManager = pinManager
        appDelegate.clipboardContainer = clipboardContainer
        appDelegate.settingsContainer = settingsContainer

        // Trigger setup (will only run once)
        appDelegate.performSetup()
    }
}
