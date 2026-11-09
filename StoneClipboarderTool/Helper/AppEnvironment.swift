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

    /// `--screenshots <dir>`: the demo, plus a tour that shows each screen
    /// in dark and light and waits for `scripts/screenshots.sh` to capture
    /// it into `dir`, then quits. See docs/DEMO_MODE.md.
    static let screenshotsDirectory: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--screenshots"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }()

    /// `--demo` (or `--screenshots`): made-up history in memory
    /// (`DemoData`), throwaway settings, and nothing that touches the real
    /// system: no clipboard watching, global hotkeys, menu bar item, pins,
    /// login item or update checks. Safe next to the installed app.
    static let isDemo: Bool = ProcessInfo.processInfo.arguments.contains("--demo") || screenshotsDirectory != nil

    /// Where `SettingsManager` keeps its values: a fresh suite in a demo, so
    /// the real preferences are never read or written.
    static let settingsDefaults: UserDefaults = {
        guard isDemo, let demo = UserDefaults(suiteName: DemoData.defaultsSuite) else { return .standard }
        demo.removePersistentDomain(forName: DemoData.defaultsSuite)
        DemoData.presetSettings(in: demo)
        return demo
    }()
}
