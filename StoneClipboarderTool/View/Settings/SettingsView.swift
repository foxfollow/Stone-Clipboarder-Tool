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
    @Environment(\.dismiss) private var dismiss
    let updater: SPUUpdater?

    @State private var selectedTab = 0

    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                Tab("General", systemImage: "gearshape", value: 0) {
                    generalSettings
                }

                Tab("Hotkeys", systemImage: "keyboard", value: 1) {
                    HotkeySettingsView()
                }

                Tab("About", systemImage: "info.circle", value: 2) {
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
        }
        .formStyle(.grouped)
    }
}
#Preview {
    let schema = Schema([CBItem.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    let viewModel = CBViewModel()
    let settingsManager = SettingsManager()
    let hotkeyManager = HotkeyManager()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    SettingsView(updater: updaterController.updater)
        .environmentObject(viewModel)
        .environmentObject(settingsManager)
        .environmentObject(hotkeyManager)
        .modelContainer(container)
        .onAppear {
            viewModel.setModelContext(container.mainContext)
        }
    //        .environmentObject(SettingsManager())
    //        .environmentObject(HotkeyManager())
}
