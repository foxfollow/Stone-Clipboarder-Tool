//
//  TimeUnit.swift
//  StoneClipboarderTool
//
//  Created by Heorhii Savoiskyi on 15.02.2026.
//

import Foundation

enum TimeUnit: String, CaseIterable {
    case seconds = "Seconds"
    case minutes = "Minutes"
    case hours = "Hours"
    case days = "Days"

    var multiplier: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        case .days: return 86400
        }
    }
}
