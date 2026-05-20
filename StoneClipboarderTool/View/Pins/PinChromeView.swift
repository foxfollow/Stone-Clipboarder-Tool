//
//  PinChromeView.swift
//  StoneClipboarderTool
//
//  Compact header bar shown on top of a pinned-window's content. Hosts the
//  drag handle, opacity slider, lock / click-through / copy / collapse /
//  close controls. Reads from PinViewState (context-free snapshot).
//

import SwiftUI

struct PinChromeView: View {
    @ObservedObject var state: PinViewState
    let controller: PinWindowController
    @ObservedObject var settings: SettingsManager

    private var typeIcon: String {
        switch state.itemType {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .combined: return "doc.richtext"
        }
    }

    private var openInAppHelp: String {
        switch state.itemType {
        case .text, .combined: return "Open in TextEdit"
        case .image: return "Open in Preview"
        case .file: return "Open in default app"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Drag affordance / title. The whole panel is draggable via
            // isMovableByWindowBackground; double-click toggles collapse.
            Text(titleText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    controller.toggleCollapsed()
                }

            // Click-through hint so the user knows how to regain interaction.
            if state.isClickThrough {
                Text("⌘ to interact")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
                    .help("Click-through is on. Hold ⌘ to interact with this pin, then click the hand icon to turn it off.")
            }

            // Opacity slider (compact)
            if !state.isCollapsed {
                Slider(
                    value: Binding(
                        get: { state.opacity },
                        set: { controller.setOpacity($0) }
                    ),
                    in: 0.2...1.0
                )
                .controlSize(.mini)
                .frame(width: 60)
                .help("Opacity")
            }

            // Lock toggle
            iconButton(
                systemName: state.isLocked ? "lock.fill" : "lock.open",
                help: state.isLocked ? "Unlock position & size" : "Lock position & size",
                tint: state.isLocked ? .accentColor : nil
            ) {
                controller.setLocked(!state.isLocked)
            }

            // Click-through toggle
            iconButton(
                systemName: state.isClickThrough ? "hand.tap.fill" : "hand.tap",
                help: state.isClickThrough ? "Disable click-through" : "Enable click-through (clicks pass through to apps beneath)",
                tint: state.isClickThrough ? .orange : nil
            ) {
                controller.setClickThrough(!state.isClickThrough)
            }

            // Copy button
            iconButton(
                systemName: "doc.on.doc",
                help: "Copy to clipboard"
            ) {
                controller.copyToClipboard()
            }

            // Open in default app (Preview / TextEdit / etc.)
            iconButton(
                systemName: "arrow.up.forward.app",
                help: openInAppHelp
            ) {
                controller.openInDefaultApp()
            }

            // Collapse / expand
            iconButton(
                systemName: state.isCollapsed ? "chevron.down" : "chevron.up",
                help: state.isCollapsed ? "Expand" : "Collapse to header"
            ) {
                controller.toggleCollapsed()
            }

            // Close
            iconButton(
                systemName: "xmark",
                help: "Unpin",
                tint: .red
            ) {
                controller.dismissByUser()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Rectangle()
                .fill(.thinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.primary.opacity(0.1)),
            alignment: .bottom
        )
    }

    private var titleText: String {
        switch state.itemType {
        case .text, .combined:
            let s = (state.content ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? "Pinned text" : String(s.prefix(40))
        case .image:
            return "Pinned image"
        case .file:
            return state.fileName ?? "Pinned file"
        }
    }

    @ViewBuilder
    private func iconButton(
        systemName: String,
        help: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
