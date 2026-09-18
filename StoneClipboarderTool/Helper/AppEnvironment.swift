//
//  AppEnvironment.swift
//  StoneClipboarderTool
//
//  Facts about the process the app is running in.
//

import Foundation

enum AppEnvironment {
    /// True when this process only hosts the XCTest bundle (the test target
    /// has TEST_HOST = the app). The host still runs `App.body` and the app
    /// delegate, so without this check a test run would open the real
    /// SwiftData stores, watch the real clipboard, register global hotkeys,
    /// restore pins and start Sparkle. Unsigned test runs are unsandboxed,
    /// which means the *installed* app's store and preferences.
    static let isRunningUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()
}
