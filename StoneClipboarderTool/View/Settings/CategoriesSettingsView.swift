//
//  CategoriesSettingsView.swift
//  StoneClipboarderTool
//

import SwiftUI

/// Settings → Categories: the Quick Picker's chip bar, the source app, the
/// built-in categories, custom regex rules and app groups.
struct CategoriesSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var cbViewModel: CBViewModel

    /// The category in the editor sheet and whether it is new.
    private struct Editing: Identifiable {
        let category: ItemCategory
        let isNew: Bool
        var id: String { category.id }
    }

    @State private var editing: Editing?
    @State private var pendingDelete: ItemCategory?
    @State private var confirmingForgetApps = false
    @State private var confirmingReset = false

    private func categories(_ kind: ItemCategory.Kind) -> [ItemCategory] {
        settingsManager.itemCategories.filter { $0.kind == kind }
    }

    var body: some View {
        Form {
            Section("Quick Picker") {
                Toggle("Show the category bar", isOn: $settingsManager.showCategoryBar)
                Text("Chips under the tabs filter the list; ⌥← and ⌥→ switch between them. In the search field, is:link, app:Safari and lang:uk filter too, and combine with text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Source app") {
                Toggle("Remember the source app", isOn: $settingsManager.recordSourceApp)
                Text("Saves which app was in front when you copied, for app groups and app: search. Stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Forget Recorded Apps…") { confirmingForgetApps = true }
            }

            Section {
                ForEach(categories(.builtIn)) { category in
                    row(for: category, deletable: false)
                }
            } header: {
                HStack {
                    Text("Built-in")
                    Spacer()
                    Button("Reset…") { confirmingReset = true }
                        .controlSize(.small)
                }
            }

            Section {
                ForEach(categories(.regex)) { category in
                    row(for: category, deletable: true)
                }
                Button("Add Rule…") {
                    editing = Editing(category: .newRegex(), isNew: true)
                }
            } header: {
                Text("Custom rules")
            } footer: {
                Text("A regular expression, e.g. №\\s*\\d+/\\d{4} for document numbers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App groups") {
                ForEach(categories(.apps)) { category in
                    row(for: category, deletable: true)
                }
                Button("Add App Group…") {
                    editing = Editing(category: .newAppGroup(), isNew: true)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { editing in
            CategoryEditorView(category: editing.category, isNew: editing.isNew) { saved in
                settingsManager.saveCategory(saved)
            }
        }
        .alert("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { settingsManager.deleteCategory(id: pendingDelete.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Items stay in the history; only this chip goes away.")
        }
        .alert("Forget recorded apps?", isPresented: $confirmingForgetApps) {
            Button("Forget", role: .destructive) { cbViewModel.clearSourceApps() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the source app from every item in the history. App groups and app: search will only find items copied from now on.")
        }
        .alert("Reset built-in categories?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { settingsManager.resetBuiltInCategories() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turns every built-in category back on with its original icon, color and match mode. Custom rules and app groups stay.")
        }
    }

    private func row(for category: ItemCategory, deletable: Bool) -> some View {
        CategorySettingsRow(
            category: category,
            onToggle: { isOn in
                var updated = category
                updated.isEnabled = isOn
                settingsManager.saveCategory(updated)
            },
            onEdit: { editing = Editing(category: category, isNew: false) },
            onDelete: deletable ? { pendingDelete = category } : nil
        )
    }
}
