//
//  PinContentView.swift
//  StoneClipboarderTool
//
//  Root SwiftUI view rendered inside a pinned-clipboard NSPanel.
//

import AppKit
import SwiftUI

struct PinContentView: View {
    /// The shared config — mutated by the chrome (opacity, lock, etc.) and
    /// observed by the panel for size/position persistence. The pin owns a
    /// single config instance shared with the controller.
    @Bindable var config: PinnedItemConfig
    let controller: PinWindowController
    @ObservedObject var settings: SettingsManager

    @State private var isHovering = false
    @State private var editedText: String = ""
    @FocusState private var isEditing: Bool

    private var showChrome: Bool {
        settings.pinAlwaysShowChrome || isHovering || config.isCollapsed
    }

    var body: some View {
        ZStack(alignment: .top) {
            if !config.isCollapsed {
                contentBody
                    .padding(.top, settings.pinAlwaysShowChrome ? chromeHeight : 0)
            }

            if showChrome {
                PinChromeView(
                    config: config,
                    controller: controller,
                    settings: settings
                )
                .frame(height: chromeHeight)
                .transition(.opacity)
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
        .onAppear {
            editedText = config.content ?? ""
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
        switch config.itemType {
        case .text, .combined:
            textBody
        case .image:
            PinImageView(
                imageData: config.imageData,
                zoom: Binding(
                    get: { config.imageZoom },
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
            TextEditor(text: $editedText)
                .font(.system(size: 13))
                .padding(8)
                .focused($isEditing)
                .scrollContentBackground(.hidden)
                .onChange(of: editedText) { _, newValue in
                    config.content = newValue
                }
        } else {
            ScrollView {
                Text(config.content ?? "")
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
                if let data = config.fileData, let img = NSImage(data: data) {
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
                    Text(config.fileName ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text(byteString(config.fileData?.count ?? 0))
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
