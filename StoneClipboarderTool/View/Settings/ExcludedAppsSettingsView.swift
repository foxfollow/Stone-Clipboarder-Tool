//
//  ExcludedAppsSettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 01.12.2025.
//

import AppKit
import SwiftData
import SwiftUI

struct ExcludedAppsSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExcludedApp.appName) private var excludedApps: [ExcludedApp]

    @State private var showingAppPicker = false
    @State private var selectedApp: ExcludedApp?

    var body: some View {
        Form {
            Section {
                Toggle("Enable app exclusion", isOn: $settingsManager.enableAppExclusion)
                    .help("When enabled, clipboard content from selected apps will not be saved")
                
                Text(
                    "If enabled: Clipboard content copied from selected apps will not be saved to the database."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if settingsManager.enableAppExclusion {
                Section("Excluded Apps") {
                    if excludedApps.isEmpty {
                        Text("No apps excluded")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(excludedApps) { app in
                                    HStack {
                                        if let icon = getAppIcon(for: app.bundleIdentifier) {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 24, height: 24)
                                        } else {
                                            Image(systemName: "app")
                                                .resizable()
                                                .frame(width: 24, height: 24)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.appName)
                                                .font(.body)
                                            Text(app.bundleIdentifier)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Button(action: {
                                            removeApp(app)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove from excluded apps")
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)

                                    if app.id != excludedApps.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 200, maxHeight: 260)
                    }

                    HStack {
                        Button("Add App...") {
                            showingAppPicker = true
                        }
                        .help("Choose an app to exclude from clipboard tracking")

                        Spacer()

                        if !excludedApps.isEmpty {
                            Button("Remove All") {
                                removeAllApps()
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(
                labels: .exclusion,
                selectedBundleIDs: Set(excludedApps.map(\.bundleIdentifier)),
                onAdd: { selectedBundleId, selectedAppName in
                    addApp(bundleIdentifier: selectedBundleId, appName: selectedAppName)
                },
                onRemove: { bundleID in
                    if let app = excludedApps.first(where: { $0.bundleIdentifier == bundleID }) {
                        removeApp(app)
                    }
                }
            )
        }
    }

    private func getAppIcon(for bundleIdentifier: String) -> NSImage? {
        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }

    private func addApp(bundleIdentifier: String, appName: String) {
        // Check if app is already excluded
        let descriptor = FetchDescriptor<ExcludedApp>(
            predicate: #Predicate { app in
                app.bundleIdentifier == bundleIdentifier
            }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            if !existing.isEmpty {
                return  // App already excluded
            }

            let newApp = ExcludedApp(bundleIdentifier: bundleIdentifier, appName: appName)
            modelContext.insert(newApp)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to add excluded app: \(bundleIdentifier)", category: "SwiftData", error: error)
        }
    }

    private func removeApp(_ app: ExcludedApp) {
        modelContext.delete(app)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to remove excluded app", category: "SwiftData", error: error)
        }
    }

    private func removeAllApps() {
        for app in excludedApps {
            modelContext.delete(app)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ErrorLogger.shared.log("Failed to remove all excluded apps", category: "SwiftData", error: error)
        }
    }
}
