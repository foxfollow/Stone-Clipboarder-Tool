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
                excludedApps: excludedApps,
                onAppSelected: { selectedBundleId, selectedAppName in
                    addApp(bundleIdentifier: selectedBundleId, appName: selectedAppName)
                },
                onAppRemoved: { app in
                    removeApp(app)
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

struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var applications: [AppInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showingAlert = false
    @State private var alertApp: AppInfo?

    let excludedApps: [ExcludedApp]
    let onAppSelected: (String, String) -> Void
    let onAppRemoved: (ExcludedApp) -> Void

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

    private func isAppExcluded(_ app: AppInfo) -> Bool {
        excludedApps.contains { $0.bundleIdentifier == app.bundleIdentifier }
    }

    private var appsToExclude: [AppInfo] {
        filteredApps.filter { !isAppExcluded($0) }
    }

    private var appsToInclude: [AppInfo] {
        filteredApps.filter { isAppExcluded($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select App to Exclude")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 16)

            if !searchText.isEmpty {
                HStack {
                    Button("Exclude All Matching") {
                        for app in appsToExclude {
                            onAppSelected(app.bundleIdentifier, app.name)
                        }
                    }
                    .disabled(appsToExclude.isEmpty)
                    .opacity(appsToExclude.isEmpty ? 0.5 : 1.0)

                    Spacer()

                    Button("Include All Matching") {
                        for app in appsToInclude {
                            if let excludedApp = excludedApps.first(where: {
                                $0.bundleIdentifier == app.bundleIdentifier
                            }) {
                                onAppRemoved(excludedApp)
                            }
                        }
                    }
                    .disabled(appsToInclude.isEmpty)
                    .opacity(appsToInclude.isEmpty ? 0.5 : 1.0)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            if isLoading {
                ProgressView("Loading applications...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps) { app in
                    Button(action: {
                        if isAppExcluded(app) {
                            alertApp = app
                            showingAlert = true
                        } else {
                            onAppSelected(app.bundleIdentifier, app.name)
                        }
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

                            if isAppExcluded(app) {
                                Image(systemName: "lock.app.dashed")
                                    .foregroundColor(.red)
                                    .font(.title3)
                            } else {
                                Image(systemName: "app.dashed")
                                    .foregroundColor(.yellow)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 4)
                        .opacity(isAppExcluded(app) ? 0.5 : 1.0)
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
        .alert("App Already Excluded", isPresented: $showingAlert, presenting: alertApp) { app in
            Button("Remove", role: .destructive) {
                if let excludedApp = excludedApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                    onAppRemoved(excludedApp)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { app in
            Text("'\(app.name)' is already in the excluded apps list. Do you want to remove it?")
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
