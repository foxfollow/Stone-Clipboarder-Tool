//
//  SettingsSearchIndex.swift
//  StoneClipboarderTool
//
//  Every setting the Settings search can find, and the search itself.
//

import Foundation

/// One searchable setting: where it lives and the view anchor to scroll to.
struct SettingsSearchEntry: Identifiable, Hashable {
    /// Unique per entry.
    let id: String
    let title: String
    let section: SettingsSection
    /// The Form section heading it sits under.
    let group: String
    /// The `.settingsAnchor` id of its row; entries may share one.
    let anchor: String
    /// Extra words people may type: synonyms, the help text, shortcuts.
    var keywords: [String] = []
    /// Shown under the title in results, e.g. "When Auto-cleanup is on".
    var note: String?
    /// A row it depends on (shown only when that is on): scrolled to and
    /// highlighted as well, so the search lands somewhere visible.
    var parentAnchor: String?
}

/// Ids shared by `SettingsSearchIndex` and the `.settingsAnchor` modifiers.
enum SettingsAnchor {
    static func hotkey(_ action: HotkeyAction) -> String { "hotkey.\(action.rawValue)" }
    static func category(_ id: String) -> String { "category.\(id)" }
}

enum SettingsSearchIndex {
    // MARK: - Catalog

    /// The fixed settings, in the order the pages show them.
    static let staticEntries: [SettingsSearchEntry] = general + hotkeys + quickPicker + categories + pins
        + excludedApps + accessibility + about

    /// Everything searchable: the fixed settings, every hotkey action and
    /// the given categories (built-in, custom rules, app groups).
    static func entries(categories: [ItemCategory] = ItemCategory.builtIns) -> [SettingsSearchEntry] {
        var result = staticEntries
        let hotkeyRows = HotkeyAction.allCases.map { action in
            SettingsSearchEntry(
                id: SettingsAnchor.hotkey(action), title: action.displayName, section: .hotkeys,
                group: hotkeyGroup(for: action), anchor: SettingsAnchor.hotkey(action),
                keywords: ["shortcut", "hotkey", action.defaultShortcut])
        }
        let hotkeysEnd = result.lastIndex { $0.section == .hotkeys }.map { $0 + 1 } ?? result.endIndex
        result.insert(contentsOf: hotkeyRows, at: hotkeysEnd)

        let categoryRows = categories.map { category in
            SettingsSearchEntry(
                id: SettingsAnchor.category(category.id), title: category.name.isEmpty ? "Untitled" : category.name,
                section: .categories, group: categoryGroup(for: category),
                anchor: SettingsAnchor.category(category.id),
                keywords: ["category", "chip", category.pattern] + category.appNames)
        }
        let categoriesEnd = result.lastIndex { $0.section == .categories }.map { $0 + 1 } ?? result.endIndex
        result.insert(contentsOf: categoryRows, at: categoriesEnd)
        return result
    }

    private static func hotkeyGroup(for action: HotkeyAction) -> String {
        if action.isLastAction { return "Last Items Hotkeys" }
        if action.isFavoriteAction { return "Favorite Items Hotkeys" }
        return action == .mainPanel ? "Quick Picker" : "Pins"
    }

    private static func categoryGroup(for category: ItemCategory) -> String {
        switch category.kind {
        case .builtIn: return category.builtIn?.isImageCategory == true ? "Built-in: images" : "Built-in: text"
        case .regex: return "Custom rules"
        case .apps: return "App groups"
        }
    }

    // MARK: - Search

    /// Entries matching every word of `query` in their title, group, page or
    /// keywords (case and accents ignored). Titles that start with or contain
    /// the query come first; otherwise the catalog order is kept.
    static func search(_ query: String, in entries: [SettingsSearchEntry]) -> [SettingsSearchEntry] {
        let words = normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")

        let ranked: [(rank: Int, index: Int, entry: SettingsSearchEntry)] = entries.enumerated().compactMap {
            index, entry in
            let title = normalize(entry.title)
            let haystack = ([title, entry.group, entry.section.title, entry.note ?? ""] + entry.keywords)
                .map(normalize).joined(separator: " ")
            guard words.allSatisfy(haystack.contains) else { return nil }
            let rank: Int
            if title.hasPrefix(phrase) {
                rank = 0
            } else if title.contains(phrase) {
                rank = 1
            } else if words.allSatisfy(title.contains) {
                rank = 2
            } else {
                rank = 3
            }
            return (rank, index, entry)
        }
        return ranked.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.entry)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Pages

    private static func entry(
        _ id: String, _ title: String, _ section: SettingsSection, _ group: String,
        keywords: [String] = [], note: String? = nil, anchor: String? = nil, parent: String? = nil
    ) -> SettingsSearchEntry {
        SettingsSearchEntry(
            id: id, title: title, section: section, group: group, anchor: anchor ?? id,
            keywords: keywords, note: note, parentAnchor: parent)
    }

    private static let general: [SettingsSearchEntry] = [
        entry("general.showInMenubar", "Show in Menu Bar", .general, "Appearance",
              keywords: ["status bar", "icon", "tray"]),
        entry("general.showMainWindow", "Show Main Window (in Dock & Cmd+Tab)", .general, "Appearance",
              keywords: ["dock", "command tab", "window", "app switcher"]),
        entry("general.confirmQuit", "Hold or double-tap ⌘Q to quit", .general, "Appearance",
              keywords: ["quit", "cmd q", "accidental", "exit"]),
        entry("general.hideOtherWindows", "Hide other windows when Quick Picker opens", .general, "Appearance",
              keywords: ["close", "main window"]),
        entry("general.captureMode", "Clipboard capture mode", .general, "Clipboard Behavior",
              keywords: ["text", "image", "prefer", "capture", "copy", "both"]),
        entry("general.autoCleanup", "Auto-cleanup old items", .general, "Memory Optimization",
              keywords: ["history", "limit", "delete old", "retention"]),
        entry("general.maxItems", "Keep maximum items", .general, "Memory Optimization",
              keywords: ["history size", "limit", "count"], note: "When Auto-cleanup is on",
              parent: "general.autoCleanup"),
        entry("general.cleanUpNow", "Clean Up Now", .general, "Memory Optimization",
              keywords: ["free memory", "cleanup"], anchor: "general.cleanupButtons"),
        entry("general.deleteAllHistory", "Delete All History", .general, "Memory Optimization",
              keywords: ["clear", "erase", "wipe", "remove everything"], anchor: "general.cleanupButtons"),
        entry("general.menuBarLimit", "Menu bar display items", .general, "Menu Bar Display",
              keywords: ["menu bar", "count", "dropdown"]),
        entry("general.memoryCleanup", "Enable memory cleanup", .general, "Memory Management",
              keywords: ["ram", "memory", "inactive"]),
        entry("general.memoryInterval", "Cleanup interval (minutes)", .general, "Memory Management",
              note: "When memory cleanup is on", parent: "general.memoryCleanup"),
        entry("general.maxInactive", "Max inactive time (minutes)", .general, "Memory Management",
              note: "When memory cleanup is on", parent: "general.memoryCleanup"),
        entry("general.errorLog", "Save errors to log file", .general, "Error Logging",
              keywords: ["debug", "log", "diagnostics", "errors"]),
        entry("general.logFinder", "Show log in Finder", .general, "Error Logging",
              keywords: ["log file", "clear log"], note: "When the log file is on", anchor: "general.logButtons",
              parent: "general.errorLog"),
        entry("general.clearLog", "Clear Log", .general, "Error Logging",
              note: "When the log file is on", anchor: "general.logButtons", parent: "general.errorLog"),
    ]

    private static let hotkeys: [SettingsSearchEntry] = [
        entry("hotkeys.enable", "Enable Global Hotkeys", .hotkeys, "General Hotkey Settings",
              keywords: ["shortcuts", "keyboard", "disable"]),
        entry("hotkeys.maxLast", "Max Last Items", .hotkeys, "General Hotkey Settings",
              keywords: ["recent", "count"]),
        entry("hotkeys.maxFavorite", "Max Favorite Items", .hotkeys, "General Hotkey Settings",
              keywords: ["favorites", "count"]),
        entry("hotkeys.reset", "Reset Hotkeys to Defaults", .hotkeys, "Hotkeys",
              keywords: ["restore", "default shortcuts"]),
    ]

    private static let quickPicker: [SettingsSearchEntry] = [
        entry("quickPicker.previewMode", "Preview mode", .quickPicker, "Quick Look",
              keywords: ["quick look", "preview", "custom", "native"]),
        entry("quickPicker.triggerKey", "Preview trigger key", .quickPicker, "Quick Look",
              keywords: ["space", "arrow", "quick look"]),
        entry("quickPicker.ocrKey", "⌥ Enter to extract text (Apple Vision)", .quickPicker, "Quick Look",
              keywords: ["ocr", "option return", "vision", "text recognition"]),
        entry("quickPicker.typeOutDelay", "Type-out delay per character", .quickPicker, "Type-Out Paste",
              keywords: ["type out", "⌘⇧⏎", "remote desktop", "speed", "keystrokes"]),
        entry("passwords.show", "Show the Passwords tab", .quickPicker, "Passwords",
              keywords: ["vault", "secret", "keychain", "touch id", "encrypted"]),
        entry("passwords.password", "Require a password for Passwords", .quickPicker, "Passwords",
              keywords: ["master password", "vault password", "hint", "change password", "remove password",
                         "protect", "security"]),
        entry("passwords.relock", "Lock passwords again after", .quickPicker, "Passwords",
              keywords: ["timeout", "auto-lock", "idle", "touch id"]),
        entry("passwords.clearClipboard", "Clear the clipboard after pasting a password", .quickPicker, "Passwords",
              keywords: ["clipboard", "seconds", "secret"]),
        entry("passwords.lockNow", "Lock Passwords Now", .quickPicker, "Passwords",
              keywords: ["vault", "lock"], anchor: "passwords.actions"),
        entry("passwords.deleteAll", "Delete All Passwords", .quickPicker, "Passwords",
              keywords: ["vault", "reset", "keychain key", "erase"], anchor: "passwords.actions"),
    ]

    private static let categories: [SettingsSearchEntry] = [
        entry("categories.showBar", "Show the category bar", .categories, "Quick Picker",
              keywords: ["chips", "filter"]),
        entry("categories.rowBadges", "Show category, language and app icons on rows", .categories, "Quick Picker",
              keywords: ["badges", "icons"]),
        entry("categories.sourceApp", "Remember the source app", .categories, "Source app",
              keywords: ["app", "copied from", "app:"]),
        entry("categories.forgetApps", "Forget Recorded Apps", .categories, "Source app",
              keywords: ["clear", "source app"]),
        entry("categories.reset", "Reset built-in categories", .categories, "Built-in: text",
              keywords: ["restore", "defaults"]),
        entry("categories.analyzeImages", "Find QR codes, faces and transparency", .categories, "Built-in: images",
              keywords: ["vision", "barcode", "qr", "face"]),
        entry("categories.ocrNew", "Recognize text in new images", .categories, "Text in images (OCR)",
              keywords: ["ocr", "vision", "screenshot"]),
        entry("categories.ocrAll", "Recognize Text in All Images", .categories, "Text in images (OCR)",
              keywords: ["ocr", "older images", "rescan"]),
        entry("categories.searchImageText", "Find images by the text in them", .categories, "Text in images (OCR)",
              keywords: ["ocr", "search"]),
        entry("categories.imageTextRows", "Show the text of images in Quick Picker rows", .categories,
              "Text in images (OCR)", keywords: ["ocr", "rows"]),
        entry("categories.addRule", "Add Rule (regular expression)", .categories, "Custom rules",
              keywords: ["regex", "pattern", "custom category"]),
        entry("categories.addAppGroup", "Add App Group", .categories, "App groups",
              keywords: ["apps", "group", "custom category"]),
    ]

    private static let pins: [SettingsSearchEntry] = [
        entry("pins.persist", "Persist pins across launches", .pins, "Pin Behavior",
              keywords: ["restore", "restart", "remember"]),
        entry("pins.alwaysShowControls", "Always show pin controls", .pins, "Pin Behavior",
              keywords: ["hover", "chrome", "buttons"]),
        entry("pins.fullscreen", "Show over fullscreen apps", .pins, "Pin Behavior",
              keywords: ["spaces", "on top"]),
        entry("pins.snap", "Snap to screen edges", .pins, "Pin Behavior", keywords: ["magnet", "edge"]),
        entry("pins.shadow", "Drop shadow", .pins, "Pin Behavior", keywords: ["shadow"]),
        entry("pins.quickPickerDismisses", "Quick Picker dismisses pins", .pins, "Pin Behavior",
              keywords: ["hide pins"]),
        entry("pins.maxConcurrent", "Maximum simultaneous pins", .pins, "Pin Behavior",
              keywords: ["limit", "count", "oldest"]),
        entry("pins.cornerRadius", "Pin corner radius", .pins, "Pin Behavior", keywords: ["rounded"]),
        entry("pins.opacity", "Default pin opacity", .pins, "Defaults", keywords: ["transparency", "alpha"]),
        entry("pins.textSize", "Text pins default size", .pins, "Defaults", keywords: ["width", "height"]),
        entry("pins.imageSize", "Image pins default size", .pins, "Defaults", keywords: ["width", "height"]),
        entry("pins.fileSize", "File pins default size", .pins, "Defaults", keywords: ["width", "height"]),
        entry("pins.allowTextEdit", "Allow editing text inside pins", .pins, "Advanced",
              keywords: ["edit", "editable"]),
        entry("pins.confirmDismissAll", "Confirm before dismissing all pins", .pins, "Advanced",
              keywords: ["ask", "confirmation"]),
        entry("pins.dismissAll", "Dismiss All Pins", .pins, "Active Pins",
              keywords: ["close", "unpin"], note: "When pins are open"),
    ]

    private static let excludedApps: [SettingsSearchEntry] = [
        entry("excluded.enable", "Enable app exclusion", .excludedApps, "Excluded Apps",
              keywords: ["ignore", "password manager", "privacy", "block app"]),
        entry("excluded.add", "Add App to exclude", .excludedApps, "Excluded Apps",
              keywords: ["ignore app"], note: "When app exclusion is on", anchor: "excluded.buttons",
              parent: "excluded.enable"),
        entry("excluded.removeAll", "Remove All excluded apps", .excludedApps, "Excluded Apps",
              note: "When app exclusion is on", anchor: "excluded.buttons", parent: "excluded.enable"),
    ]

    private static let accessibility: [SettingsSearchEntry] = [
        entry("accessibility.login", "Start StoneClipboarder at login", .accessibility, "Launch at Login",
              keywords: ["login item", "autostart", "startup", "boot"]),
        entry("accessibility.status", "Accessibility permission", .accessibility, "Accessibility Permission",
              keywords: ["auto-paste", "privacy", "permission", "status"]),
        entry("accessibility.open", "Open Accessibility Settings", .accessibility, "Accessibility Permission",
              keywords: ["system settings", "grant"], note: "When access isn't granted",
              parent: "accessibility.status"),
    ]

    private static let about: [SettingsSearchEntry] = [
        entry("about.updates", "Check for Updates", .about, "About", keywords: ["version", "sparkle", "update"]),
        entry("about.site", "Website", .about, "About", keywords: ["site", "home page"], anchor: "about.links"),
        entry("about.privacy", "Privacy Policy", .about, "About", anchor: "about.links"),
        entry("about.terms", "Terms of Use", .about, "About", anchor: "about.links"),
        entry("about.feedback", "Send feedback", .about, "About", keywords: ["email", "bug", "contact"]),
        entry("about.social", "Developer on Threads", .about, "Social Networks", keywords: ["social", "threads"]),
    ]
}
