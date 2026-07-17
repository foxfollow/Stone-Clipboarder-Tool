//
//  TypePaster.swift
//  StoneClipboarderTool
//

import AppKit

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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { Task { @MainActor in self?.finish() } }

            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            let location = CGEventTapLocation.cghidEventTap

            for character in text {
                if token.isCancelled { break }

                let utf16 = Array(String(character).utf16)
                if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    down.post(tap: location)
                }
                if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    up.post(tap: location)
                }

                usleep(delayMicroseconds)
            }
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
