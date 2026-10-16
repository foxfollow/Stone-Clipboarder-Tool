//
//  HotkeyShortcut.swift
//  StoneClipboarderTool
//
//  Parses and formats the shortcut strings stored in
//  HotkeyConfig.shortcutKeys ("⌃⌥1", "⌃⌥Space", "⌃⌥⇧P").
//
//  Why one type: the recorder in HotkeySettingsView and the Carbon
//  registration in HotkeyManager used to keep separate key tables. The
//  recorder accepted Return, arrows and punctuation that registration could
//  not parse, so such shortcuts were saved and then silently never worked.
//  Both sides now go through `keys`: whatever can be recorded can be
//  registered.
//

import AppKit
import Carbon.HIToolbox

struct HotkeyShortcut: Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Carbon virtual key code: a physical key position, independent of the
    /// active keyboard layout.
    let keyCode: UInt16
    let modifiers: Modifiers

    /// Glyphs in the canonical order used when formatting.
    private static let modifierGlyphs: [(glyph: Character, modifier: Modifiers)] = [
        ("⌃", .control), ("⌥", .option), ("⇧", .shift), ("⌘", .command),
    ]

    /// Every key a shortcut may use, with the label stored after the
    /// modifier glyphs. Labels are the US (ANSI) legends of the physical keys,
    /// so a shortcut keeps the same label whatever layout is active.
    static let keys: [(label: String, keyCode: UInt16)] = {
        var keys: [(String, Int)] = [
            ("A", kVK_ANSI_A), ("B", kVK_ANSI_B), ("C", kVK_ANSI_C), ("D", kVK_ANSI_D),
            ("E", kVK_ANSI_E), ("F", kVK_ANSI_F), ("G", kVK_ANSI_G), ("H", kVK_ANSI_H),
            ("I", kVK_ANSI_I), ("J", kVK_ANSI_J), ("K", kVK_ANSI_K), ("L", kVK_ANSI_L),
            ("M", kVK_ANSI_M), ("N", kVK_ANSI_N), ("O", kVK_ANSI_O), ("P", kVK_ANSI_P),
            ("Q", kVK_ANSI_Q), ("R", kVK_ANSI_R), ("S", kVK_ANSI_S), ("T", kVK_ANSI_T),
            ("U", kVK_ANSI_U), ("V", kVK_ANSI_V), ("W", kVK_ANSI_W), ("X", kVK_ANSI_X),
            ("Y", kVK_ANSI_Y), ("Z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
            ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
            ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal), ("[", kVK_ANSI_LeftBracket),
            ("]", kVK_ANSI_RightBracket), ("\\", kVK_ANSI_Backslash), (";", kVK_ANSI_Semicolon),
            ("'", kVK_ANSI_Quote), (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period),
            ("/", kVK_ANSI_Slash), ("`", kVK_ANSI_Grave),
            ("Space", kVK_Space), ("Return", kVK_Return), ("Enter", kVK_ANSI_KeypadEnter),
            ("Tab", kVK_Tab), ("Delete", kVK_Delete), ("Escape", kVK_Escape),
            ("←", kVK_LeftArrow), ("→", kVK_RightArrow), ("↓", kVK_DownArrow), ("↑", kVK_UpArrow),
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() {
            keys.append(("F\(index + 1)", code))
        }
        return keys.map { (label: $0.0, keyCode: UInt16($0.1)) }
    }()

    static func label(forKeyCode keyCode: UInt16) -> String? {
        keys.first { $0.keyCode == keyCode }?.label
    }

    static func keyCode(forLabel label: String) -> UInt16? {
        keys.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }?.keyCode
    }

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Parses a stored shortcut. Modifier order doesn't matter and labels are
    /// case-insensitive. nil for nil, "", "None", a shortcut without a
    /// modifier, or a key missing from `keys`.
    init?(_ string: String?) {
        guard let string else { return nil }
        var modifiers: Modifiers = []
        var label = ""
        for character in string where !character.isWhitespace {
            if let glyph = Self.modifierGlyphs.first(where: { $0.glyph == character }) {
                modifiers.insert(glyph.modifier)
            } else {
                label.append(character)
            }
        }
        guard !modifiers.isEmpty, let keyCode = Self.keyCode(forLabel: label) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// A shortcut from a recorded key press. nil when no modifier is held or
    /// the key isn't in `keys`.
    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if modifierFlags.contains(.control) { modifiers.insert(.control) }
        if modifierFlags.contains(.option) { modifiers.insert(.option) }
        if modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if modifierFlags.contains(.command) { modifiers.insert(.command) }
        guard !modifiers.isEmpty, Self.label(forKeyCode: keyCode) != nil else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    /// The stored form, modifiers in canonical order: "⌃⌥⇧P".
    var stringValue: String {
        let glyphs = Self.modifierGlyphs.filter { modifiers.contains($0.modifier) }.map(\.glyph)
        return String(glyphs) + (Self.label(forKeyCode: keyCode) ?? "?")
    }

    /// Modifier mask for Carbon's RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var mask = 0
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        if modifiers.contains(.command) { mask |= cmdKey }
        return UInt32(mask)
    }

    /// Shortcuts macOS or nearly every app already uses; the recorder refuses
    /// them. Compared structurally, so modifier order in this list is free.
    static let reservedBySystem: Set<HotkeyShortcut> = Set([
        "⌘A", "⌘C", "⌘V", "⌘X", "⌘Z", "⌘Y", "⌘S", "⌘O", "⌘N", "⌘W", "⌘Q",
        "⌘T", "⌘R", "⌘P", "⌘F", "⌘G", "⌘H", "⌘M", "⌘,", "⌘Space",
        "⌘⇧Z", "⌘⇧T", "⌘⇧N", "⌘⇧W", "⌘⇧A", "⌘⇧S", "⌘⇧P",
        "⌃Space", "⌥Space", "⌘⌥Space", "⌘⌃Space",
        "⌘Tab", "⌘⇧Tab", "⌘`", "⌘⇧`",
    ].compactMap { HotkeyShortcut($0) })

    var isReservedBySystem: Bool {
        Self.reservedBySystem.contains(self)
    }
}
