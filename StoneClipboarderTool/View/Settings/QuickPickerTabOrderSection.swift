//
//  QuickPickerTabOrderSection.swift
//  StoneClipboarderTool
//

import SwiftUI

/// Settings → Quick Picker → Tabs: the order of the tabs, which is also
/// the order of ⌘1…⌘6, Tab cycling and the tab the picker opens on.
struct QuickPickerTabOrderSection: View {
    @EnvironmentObject var settingsManager: SettingsManager

    private var tabs: [QPTab] {
        QPTab.ordered(settingsManager.quickPickerTabOrder)
    }

    /// Number keys follow the shown tabs, so a hidden Passwords tab
    /// takes no number.
    private func shortcut(for tab: QPTab) -> String? {
        let shown = tabs.filter { $0 != .passwords || settingsManager.showPasswordsTab }
        guard let index = shown.firstIndex(of: tab), index < 9 else { return nil }
        return "⌘\(index + 1)"
    }

    var body: some View {
        Section {
            Text("⌘1…⌘6 in the Quick Picker jump to a tab; Tab and ⇧Tab go through them in this order. The picker opens on the first one.")
                .font(.caption)
                .foregroundColor(.secondary)
                .settingsAnchor("quickPicker.tabOrder")

            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                HStack(spacing: 10) {
                    Text(shortcut(for: tab) ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(tab.title)
                    if tab == .passwords && !settingsManager.showPasswordsTab {
                        Text("hidden")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .help("Move \(tab.title) left")
                    Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless)
                        .disabled(index == tabs.count - 1)
                        .help("Move \(tab.title) right")
                }
            }

            HStack {
                Spacer()
                Button("Reset Order") { settingsManager.quickPickerTabOrder = [] }
                    .disabled(settingsManager.quickPickerTabOrder.isEmpty)
            }
        } header: {
            Text("Tabs")
        }
    }

    private func move(_ index: Int, by offset: Int) {
        var order = tabs
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        settingsManager.quickPickerTabOrder = order.map(\.rawValue)
    }
}
