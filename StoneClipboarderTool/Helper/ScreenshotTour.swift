//
//  ScreenshotTour.swift
//  StoneClipboarderTool
//
//  `--screenshots <dir>`: shows each screen of the demo in dark and light,
//  asks scripts/screenshots.sh to capture its window, then quits. The app
//  can't capture itself without Screen Recording; the terminal running the
//  script has it. See docs/DEMO_MODE.md.
//

import AppKit
import SwiftData
import SwiftUI

@MainActor
final class ScreenshotTour {
    let directory: URL
    let viewModel: CBViewModel
    let settings: SettingsManager
    let quickPicker: QuickPickerWindowManager
    let hotkeyManager: HotkeyManager
    let pinManager: PinManager
    let vaultManager: VaultManager
    let settingsContainer: ModelContainer
    /// Found once: with an item selected the window takes the detail's
    /// title ("Clipboard Item"), which `MainWindow.find()` doesn't match.
    private var mainWindowRef: NSWindow?

    init(directory: URL, viewModel: CBViewModel, settings: SettingsManager, quickPicker: QuickPickerWindowManager,
         hotkeyManager: HotkeyManager, pinManager: PinManager, vaultManager: VaultManager,
         settingsContainer: ModelContainer) {
        self.directory = directory
        self.viewModel = viewModel
        self.settings = settings
        self.quickPicker = quickPicker
        self.hotkeyManager = hotkeyManager
        self.pinManager = pinManager
        self.vaultManager = vaultManager
        self.settingsContainer = settingsContainer
    }

    /// How long a screen gets to settle (async loads, animations).
    private let settle: Duration = .milliseconds(1200)

    func run() async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(2))  // first fetch, window restoration
        mainWindowRef = MainWindow.find()

        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            await mainWindow(scheme)
            await quickPickerPanel(scheme)
            await passwordsPanel(scheme)
            await menuBar(scheme)
            await categoriesSettings(scheme)
        }
        NSApp.terminate(nil)
    }

    // MARK: - Screens

    /// The real "Clipboard History" window with the screenshot item selected.
    private func mainWindow(_ scheme: String) async {
        guard let window = mainWindowRef else { return }
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let image = viewModel.items.first(where: { $0.itemType == .image }) {
            NotificationCenter.default.post(name: .selectClipboardItem, object: image.persistentModelID)
        }
        try? await Task.sleep(for: settle)
        await capture(window, "sct-\(scheme)-basicwindow.png")
    }

    /// The real Quick Picker panel, as the hotkey opens it.
    private func quickPickerPanel(_ scheme: String) async {
        quickPicker.showQuickPicker()
        try? await Task.sleep(for: settle)
        if let panel = quickPicker.pickerWindow {
            await capture(panel, "sct-\(scheme)-quickpicker.png")
        }
        quickPicker.hideQuickPicker()
    }

    /// The Quick Picker opened on the Passwords tab, with the made-up entries.
    private func passwordsPanel(_ scheme: String) async {
        vaultManager.noteUse()
        quickPicker.showQuickPicker(on: .passwords)
        try? await Task.sleep(for: settle)
        if let panel = quickPicker.pickerWindow {
            await capture(panel, "sct-\(scheme)-passwords.png")
        }
        quickPicker.hideQuickPicker()
    }

    /// The menu bar popover's view, in a borderless panel of the same size.
    private func menuBar(_ scheme: String) async {
        let view = MenuBarView()
            .environmentObject(viewModel)
            .environmentObject(settings)
            .environmentObject(viewModel.getClipboardManager())
            .frame(width: 350, height: 400)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.orderFrontRegardless()
        try? await Task.sleep(for: settle)
        await capture(panel, "sct-\(scheme)-menubar.png")
        panel.close()
    }

    /// Settings opened on Categories.
    private func categoriesSettings(_ scheme: String) async {
        let view = SettingsView(updater: nil, initialSection: .categories)
            .environmentObject(settings)
            .environmentObject(hotkeyManager)
            .environmentObject(viewModel)
            .environmentObject(pinManager)
            .environmentObject(vaultManager)
            .modelContainer(settingsContainer)
            .frame(width: 880, height: 640)
        // Wide enough for the sidebar's ideal width: page names and the
        // search field aren't cut off.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        host.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = host
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: settle)
        await capture(window, "sct-\(scheme)-categories.png")
        window.close()
    }

    // MARK: - Capture

    /// Writes `<name>.wid` (the window number) and waits for the script to
    /// write `<name>`. Gives up after 30 s.
    private func capture(_ window: NSWindow, _ name: String) async {
        let url = directory.appendingPathComponent(name)
        let request = url.appendingPathExtension("wid")
        try? FileManager.default.removeItem(at: url)
        try? String(window.windowNumber).write(to: request, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: request) }
        for _ in 0..<150 {
            try? await Task.sleep(for: .milliseconds(200))
            if FileManager.default.fileExists(atPath: url.path), NSImage(contentsOf: url) != nil { return }
        }
        ErrorLogger.shared.log("Screenshot \(name) was not captured", category: "Demo")
    }
}
