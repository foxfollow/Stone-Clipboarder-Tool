//
//  QuickPickerSettingsView.swift
//  StoneClipboarderTool
//

import SwiftUI

struct QuickPickerSettingsView: View {
    var body: some View {
        Form {
            QuickLookSection()
            TypeOutPasteSection()
        }
        .formStyle(.grouped)
    }
}

private struct QuickLookSection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Section("Quick Look") {
            Picker("Preview mode:", selection: $settingsManager.quickLookMode) {
                ForEach(QuickLookMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .help("Choose preview style when pressing the trigger key in QuickPicker")

            Picker("Trigger key:", selection: $settingsManager.quickLookTriggerKey) {
                ForEach(QuickLookTriggerKey.allCases, id: \.self) { key in
                    Text(key.displayName).tag(key)
                }
            }
            .pickerStyle(.menu)
            .disabled(settingsManager.quickLookMode == .disabled)
            .opacity(settingsManager.quickLookMode == .disabled ? 0.5 : 1)
            .help("Key to open preview in QuickPicker")

            Toggle("⌥ Enter to extract text (Apple Vision)", isOn: $settingsManager.enableOCROptionKey)
                .help("When enabled, pressing Option+Enter on an image in QuickPicker will extract and paste text using Apple Vision OCR instead of the image")
        }
    }
}

private struct TypeOutPasteSection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Section("Type-Out Paste") {
            Text("Press ⌘⇧Return in the Quick Picker to type the selected text out character by character (instead of pasting), so it lands in fields that block ⌘V.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Delay per character")
                    Spacer()
                    Text("\(max(1, settingsManager.typePasteCharDelayMs)) ms")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                // Minimum 1 ms: at 0 the OS coalesces/drops the burst of
                // synthetic keystrokes and nothing gets typed.
                Slider(
                    value: Binding(
                        get: { Double(max(1, settingsManager.typePasteCharDelayMs)) },
                        set: { settingsManager.typePasteCharDelayMs = Int($0) }
                    ),
                    in: 1...500,
                    step: 1
                ) {
                    Text("Delay per character")
                } minimumValueLabel: {
                    Text("Fast")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text("Slow")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(speedDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .help("How long to wait between each typed character. Raise this if a slow text field drops characters.")
        }
    }

    private var speedDescription: String {
        let ms = max(1, settingsManager.typePasteCharDelayMs)
        let perSecond = max(1, Int((1000.0 / Double(ms)).rounded()))
        return "≈ \(perSecond) character\(perSecond == 1 ? "" : "s") per second."
    }
}
