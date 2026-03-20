//
//  AccessibilitySettingsView.swift
//  StoneClipboarderTool
//
//  Created by Claude on 20.03.2026.
//

import ServiceManagement
import SwiftUI

struct AccessibilitySettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var accessibilityGranted = false
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("Launch at Login") {
                Toggle("Start StoneClipboarder at login", isOn: $settingsManager.startAtLogin)
                    .help("Automatically launch StoneClipboarder when you log in to your Mac")

                Text("You can also manage this in System Settings > General > Login Items.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Accessibility Permission") {
                HStack {
                    Text("Status")
                    Spacer()
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13, weight: .medium))
                    } else {
                        Label("Not Granted", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 13, weight: .medium))
                    }
                }

                if !accessibilityGranted {
                    Text("Accessibility access is required for auto-paste (⌘V simulation) and global hotkeys to work.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    Text("StoneClipboarder has accessibility access. Auto-paste and global hotkeys are fully functional.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityGranted = AccessibilityAlertHelper.isAccessibilityGranted
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                DispatchQueue.main.async {
                    accessibilityGranted = AccessibilityAlertHelper.isAccessibilityGranted
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
}
