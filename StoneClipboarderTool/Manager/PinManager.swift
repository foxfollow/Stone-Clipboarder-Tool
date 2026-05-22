//
//  PinManager.swift
//  StoneClipboarderTool
//
//  Owns the lifecycle of pinned-clipboard floating windows. One
//  PinWindowController per active pin; the controllers create / manage
//  their own NSPanel and persist their state to PinnedItemConfig (only when
//  the pinPersistAcrossLaunches setting is on).
//

import AppKit
import Combine
import SwiftData
import SwiftUI

@MainActor
final class PinManager: ObservableObject {
    /// Set of CBItem ids that currently have an active pin. Drives the
    /// "is pinned" indicator in QuickPicker / main window. Published so views
    /// re-render when a pin opens or closes.
    @Published private(set) var pinnedItemIds: Set<PersistentIdentifier> = []

    /// Active controllers keyed by PinnedItemConfig.id. The CBItem-id map
    /// above is a secondary index for fast UI lookups.
    private var controllers: [UUID: PinWindowController] = [:]
    private var configIdsByItemId: [PersistentIdentifier: UUID] = [:]

    weak var viewModel: CBViewModel?
    weak var settingsManager: SettingsManager?
    var modelContext: ModelContext?

    private var hudWindow: NSWindow?
    private var itemDeleteObserver: NSObjectProtocol?

    func startObservingItemDeletes() {
        if itemDeleteObserver != nil { return }
        itemDeleteObserver = NotificationCenter.default.addObserver(
            forName: .clipboardItemDeleted,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if let id = note.object as? PersistentIdentifier {
                    self.handleSourceItemDeleted(itemId: id)
                } else {
                    // Wipe — close every pin tied to a known item; orphans
                    // (no item link) stay open since their content snapshot
                    // is self-sufficient.
                    let ids = Array(self.pinnedItemIds)
                    for id in ids { self.handleSourceItemDeleted(itemId: id) }
                }
            }
        }
    }

    // MARK: - Public API

    func isPinned(_ item: CBItem) -> Bool {
        pinnedItemIds.contains(item.persistentModelID)
    }

    /// Pin if currently unpinned, otherwise unpin. Used by the ⌥P shortcut
    /// in QuickPicker and the row context menu in the main window.
    func togglePin(_ item: CBItem) {
        if let configId = configIdsByItemId[item.persistentModelID] {
            unpin(configId: configId)
        } else {
            pin(item)
        }
    }

    func pin(_ item: CBItem) {
        guard let settings = settingsManager else { return }

        // Enforce the cap. 0 (or negative) == unlimited. When at the limit,
        // close the oldest pin(s) so the new one can open (FIFO eviction).
        let limit = settings.pinMaxConcurrent
        if limit > 0 {
            while controllers.count >= limit {
                guard let oldest = controllers.values.min(by: {
                    $0.config.createdAt < $1.config.createdAt
                }) else { break }
                unpin(configId: oldest.config.id)
            }
        }

        let config = makeConfig(for: item, settings: settings)

        // Persist now so future settings → "active pins" list sees it,
        // and so a crash doesn't lose the pin.
        if settings.pinPersistAcrossLaunches, let ctx = modelContext {
            ctx.insert(config)
            do {
                try ctx.save()
            } catch {
                ctx.rollback()
                ErrorLogger.shared.log("Failed to save PinnedItemConfig", category: "SwiftData", error: error)
            }
        }

        let controller = PinWindowController(
            config: config,
            settingsManager: settings,
            pinManager: self
        )
        controllers[config.id] = controller
        configIdsByItemId[item.persistentModelID] = config.id
        pinnedItemIds.insert(item.persistentModelID)

        controller.showWindow()
    }

    func unpin(itemId: PersistentIdentifier) {
        guard let configId = configIdsByItemId[itemId] else { return }
        unpin(configId: configId)
    }

    func unpin(configId: UUID) {
        guard let controller = controllers[configId] else { return }

        controller.close()
        controllers.removeValue(forKey: configId)

        if let itemId = configIdsByItemId.first(where: { $0.value == configId })?.key {
            configIdsByItemId.removeValue(forKey: itemId)
            pinnedItemIds.remove(itemId)
        }

        if let ctx = modelContext, settingsManager?.pinPersistAcrossLaunches == true {
            ctx.delete(controller.config)
            do {
                try ctx.save()
            } catch {
                ctx.rollback()
                ErrorLogger.shared.log("Failed to delete PinnedItemConfig", category: "SwiftData", error: error)
            }
        }
    }

    func dismissAll() {
        let ids = Array(controllers.keys)
        for id in ids { unpin(configId: id) }
    }

    /// Pin the most-recent CBItem. Used by the configurable global hotkey.
    func togglePinForLastItem() {
        guard let item = viewModel?.recentItems.first else { return }
        togglePin(item)
    }

    /// Called by a controller after a move/resize/state-change so the manager
    /// can persist the new config. Debounced inside the controller.
    func saveConfig(_ config: PinnedItemConfig) {
        guard settingsManager?.pinPersistAcrossLaunches == true,
              let ctx = modelContext else { return }
        do {
            try ctx.save()
        } catch {
            ctx.rollback()
            ErrorLogger.shared.log("Failed to persist pin state", category: "SwiftData", error: error)
        }
    }

    /// Re-apply collection-behavior / shadow / corner radius to all open pins
    /// after the user changes a behavior setting.
    func applyBehaviorSettingsToOpenPins() {
        for controller in controllers.values {
            controller.applyBehaviorSettings()
        }
    }

    // MARK: - Restore

    /// Called once after app launch wiring. No-op if persistence is off or no
    /// configs are stored.
    func restorePersistedPins() {
        guard let settings = settingsManager else { return }
        guard settings.pinPersistAcrossLaunches else {
            // Persistence got turned off between launches — purge stale rows.
            purgeAllPersistedConfigs()
            return
        }
        guard let ctx = modelContext else { return }

        let descriptor = FetchDescriptor<PinnedItemConfig>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let configs: [PinnedItemConfig]
        do {
            configs = try ctx.fetch(descriptor)
        } catch {
            ErrorLogger.shared.log("Failed to fetch pinned configs", category: "SwiftData", error: error)
            return
        }
        guard !configs.isEmpty else { return }

        for config in configs {
            // Clamp the saved frame to a currently-visible screen so an
            // off-screen pin (display disconnected) doesn't end up unreachable.
            clampFrameIntoVisibleScreen(config)

            let controller = PinWindowController(
                config: config,
                settingsManager: settings,
                pinManager: self
            )
            controllers[config.id] = controller

            // Best-effort link back to a live CBItem so the pin indicator
            // works after restore. Match by timestamp + content equality.
            if let item = findSourceItem(for: config) {
                configIdsByItemId[item.persistentModelID] = config.id
                pinnedItemIds.insert(item.persistentModelID)
            }

            controller.showWindow()
        }
    }

    func handlePersistenceSettingChanged() {
        guard let settings = settingsManager, let ctx = modelContext else { return }

        if settings.pinPersistAcrossLaunches {
            // Newly enabled — write any open pins to disk.
            for controller in controllers.values {
                ctx.insert(controller.config)
            }
            try? ctx.save()
        } else {
            purgeAllPersistedConfigs()
        }
    }

    /// Called when a CBItem is about to be deleted from the clipboard history.
    /// Closes any open pin that references it so we don't end up with a pin
    /// that survives but loses its row indicator.
    func handleSourceItemDeleted(itemId: PersistentIdentifier) {
        unpin(itemId: itemId)
    }

    /// Visible-pin snapshots for the Settings "Active pins" list. Returned as
    /// an array so SwiftUI's ForEach is happy without exposing the controllers.
    var activePinSnapshots: [PinSnapshot] {
        controllers.values
            .sorted(by: { $0.config.createdAt < $1.config.createdAt })
            .map { ctrl in
                PinSnapshot(
                    configId: ctrl.config.id,
                    itemType: ctrl.state.itemType,
                    preview: previewString(for: ctrl.state),
                    createdAt: ctrl.config.createdAt
                )
            }
    }

    // MARK: - Internals

    private func makeConfig(for item: CBItem, settings: SettingsManager) -> PinnedItemConfig {
        let (w, h) = pinSize(for: item, settings: settings)
        let origin = nextSpawnOrigin(for: NSSize(width: w, height: h))

        return PinnedItemConfig(
            itemType: item.itemType,
            content: item.content,
            imageData: item.imageData,
            fileData: item.fileData,
            fileName: item.fileName,
            fileUTI: item.fileUTI,
            x: Double(origin.x),
            y: Double(origin.y),
            width: w,
            height: h,
            opacity: settings.pinDefaultOpacity,
            sourceTimestamp: item.timestamp
        )
    }

    /// Window size at pin time. For images the window is sized to the image's
    /// aspect ratio scaled to fit within the default image box, so the image
    /// fills the pin edge-to-edge (no letterboxing) rather than sitting inside
    /// a fixed square.
    private func pinSize(for item: CBItem, settings: SettingsManager) -> (Double, Double) {
        switch item.itemType {
        case .text:
            return (settings.pinDefaultTextWidth, settings.pinDefaultTextHeight)
        case .image, .combined:
            return aspectFitSize(
                for: item.image,
                maxW: settings.pinDefaultImageWidth,
                maxH: settings.pinDefaultImageHeight
            )
        case .file:
            if item.isImageFile {
                return aspectFitSize(
                    for: item.filePreviewImage,
                    maxW: settings.pinDefaultImageWidth,
                    maxH: settings.pinDefaultImageHeight
                )
            }
            return (settings.pinDefaultFileWidth, settings.pinDefaultFileHeight)
        }
    }

    /// Largest size that preserves the image's aspect ratio while fitting
    /// inside maxW × maxH. Falls back to the full box when the image size is
    /// unavailable.
    private func aspectFitSize(for image: NSImage?, maxW: Double, maxH: Double) -> (Double, Double) {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return (maxW, maxH)
        }
        let iw = Double(image.size.width)
        let ih = Double(image.size.height)
        let scale = min(maxW / iw, maxH / ih)
        let w = (iw * scale).rounded()
        let h = (ih * scale).rounded()
        return (max(120, w), max(80, h))
    }

    /// Cascade new pins ~30pt down-right of the most recently created pin so
    /// they don't stack invisibly on top of each other.
    private func nextSpawnOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        let visible = screen.visibleFrame

        let offsetStep: CGFloat = 32
        let count = CGFloat(controllers.count)
        let baseX = visible.maxX - size.width - 40
        let baseY = visible.maxY - size.height - 40

        var x = baseX - count * offsetStep
        var y = baseY - count * offsetStep

        // Wrap if we've drifted off the bottom-left.
        if x < visible.minX + 20 { x = baseX }
        if y < visible.minY + 20 { y = baseY }
        return NSPoint(x: x, y: y)
    }

    private func clampFrameIntoVisibleScreen(_ config: PinnedItemConfig) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let frame = config.frame
        // If the pin's frame intersects any visible screen, keep it as-is.
        if screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return }

        // Otherwise, re-center on main.
        guard let main = NSScreen.main else { return }
        let v = main.visibleFrame
        config.x = Double(v.midX - frame.width / 2)
        config.y = Double(v.midY - frame.height / 2)
    }

    private func findSourceItem(for config: PinnedItemConfig) -> CBItem? {
        guard let vm = viewModel else { return nil }
        guard let ts = config.sourceTimestamp else { return nil }

        // Tight timestamp window first (cheap). If multiple items share a
        // second-truncated timestamp, fall back to content equality.
        let candidates = vm.recentItems.filter { abs($0.timestamp.timeIntervalSince(ts)) < 1.0 }
        return candidates.first(where: { matches(config: config, item: $0) }) ?? candidates.first
    }

    private func matches(config: PinnedItemConfig, item: CBItem) -> Bool {
        guard config.itemType == item.itemType else { return false }
        switch config.itemType {
        case .text: return config.content == item.content
        case .image: return config.imageData == item.imageData
        case .combined: return config.content == item.content && config.imageData == item.imageData
        case .file: return config.fileName == item.fileName
        }
    }

    private func purgeAllPersistedConfigs() {
        guard let ctx = modelContext else { return }
        do {
            let all = try ctx.fetch(FetchDescriptor<PinnedItemConfig>())
            for c in all { ctx.delete(c) }
            try ctx.save()
        } catch {
            ErrorLogger.shared.log("Failed to purge pinned configs", category: "SwiftData", error: error)
        }
    }

    private func previewString(for state: PinViewState) -> String {
        switch state.itemType {
        case .text, .combined:
            let text = (state.content ?? "").prefix(60)
            return String(text)
        case .image:
            return "[Image]"
        case .file:
            return state.fileName ?? "[File]"
        }
    }

    // MARK: - HUD

    /// Public entry point used by controllers (e.g. click-through hint).
    func showHUDMessage(_ message: String) {
        showHUD(message)
    }

    private func showHUD(_ message: String) {
        hudWindow?.orderOut(nil)
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let host = NSHostingView(rootView: PinHUDView(message: message))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if let screen = NSScreen.main {
            let f = screen.frame
            let s = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: f.midX - s.width / 2, y: f.midY - s.height / 2))
        }
        panel.orderFront(nil)
        hudWindow = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.hudWindow === panel { self?.hudWindow = nil }
        }
    }
}

struct PinSnapshot: Identifiable {
    let configId: UUID
    var id: UUID { configId }
    let itemType: CBItemType
    let preview: String
    let createdAt: Date
}

private struct PinHUDView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.18).opacity(0.95))
            )
    }
}
