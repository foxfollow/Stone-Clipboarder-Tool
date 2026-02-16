//
//  PauseTimerView.swift
//  StoneClipboarderTool
//
//  Created by Claude Code
//

import SwiftUI

struct PauseTimerView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var inputValue: String = "5"
    @State private var selectedUnit: TimeUnit = .minutes
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if clipboardManager.isPaused {
                    // Active pause display
                    ActivePauseView(clipboardManager: clipboardManager)
                } else {
                    // Pause setup controls
                    PauseSetupView(
                        clipboardManager: clipboardManager,
                        settingsManager: settingsManager,
                        inputValue: $inputValue,
                        selectedUnit: $selectedUnit
                    )
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: clipboardManager.isPaused ? "pause.circle.fill" : "pause.circle")
                    .foregroundStyle(clipboardManager.isPaused ? .orange : .secondary)

                Text(clipboardManager.isPaused ? "Monitoring Paused" : "Pause Monitoring")
                    .font(.subheadline)
                    .fontWeight(clipboardManager.isPaused ? .semibold : .regular)

                if clipboardManager.isPaused {
                    Spacer()
                    Text(remainingTimeCompact)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            loadLastDuration()
        }
        // Auto-expand when paused
        .onChange(of: clipboardManager.isPaused) { _, newValue in
            if newValue {
                isExpanded = true
            }
        }
    }

    private var remainingTimeCompact: String {
        let remaining = clipboardManager.remainingPauseTime

        if remaining <= 0 {
            return "..."
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    private func loadLastDuration() {
        let lastSeconds = settingsManager.lastPauseDuration

        // Convert to appropriate unit
        if lastSeconds >= 86400 && lastSeconds % 86400 == 0 {
            selectedUnit = .days
            inputValue = "\(lastSeconds / 86400)"
        } else if lastSeconds >= 3600 && lastSeconds % 3600 == 0 {
            selectedUnit = .hours
            inputValue = "\(lastSeconds / 3600)"
        } else if lastSeconds >= 60 && lastSeconds % 60 == 0 {
            selectedUnit = .minutes
            inputValue = "\(lastSeconds / 60)"
        } else {
            selectedUnit = .seconds
            inputValue = "\(lastSeconds)"
        }
    }
}

// MARK: - Active Pause View
struct ActivePauseView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @State private var currentTime = Date()

    // Timer to force UI updates every second
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                Text("Time Remaining")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text(remainingTimeText)
                .font(.system(.title, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.orange)

            Button {
                clipboardManager.resumeMonitoring()
            } label: {
                Label("Resume Now", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
        }
        .onReceive(timer) { time in
            // Force update by changing state
            currentTime = time
        }
    }

    private var remainingTimeText: String {
        // Force recomputation by using currentTime
        _ = currentTime

        let remaining = clipboardManager.remainingPauseTime

        if remaining <= 0 {
            return "Resuming..."
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Pause Setup View
struct PauseSetupView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var settingsManager: SettingsManager

    @Binding var inputValue: String
    @Binding var selectedUnit: TimeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pause Duration")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Duration", text: $inputValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        validateInput()
                    }

                Picker("Unit", selection: $selectedUnit) {
                    ForEach(TimeUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }

            // Quick preset buttons
            HStack(spacing: 6) {
                quickPresetButton(value: 5, unit: .minutes, label: "5m")
                quickPresetButton(value: 15, unit: .minutes, label: "15m")
                quickPresetButton(value: 30, unit: .minutes, label: "30m")
                quickPresetButton(value: 1, unit: .hours, label: "1h")
            }

            Button {
                startPause()
            } label: {
                Label("Start Pause", systemImage: "pause.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
            .disabled(!isValidInput)
        }
    }

    private var isValidInput: Bool {
        guard let value = Int(inputValue), value > 0 else {
            return false
        }
        return true
    }

    private func quickPresetButton(value: Int, unit: TimeUnit, label: String) -> some View {
        Button(label) {
            inputValue = "\(value)"
            selectedUnit = unit
            startPause()
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    private func startPause() {
        validateInput()

        guard let value = Int(inputValue), value > 0 else {
            return
        }

        let seconds = value * selectedUnit.multiplier

        // Save this duration for next time
        settingsManager.lastPauseDuration = seconds

        clipboardManager.pauseMonitoring(for: seconds)
    }

    private func validateInput() {
        // Ensure input is a valid positive integer
        if let value = Int(inputValue), value > 0 {
            inputValue = "\(value)"
        } else {
            inputValue = "1"
        }
    }
}
