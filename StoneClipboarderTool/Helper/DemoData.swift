//
//  DemoData.swift
//  StoneClipboarderTool
//
//  The made-up history and settings behind demo mode (`--demo`,
//  `--screenshots`) and the landing page screenshots. Nothing here is real
//  clipboard content. See docs/DEMO_MODE.md.
//

import AppKit
import CoreImage
import SwiftData

@MainActor
enum DemoData {
    nonisolated static let defaultsSuite = "d3f0ld.StoneClipboarderTool.demo"

    /// A custom rule and an app group, so Settings → Categories and the chip
    /// row show both kinds.
    static let documentsRule: ItemCategory = {
        var rule = ItemCategory.newRegex()
        rule.id = "demo-documents"
        rule.name = "Documents"
        rule.pattern = #"№\s*\d+/\d{4}"#
        rule.icon = .emoji("📄")
        rule.colorHex = "#FFD60A"
        return rule
    }()

    static let browsersGroup: ItemCategory = {
        var group = ItemCategory.newAppGroup()
        group.id = "demo-browsers"
        group.name = "Browsers"
        group.appBundleIDs = ["com.apple.Safari"]
        group.appNames = ["Safari"]
        group.icon = .symbol("safari")
        return group
    }()

    /// Settings a demo starts with: the main window on, no menu bar item,
    /// no first-launch prompt, the two extra categories.
    nonisolated static func presetSettings(in defaults: UserDefaults) {
        defaults.set(true, forKey: "showMainWindow")
        defaults.set(false, forKey: "showInMenubar")
        defaults.set(true, forKey: "hasShownAutoStartPrompt")
        defaults.set(false, forKey: "closeOtherWindowsOnQuickPicker")
        defaults.set(false, forKey: "enableHotkeys")
    }

    static func addCategories(to settings: SettingsManager) {
        settings.saveCategory(documentsRule)
        settings.saveCategory(browsersGroup)
    }

    /// Text, links, code, a document number, titled favorites, images with
    /// recognized text and a QR code, a file, and older filler so the counts
    /// look lived in. Image results are given, not computed, so the demo
    /// starts instantly and looks the same every time.
    static func fill(_ context: ModelContext, ruleset: ContentClassifier.Ruleset, now: Date = Date()) throws {
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
        let siteURL = "https://foxfollow.github.io/Stone-Clipboarder-Tool/"

        add(text("brew install stone-clipboarder-tool"), ago: 8, app: "com.apple.Terminal", appName: "Terminal")
        add(CBItem(timestamp: now, imageData: screenshotImage(), itemType: .image), ago: 95,
            app: "com.apple.Safari", appName: "Safari",
            image: ImageClassifier.Result(
                recognizedText: "Release notes 1.11.0\n\(siteURL)", foundText: true, ranVisual: true))
        add(text("Dear team, please find the signed contract attached. I'll be in the office tomorrow."),
            ago: 260, app: "com.apple.mail", appName: "Mail", title: "Reply to the bank", favorite: 0)
        add(text("Звіт за квартал — до 19.05.2026"), ago: 410, app: "com.apple.Notes", appName: "Notes")
        add(text("git remote add origin https://github.com/foxfollow/Stone-Clipboarder-Tool.git"),
            ago: 640, app: "com.apple.Terminal", appName: "Terminal")
        add(CBItem(timestamp: now, imageData: qrImage(siteURL), itemType: .image), ago: 900,
            app: "com.apple.Safari", appName: "Safari",
            image: ImageClassifier.Result(keys: ["barcode"], payloads: [siteURL], ranVisual: true))
        add(text("~/Projects/StoneClipboarderTool/docs/index.html"), ago: 1500, app: "com.apple.Terminal", appName: "Terminal")
        add(text("Привіт! Нагадую про зустріч завтра о 10:00 у переговорній на третьому поверсі."),
            ago: 2400, app: "com.apple.Notes", appName: "Notes", title: "Meeting reminder (UA)", favorite: 1)
        add(CBItem(timestamp: now, fileData: Data(repeating: 1, count: 5_120), fileName: "invite.ics",
                   fileUTI: "com.apple.ical.ics", itemType: .file), ago: 3600, app: "com.apple.mail", appName: "Mail")
        add(text(#"{"version": "1.11.0", "build": 27, "passwords": true}"#), ago: 5400, app: "com.apple.Terminal", appName: "Terminal")
        add(text("hello@stone.example"), ago: 7200, app: "com.apple.Safari", appName: "Safari")
        add(text("+380 44 123 45 67"), ago: 9000, app: "com.apple.Notes", appName: "Notes")

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

    // MARK: - Passwords

    /// Made-up Passwords entries (no real secret anywhere): logins and a
    /// token with their own icons and colors, a 2FA QR code and a key file. The demo vault lives
    /// in memory with in-memory keys; the demo unlocks it without a prompt.
    static let vaultEntries: [VaultPayload] = [
        VaultPayload(itemType: .text, title: "Bank login", content: "Demo-Pass-2026!",
                     icon: .symbol("building.columns"), colorHex: "#0A84FF"),
        VaultPayload(itemType: .text, title: "GitHub token", content: "ghp_DEMO0000000000000000000000000000demo",
                     icon: .symbol("chevron.left.forwardslash.chevron.right"), colorHex: "#BF5AF2"),
        VaultPayload(itemType: .image, title: "2FA recovery QR",
                     imageData: qrImage("otpauth://totp/Stone:demo@stone.example?secret=DEMODEMODEMODEMO"),
                     icon: .emoji("🔐")),
        VaultPayload(itemType: .file, title: "Deploy key",
                     fileData: Data("-----BEGIN DEMO KEY-----\nnot a real key\n-----END DEMO KEY-----\n".utf8),
                     fileName: "deploy_key.pem", fileUTI: "public.x509-certificate"),
        VaultPayload(itemType: .text, title: "Server root password", content: "demo-root-0000",
                     icon: .symbol("server.rack"), colorHex: "#FF9F0A"),
    ]

    /// Unlocks the demo vault and fills it. Only for the inert demo vault.
    static func fillVault(_ vault: VaultManager) async {
        guard await vault.unlock(reason: "show the demo passwords") else { return }
        for entry in vaultEntries {
            _ = vault.add(entry)
        }
    }

    // MARK: - Pictures

    /// A dark window-like picture with a title, for the OCR row.
    static func screenshotImage() -> Data {
        draw(width: 1470, height: 923) { size in
            NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 120, y: 520, width: 520, height: 120), xRadius: 24, yRadius: 24).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 84, weight: .bold), .foregroundColor: NSColor.white,
            ]
            ("Release notes 1.11.0" as NSString).draw(at: NSPoint(x: 120, y: 360), withAttributes: attributes)
        }
    }

    static func qrImage(_ message: String) -> Data {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return Data() }
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 20, y: 20)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return Data() }
        let side = cgImage.width + 160
        return draw(width: side, height: side) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: side, height: side).fill()
            NSGraphicsContext.current?.cgContext.draw(
                cgImage, in: CGRect(x: 80, y: 80, width: cgImage.width, height: cgImage.height))
        }
    }

    private static func draw(width: Int, height: Int, _ body: (NSSize) -> Void) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body(NSSize(width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
