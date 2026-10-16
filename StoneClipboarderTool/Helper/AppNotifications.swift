//
//  AppNotifications.swift
//  StoneClipboarderTool
//
//  Every NotificationCenter name the app posts, in one place.
//

import Foundation

extension Notification.Name {
    /// Posted when a pin behavior setting that needs to propagate to live
    /// NSPanels changes (collection behavior, shadow, corner radius).
    static let pinBehaviorSettingsChanged = Notification.Name("StoneClipboarder.pinBehaviorSettingsChanged")

    /// Posted with `object` = `PersistentIdentifier` of a CBItem about to be
    /// deleted from the history (`nil` = everything is being wiped), before
    /// its backing data goes away. PinManager closes pins for it; views drop
    /// rows that still reference it.
    static let clipboardItemDeleted = Notification.Name("StoneClipboarder.clipboardItemDeleted")

    /// Posted with `object` = `PersistentIdentifier` of the CBItem the main
    /// window should select (menu bar → "Open in Main Window").
    static let selectClipboardItem = Notification.Name("StoneClipboarder.selectClipboardItem")

    /// Posted when the item shown in the main window's detail pane is being
    /// deleted, so the pane lets go of it first.
    static let clearClipboardSelection = Notification.Name("StoneClipboarder.clearClipboardSelection")
}
