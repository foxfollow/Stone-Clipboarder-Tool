//
//  ItemCategory.swift
//  StoneClipboarderTool
//

import AppKit
import SwiftUI

/// How a category draws itself: an SF Symbol name or a single emoji.
enum CategoryIcon: Codable, Hashable {
    case symbol(String)
    case emoji(String)
}

/// A group in the Quick Picker's category bar: something found in the text
/// (built in, or a user regex) or a set of source apps.
///
/// Stored as a JSON array in UserDefaults (`SettingsManager.itemCategories`).
/// `id` doubles as the key written into `CBItem.categoryKeys`, so built-in
/// ids and raw values here must never be renamed.
struct ItemCategory: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case builtIn
        case regex
        case apps
    }

    /// Whether a match anywhere counts, or only one covering the whole text.
    enum MatchMode: String, Codable, CaseIterable, Identifiable {
        case contains
        case entireText

        var id: Self { self }

        var displayName: String {
            switch self {
            case .contains: return "Contains"
            case .entireText: return "Entire text"
            }
        }
    }

    /// Stable ids of the built-in categories.
    enum BuiltIn: String, CaseIterable {
        case link, email, phone, address, date, code, json, path, language
        // Found in images by `ImageClassifier`.
        case ocr, barcode, face, transparent

        /// Settings lists these under "Images".
        var isImageCategory: Bool {
            switch self {
            case .ocr, .barcode, .face, .transparent: return true
            default: return false
            }
        }
    }

    var id: String
    var name: String
    var kind: Kind
    var isEnabled: Bool = true
    var matchMode: MatchMode = .contains
    /// Regex categories only.
    var pattern: String = ""
    var caseSensitive: Bool = false
    /// App-group categories only; `appNames` runs parallel to `appBundleIDs`.
    var appBundleIDs: [String] = []
    var appNames: [String] = []
    var icon: CategoryIcon
    var colorHex: String

    var builtIn: BuiltIn? {
        kind == .builtIn ? BuiltIn(rawValue: id) : nil
    }

    /// Built-ins found by a detector or path rule, and regex rules, can
    /// require the match to cover the whole text.
    var supportsMatchMode: Bool {
        switch kind {
        case .regex: return true
        case .apps: return false
        case .builtIn:
            switch builtIn {
            case .link, .email, .phone, .address, .date, .path: return true
            default: return false
            }
        }
    }

    /// The key in `CBItem.categoryKeys` this category looks for.
    var storedKey: String {
        supportsMatchMode && matchMode == .entireText ? ContentClassifier.fullKey(id) : id
    }

    /// Whether `item` belongs to this category, ignoring `isEnabled`.
    func matches(_ item: CBItem) -> Bool {
        switch kind {
        case .apps:
            guard let bundleID = item.sourceAppBundleID else { return false }
            return appBundleIDs.contains(bundleID)
        case .builtIn where builtIn == .language:
            return item.languageCode != nil
        case .builtIn, .regex:
            return item.hasCategoryKey(storedKey)
        }
    }

    /// Items counted for this category in `facets`.
    func count(in facets: FacetCounts) -> Int {
        switch kind {
        case .apps:
            return appBundleIDs.reduce(0) { $0 + (facets.apps[$1] ?? 0) }
        case .builtIn where builtIn == .language:
            return facets.languages.values.reduce(0, +)
        case .builtIn, .regex:
            return facets.keys[storedKey] ?? 0
        }
    }

    /// The rule handed to the classifier; nil unless this is a regex with a
    /// valid pattern. Disabled rules still classify, so turning one on needs
    /// no rescan.
    var regexRule: ContentClassifier.RegexRule? {
        guard kind == .regex, Self.isValidPattern(pattern) else { return nil }
        return ContentClassifier.RegexRule(id: id, pattern: pattern, caseSensitive: caseSensitive)
    }

    // MARK: - Color

    var color: Color { Color(nsColor: Self.nsColor(hex: colorHex) ?? .systemGray) }

    /// "#RRGGBB" (sRGB). Alpha is dropped.
    static func hex(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .systemGray
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func nsColor(hex: String) -> NSColor? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }

    // MARK: - Validation

    static func isValidPattern(_ pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        return (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// Exactly one character that shows as an emoji ("1" or "#" don't).
    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, let first = text.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && text.unicodeScalars.count > 1)
    }

    // MARK: - Defaults

    static let builtIns: [ItemCategory] = [
        builtIn(.link, "Link", .symbol("link"), "#0A84FF"),
        builtIn(.email, "Email", .symbol("envelope"), "#5E5CE6"),
        builtIn(.phone, "Phone", .symbol("phone"), "#30D158"),
        builtIn(.address, "Address", .symbol("mappin.and.ellipse"), "#FF453A"),
        builtIn(.date, "Date", .symbol("calendar"), "#FF9F0A"),
        builtIn(.code, "Code", .symbol("chevron.left.forwardslash.chevron.right"), "#BF5AF2"),
        builtIn(.json, "JSON", .symbol("curlybraces"), "#64D2FF"),
        builtIn(.path, "Path", .symbol("folder"), "#AC8E68"),
        builtIn(.language, "Languages", .symbol("globe"), "#8E8E93"),
        builtIn(.ocr, "Text in Image", .symbol("text.viewfinder"), "#30B0C7"),
        builtIn(.barcode, "QR & Barcode", .symbol("qrcode"), "#FF375F"),
        builtIn(.face, "People", .symbol("person.crop.square"), "#FF9F0A"),
        builtIn(.transparent, "Transparent", .symbol("checkerboard.rectangle"), "#A2845E"),
    ]

    private static func builtIn(_ id: BuiltIn, _ name: String, _ icon: CategoryIcon, _ hex: String) -> ItemCategory {
        ItemCategory(id: id.rawValue, name: name, kind: .builtIn, icon: icon, colorHex: hex)
    }

    static func newRegex() -> ItemCategory {
        ItemCategory(
            id: UUID().uuidString, name: "", kind: .regex,
            icon: .symbol("number"), colorHex: "#FFD60A")
    }

    static func newAppGroup() -> ItemCategory {
        ItemCategory(
            id: UUID().uuidString, name: "", kind: .apps,
            icon: .symbol("app.badge"), colorHex: "#32ADE6")
    }

    /// The stored list, deduplicated, with built-ins it lacks appended (a
    /// newer version may add some) and built-in names taken from the code.
    static func merged(stored: [ItemCategory]) -> [ItemCategory] {
        var seen = Set<String>()
        var result: [ItemCategory] = []
        for var category in stored where seen.insert(category.id).inserted {
            if category.kind == .builtIn {
                guard let fresh = builtIns.first(where: { $0.id == category.id }) else { continue }
                category.name = fresh.name
            }
            result.append(category)
        }
        for fresh in builtIns where !seen.contains(fresh.id) {
            result.append(fresh)
        }
        return result
    }

    /// English name of a BCP-47 language code ("uk" → "Ukrainian").
    static func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, isEnabled, matchMode, pattern, caseSensitive
        case appBundleIDs, appNames, icon, colorHex
    }

    init(
        id: String, name: String, kind: Kind, isEnabled: Bool = true,
        matchMode: MatchMode = .contains, pattern: String = "", caseSensitive: Bool = false,
        appBundleIDs: [String] = [], appNames: [String] = [],
        icon: CategoryIcon, colorHex: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isEnabled = isEnabled
        self.matchMode = matchMode
        self.pattern = pattern
        self.caseSensitive = caseSensitive
        self.appBundleIDs = appBundleIDs
        self.appNames = appNames
        self.icon = icon
        self.colorHex = colorHex
    }

    /// Fields missing from older JSON fall back to their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decode(Kind.self, forKey: .kind)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        // A value from a newer version falls back instead of failing the category.
        matchMode = ((try? c.decodeIfPresent(MatchMode.self, forKey: .matchMode)) ?? nil) ?? .contains
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        appBundleIDs = try c.decodeIfPresent([String].self, forKey: .appBundleIDs) ?? []
        appNames = try c.decodeIfPresent([String].self, forKey: .appNames) ?? []
        icon = ((try? c.decodeIfPresent(CategoryIcon.self, forKey: .icon)) ?? nil) ?? .symbol("tag")
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#8E8E93"
    }
}
