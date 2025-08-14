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

//            Section("Clipboard Settings") {
//                HStack {
//                    Text("Maximum History Items")
//                    Spacer()
//                    Stepper(value: $settingsManager.maxLastItems, in: 10...1000, step: 10) {
//                        Text("\(settingsManager.maxLastItems)")
//                    }
//                }
//                .help("Maximum number of items to keep in clipboard history")
//            }
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
