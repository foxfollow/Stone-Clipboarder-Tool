//
//  AppPickerView.swift
//  StoneClipboarderTool
//
//  Moved out of ExcludedAppsSettingsView.swift; shared with app groups.
//

import AppKit
import SwiftUI

/// Lists running and installed apps to pick from: the Excluded Apps list
/// and the app groups in Categories.
struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var applications: [AppInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showingAlert = false
    @State private var alertApp: AppInfo?

    /// The texts that differ between Excluded Apps and an app group.
    struct Labels {
        let title: String
        let addAllMatching: String
        let removeAllMatching: String
        let alreadySelectedTitle: String
        /// "'Safari' is already in …": the list's name.
        let listName: String
        /// Marks a selected app in the list.
        let selectedSymbol: String
        let selectedColor: Color

        static let exclusion = Labels(
            title: "Select App to Exclude",
            addAllMatching: "Exclude All Matching",
            removeAllMatching: "Include All Matching",
            alreadySelectedTitle: "App Already Excluded",
            listName: "the excluded apps list",
            selectedSymbol: "lock.app.dashed",
            selectedColor: .red)

        static let appGroup = Labels(
            title: "Select Apps for the Group",
            addAllMatching: "Add All Matching",
            removeAllMatching: "Remove All Matching",
            alreadySelectedTitle: "App Already in the Group",
            listName: "this group",
            selectedSymbol: "checkmark.circle.fill",
            selectedColor: .accentColor)
    }

    let labels: Labels
    let selectedBundleIDs: Set<String>
    /// bundle id, app name
    let onAdd: (String, String) -> Void
    /// bundle id
    let onRemove: (String) -> Void

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
        selectedBundleIDs.contains(app.bundleIdentifier)
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
                Text(labels.title)
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
                    Button(labels.addAllMatching) {
                        for app in appsToExclude {
                            onAdd(app.bundleIdentifier, app.name)
                        }
                    }
                    .disabled(appsToExclude.isEmpty)
                    .opacity(appsToExclude.isEmpty ? 0.5 : 1.0)

                    Spacer()

                    Button(labels.removeAllMatching) {
                        for app in appsToInclude {
                            onRemove(app.bundleIdentifier)
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
                            onAdd(app.bundleIdentifier, app.name)
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
                                Image(systemName: labels.selectedSymbol)
                                    .foregroundColor(labels.selectedColor)
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
        .alert(labels.alreadySelectedTitle, isPresented: $showingAlert, presenting: alertApp) { app in
            Button("Remove", role: .destructive) {
                onRemove(app.bundleIdentifier)
            }
            Button("Cancel", role: .cancel) { /* No action needed for cancel */ }
        } message: { app in
            Text("'\(app.name)' is already in \(labels.listName). Do you want to remove it?")
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
