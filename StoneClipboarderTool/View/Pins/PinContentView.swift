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
        // editor needs that for normal copy behavior.
        .background(
            CommandKeyHandler { event in
                guard !isEditing else { return false }
                if event.charactersIgnoringModifiers == "c" {
                    controller.copyToClipboard()
                    return true
                }
                if event.charactersIgnoringModifiers == "w" {
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
                if event.modifierFlags.contains(.command),
                   self.onCommand?(event) == true {
                    return nil
                }
                return event
            }
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
