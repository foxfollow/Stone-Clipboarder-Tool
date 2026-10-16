//
//  PasteSimulator.swift
//  StoneClipboarderTool
//
//  Posts ⌘V to the frontmost app once an item is on the pasteboard. Used by
//  global hotkeys and the Quick Picker.
//

import AppKit
import Carbon.HIToolbox

@MainActor
enum PasteSimulator {
    /// Gives focus time to return to the target app (the Quick Picker has
    /// just closed, or the hotkey's modifiers are still being released).
    nonisolated static let defaultDelay: TimeInterval = 0.15

    /// True when synthetic key events can be posted. Without Accessibility
    /// permission macOS drops them silently, so show the explanation instead.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        guard AccessibilityAlertHelper.isAccessibilityGranted else {
            AccessibilityAlertHelper.showAccessibilityAlert()
            return false
        }
        return true
    }

    /// Posts ⌘V after `delay`, or shows the Accessibility alert.
    static func paste(after delay: TimeInterval = defaultDelay) {
        guard ensureAccessibility() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            postCommandV()
        }
    }

    private static func postCommandV() {
        let keyV = CGKeyCode(kVK_ANSI_V)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
