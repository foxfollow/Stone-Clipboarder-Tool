//
//  SettingsView.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 08.08.2025.
//

import Sparkle
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    let updater: SPUUpdater?

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show in Menu Bar", isOn: $settingsManager.showInMenubar)
                    .help("Show clipboard history in the menu bar for quick access")

                Toggle("Show Main Window", isOn: $settingsManager.showMainWindow)
                    .help("Keep the main window visible in the dock")
            }

            Section("About") {
                HStack {
                    Image("128AppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading) {
                        Text("StoneClipboarderTool")
                            .font(.headline)
                        Text("Clipboard History Manager")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)

                HStack {
                    Text(
                        "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Check for Updates") {
                        updater?.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(updater?.canCheckForUpdates ?? false))
                }

                HStack {
                    Text("Built with ❤️")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Site") {
                        if let url = URL(
                            string: "https://foxfollow.github.io/Stone-Clipboarder-Tool/")
                        {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    //                    .buttonStyle(.borderedProminent)

                    Button("Privacy Policy") {
                        if let url = URL(
                            string:
                                "https://github.com/foxfollow/Stone-Clipboarder-Tool/blob/main/PrivacyPolicy.md"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Terms of Use") {
                        if let url = URL(
                            string:
                                "https://github.com/foxfollow/Stone-Clipboarder-Tool/blob/main/TermsOfUse.md"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }

                }

                HStack {
                    Text("© 2025 Heorhii Savoiskyi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Send feedback") {
                        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
                        let deviceModel = getDeviceModel()

                        let subject = "StoneClipboarderTool Feedback"
                        let body = """
                        Hi,

                        I'd like to share feedback about StoneClipboarderTool:

                        [Please describe your feedback here]

                        ---
                        App Version: \(appVersion) (\(buildNumber))
                        macOS Version: \(osVersion)
                        Device: \(deviceModel)
                        """

                        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

                        if let url = URL(string: "mailto:d3f0ld@pm.me?subject=\(encodedSubject)&body=\(encodedBody)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(width: 400, height: 400)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func getDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

#Preview {
    SettingsView(updater: nil)
        .environmentObject(SettingsManager())
}
