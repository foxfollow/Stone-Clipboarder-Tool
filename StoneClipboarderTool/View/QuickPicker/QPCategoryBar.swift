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

    /// Enabled categories with items in `facets`, in bar order: image
    /// categories first (only on the Images tab, `forImages`), then the
    /// other built-ins, one chip per language, regex rules and app groups.
    static func chips(for categories: [ItemCategory], facets: FacetCounts, forImages: Bool = false) -> [QPCategoryChip] {
        let enabled = categories.filter(\.isEnabled)
        var chips: [QPCategoryChip] = []

        if forImages {
            for category in enabled where category.builtIn?.isImageCategory == true {
                chips.append(chip(for: category, facets: facets))
            }
        }
        for category in enabled where category.kind == .builtIn && category.builtIn?.isImageCategory != true {
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

/// The chips under the Quick Picker's tabs. A click picks one chip,
/// ⇧-click adds or removes one; ⌥← / ⌥→ and ⌥⇧← / ⌥⇧→ (handled by the
/// picker) do the same from the keyboard.
struct QPCategoryBar: View {
    let chips: [QPCategoryChip]
    let selection: ChipSelection
    /// The clicked chip and whether ⇧ was held.
    let onClick: (CategorySelection, Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips) { chip in
                            Button {
                                onClick(chip.selection, NSEvent.modifierFlags.contains(.shift))
                            } label: {
                                CategoryChipView(chip: chip, isActive: selection.selected.contains(chip.selection))
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .id(chip.id)
                            .help("Show only \(chip.name); ⇧-click to add it to the others")
                        }
                    }
                    .padding(.vertical, 1)
                }
                .onChange(of: selection.cursor) { _, newValue in
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
        .help("⌥← / ⌥→ switch categories, ⌥⇧← / ⌥⇧→ select several in a row, ⇧-click adds one. is:, app: and lang: in the search field filter too.")
    }
}
