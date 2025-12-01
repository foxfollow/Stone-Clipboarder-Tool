//
//  ExcludedApp.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 01.12.2025.
//

import Foundation
import SwiftData

@Model
final class ExcludedApp {
    var bundleIdentifier: String
    var appName: String
    var dateAdded: Date

    init(bundleIdentifier: String, appName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.dateAdded = Date()
    }
}
