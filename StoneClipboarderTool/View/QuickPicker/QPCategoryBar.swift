//
//  QPCategoryBar.swift
//  StoneClipboarderTool
//

import SwiftUI

/// A chip in the category bar, built from the settings and the counts of
/// the active tab.
struct QPCategoryChip: Identifiable, Equatable {
    let selection: CategorySelection
    let name: String
    let icon: CategoryIcon
    let color: Color
    let count: Int

    var id: CategorySelection { selection }

    /// Enabled categories with items in `facets`, in bar order: built-ins,
    /// then one chip per language, then regex rules, then app groups.
    static func chips(for categories: [ItemCategory], facets: FacetCounts) -> [QPCategoryChip] {
        let enabled = categories.filter(\.isEnabled)
        var chips: [QPCategoryChip] = []

        for category in enabled where category.kind == .builtIn {
            if category.builtIn == .language {
                let languages = facets.languages.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                for (code, count) in languages where count > 0 {
                    chips.append(QPCategoryChip(
                        selection: .language(code), name: ItemCategory.languageName(code),
                        icon: category.icon, color: category.color, count: count))
                }
            } else {
                chips.append(chip(for: category, facets: facets))
            }
        }
        for category in enabled where category.kind == .regex {
            chips.append(chip(for: category, facets: facets))
        }
        for category in enabled where category.kind == .apps {
            chips.append(chip(for: category, facets: facets))
        }
        return chips.filter { $0.count > 0 }
    }

    private static func chip(for category: ItemCategory, facets: FacetCounts) -> QPCategoryChip {
        QPCategoryChip(
            selection: .category(category.id), name: category.name, icon: category.icon,
            color: category.color, count: category.count(in: facets))
    }
}

/// The chips under the Quick Picker's tabs. Clicking the active chip
/// clears it; ⌥← / ⌥→ (handled by the picker) step through them.
struct QPCategoryBar: View {
    let chips: [QPCategoryChip]
    let selection: CategorySelection?
    let onSelect: (CategorySelection?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips) { chip in
                            Button {
                                onSelect(selection == chip.selection ? nil : chip.selection)
                            } label: {
                                CategoryChipView(chip: chip, isActive: selection == chip.selection)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .id(chip.id)
                            .help(selection == chip.selection ? "Show all" : "Show only \(chip.name)")
                        }
                    }
                    .padding(.vertical, 1)
                }
                .onChange(of: selection) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            hint
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var hint: some View {
        HStack(spacing: 4) {
            Text("⌥←→")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .foregroundStyle(.tertiary)
        .help("Option+Left / Option+Right to switch categories; is:, app: and lang: in the search field filter too")
    }
}
