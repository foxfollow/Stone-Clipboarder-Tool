//
//  SettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Sparkle
import SwiftUI

#if DEBUG
    import SwiftData
#endif

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var cbViewModel: CBViewModel
    @Environment(\.dismiss) private var dismiss
    let updater: SPUUpdater?

    @State private var selectedTab = 0
    @State private var showingCleanupAlert = false

    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                Tab("General", systemImage: "gearshape", value: 0) {
                    generalSettings
                }

                Tab("Hotkeys", systemImage: "keyboard", value: 1) {
                    HotkeySettingsView()
                }

                Tab("Excluded Apps", systemImage: "lock.app.dashed", value: 2) {
                    ExcludedAppsSettingsView()
                }

                Tab("About", systemImage: "info.circle", value: 3) {
                    AboutSettingsView(updater: updater)
                }
            }
        }
        .frame(width: 500, height: 500)
    }

    @ViewBuilder
    private var generalSettings: some View {
        Form {
            Section("Appearance") {
                Toggle("Show in Menu Bar", isOn: $settingsManager.showInMenubar)
                    .help("Show clipboard history in the menu bar for quick access")

                Toggle("Show Main Window", isOn: $settingsManager.showMainWindow)
                    .help("Keep the main window visible in the dock")
            }

            Section("Quick Look") {
                Picker("Preview mode:", selection: $settingsManager.quickLookMode) {
                    ForEach(QuickLookMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .help("Choose preview style when pressing the trigger key in QuickPicker")

                Picker("Trigger key:", selection: $settingsManager.quickLookTriggerKey) {
                    ForEach(QuickLookTriggerKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .disabled(settingsManager.quickLookMode == .disabled)
                .opacity(settingsManager.quickLookMode == .disabled ? 0.5 : 1)
                .help("Key to open preview in QuickPicker")

                Toggle("⌥ Enter to extract text (Apple Vision)", isOn: $settingsManager.enableOCROptionKey)
                    .help("When enabled, pressing Option+Enter on an image in QuickPicker will extract and paste text using Apple Vision OCR instead of the image")
            }

            Section("Clipboard Behavior") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Clipboard capture mode:", selection: $settingsManager.clipboardCaptureMode) {
                        ForEach(ClipboardCaptureMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(settingsManager.clipboardCaptureMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help("Choose how to capture clipboard content. Files are always captured regardless of this setting.")
            }
            
            Section("Memory Optimization") {
                Toggle("Auto-cleanup old items", isOn: $settingsManager.enableAutoCleanup)
                    .help("Automatically remove old clipboard items to maintain performance")

                if settingsManager.enableAutoCleanup {
                    HStack {
                        Text("Keep maximum items")
                        Spacer()
                        Stepper(value: $settingsManager.maxItemsToKeep, in: 100...5000, step: 100) {
                            Text("\(settingsManager.maxItemsToKeep)")
                        }
                    }
                    .help("Maximum number of items to keep before auto-cleanup")
                }

                Button("Clean Up Now") {
                    showingCleanupAlert = true
                }
                .help("Manually trigger cleanup to remove old items and free memory")
            }

            Section("Menu Bar Display") {
                HStack {
                    Text("Menu bar display items")
                    Spacer()
                    Stepper(value: $settingsManager.menuBarDisplayLimit, in: 5...50, step: 5) {
                        Text("\(settingsManager.menuBarDisplayLimit)")
                    }
                }
                .help("Number of items shown in menu bar dropdown")
            }

            Section("Memory Management") {
                Toggle("Enable memory cleanup", isOn: $settingsManager.enableMemoryCleanup)
                    .help("Automatically release memory from inactive clipboard items")

                if settingsManager.enableMemoryCleanup {
                    HStack {
                        Text("Cleanup interval (minutes)")
                        Spacer()
                        Stepper(value: $settingsManager.memoryCleanupInterval, in: 1...60, step: 1)
                        {
                            Text("\(settingsManager.memoryCleanupInterval)")
                        }
                    }
                    .help("How often to check for inactive items")

                    HStack {
                        Text("Max inactive time (minutes)")
                        Spacer()
                        Stepper(value: $settingsManager.maxInactiveTime, in: 5...120, step: 5) {
                            Text("\(settingsManager.maxInactiveTime)")
                        }
                    }
                    .help("How long items stay in memory without access")
                }
            }

            Section("Error Logging") {
                Toggle("Save errors to log file", isOn: $settingsManager.enableErrorFileLogging)
                    .help("When enabled, SwiftData and other errors are saved to a .log file for debugging")

                if settingsManager.enableErrorFileLogging {
                    HStack {
                        Text("Log file size")
                        Spacer()
                        Text(ErrorLogger.shared.logFileSizeString)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Button("Show in Finder") {
                            let url = URL(fileURLWithPath: ErrorLogger.shared.logFilePath)
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }

                        Spacer()

                        Button("Clear Log") {
                            ErrorLogger.shared.clearLog()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Clean Up Clipboard History", isPresented: $showingCleanupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Up", role: .destructive) {
                cbViewModel.performManualCleanup()
            }
        } message: {
            Text(
                "This will remove old items beyond the maximum limit and free up memory. Favorites will be preserved."
            )
        }
    }
}
//#Preview {
//    let schema = Schema([CBItem.self])
//    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//    let container = try! ModelContainer(for: schema, configurations: [configuration])
//    let viewModel = CBViewModel()
//    let settingsManager = SettingsManager()
//    let hotkeyManager = HotkeyManager()
//    let updaterController = SPUStandardUpdaterController(
//        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
//
//    SettingsView(updater: updaterController.updater)
//        .environmentObject(viewModel)
//        .environmentObject(settingsManager)
//        .environmentObject(hotkeyManager)
//        .modelContainer(container)
//        .onAppear {
//            viewModel.setModelContext(container.mainContext)
//            viewModel.setSettingsManager(settingsManager)
//        }
//}
