//
//  AppIconCache.swift
//  StoneClipboarderTool
//

import AppKit

/// App icons by bundle id, for source-app badges. Looked up once per app;
/// nil when the app isn't installed.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(for bundleID: String) -> NSImage? {
        if let icon = icons[bundleID] { return icon }
        if missing.contains(bundleID) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}
