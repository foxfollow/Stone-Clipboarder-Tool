# AGENTS.md

Rules and orientation for anyone — person or coding agent — changing this
repository. Where things live and how they connect:
[docs/CODEMAP.md](docs/CODEMAP.md). Manual checks:
[TESTING_GUIDE.md](TESTING_GUIDE.md).

## What this is

Stone Clipboarder Tool is a macOS 15+ clipboard history manager written in
SwiftUI and SwiftData. It watches the pasteboard and keeps the history on
the Mac. People reach it through the menu bar, a main window, global
hotkeys, a floating Quick Picker and floating pinned windows. Sparkle 2.9
(Swift Package) handles updates, Vision does on-device OCR, Carbon registers
global hotkeys and CGEvent posts the paste keystrokes.

## Iron rules

1. **On-device only.** No cloud sync, telemetry, analytics or network calls
   besides Sparkle's update feed. This is the product's promise and part of
   the shipped privacy policy. The `network.client` entitlement exists for
   Sparkle; keep it.
2. **Never log clipboard content.** The ErrorLogger file is plaintext. Log
   metadata only: item type, counts, error descriptions.
3. **Never commit Sparkle keys.** CI signs updates with the
   `SPARKLE_PRIVATE_KEY` secret.
4. **A new `@Model` goes into the right container's `Schema`** in
   `ModelContainerFactory` (StoneClipboarderToolApp.swift). `CBItem` lives in
   the clipboard container; `HotkeyConfig`, `ExcludedApp` and
   `PinnedItemConfig` live in the settings container. The wrong container
   fails at runtime (crash or silently empty fetches), not at compile time.
5. **Every SwiftData save rolls back on failure:**
   `do { try context.save() } catch { context.rollback(); ErrorLogger.shared.log(…) }`.
   A failed save that isn't rolled back poisons every later save.
6. **CBViewModel is the only data path for `CBItem`.** Views read its
   published `items` / `favoriteItems` and its queries (`historyPage`,
   `items(ofTypes:)`, `searchItems`, `existingItem(matching:)`,
   `itemTypeCounts()`). Mutations end with `fetchItems(reset: true)`. No
   `@Query` for `CBItem` and no fetches in views; `@Query` is fine for
   settings-container models in settings views.
7. **Deleting is two steps.** Post `.clipboardItemDeleted`, drop the item
   from every array a view renders, and only on the next main-queue turn
   delete it from the context (see `CBViewModel.deleteItem`). A view that
   still holds a deleted model crashes with "backing data was detached".
8. **Pins render from snapshots.** Never read `PinnedItemConfig`'s
   external-storage fields in a SwiftUI body; `PinViewState` copies them
   once.

## Build and test

Prefer the XcodeBuildMCP tools when they are connected (`build_macos` to
compile, `test_macos` to test). Otherwise:

```bash
xcodebuild -project StoneClipboarderTool.xcodeproj -scheme StoneClipboarderTool \
  -configuration Debug -destination "platform=macOS" build

xcodebuild test -project StoneClipboarderTool.xcodeproj -scheme StoneClipboarderTool \
  -destination "platform=macOS"

# a single class or test
xcodebuild test -project StoneClipboarderTool.xcodeproj -scheme StoneClipboarderTool \
  -destination "platform=macOS" -only-testing:StoneClipboarderToolTests/CBViewModelListTests
```

- Building needs Xcode 26: the app icon is an Icon Composer file and some
  views use macOS 26 APIs behind `#available`.
- Don't quit or relaunch a running copy of the app without asking its
  owner.
- Tests run inside the app (TEST_HOST). `AppEnvironment.isRunningUnitTests`
  keeps that host inert: in-memory stores, no clipboard monitoring,
  hotkeys, menu bar item, pins or Sparkle. In tests, create your own
  in-memory `ModelContainer`, use `IsolatedDefaults` with
  `SettingsManager(defaults:)`, and pass a scratch `root` to
  `PasteboardFileStore`. Never write `UserDefaults.standard` or real
  Application Support / temp folders: an unsigned test run is unsandboxed
  and would change the installed app's data.
- Unit tests cover models and enums, `HotkeyShortcut`, the capture rules,
  CBViewModel (list paging, deduplication, queries, cleanup), pin linking,
  settings and the type-out key tables. Clipboard, windows, hotkeys and
  synthetic key events are checked by hand with TESTING_GUIDE.md.

## Architecture in one screen

- `StoneClipboarderToolApp` creates the shared objects as `@StateObject`s
  and hands them to `AppDelegate` while SwiftUI evaluates `App.body`.
  `AppDelegate.performSetup()` runs once, wires everything with `set*`
  calls and starts it. That is the single wiring point: no singletons
  besides `ErrorLogger`.
- Views receive four shared objects through `.environmentObject`:
  `CBViewModel`, `SettingsManager`, `HotkeyManager`, `PinManager`.
- Two SwiftData containers: clipboard history (high churn, reset if the
  store is corrupt) and settings (must survive).
- The Dock icon follows "Show Main Window". `applicationDidFinishLaunching`
  re-applies the activation policy and `startGuardingActivationPolicy`
  undoes late LaunchServices resets during login-item launches. Keep both,
  or the Dock icon comes back after a restart.

## Conventions

- **Concurrency.** Everything UI-facing is `@MainActor`: CBViewModel, every
  manager, AppDelegate, helpers that touch AppKit. SwiftData's
  `mainContext` is main-thread only. Timers on the main run loop enter with
  `MainActor.assumeIsolated`; background work returns with
  `Task { @MainActor in }` or by awaiting a main-actor method. Timers and
  event monitors owned by `@MainActor` classes are `nonisolated(unsafe)` so
  `deinit` can release them.
- **Settings.** Add `@Published var foo: T { didSet { defaults.set(…) } }` to
  `SettingsManager` and read the default in `init`, always through the
  injected `defaults`. No `@AppStorage` for app settings: the managers
  observe `SettingsManager` and wouldn't see the change.
- **Persisted enums** (`Model/Types/`) have raw `String` values and a
  `displayName`. Never rename or reorder a shipped raw value.
- **Hotkeys.** Shortcut strings (`HotkeyConfig.shortcutKeys`) go through
  `HotkeyShortcut`, the one key table shared by recording and registration.
- **Logging.** `ErrorLogger.shared.log(_:category:error:)` for errors
  (unified log, plus the file when enabled) and `.debug(_:category:)` for
  diagnostics. No `print`.
- **Views.** One `struct Foo: View` per file in its feature folder under
  `View/`; no `func makeFoo() -> some View` helpers for standalone views.
  Shared pieces go in `View/Components` or `View/Small`, non-view helpers
  in `Helper/`.
- **Notifications.** Names live in `Helper/AppNotifications.swift`.
- **Temp files.** Files put on the pasteboard go through
  `PasteboardFileStore`, "open in another app" through `ExternalOpener`,
  previews through `QPQuickLookCoordinator`. Don't write clipboard content
  anywhere else.
- **The 0.5 s poll.** `ClipboardManager.checkClipboard()` must stay cheap
  until `changeCount` changes. Decode images, run OCR or read files only
  after a confirmed change, and read large files off the main thread.

## Repo traps

- `.gitignore` ignores root-level `test*` (anchored on purpose: macOS
  clones compare case-insensitively). `*.xcscheme` is ignored, so CI builds
  with xcodebuild's generated scheme.
- `CLAUDE.md`, `CLAUDE.local.md`, `GEMINI.md`, `*hint-note.md` and
  `buildServer.json` are gitignored local notes. Rules everyone needs go
  here.
- **Sandbox differs between builds.** Debug builds signed by Xcode apply
  the entitlements: sandboxed, data under
  `~/Library/Containers/d3f0ld.StoneClipboarderTool/`. Release builds are
  compiled unsigned in CI and ad-hoc signed without entitlements: not
  sandboxed, data in `~/Library/Application Support/StoneClipboarderTool/`.
  Changing signing or entitlements moves user data and needs a migration
  plan.
- Favorites have had no drag-to-reorder UI since Dec 2025. Their order is
  the order they were favorited (`orderIndex`), which ⌃⇧1…0 follow.

## Releasing

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in both build
   configurations of `project.pbxproj`.
2. Write the release bullets once, as `<li>` lines inside a `<new>…</new>`
   block right after `</language>` in `docs/appcast.xml` (template:
   `docs/next_appcast.md`). Mirror them in README's "New in Version" block
   (latest release only) and a new top card in `docs/version-history.html`.
3. Merge, then push the tag `vX.Y.Z`. `.github/workflows/release.yml`
   builds, signs, publishes the GitHub release, turns the `<new>` block into
   the appcast item and updates the Homebrew tap. It refuses a tag that
   differs from `MARKETING_VERSION`, or a build number that isn't above the
   newest one in the appcast.
