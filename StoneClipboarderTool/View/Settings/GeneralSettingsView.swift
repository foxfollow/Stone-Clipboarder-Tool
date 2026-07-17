//
//  GeneralSettingsView.swift
//  StoneClipboarderTool
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var cbViewModel: CBViewModel

    @State private var activeAlert: ClipboardAlert?

    var body: some View {
        Form {
            AppearanceSection()
            ClipboardBehaviorSection()
            MemoryOptimizationSection(activeAlert: $activeAlert)
            MenuBarDisplaySection()
            MemoryManagementSection()
            ErrorLoggingSection()
        }
        .formStyle(.grouped)
        .clipboardAlert(
            $activeAlert,
            onCleanup: { cbViewModel.performManualCleanup() },
            onDeleteAll: { cbViewModel.deleteAllItems() }
        )
    }
}

private struct AppearanceSection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show in Menu Bar", isOn: $settingsManager.showInMenubar)
                    .disabled(!settingsManager.showMainWindow)
                    .help("Show clipboard history in the menu bar for quick access")

                Text("Display the app icon in the macOS menu bar for quick access.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show Main Window (in Dock & Cmd+Tab)", isOn: $settingsManager.showMainWindow)
                    .disabled(!settingsManager.showInMenubar)
                    .help("Show the app icon in the Dock and the Command+Tab switcher")

                Text("Show the app in the Dock and Command+Tab switcher; the main window opens normally.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("At least one of the above must stay on so the app remains accessible.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))

            Toggle("Hold or double-tap ⌘Q to quit", isOn: $settingsManager.confirmQuitOnCmdQ)
                .help("Require holding ⌘Q for 1 second, or double-tapping ⌘Q, to quit — preventing accidental quits")

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Hide other windows when Quick Picker opens", isOn: $settingsManager.closeOtherWindowsOnQuickPicker)
                    .help("Hide the main window (and others) while the Quick Picker is shown.")
                Text("Pinned windows and the Settings window are kept open. Use the Pins tab to let the Quick Picker dismiss pins.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct ClipboardBehaviorSection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
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
    }
}

private struct MemoryOptimizationSection: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var cbViewModel: CBViewModel
    @Binding var activeAlert: ClipboardAlert?

    var body: some View {
        Section("Memory Optimization") {
            HStack(spacing: 4) {
                Text("Items:")
                    .foregroundColor(.secondary)
                Text("\(cbViewModel.totalItemCount) + \(cbViewModel.favoriteItemCount) favorites on Disk")
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary.opacity(0.6))
                Text("\(cbViewModel.inMemoryItemCount) in memory")
                    .foregroundColor(.secondary)
            }
            .font(.caption)

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

            HStack {
                Button("Clean Up Now") { activeAlert = .cleanup }
                    .help("Manually trigger cleanup to remove old items and free memory")

                Spacer()

                Button("Delete All") { activeAlert = .deleteAll }
                    .foregroundColor(.red)
                    .help("Delete all clipboard history items permanently")
            }
        }
    }
}

private struct MenuBarDisplaySection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
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
    }
}

private struct MemoryManagementSection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Section("Memory Management") {
            Toggle("Enable memory cleanup", isOn: $settingsManager.enableMemoryCleanup)
                .help("Automatically release memory from inactive clipboard items")

            if settingsManager.enableMemoryCleanup {
                HStack {
                    Text("Cleanup interval (minutes)")
                    Spacer()
                    Stepper(value: $settingsManager.memoryCleanupInterval, in: 1...60, step: 1) {
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
}

private struct ErrorLoggingSection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
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
                        NSWorkspace.shared.selectFile(
                            url.path,
                            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
                        )
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
}
