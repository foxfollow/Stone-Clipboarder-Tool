//
//  StoneClipboarderToolApp.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import SwiftData
import SwiftUI
import Sparkle

@main
struct StoneClipboarderToolApp: App {
    @StateObject private var cbViewModel = CBViewModel()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var menuBarManager = MenuBarManager()
    
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

    var body: some Scene {
        WindowGroup("Clipboard History") {
            ContentView()
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
        
        Settings {
            SettingsView()
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
                    if window.title == "Clipboard History" || window.contentView?.subviews.first is NSHostingView<ContentView> {
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
