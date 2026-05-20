//
//  PinSettingsView.swift
//  StoneClipboarderTool
//

import SwiftUI

struct PinSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var pinManager: PinManager

    @State private var showDismissConfirm: Bool = false

    var body: some View {
        Form {
            generalSection
            defaultsSection
            advancedSection
            activePinsSection
        }
        .formStyle(.grouped)
        .alert("Dismiss all pins?", isPresented: $showDismissConfirm) {
            Button("Dismiss All", role: .destructive) {
                pinManager.dismissAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will close every floating pin on screen. Pin contents in clipboard history are unaffected.")
        }
        .onChange(of: settingsManager.pinPersistAcrossLaunches) { _, _ in
            pinManager.handlePersistenceSettingChanged()
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section("Pin Behavior") {
            Toggle("Persist pins across launches", isOn: $settingsManager.pinPersistAcrossLaunches)
                .help("Reopen your pins when the app restarts. Stored locally; never synced.")

            Toggle("Always show pin controls", isOn: $settingsManager.pinAlwaysShowChrome)
                .help("When off, the close / lock / opacity controls only appear on hover.")

            Toggle("Show on all Spaces", isOn: $settingsManager.pinShowOnAllSpaces)
                .help("Pins follow you to every Mission Control Space. When off they stay on the Space where they were created.")

            Toggle("Show over fullscreen apps", isOn: $settingsManager.pinShowOverFullscreen)
                .help("Render pins on top of another app's fullscreen Space.")

            Toggle("Snap to screen edges", isOn: $settingsManager.pinSnapToScreenEdges)
                .help("Stick a pin to a nearby screen edge while dragging.")

            Toggle("Drop shadow", isOn: $settingsManager.pinShadowEnabled)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Maximum simultaneous pins")
                    Spacer()
                    Stepper(value: $settingsManager.pinMaxConcurrent, in: 1...50) {
                        Text("\(settingsManager.pinMaxConcurrent)")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                    .labelsHidden()
                }
                Text("Attempting to pin past this cap shows a brief HUD instead of opening the pin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Corner radius")
                Slider(value: $settingsManager.pinCornerRadius, in: 0...20)
                Text("\(Int(settingsManager.pinCornerRadius))")
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }

    private var defaultsSection: some View {
        Section("Defaults") {
            HStack {
                Text("Default opacity")
                Slider(value: $settingsManager.pinDefaultOpacity, in: 0.3...1.0)
                Text("\(Int(settingsManager.pinDefaultOpacity * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .help("Initial opacity when a pin is first created. Each pin can then be adjusted independently.")

            sizeRow(
                label: "Text pins",
                width: $settingsManager.pinDefaultTextWidth,
                height: $settingsManager.pinDefaultTextHeight
            )
            sizeRow(
                label: "Image pins",
                width: $settingsManager.pinDefaultImageWidth,
                height: $settingsManager.pinDefaultImageHeight
            )
            sizeRow(
                label: "File pins",
                width: $settingsManager.pinDefaultFileWidth,
                height: $settingsManager.pinDefaultFileHeight
            )
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Allow editing text inside pins", isOn: $settingsManager.pinAllowTextEdit)
                .help("Turns text pins into editable fields. Edits sync back to the clipboard item.")

            Toggle("Confirm before dismissing all pins", isOn: $settingsManager.pinDismissAllConfirm)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hotkeys")
                    .font(.subheadline.weight(.semibold))
                Text("Customize the pin shortcuts in the Hotkeys tab. Defaults: ⌃⌥P pin most recent · ⌃⌥⇧P dismiss all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activePinsSection: some View {
        Section {
            let snapshots = pinManager.activePinSnapshots
            if snapshots.isEmpty {
                Text("No pins are currently open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshots) { snap in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: snap.itemType))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(snap.preview.isEmpty ? "Pinned item" : snap.preview)
                            .lineLimit(1)
                        Spacer()
                        Button("Unpin") {
                            pinManager.unpin(configId: snap.configId)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Spacer()
                    Button("Dismiss All Pins", role: .destructive) {
                        if settingsManager.pinDismissAllConfirm {
                            showDismissConfirm = true
                        } else {
                            pinManager.dismissAll()
                        }
                    }
                }
            }
        } header: {
            Text("Active Pins (\(pinManager.activePinSnapshots.count))")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sizeRow(label: String, width: Binding<Double>, height: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            Stepper(value: width, in: 120...1200, step: 20) {
                HStack(spacing: 2) {
                    Text("W")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(width.wrappedValue))")
                        .monospacedDigit()
                }
            }
            Stepper(value: height, in: 60...1000, step: 20) {
                HStack(spacing: 2) {
                    Text("H")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(height.wrappedValue))")
                        .monospacedDigit()
                }
            }
        }
    }

    private func icon(for type: CBItemType) -> String {
        switch type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .combined: return "doc.richtext"
        }
    }
}
