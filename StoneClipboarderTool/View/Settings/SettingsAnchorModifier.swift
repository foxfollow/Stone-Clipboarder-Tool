//
//  SettingsAnchorModifier.swift
//  StoneClipboarderTool
//

import SwiftUI

/// The anchors a Settings search result points at; the page scrolls to them
/// and their rows glow for a moment.
struct SettingsHighlight: Equatable {
    var anchors: Set<String> = []
    /// Scrolled to in this order: a parent row first, then the row itself
    /// (missing while its parent toggle is off).
    var scrollTargets: [String] = []
    /// Changes on every new search pick, so picking the same row again
    /// scrolls and glows again.
    var token = UUID()
}

private struct SettingsHighlightKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    /// Anchors of `SettingsSearchIndex` entries to highlight on this page.
    var settingsHighlightedAnchors: Set<String> {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}

/// Marks a settings row with a `SettingsSearchIndex` anchor: an id to scroll
/// to and a short highlight when a search result points here.
private struct SettingsAnchorModifier: ViewModifier {
    let anchor: String
    @Environment(\.settingsHighlightedAnchors) private var highlighted

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(highlighted.contains(anchor) ? 0.22 : 0))
                    .padding(-4)
                    .animation(.easeInOut(duration: 0.35), value: highlighted.contains(anchor))
            )
    }
}

extension View {
    func settingsAnchor(_ anchor: String) -> some View {
        modifier(SettingsAnchorModifier(anchor: anchor))
    }
}
