//
//  TypePaster.swift
//  StoneClipboarderTool
//

import AppKit
import Carbon.HIToolbox

/// A physical key plus the modifiers that produce a character on a keyboard
/// layout.
private struct KeyStroke: Sendable {
    let keyCode: CGKeyCode
    let flagsRawValue: UInt64
    /// True when the key code comes from a layout that is *not* the active one
    /// (the ASCII fallback). The active layout would translate that key code
    /// into a different character, so the event also carries an explicit
    /// Unicode payload for apps that read it.
    let overridesUnicode: Bool

    var flags: CGEventFlags { CGEventFlags(rawValue: flagsRawValue) }
}

/// Builds character → keystroke tables from keyboard layouts.
///
/// Why this exists: posting a key event with `virtualKey: 0` plus a Unicode
/// payload only works for apps that read the event's Unicode string.
/// virtualKey 0 is literally `kVK_ANSI_A`, so anything that reads the *key
/// code* instead — terminals, VMs, remote desktops, `KeyboardEvent.code` in a
/// browser — sees every character as "A". Mapping each character to its real
/// key code makes synthesized keystrokes indistinguishable from typing.
///
/// Two tables, because the active layout may not be able to type the character
/// at all: on a Cyrillic layout (Ukrainian, Russian, …) every Latin letter is
/// missing, and ASCII punctuation sits on different keys (`#` is ⌥3 on
/// Ukrainian-PC, ⇧3 on ABC). ASCII characters therefore prefer the ASCII
/// fallback layout's key codes — that is what a key-code reader on the far end
/// of a remote-desktop session expects — while non-ASCII characters use the
/// active layout.
private struct KeyboardLayoutTables: Sendable {
    /// Strokes from the layout the user is actually typing on.
    let active: [Character: KeyStroke]
    /// Strokes from the ASCII-capable layout macOS falls back to. Empty when
    /// the active layout is already ASCII-capable (then `active` covers ASCII).
    let asciiFallback: [Character: KeyStroke]

    func stroke(for character: Character) -> KeyStroke? {
        if character.isASCII, let stroke = asciiFallback[character] { return stroke }
        return active[character] ?? asciiFallback[character]
    }

    static func build() -> KeyboardLayoutTables {
        let activeSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
            ?? TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        var active = table(from: activeSource, overridesUnicode: false)

        // Whitespace the layout tables don't yield as printable scalars.
        active["\n"] = KeyStroke(keyCode: CGKeyCode(kVK_Return), flagsRawValue: 0, overridesUnicode: false)
        active["\r"] = KeyStroke(keyCode: CGKeyCode(kVK_Return), flagsRawValue: 0, overridesUnicode: false)
        active["\t"] = KeyStroke(keyCode: CGKeyCode(kVK_Tab), flagsRawValue: 0, overridesUnicode: false)

        // Only needed when the active layout can't produce plain ASCII.
        let needsFallback = active["a"] == nil || active["A"] == nil
        let fallback = needsFallback
            ? table(
                from: TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
                overridesUnicode: true
            )
            : [:]

        return KeyboardLayoutTables(active: active, asciiFallback: fallback)
    }

    /// Numeric-keypad key codes, left out of the tables entirely.
    ///
    /// The unmodified pass wins ties, so without this `*` resolves to keypad
    /// multiply and `+` to keypad plus — no modifier needed, which looks like a
    /// win until the far end of a remote-desktop session interprets keypad keys
    /// against its own NumLock state, or a field treats them differently from
    /// the main row. The main keyboard can type every one of these characters.
    private static let keypadKeyCodes: Set<UInt16> = [
        UInt16(kVK_ANSI_Keypad0), UInt16(kVK_ANSI_Keypad1), UInt16(kVK_ANSI_Keypad2),
        UInt16(kVK_ANSI_Keypad3), UInt16(kVK_ANSI_Keypad4), UInt16(kVK_ANSI_Keypad5),
        UInt16(kVK_ANSI_Keypad6), UInt16(kVK_ANSI_Keypad7), UInt16(kVK_ANSI_Keypad8),
        UInt16(kVK_ANSI_Keypad9), UInt16(kVK_ANSI_KeypadDecimal), UInt16(kVK_ANSI_KeypadMultiply),
        UInt16(kVK_ANSI_KeypadPlus), UInt16(kVK_ANSI_KeypadClear), UInt16(kVK_ANSI_KeypadDivide),
        UInt16(kVK_ANSI_KeypadEnter), UInt16(kVK_ANSI_KeypadMinus), UInt16(kVK_ANSI_KeypadEquals),
    ]

    private static func table(
        from inputSource: TISInputSource?,
        overridesUnicode: Bool
    ) -> [Character: KeyStroke] {
        guard let inputSource,
              let layoutPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }

        let layoutData = unsafeBitCast(layoutPtr, to: CFData.self) as Data
        var table: [Character: KeyStroke] = [:]

        // Unmodified first, so it wins for characters reachable more than one
        // way (the dictionary insert below only fills empty slots). Shift
        // before Option for the same reason: ⌥ is AltGr on the far side of a
        // remote desktop and can trip menu accelerators.
        let combos: [(CGEventFlags, UInt32)] = [
            ([], 0),
            (.maskShift, UInt32(shiftKey >> 8)),
            (.maskAlternate, UInt32(optionKey >> 8)),
            ([.maskShift, .maskAlternate], UInt32((shiftKey | optionKey) >> 8)),
        ]

        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return
            }
            let keyboardType = UInt32(LMGetKbdType())

            for (flags, carbonModifiers) in combos {
                for keyCode in UInt16(0)..<128 where !keypadKeyCodes.contains(keyCode) {
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0

                    let status = UCKeyTranslate(
                        layout,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        carbonModifiers,
                        keyboardType,
                        OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        chars.count,
                        &length,
                        &chars
                    )

                    guard status == noErr, length == 1,
                          let scalar = Unicode.Scalar(chars[0]),
                          scalar.value >= 32  // skip control chars, handled above
                    else { continue }

                    let character = Character(scalar)
                    if table[character] == nil {
                        table[character] = KeyStroke(
                            keyCode: CGKeyCode(keyCode),
                            flagsRawValue: flags.rawValue,
                            overridesUnicode: overridesUnicode
                        )
                    }
                }
            }
        }

        return table
    }
}

/// Types text out as synthetic keystrokes, character by character, so it lands
/// in fields that block programmatic paste (⌘V). Owned by
/// `QuickPickerWindowManager` so an in-flight type-out survives the Quick
/// Picker closing and stays cancellable — by pressing Escape (a global key
/// monitor installed only while typing), or by reopening the Quick Picker.
@MainActor
final class TypePaster {
    /// Thread-safe stop flag shared with the background typing loop. A fresh
    /// token is minted per run so a late `cancel()` can't kill a newer run.
    private final class CancelToken: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    private var currentToken: CancelToken?
    private(set) var isTyping = false
    nonisolated(unsafe) private var escGlobalMonitor: Any?
    nonisolated(unsafe) private var escLocalMonitor: Any?

    /// Type `text`, waiting `charDelayMs` (floored to 1 ms) between characters.
    /// Cancels any previous run first.
    func type(_ text: String, charDelayMs: Int) {
        cancel()
        guard !text.isEmpty else { return }

        let token = CancelToken()
        currentToken = token
        isTyping = true
        installEscMonitors()

        // Floor at 1 ms: with zero delay the OS coalesces/drops the burst of
        // synthetic events and little or nothing actually gets typed.
        let delayMicroseconds = UInt32(max(1, charDelayMs)) * 1000
        let layout = KeyboardLayoutTables.build()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { Task { @MainActor in self?.finish() } }

            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            let location = CGEventTapLocation.cghidEventTap

            // The trigger chord (⌘⇧Return) is usually still physically held at
            // this point; those modifiers would combine with the first
            // keystrokes (uppercase, or worse, fire shortcuts). Let go first.
            Self.waitForModifierRelease(token: token)

            // Modifiers stay down across a run of characters that need them, the
            // way a hand does for "ABC" — fewer state changes for the far end to
            // miss, and no settle cost per character.
            var held: CGEventFlags = []
            defer { Self.setModifiers([], held: &held, source: source, location: location) }

            for character in text {
                if token.isCancelled { break }
                Self.post(character, layout: layout, held: &held, source: source, location: location)
                usleep(delayMicroseconds)
            }
        }
    }

    /// Block until the user releases every modifier, or ~1s passes.
    nonisolated private static func waitForModifierRelease(token: CancelToken) {
        let interesting: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        var waitedMicroseconds = 0
        while waitedMicroseconds < 1_000_000 {
            if token.isCancelled { return }
            let held = CGEventSource.flagsState(.combinedSessionState)
            if held.intersection(interesting).isEmpty { return }
            usleep(20_000)
            waitedMicroseconds += 20_000
        }
    }

    /// Modifiers we synthesize, in press order (release happens in reverse).
    nonisolated private static let modifierKeys: [(mask: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskShift, CGKeyCode(kVK_Shift)),
        (.maskAlternate, CGKeyCode(kVK_Option)),
    ]

    /// How long to wait after changing modifier state before sending the key.
    ///
    /// Not paranoia padding: a remote-desktop client forwards input to the far
    /// end on its own thread and samples the modifier state when it dequeues the
    /// key event. Press-and-release inside a millisecond and that sample sees
    /// nothing held, which is why "!@#" arrived as "123" and "FGH" as "fgh". A
    /// hand holds Shift for ~100 ms; 25 ms is enough to be observed and is only
    /// paid when the modifier set actually changes.
    nonisolated private static let modifierSettleMicroseconds: UInt32 = 25_000

    nonisolated private static func post(
        _ character: Character,
        layout: KeyboardLayoutTables,
        held: inout CGEventFlags,
        source: CGEventSource,
        location: CGEventTapLocation
    ) {
        guard let stroke = layout.stroke(for: character) else {
            // Unreachable on any layout (emoji, other scripts): fall back to a
            // Unicode payload. Key-code readers can't represent these anyway.
            setModifiers([], held: &held, source: source, location: location)
            postUnicodeOnly(character, source: source, location: location)
            return
        }

        // Press the modifiers as real modifier events, not just as flags on the
        // key event. Remote-desktop clients, VMs and terminals derive modifier
        // state from the modifier events themselves and forward it to the far
        // end as its own key press; flags riding along on the character event
        // alone are invisible to them.
        setModifiers(stroke.flags, held: &held, source: source, location: location)

        // Real key code + explicit flags: key-code readers see the right key,
        // and setting flags outright stops any still-held physical modifier
        // from leaking into the event.
        let utf16 = stroke.overridesUnicode ? Array(String(character).utf16) : nil
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: isDown)
            else { continue }
            event.flags = stroke.flags
            if let utf16 {
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            }
            event.post(tap: location)
        }
    }

    /// Bring the held modifier set to `wanted`, posting only the difference.
    /// No-op — and no settle delay — when nothing has to change.
    nonisolated private static func setModifiers(
        _ wanted: CGEventFlags,
        held: inout CGEventFlags,
        source: CGEventSource,
        location: CGEventTapLocation
    ) {
        guard held != wanted else { return }

        // Release before pressing, mirroring a real hand.
        for modifier in modifierKeys.reversed()
        where held.contains(modifier.mask) && !wanted.contains(modifier.mask) {
            held.remove(modifier.mask)
            postModifier(keyCode: modifier.keyCode, down: false, flags: held, source: source, location: location)
        }
        for modifier in modifierKeys
        where wanted.contains(modifier.mask) && !held.contains(modifier.mask) {
            held.insert(modifier.mask)
            postModifier(keyCode: modifier.keyCode, down: true, flags: held, source: source, location: location)
        }

        usleep(modifierSettleMicroseconds)
    }

    /// Post one modifier press or release. `flags` is the *cumulative* state
    /// after this change, which is how the window server reports real modifier
    /// keys — `.flagsChanged` is the event type a physical Shift produces, and
    /// it updates the system-wide modifier state that clients poll.
    nonisolated private static func postModifier(
        keyCode: CGKeyCode,
        down: Bool,
        flags: CGEventFlags,
        source: CGEventSource,
        location: CGEventTapLocation
    ) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
        else { return }
        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: location)
    }

    nonisolated private static func postUnicodeOnly(
        _ character: Character,
        source: CGEventSource,
        location: CGEventTapLocation
    ) {
        let utf16 = Array(String(character).utf16)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
            event.flags = []
            event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            event.post(tap: location)
        }
    }

    /// Stop an in-flight type-out (no-op if idle).
    func cancel() {
        currentToken?.cancel()
        currentToken = nil
        // While typing, the background loop's `defer` calls finish() (which
        // removes the monitors) once it observes the cancel. When idle, make
        // sure no monitors linger.
        if !isTyping { removeEscMonitors() }
    }

    private func finish() {
        isTyping = false
        currentToken = nil
        removeEscMonitors()
    }

    private func installEscMonitors() {
        removeEscMonitors()
        // Global monitor: catches Escape while another app is frontmost — the
        // usual case during type-out, since focus is in the target field. A
        // global monitor can't consume the event, so Escape also reaches that
        // app, which is benign.
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return }  // Escape
            self?.cancel()
        }
        // Local monitor: covers the case where our app happens to be frontmost;
        // here we consume the Escape so it doesn't leak into our own UI.
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
    }

    private func removeEscMonitors() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
    }

    deinit {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m) }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m) }
    }
}
