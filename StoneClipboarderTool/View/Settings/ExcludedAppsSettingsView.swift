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
                        List {
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
                            }
                        }
                        .frame(minHeight: 200, maxHeight: 300)
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
            AppPickerView { selectedBundleId, selectedAppName in
                addApp(bundleIdentifier: selectedBundleId, appName: selectedAppName)
            }
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
            print("Error adding excluded app: \(error)")
        }
    }

    private func removeApp(_ app: ExcludedApp) {
        modelContext.delete(app)
        do {
            try modelContext.save()
        } catch {
            print("Error removing excluded app: \(error)")
        }
    }

    private func removeAllApps() {
        for app in excludedApps {
            modelContext.delete(app)
        }
        do {
            try modelContext.save()
        } catch {
            print("Error removing all excluded apps: \(error)")
        }
    }
}

struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var applications: [AppInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true

    let onAppSelected: (String, String) -> Void

    struct AppInfo: Identifiable {
        let id = UUID()
        let bundleIdentifier: String
        let name: String
        let icon: NSImage?
        let url: URL
    }

    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return applications
        } else {
            return applications.filter { app in
                app.name.localizedCaseInsensitiveContains(searchText)
                    || app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select App to Exclude")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Divider()

            if isLoading {
                ProgressView("Loading applications...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps) { app in
                    Button(action: {
                        onAppSelected(app.bundleIdentifier, app.name)
                        dismiss()
                    }) {
                        HStack {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "app")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.body)
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadApplications()
        }
    }

    private func loadApplications() {
        DispatchQueue.global(qos: .userInitiated).async {
            var apps: [AppInfo] = []
            var seenBundleIds = Set<String>()

            // First, get currently running applications
            let runningApps = NSWorkspace.shared.runningApplications
            for app in runningApps {
                guard let bundleId = app.bundleIdentifier,
                      let url = app.bundleURL,
                      !bundleId.isEmpty else { continue }

                let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
                let icon = app.icon ?? NSWorkspace.shared.icon(forFile: url.path)

                if !seenBundleIds.contains(bundleId) {
                    apps.append(
                        AppInfo(
                            bundleIdentifier: bundleId,
                            name: name,
                            icon: icon,
                            url: url
                        ))
                    seenBundleIds.insert(bundleId)
                }
            }

            // Then scan common application directories (limit depth to avoid slowness)
            let appDirectories = [
                "/Applications",
                "/System/Applications",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
            ]

            let fileManager = FileManager.default

            for directory in appDirectories {
                guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }

                for item in contents {
                    guard item.hasSuffix(".app") else { continue }

                    let fullPath = (directory as NSString).appendingPathComponent(item)
                    let url = URL(fileURLWithPath: fullPath)

                    if let bundle = Bundle(url: url),
                       let bundleId = bundle.bundleIdentifier,
                       !seenBundleIds.contains(bundleId)
                    {
                        let name = bundle.infoDictionary?["CFBundleName"] as? String
                            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                            ?? url.deletingPathExtension().lastPathComponent
                        let icon = NSWorkspace.shared.icon(forFile: url.path)

                        apps.append(
                            AppInfo(
                                bundleIdentifier: bundleId,
                                name: name,
                                icon: icon,
                                url: url
                            ))
                        seenBundleIds.insert(bundleId)
                    }
                }
            }

            // Sort by app name
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self.applications = apps
                self.isLoading = false
            }
        }
    }
}
