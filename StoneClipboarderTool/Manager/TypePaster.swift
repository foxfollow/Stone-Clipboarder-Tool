//
//  TypePaster.swift
//  StoneClipboarderTool
//

import AppKit
import Carbon.HIToolbox

/// A physical key plus the modifiers that produce a character on the user's
/// current keyboard layout.
private struct KeyStroke: Sendable {
    let keyCode: CGKeyCode
    let flagsRawValue: UInt64

    var flags: CGEventFlags { CGEventFlags(rawValue: flagsRawValue) }
}

/// Builds a character → keystroke table from the active keyboard layout.
///
/// Why this exists: posting a key event with `virtualKey: 0` plus a Unicode
/// payload only works for apps that read the event's Unicode string.
/// virtualKey 0 is literally `kVK_ANSI_A`, so anything that reads the *key
/// code* instead — terminals, VMs, remote desktops, `KeyboardEvent.code` in a
/// browser — sees every character as "A". Mapping each character to its real
/// key code makes synthesized keystrokes indistinguishable from typing.
private enum KeyboardLayoutTable {
    static func build() -> [Character: KeyStroke] {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
                ?? TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }

        let layoutData = unsafeBitCast(layoutPtr, to: CFData.self) as Data
        var table: [Character: KeyStroke] = [:]

        // Unmodified first, so it wins for characters reachable more than one
        // way (the dictionary insert below only fills empty slots).
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
                for keyCode in UInt16(0)..<128 {
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
                          scalar.value >= 32  // skip control chars, handled below
                    else { continue }

                    let character = Character(scalar)
                    if table[character] == nil {
                        table[character] = KeyStroke(keyCode: CGKeyCode(keyCode), flagsRawValue: flags.rawValue)
                    }
                }
            }
        }

        // Whitespace the layout tables don't yield as printable scalars.
        table["\n"] = KeyStroke(keyCode: CGKeyCode(kVK_Return), flagsRawValue: 0)
        table["\r"] = KeyStroke(keyCode: CGKeyCode(kVK_Return), flagsRawValue: 0)
        table["\t"] = KeyStroke(keyCode: CGKeyCode(kVK_Tab), flagsRawValue: 0)

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
        let layout = KeyboardLayoutTable.build()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { Task { @MainActor in self?.finish() } }

            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            let location = CGEventTapLocation.cghidEventTap

            // The trigger chord (⌘⇧Return) is usually still physically held at
            // this point; those modifiers would combine with the first
            // keystrokes (uppercase, or worse, fire shortcuts). Let go first.
            Self.waitForModifierRelease(token: token)

            for character in text {
                if token.isCancelled { break }
                Self.post(character, layout: layout, source: source, location: location)
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

    nonisolated private static func post(
        _ character: Character,
        layout: [Character: KeyStroke],
        source: CGEventSource,
        location: CGEventTapLocation
    ) {
        if let stroke = layout[character] {
            // Real key code + explicit flags: key-code readers see the right
            // key, and setting flags outright stops any still-held physical
            // modifier from leaking into the event.
            if let down = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: true) {
                down.flags = stroke.flags
                down.post(tap: location)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: false) {
                up.flags = stroke.flags
                up.post(tap: location)
            }
            return
        }

        // Unreachable on this layout (emoji, other scripts): fall back to a
        // Unicode payload. Key-code readers can't represent these anyway.
        let utf16 = Array(String(character).utf16)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            down.flags = []
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down.post(tap: location)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            up.flags = []
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up.post(tap: location)
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
