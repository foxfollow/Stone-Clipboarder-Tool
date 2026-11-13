# Demo mode and landing screenshots

The app can run with a made-up history instead of yours. Use it to show the
app, to try a UI change on realistic data, and to render the landing page
screenshots (`docs/resources/index/sct-*.png`). The site never shows real
clipboard content.

## Quick start

```bash
make demo          # open the app with made-up data
make screenshots   # re-render every landing screenshot (dark + light)
```

Both build a Debug copy of the app into `build/DemoDD` (unsigned, so it isn't
sandboxed and can write the PNGs into `docs/`) and run it from there. The
installed app can keep running: the demo doesn't register global hotkeys,
watch the clipboard, add a menu bar item, restore pins, check for updates or
touch your history and preferences.

`make screenshots` needs **Screen Recording** permission for the terminal it
runs in (System Settings → Privacy & Security → Screen & System Audio
Recording). Without it each capture fails with "Could not capture …" and the
tour gives up on that screen after 30 seconds.

## How it works

| Piece | What it does |
| --- | --- |
| `AppEnvironment.isDemo` | True with `--demo` or `--screenshots <dir>` on the command line. |
| `AppEnvironment.settingsDefaults` | A fresh `d3f0ld.StoneClipboarderTool.demo` UserDefaults suite in a demo (wiped at launch, preset by `DemoData.presetSettings`), `.standard` otherwise. `SettingsManager` reads it. |
| `ModelContainerFactory` | In-memory clipboard and settings stores in a demo. |
| `VaultManager.makeForApp` | A Passwords vault in a throwaway folder with in-memory keys (`makeInert`), opened by `DemoAuthenticator` without a prompt and filled by `DemoData.fillVault` with made-up entries (a bank login, a token, a 2FA QR, a key file, a server password). The demo never reads or writes the Keychain or the real vault. |
| `AppDelegate.setUpDemo` | Fills the store with `DemoData.fill`, adds the demo categories, wires only what the screens need, and starts the tour for `--screenshots`. |
| `Helper/DemoData.swift` | The made-up history: text, links, code, a document number, two titled favorites, an image with recognized text, a QR code, a file, a Ukrainian note, 120 older filler rows, source apps (Apple apps, so their icons show), the "Documents" regex rule and the "Browsers" app group. Image results are given, not computed, so the demo starts instantly and looks the same every run. |
| `Helper/ScreenshotTour.swift` | For each of dark and light: the main window (800×600, the image item selected), the Quick Picker, the Quick Picker on the Passwords tab (`sct-*-passwords.png`; the tour puts that tab first for one shot), the menu bar view and Settings → Categories. For each it writes `<name>.wid` with the window number and waits for `<name>` to appear, then quits the app. |
| `scripts/screenshots.sh` | Builds, runs the app with `--screenshots`, and turns every `.wid` request into a PNG with `screencapture -x -o -l <window>` (the window as the window server draws it, no shadow, at the screen's scale). |

The app can't capture its own windows without Screen Recording, and asking
for that permission for an unsigned build would mean a new prompt after every
build. The terminal usually has it already, so the script captures instead.

## Running it by hand

```bash
scripts/screenshots.sh                  # into docs/resources/index
scripts/screenshots.sh /tmp/shots       # somewhere else, e.g. to compare first
scripts/screenshots.sh --demo           # same as make demo

# or the built app directly
build/DemoDD/Build/Products/Debug/StoneClipboarderTool.app/Contents/MacOS/StoneClipboarderTool --demo
```

Windows of the demo appear on screen for a few seconds during the tour; don't
type into them. On a Retina screen the PNGs come out at 2×.

## Changing it

- **Different data:** edit `DemoData.fill` and `DemoData.vaultEntries`
  (keep them plausible and free of anything personal or real secrets). `DemoDataTests` checks it still covers every kind of
  row.
- **Another screen:** add a step to `ScreenshotTour.run` that shows a window,
  waits `settle`, then calls `capture(window, "sct-<scheme>-<name>.png")`.
  Add the image to the App Preview section of `docs/index.html` and
  `docs/index-ua.html` (`data-light-src` / `data-dark-src`).
- **Window sizes:** set in each tour step (main window 800×600, Settings
  760×640, menu bar 350×400; the Quick Picker uses its own size).

After `make screenshots`, look at the PNGs before committing them: they show
the current UI, so a half-finished change ends up on the site.

## Safety

- The demo only runs with the launch arguments; a normal launch, `make run`,
  `make install` and releases never enter it.
- Unit tests never run as a demo (`DemoDataTests` checks this).
- Demo settings live in their own suite, demo items only in memory: quitting
  the demo leaves nothing behind except the suite's plist, which is wiped at
  the next demo launch.
