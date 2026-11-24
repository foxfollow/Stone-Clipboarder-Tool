//
//  PinContentView.swift
//  StoneClipboarderTool
//
//  Root SwiftUI view rendered inside a pinned-clipboard NSPanel. Renders
//  exclusively from PinViewState (a context-free snapshot) — never from the
//  SwiftData model — to avoid faulting crashes.
//

import AppKit
import SwiftUI

struct PinContentView: View {
    @ObservedObject var state: PinViewState
    let controller: PinWindowController
    @ObservedObject var settings: SettingsManager

    @State private var isHovering = false
    @FocusState private var isEditing: Bool

    private var showChrome: Bool {
        // Click-through pins always show chrome: hover can't trigger because
        // the mouse passes through, so without this the controls (incl. the
        // hand icon to turn click-through off) would be unreachable.
        settings.pinAlwaysShowChrome || isHovering || state.isCollapsed || state.isClickThrough
    }

    var body: some View {
        // VStack (not ZStack): the chrome sits *above* the content and pushes
        // it down, so a hover-revealed control bar never covers the text.
        VStack(spacing: 0) {
            if showChrome {
                PinChromeView(
                    state: state,
                    controller: controller,
                    settings: settings
                )
                .frame(height: chromeHeight)
            }

            if !state.isCollapsed {
                contentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: settings.pinCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: settings.pinCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        // Don't make Cmd+C trigger when text is being actively edited — the
        // editor needs that for normal copy behavior. With selectable
        // (read-only) text, the handler copies the selection first and only
        // falls back to the whole pin when nothing is selected.
        .background(
            CommandKeyHandler { event in
                guard !isEditing else { return false }
                if CommandKeyHandler.isKey(event, "c", keyCode: 8) {
                    controller.copyToClipboard()
                    return true
                }
                if CommandKeyHandler.isKey(event, "w", keyCode: 13) {
                    controller.dismissByUser()
                    return true
                }
                return false
            }
        )
    }

    private var chromeHeight: CGFloat { 28 }

    // MARK: - Content body

    @ViewBuilder
    private var contentBody: some View {
        switch state.itemType {
        case .text, .combined:
            textBody
        case .image:
            PinImageView(
                image: state.displayImage,
                zoom: Binding(
                    get: { state.imageZoom },
                    set: { controller.setImageZoom($0) }
                )
            )
        case .file:
            fileBody
        }
    }

    @ViewBuilder
    private var textBody: some View {
        if settings.pinAllowTextEdit {
            TextEditor(text: $state.editedText)
                .font(.system(size: 13))
                .padding(8)
                .focused($isEditing)
                .scrollContentBackground(.hidden)
                .onChange(of: state.editedText) { _, newValue in
                    // Persist edits live (debounced disk write inside).
                    controller.commitTextEdit(newValue)
                }
        } else {
            ScrollView {
                // Use editedText so any prior edit is reflected even when
                // editing is currently disabled.
                Text(state.editedText)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private var fileBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let img = state.displayImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.fileName ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text(byteString(state.fileData?.count ?? 0))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Spacer()
        }
        .padding(10)
    }

    private func byteString(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}

/// Hosts an NSView that catches Cmd+key events and forwards them to a
/// closure. SwiftUI's `.onKeyPress` doesn't reliably see Cmd-modified keys
/// inside a borderless NSPanel.
private struct CommandKeyHandler: NSViewRepresentable {
    let onCommand: (NSEvent) -> Bool

    /// Matches a ⌘-letter by its character, or by the US key position when
    /// the layout types a non-Latin letter there (Ukrainian ⌘С is ⌘C).
    static func isKey(_ event: NSEvent, _ letter: String, keyCode: UInt16) -> Bool {
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        if chars == letter { return true }
        return event.keyCode == keyCode && chars.unicodeScalars.contains { !$0.isASCII }
    }

    func makeNSView(context: Context) -> CommandHandlerView {
        let v = CommandHandlerView()
        v.onCommand = onCommand
        return v
    }

    func updateNSView(_ nsView: CommandHandlerView, context: Context) {
        nsView.onCommand = onCommand
    }

    final class CommandHandlerView: NSView {
        var onCommand: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, let window = self.window, event.window === window else {
                    return event
                }
                guard event.modifierFlags.contains(.command) else { return event }
                // ⌘C with text selected copies the selection, not the whole pin.
                if CommandKeyHandler.isKey(event, "c", keyCode: 8), self.copySelection(in: window) {
                    return nil
                }
                if self.onCommand?(event) == true {
                    return nil
                }
                return event
            }
        }

        /// Sends `copy:` to the responder that owns a text selection in this
        /// window. Returns false when nothing is selected, so ⌘C falls back to
        /// copying the whole pin.
        private func copySelection(in window: NSWindow) -> Bool {
            // Text selected with Live Text in an image pin.
            if PinScrollView.find(in: window.contentView)?.copyLiveTextSelection() == true {
                return true
            }
            let copyAction = #selector(NSText.copy(_:))
            var responder = window.firstResponder
            while let current = responder, current !== window {
                if let textView = current as? NSTextView {
                    guard textView.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) else {
                        return false
                    }
                    textView.copy(nil)
                    return true
                }
                if current.responds(to: copyAction) {
                    let probe = NSMenuItem(title: "", action: copyAction, keyEquivalent: "")
                    if let validator = current as? NSUserInterfaceValidations,
                       !validator.validateUserInterfaceItem(probe) {
                        return false
                    }
                    // Only count it as handled if something reached the
                    // pasteboard; otherwise ⌘C copies the whole pin.
                    let before = NSPasteboard.general.changeCount
                    return current.tryToPerform(copyAction, with: nil)
                        && NSPasteboard.general.changeCount != before
                }
                responder = current.nextResponder
            }
            return false
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
