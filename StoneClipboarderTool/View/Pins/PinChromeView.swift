//
//  PinChromeView.swift
//  StoneClipboarderTool
//
//  Compact header bar shown on top of a pinned-window's content. Hosts the
//  drag handle, opacity slider, lock / click-through / copy / collapse /
//  close controls.
//

import SwiftUI

struct PinChromeView: View {
    @Bindable var config: PinnedItemConfig
    let controller: PinWindowController
    @ObservedObject var settings: SettingsManager

    private var typeIcon: String {
        switch config.itemType {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .combined: return "doc.richtext"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Drag affordance / title. The whole panel is draggable via
            // isMovableByWindowBackground, but the icon gives users a target.
            Text(titleText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    controller.toggleCollapsed()
                }

            // Opacity slider (compact)
            if !config.isCollapsed {
                Slider(
                    value: Binding(
                        get: { config.opacity },
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
                systemName: config.isLocked ? "lock.fill" : "lock.open",
                help: config.isLocked ? "Unlock position & size" : "Lock position & size",
                tint: config.isLocked ? .accentColor : nil
            ) {
                controller.setLocked(!config.isLocked)
            }

            // Click-through toggle
            iconButton(
                systemName: config.isClickThrough ? "hand.tap" : "hand.tap.fill",
                help: config.isClickThrough ? "Disable click-through" : "Enable click-through (clicks pass through)",
                tint: config.isClickThrough ? .accentColor : nil
            ) {
                controller.setClickThrough(!config.isClickThrough)
            }

            // Copy button
            iconButton(
                systemName: "doc.on.doc",
                help: "Copy to clipboard"
            ) {
                controller.copyToClipboard()
            }

            // Collapse / expand
            iconButton(
                systemName: config.isCollapsed ? "chevron.down" : "chevron.up",
                help: config.isCollapsed ? "Expand" : "Collapse to header"
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
        switch config.itemType {
        case .text, .combined:
            let s = (config.content ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? "Pinned text" : String(s.prefix(40))
        case .image:
            return "Pinned image"
        case .file:
            return config.fileName ?? "Pinned file"
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
