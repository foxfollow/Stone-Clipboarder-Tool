//
//  CategoryEditorView.swift
//  StoneClipboarderTool
//

import AppKit
import SwiftUI

/// Sheet for one category: name, icon, color, and the rule (match mode,
/// regex with a live test, or the apps of a group). Saves on "Save" only.
struct CategoryEditorView: View {
    let isNew: Bool
    let onSave: (ItemCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ItemCategory
    @State private var testText = ""
    @State private var showingAppPicker = false

    init(category: ItemCategory, isNew: Bool, onSave: @escaping (ItemCategory) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: category)
    }

    private var title: String {
        switch draft.kind {
        case .builtIn: return "Edit \(draft.name)"
        case .regex: return isNew ? "New Rule" : "Edit Rule"
        case .apps: return isNew ? "New App Group" : "Edit App Group"
        }
    }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var patternIsValid: Bool { ItemCategory.isValidPattern(draft.pattern) }

    private var canSave: Bool {
        switch draft.kind {
        case .builtIn: return true
        case .regex: return !trimmedName.isEmpty && patternIsValid
        case .apps: return !trimmedName.isEmpty && !draft.appBundleIDs.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CategoryIconView(icon: draft.icon, color: draft.color, size: 16)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding()

            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .disabled(draft.kind == .builtIn)
                    ColorPicker(
                        "Color",
                        selection: Binding(
                            get: { draft.color },
                            set: { draft.colorHex = ItemCategory.hex(from: $0) }
                        ),
                        supportsOpacity: false)
                    CategoryIconPicker(icon: $draft.icon, color: draft.color)
                }

                if draft.supportsMatchMode {
                    Section("Match") {
                        Picker("Match", selection: $draft.matchMode) {
                            ForEach(ItemCategory.MatchMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(draft.matchMode == .contains
                             ? "The item belongs here when this is found anywhere in its text."
                             : "The item belongs here only when its whole text is this (spaces around it are ignored).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if draft.kind == .regex {
                    regexSection
                }

                if draft.kind == .apps {
                    appsSection
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var result = draft
                    result.name = draft.kind == .builtIn ? draft.name : trimmedName
                    onSave(result)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 480, height: draft.kind == .builtIn ? 520 : 640)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(
                labels: .appGroup,
                selectedBundleIDs: Set(draft.appBundleIDs),
                onAdd: { bundleID, name in
                    guard !draft.appBundleIDs.contains(bundleID) else { return }
                    draft.appBundleIDs.append(bundleID)
                    draft.appNames.append(name)
                },
                onRemove: removeApp
            )
        }
    }

    private var regexSection: some View {
        Section("Regular expression") {
            TextField("Pattern, e.g. №\\s*\\d+/\\d{4}", text: $draft.pattern)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
            if !draft.pattern.isEmpty && !patternIsValid {
                Label("This pattern is not a valid regular expression.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Case sensitive", isOn: $draft.caseSensitive)
            TextField("Test text", text: $testText, axis: .vertical)
                .lineLimit(2...5)
            if !testText.isEmpty && patternIsValid {
                let matches = testMatches
                Label(matches ? "Matches" : "No match",
                      systemImage: matches ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(matches ? .green : .secondary)
            }
            Text("Only the first \(ContentClassifier.maxLength) characters of an item are checked. Existing items are checked again after you save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The test text through the same classifier the history uses.
    private var testMatches: Bool {
        guard let rule = draft.regexRule else { return false }
        let result = ContentClassifier.classify(testText, ruleset: .init(rules: [rule]))
        return result.keys.contains(draft.storedKey)
    }

    private var appsSection: some View {
        Section("Apps") {
            if draft.appBundleIDs.isEmpty {
                Text("No apps yet")
                    .foregroundStyle(.secondary)
                    .italic()
            }
            ForEach(Array(draft.appBundleIDs.enumerated()), id: \.element) { index, bundleID in
                HStack {
                    if let icon = AppIconCache.icon(for: bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(draft.appNames[safe: index] ?? bundleID)
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        removeApp(bundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from the group")
                }
            }
            Button("Add Apps…") { showingAppPicker = true }
            Text("Items copied while one of these apps was in front show up under this chip. Only items copied with \"Remember the source app\" on have an app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func removeApp(_ bundleID: String) {
        guard let index = draft.appBundleIDs.firstIndex(of: bundleID) else { return }
        draft.appBundleIDs.remove(at: index)
        if draft.appNames.indices.contains(index) {
            draft.appNames.remove(at: index)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
