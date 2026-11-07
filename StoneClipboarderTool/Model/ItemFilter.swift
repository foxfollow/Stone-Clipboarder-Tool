//
//  ItemFilter.swift
//  StoneClipboarderTool
//

import Foundation

/// A search box's text split into filter tokens and free text:
/// `is:link app:Safari lang:uk invoice` → is ["link"], app ["safari"],
/// lang ["uk"], text "invoice". A value with spaces goes in quotes:
/// `app:"Visual Studio Code"`. Tokens are lowercased; free text keeps its
/// case.
struct QPSearchQuery: Equatable {
    var text = ""
    var isTokens: [String] = []
    var appTokens: [String] = []
    var langTokens: [String] = []

    var hasTokens: Bool { !isTokens.isEmpty || !appTokens.isEmpty || !langTokens.isEmpty }
    var isEmpty: Bool { text.isEmpty && !hasTokens }

    static func parse(_ raw: String) -> QPSearchQuery {
        var query = QPSearchQuery()
        var words: [String] = []
        var scanner = Substring(raw)

        while let start = scanner.firstIndex(where: { !$0.isWhitespace }) {
            scanner = scanner[start...]
            let word: Substring
            let head = scanner.prefix(5).lowercased()
            if let prefix = ["is:", "app:", "lang:"].first(where: { head.hasPrefix($0) }),
               scanner.dropFirst(prefix.count).first == "\"" {
                // prefix:"quoted value"
                let valueStart = scanner.index(scanner.startIndex, offsetBy: prefix.count + 1)
                let close = scanner[valueStart...].firstIndex(of: "\"") ?? scanner.endIndex
                word = scanner[scanner.startIndex..<close]
                scanner = close < scanner.endIndex ? scanner[scanner.index(after: close)...] : ""
            } else {
                let end = scanner.firstIndex(where: \.isWhitespace) ?? scanner.endIndex
                word = scanner[scanner.startIndex..<end]
                scanner = scanner[end...]
            }

            let lower = word.lowercased()
            func value(after prefix: String) -> String {
                String(lower.dropFirst(prefix.count)).replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if lower.hasPrefix("is:"), !value(after: "is:").isEmpty {
                query.isTokens.append(value(after: "is:"))
            } else if lower.hasPrefix("app:"), !value(after: "app:").isEmpty {
                query.appTokens.append(value(after: "app:"))
            } else if lower.hasPrefix("lang:"), !value(after: "lang:").isEmpty {
                query.langTokens.append(value(after: "lang:"))
            } else {
                words.append(String(word))
            }
        }
        // Without tokens the text stays as typed (inner spacing and line
        // breaks included), like a plain search.
        query.text = query.hasTokens
            ? words.joined(separator: " ")
            : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return query
    }
}

/// A chip picked in the Quick Picker's category bar.
enum CategorySelection: Hashable {
    /// A built-in, regex or app-group category, by id.
    case category(String)
    /// One detected language, by BCP-47 code.
    case language(String)
}

/// The chips that are on, plus a keyboard cursor and a range anchor, like
/// the list's ⇧↑↓ selection. ⌥←/→ move to one chip (passing through "none"),
/// ⌥⇧←/→ extend a run of neighbors, a click picks one, ⇧-click adds or
/// removes one.
struct ChipSelection: Equatable {
    var selected: Set<CategorySelection> = []
    var cursor: CategorySelection?
    var anchor: CategorySelection?

    var isEmpty: Bool { selected.isEmpty }

    /// ⌥← / ⌥→: one chip, or none, wrapping around.
    mutating func step(_ step: Int, in chips: [CategorySelection]) {
        guard !chips.isEmpty else { return }
        let options: [CategorySelection?] = [nil] + chips
        let current = selected.isEmpty ? 0 : (options.firstIndex(of: cursor) ?? 0)
        let next = options[(current + step + options.count) % options.count]
        cursor = next
        anchor = nil
        selected = next.map { [$0] } ?? []
    }

    /// ⌥⇧← / ⌥⇧→: from the anchor to the moved cursor, no wrapping.
    mutating func extend(_ step: Int, in chips: [CategorySelection]) {
        guard !chips.isEmpty else { return }
        let cursorIndex = selected.isEmpty ? nil : cursor.flatMap { chips.firstIndex(of: $0) }
        let next: Int
        if let cursorIndex {
            next = min(max(cursorIndex + step, 0), chips.count - 1)
        } else {
            next = step > 0 ? 0 : chips.count - 1
        }
        if anchor.flatMap({ chips.firstIndex(of: $0) }) == nil {
            anchor = chips[cursorIndex ?? next]
        }
        let anchorIndex = anchor.flatMap { chips.firstIndex(of: $0) } ?? next
        cursor = chips[next]
        selected = Set(chips[min(anchorIndex, next)...max(anchorIndex, next)])
    }

    /// A click picks only this chip (or clears it when it was the only
    /// one); with ⇧ it toggles the chip and keeps the others.
    mutating func click(_ chip: CategorySelection, adding: Bool) {
        if adding {
            if selected.contains(chip) { selected.remove(chip) } else { selected.insert(chip) }
            anchor = chip
        } else {
            selected = selected == [chip] ? [] : [chip]
            anchor = nil
        }
        cursor = chip
    }

    /// Drops chips the current tab doesn't show.
    mutating func keep(only chips: [CategorySelection]) {
        let available = Set(chips)
        selected.formIntersection(available)
        if let cursor, !available.contains(cursor) { self.cursor = nil }
        if let anchor, !available.contains(anchor) { self.anchor = nil }
    }
}

/// Everything the Quick Picker filters on besides the item type: the chip
/// and the search query. Matches only inline columns, except the free
/// text, which reads the content (`CBItem.matchesSearch`).
struct ItemFilter {
    var categories: [ItemCategory] = []
    /// Chips that are on; an item in any of them passes.
    var selections: Set<CategorySelection> = []
    var query = QPSearchQuery()
    /// Free text also matches the text recognized in images.
    var searchImageText = true

    var isEmpty: Bool { selections.isEmpty && query.isEmpty }
    /// True when only inline columns are checked (no content reads).
    var isCheap: Bool { query.text.isEmpty }

    func matches(_ item: CBItem) -> Bool {
        if !selections.isEmpty, !selections.contains(where: { matches(item, selection: $0) }) { return false }
        for token in query.isTokens where !matches(item, isToken: token) { return false }
        for token in query.appTokens where !Self.matches(item, app: token) { return false }
        for token in query.langTokens where !Self.matches(item, language: token) { return false }
        if !query.text.isEmpty && !item.matchesSearch(query.text, includingImageText: searchImageText) {
            return false
        }
        return true
    }

    private func matches(_ item: CBItem, selection: CategorySelection) -> Bool {
        switch selection {
        case .category(let id):
            return categories.first { $0.id == id }?.matches(item) ?? false
        case .language(let code):
            return item.languageCode == code
        }
    }

    /// `is:` takes a category id or the start of its name ("is:link",
    /// "is:lang", "is:doc" for a "Documents" rule), plus "fav"/"favorite"
    /// and "titled". Disabled categories don't match.
    private func matches(_ item: CBItem, isToken token: String) -> Bool {
        if token == "fav" || token == "favorite" || token == "favorites" { return item.isFavorite }
        if token == "titled" || token == "title" { return item.displayTitle != nil }
        let candidates = categories.filter { $0.isEnabled && Self.category($0, answers: token) }
        return candidates.contains { $0.matches(item) }
    }

    static func category(_ category: ItemCategory, answers token: String) -> Bool {
        if category.id.lowercased() == token { return true }
        let name = category.name.lowercased()
        return !name.isEmpty
            && (name.hasPrefix(token) || name.replacingOccurrences(of: " ", with: "").hasPrefix(token))
    }

    static func matches(_ item: CBItem, app token: String) -> Bool {
        if item.sourceAppName?.lowercased().contains(token) == true { return true }
        return item.sourceAppBundleID?.lowercased().contains(token) == true
    }

    static func matches(_ item: CBItem, language token: String) -> Bool {
        guard let code = item.languageCode?.lowercased() else { return false }
        if code == token { return true }
        return token.count >= 2 && ItemCategory.languageName(code).lowercased().hasPrefix(token)
    }
}

/// Per-key counts over a set of items, for the category chips: stored
/// classifier keys, languages and source apps. Settings-independent, so the
/// view model can cache it until the history changes.
struct FacetCounts: Equatable {
    var keys: [String: Int] = [:]
    var languages: [String: Int] = [:]
    var apps: [String: Int] = [:]

    init() {}

    init<S: Sequence>(items: S) where S.Element == CBItem {
        for item in items { add(item) }
    }

    mutating func add(_ item: CBItem) {
        for key in item.categoryKeySet { keys[key, default: 0] += 1 }
        if let language = item.languageCode { languages[language, default: 0] += 1 }
        if let app = item.sourceAppBundleID { apps[app, default: 0] += 1 }
    }

    static func + (lhs: FacetCounts, rhs: FacetCounts) -> FacetCounts {
        var sum = lhs
        sum.keys.merge(rhs.keys, uniquingKeysWith: +)
        sum.languages.merge(rhs.languages, uniquingKeysWith: +)
        sum.apps.merge(rhs.apps, uniquingKeysWith: +)
        return sum
    }
}
