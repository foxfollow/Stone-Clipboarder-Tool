import AppKit
import CoreImage
import SwiftData
import SwiftUI
import XCTest
@testable import StoneClipboarderTool

/// Renders the landing page screenshots (docs/resources/index/sct-*.png)
/// from the app's real views, filled with made-up data from an in-memory
/// store. Skipped unless asked for:
///
///     make screenshots
///
/// which runs this test unsigned (so it may write into docs/) with
/// TEST_RUNNER_STONE_SCREENSHOTS_DIR set. Nothing touches the real history
/// or preferences: in-memory container, `IsolatedDefaults`.
@MainActor
final class LandingScreenshots: XCTestCase {

    private var outputDirectory: URL!
    private var isolated: IsolatedDefaults!
    private var container: ModelContainer!
    private var viewModel: CBViewModel!
    private var settings: SettingsManager!

    override func setUp() async throws {
        try await super.setUp()
        guard let dir = ProcessInfo.processInfo.environment["STONE_SCREENSHOTS_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_STONE_SCREENSHOTS_DIR (make screenshots) to render the landing screenshots.")
        }
        outputDirectory = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        isolated = IsolatedDefaults()
        isolated.defaults.set(true, forKey: "hasShownAutoStartPrompt")
        settings = SettingsManager(defaults: isolated.defaults)
        settings.recognizeTextInNewImages = false
        settings.saveCategory(Self.documentsRule)
        settings.saveCategory(Self.browsersGroup)

        let schema = Schema([CBItem.self])
        let config = ModelConfiguration("LandingScreenshots", schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        viewModel = CBViewModel()
        viewModel.setModelContext(container.mainContext)
        viewModel.setSettingsManager(settings)
        try MockHistory.fill(container.mainContext, ruleset: viewModel.classifierRuleset)
        viewModel.fetchItems(reset: true)
    }

    override func tearDown() async throws {
        isolated?.remove()
        try await super.tearDown()
    }

    // MARK: - Screenshots

    func testQuickPicker() async throws {
        for dark in [true, false] {
            let picker = QuickPickerView(viewModel: viewModel, pinManager: PinManager(), settingsManager: settings) {}
            try await render(picker, size: CGSize(width: 500, height: 460), dark: dark,
                             name: "sct-\(dark ? "dark" : "light")-quickpicker.png")
        }
    }

    func testMainWindow() async throws {
        let selected = try XCTUnwrap(viewModel.items.first { $0.itemType == .image })
        for dark in [true, false] {
            let window = ContentView()
                .environmentObject(viewModel)
                .environmentObject(settings)
                .environmentObject(HotkeyManager())
                .environmentObject(PinManager())
            try await render(window, size: CGSize(width: 800, height: 600), dark: dark,
                             name: "sct-\(dark ? "dark" : "light")-basicwindow.png", titled: true) {
                NotificationCenter.default.post(name: .selectClipboardItem, object: selected.persistentModelID)
            }
        }
    }

    func testMenuBar() async throws {
        for dark in [true, false] {
            let menu = MenuBarView()
                .environmentObject(viewModel)
                .environmentObject(settings)
                .environmentObject(viewModel.getClipboardManager())
            try await render(menu, size: CGSize(width: 350, height: 400), dark: dark,
                             name: "sct-\(dark ? "dark" : "light")-menubar.png")
        }
    }

    func testCategoriesSettings() async throws {
        let settingsSchema = Schema([HotkeyConfig.self, ExcludedApp.self, PinnedItemConfig.self])
        let settingsStore = try ModelContainer(
            for: settingsSchema,
            configurations: [ModelConfiguration("LandingScreenshotsSettings", schema: settingsSchema, isStoredInMemoryOnly: true)])
        for dark in [true, false] {
            let page = SettingsView(updater: nil, initialSection: .categories)
                .environmentObject(settings)
                .environmentObject(HotkeyManager())
                .environmentObject(viewModel)
                .environmentObject(PinManager())
                .modelContainer(settingsStore)
            try await render(page, size: CGSize(width: 760, height: 640), dark: dark,
                             name: "sct-\(dark ? "dark" : "light")-categories.png", titled: true)
        }
    }

    // MARK: - Rendering

    /// Hosts `view` in an off-screen window, lets it settle (onAppear,
    /// async loads), and writes what it draws as a PNG at 2×.
    private func render(
        _ view: some View, size: CGSize, dark: Bool, name: String, titled: Bool = false,
        afterAppear: () -> Void = {}
    ) async throws {
        let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let window = ActiveLookingWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        if !titled {
            // Panels draw their own rounded background.
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(\.controlActiveState, .key))
        if titled { host.sceneBridgingOptions = [.toolbars, .title] }
        window.contentView = host
        // On a real screen (Retina backing, normal rendering), behind every
        // other window for the second it takes.
        if let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.minY + 40))
        }
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }

        try await Task.sleep(for: .milliseconds(600))
        afterAppear()
        try await Task.sleep(for: .milliseconds(900))
        host.layoutSubtreeIfNeeded()

        let url = outputDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        // Retina screen first: the capture is at the screen's scale.
        let captured: Bool
        if ProcessInfo.processInfo.environment["STONE_SCREENSHOTS_EXTERNAL"] == "1" {
            captured = try await waitForExternalCapture(of: window, to: url)
        } else {
            captured = try Self.captureWindow(window, to: url)
        }
        if !captured {
            // No window capture (Screen Recording not allowed): draw the
            // layer tree instead; close, with small artifacts on strokes.
            NSLog("LandingScreenshots: window capture failed for %@, drawing layers", name)
            let target: NSView = titled ? (host.superview ?? host) : host
            try Self.snapshot(of: target).write(to: url)
        }
    }

    /// `scripts/screenshots.sh` watches for `<name>.wid`, runs
    /// `screencapture -l` on that window from the terminal (which holds the
    /// Screen Recording permission) and writes `<name>`.
    private func waitForExternalCapture(of window: NSWindow, to url: URL) async throws -> Bool {
        let request = url.appendingPathExtension("wid")
        try String(window.windowNumber).write(to: request, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: request) }
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(200))
            if let image = NSImage(contentsOf: url), image.size.width > 0 { return true }
        }
        return false
    }

    /// The window as the window server composites it (`screencapture -l`),
    /// without its shadow. False when the capture didn't produce an image.
    static func captureWindow(_ window: NSWindow, to url: URL) throws -> Bool {
        try? FileManager.default.removeItem(at: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let image = NSImage(contentsOf: url) else { return false }
        return image.size.width > 0
    }

    /// What AppKit draws for the view at 2×: no window chrome effects and
    /// small artifacts on rounded outlines, only a fallback.
    static func snapshot(of view: NSView) throws -> Data {
        let bounds = view.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    // MARK: - Made-up data

    static let documentsRule: ItemCategory = {
        var rule = ItemCategory.newRegex()
        rule.id = "screenshots-documents"
        rule.name = "Documents"
        rule.pattern = #"№\s*\d+/\d{4}"#
        rule.icon = .emoji("📄")
        rule.colorHex = "#FFD60A"
        return rule
    }()

    static let browsersGroup: ItemCategory = {
        var group = ItemCategory.newAppGroup()
        group.id = "screenshots-browsers"
        group.name = "Browsers"
        group.appBundleIDs = ["com.apple.Safari"]
        group.appNames = ["Safari"]
        group.icon = .symbol("safari")
        return group
    }()
}

/// Draws as the key window (colored traffic lights, accent selections, on
/// switches) without the test host taking focus from the user's apps.
final class ActiveLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// A plausible history: text, links, code, a document number, titled
/// favorites, images with recognized text and a QR code, files.
@MainActor
enum MockHistory {
    static func fill(_ context: ModelContext, ruleset: ContentClassifier.Ruleset) throws {
        let now = Date()
        func add(_ item: CBItem, ago: TimeInterval, app: String?, appName: String? = nil,
                 title: String? = nil, favorite: Int? = nil, image: ImageClassifier.Result? = nil) {
            item.timestamp = now.addingTimeInterval(-ago)
            item.title = title
            if let favorite {
                item.isFavorite = true
                item.orderIndex = favorite
            }
            item.sourceAppBundleID = app
            item.sourceAppName = appName
            item.classify(with: ruleset, image: image)
            context.insert(item)
        }
        func text(_ content: String) -> CBItem { CBItem(timestamp: now, content: content, itemType: .text) }

        add(text("brew install stone-clipboarder-tool"), ago: 8, app: "com.apple.Terminal", appName: "Terminal")
        add(CBItem(timestamp: now, imageData: try screenshotImage(), itemType: .image), ago: 95,
            app: "com.apple.Safari", appName: "Safari",
            image: ImageClassifier.Result(
                recognizedText: "Release notes 1.10.0\nhttps://foxfollow.github.io/Stone-Clipboarder-Tool/",
                foundText: true, ranVisual: true))
        add(text("Dear team, please find the signed contract attached. I'll be in the office tomorrow."),
            ago: 260, app: "com.apple.mail", appName: "Mail", title: "Reply to the bank", favorite: 0)
        add(text("№ 9351/2026 від 19.05.2026"), ago: 410, app: "com.apple.Notes", appName: "Notes")
        add(text("git remote add origin https://github.com/foxfollow/Stone-Clipboarder-Tool.git"),
            ago: 640, app: "com.apple.Terminal", appName: "Terminal")
        add(CBItem(timestamp: now, imageData: try qrImage("https://foxfollow.github.io/Stone-Clipboarder-Tool/"),
                   itemType: .image), ago: 900, app: "com.apple.Safari", appName: "Safari",
            image: ImageClassifier.Result(keys: ["barcode"], payloads: ["https://foxfollow.github.io/Stone-Clipboarder-Tool/"], ranVisual: true))
        add(text("~/Projects/StoneClipboarderTool/docs/index.html"), ago: 1500, app: "com.apple.Terminal", appName: "Terminal")
        add(text("Привіт! Нагадую про зустріч завтра о 10:00 у переговорній на третьому поверсі."),
            ago: 2400, app: "com.apple.Notes", appName: "Notes", title: "Meeting reminder (UA)", favorite: 1)
        add(CBItem(timestamp: now, fileData: Data(repeating: 1, count: 5_120), fileName: "invite.ics",
                   fileUTI: "com.apple.ical.ics", itemType: .file), ago: 3600, app: "com.apple.mail", appName: "Mail")
        add(text(#"{"version": "1.10.0", "build": 25, "categories": true}"#), ago: 5400, app: "com.apple.Terminal", appName: "Terminal")
        add(text("hello@stone.example"), ago: 7200, app: "com.apple.Safari", appName: "Safari")
        add(text("+380 44 123 45 67"), ago: 9000, app: "com.apple.Notes", appName: "Notes")

        // Older filler, so the counts look like a lived-in history.
        let filler = [
            "https://developer.apple.com/documentation/vision", "let total = items.reduce(0, +)",
            "Thanks, that works for me!", "Дякую, отримав документи.", "№ 1204/2026 від 02.03.2026",
            "/Users/me/Downloads/report.pdf", "Meeting on March 5, 2026 at 3 pm", "support@stone.example",
        ]
        for i in 0..<120 {
            let source = i % 3 == 0 ? ("com.apple.Safari", "Safari") : ("com.apple.Notes", "Notes")
            add(text(filler[i % filler.count] + (i < filler.count ? "" : " #\(i)")),
                ago: 10_000 + Double(i) * 3_600, app: source.0, appName: source.1)
        }
        try context.save()
    }

    /// A window-like picture with a title, for the OCR row.
    static func screenshotImage() throws -> Data {
        try draw(width: 1470, height: 923) { size in
            NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 120, y: 520, width: 520, height: 120), xRadius: 24, yRadius: 24).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 84, weight: .bold), .foregroundColor: NSColor.white,
            ]
            ("Release notes 1.10.0" as NSString).draw(at: NSPoint(x: 120, y: 360), withAttributes: attributes)
        }
    }

    static func qrImage(_ message: String) throws -> Data {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 20, y: 20))
        let cgImage = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        let side = cgImage.width + 160
        return try draw(width: side, height: side) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: side, height: side).fill()
            NSGraphicsContext.current?.cgContext.draw(
                cgImage, in: CGRect(x: 80, y: 80, width: cgImage.width, height: cgImage.height))
        }
    }

    private static func draw(width: Int, height: Int, _ body: (NSSize) -> Void) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body(NSSize(width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
