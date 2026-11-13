# Code map

Where things live and how they connect. Rules are in
[AGENTS.md](../AGENTS.md). Paths are relative to `StoneClipboarderTool/`.

## Startup and wiring

```text
StoneClipboarderToolApp (App)
├── @StateObject CBViewModel ............ owns ClipboardManager
├── @StateObject SettingsManager
├── @StateObject MenuBarManager
├── @StateObject HotkeyManager
├── @StateObject QuickPickerWindowManager  owns TypePaster, QPQuickLookCoordinator, QPCustomPreviewManager
├── @StateObject PinManager ............. one PinWindowController (NSPanel) per pin
├── @StateObject VaultManager ........... the Passwords vault (VaultManager.makeForApp)
├── clipboardContainer / settingsContainer (ModelContainerFactory)
└── body → registerWithAppDelegate() → AppDelegate.performSetup()  (runs once)
```

`performSetup()` hands out the contexts and dependencies:

| Object | Gets |
| --- | --- |
| CBViewModel | clipboard `mainContext` (also given to its ClipboardManager), SettingsManager |
| ClipboardManager | settings `mainContext`, for excluded-app lookups |
| HotkeyManager | settings `mainContext`, CBViewModel, SettingsManager, PinManager; its `quickPickerDelegate` is QuickPickerWindowManager |
| QuickPickerWindowManager | CBViewModel, SettingsManager, PinManager, a menu bar refresh callback |
| PinManager | CBViewModel, SettingsManager, settings `mainContext`; then observes deletes and restores saved pins |
| VaultManager | SettingsManager, ClipboardManager (for pasting); then observes screen lock / sleep; handed to QuickPickerWindowManager |

Then it cleans old Quick Look sessions, loads hotkeys, applies menu bar and
window visibility, installs the ⌘Q monitor, and on the next main-queue turn
loads the first history rows. Under unit tests it returns before all of
this (`AppEnvironment.isRunningUnitTests`). In demo mode (`--demo`,
`--screenshots`) it calls `setUpDemo` instead: in-memory stores filled by
`DemoData`, a separate UserDefaults suite, no monitoring, hotkeys, menu bar
item or pins, and the `ScreenshotTour` when asked (docs/DEMO_MODE.md).

## Files

### Manager/

| File | Owns / does | Talks to |
| --- | --- | --- |
| ClipboardManager | 0.5 s pasteboard poll; capture rules (`captureKinds`); the frontmost app as `CaptureSource` (when `recordSourceApp`); size check and background read of copied files; writes items back to the pasteboard, recording `changeCount` so its own writes aren't captured; pause timer; Save to File | CBViewModel via `onClipboardChange`; SettingsManager; `ExcludedApp` |
| HotkeyManager | Loads `HotkeyConfig`, registers Carbon hotkeys through `HotkeyShortcut`, runs the actions | CBViewModel (`copyAndUpdateItem`), PasteSimulator, QuickPickerDelegate, PinManager |
| QuickPickerWindowManager | The non-activating `KeyCapturingPanel` hosting QuickPickerView; focus and key routing; click-outside/Esc; Quick Look vs custom preview; session-only position | CBViewModel, SettingsManager, PinManager, TypePaster |
| TypePaster | ⌘⇧⏎ type-out: `KeyboardLayoutTables` maps characters to real key codes (active layout plus ASCII fallback, no keypad keys) and presses modifiers as real keys; Esc cancels | CGEvent |
| PinManager | Pin lifecycle: FIFO cap, persistence to `PinnedItemConfig`, restore at launch with a link back to the history item by content, closes pins on `.clipboardItemDeleted`; publishes `pinnedItemIds` and `activePinSnapshots` | CBViewModel (`existingItem(matching:)`), PinWindowController |
| PinWindowController | One floating `PinPanel`: lock, click-through (⌘-hold), opacity, collapse, edge snap; debounced saves of its config | PinManager, PasteboardFileStore, ExternalOpener |
| MenuBarManager | NSStatusItem and the popover hosting MenuBarView; icon follows pause state | CBViewModel, SettingsManager, ClipboardManager |
| SettingsManager | Every user setting (`@Published` + `didSet` → injected UserDefaults); visibility invariant; migrations; login item | — |
| VaultManager | The Passwords vault: lock state, decrypted entries (`VaultPayload`), add with dedupe / rename / move / delete / delete all, sliding unlock window (`VaultLockPolicy`, `vaultRelockMinutes`), locks on screen lock, screen saver, sleep, display sleep, session switch; paste through `ClipboardManager.copySecret`; Touch ID or the Passwords password (`unlock(password:)`, `setPassword`, `removePassword`); fingerprints for `isStoredSecret` (CBViewModel skips such captures) and `onUnlocked` (history copies of entries are deleted) | VaultStore, VaultKeyProvider, VaultAuthenticator, ClipboardManager, SettingsManager |
| VaultKeyProvider | One blob per Keychain item (read / write / delete): the vault key, raw or wrapped (account `vault-key`), and the fingerprint key (account `vault-fingerprint-key`), service `d3f0ld.StoneClipboarderTool.vault`, login keychain; `InMemoryVaultKeyProvider` for tests and demo | Security |
| VaultAuthenticator | `LocalAuthenticationAuthenticator`: Touch ID with password fallback before the key is read | LocalAuthentication |
| ErrorLogger | The only singleton: unified log, optional plaintext file with 5 MB rotation | — |

### Model/

| File | What |
| --- | --- |
| CBItem | `@Model`, clipboard container. External storage: `content`, `imageData`, `fileData`, `thumbnailData`. Inline: `timestamp`, `itemType`, `fileName`, `fileUTI`, `isFavorite`, `orderIndex`, `title` (user-given, optional), `contentPreview` (first 100 characters), `imageSize` ("W×H"), `fileSize`, `categoryKeys` (",link,link.full,…"), `languageCode`, `classificationStamp`, `sourceAppBundleID` / `sourceAppName`, `recognizedText` (what OCR read in an image, ≤10,000 characters) and `barcodeText` (QR / barcode contents from the visual pass), both searched by `matchesSearch`, `textRecognitionState` (OCR not requested / pending for a new image / queued by "Recognize Text in All Images" / no text / found / failed), `visualAnalysisVersion` (the visual pass, apart from the rules stamp; negative = failed; `visualNotApplicable` for items without an image), `imageAnalysisFailures` (failed Vision runs; `retryFailedImageAnalysis` retries failures at launch up to `ImageClassifier.maxRetries`). `classify(with:image:)` holds all image bookkeeping. Also the thumbnail cache (never written during render), `ContentKey` / `hasSameContent` for deduplication, `matchesSearch`, `classify(with:)` |
| ContentClassifier | Finds links, emails, phones, addresses, dates (NSDataDetector), code, JSON, paths, the language (NaturalLanguage) and regex-rule matches in the first 4000 characters; `key` for a match, `key.full` when it covers the whole text. `Ruleset` compiles the rules once and carries the `stamp` |
| ImageClassifier | Vision on a downscaled (2048 px) image, two independent parts: the visual pass (QR codes and barcodes with payloads, faces, transparency) and OCR. `CBItem.classify(with:image:)` stores the text and runs it through ContentClassifier. Synchronous, off the main thread only |
| ItemCategory | A chip: built-in (stable ids `link` … `language`, image ones `ocr`, `barcode`, `face`, `transparent`), regex rule or app group, with match mode, SF Symbol or emoji, color. `builtIns`, `merged(stored:)`, `matches(_:)`, `count(in:)`. JSON in UserDefaults, not a `@Model` |
| ItemFilter | `QPSearchQuery` (is:/app:/lang: tokens + free text, which keeps its spacing), `CategorySelection` and `ChipSelection` (the chips that are on, cursor and anchor for ⌥⇧←/→ and ⇧-click), `ItemFilter.matches`, `FacetCounts` (per-key / language / app counts) |
| HotkeyConfig | `@Model` per `HotkeyAction` (23 actions and their default shortcuts), settings container |
| HotkeyShortcut | Parses and formats shortcut strings; the key table; reserved system shortcuts; Carbon modifier mask |
| PinnedItemConfig | `@Model` pin: content snapshot plus layout and flags, settings container; `contentKey` |
| ExcludedApp | `@Model` bundle id whose copies are ignored, settings container |
| Vault/ | `VaultPayload` (one entry: type, title, content, image, file; dedupe, search, order), `VaultCrypto` ("SCTV" + version + AES-GCM, header and entry id authenticated), `VaultStore` (`<root>/<uuid>.sctv`, owner-only, atomic writes; a file that won't open is counted and kept), `VaultLockPolicy` (sliding unlock window), `VaultFingerprint` (HMAC of an entry's content under its own Keychain key: recognizes a copy of a saved entry while locked), `VaultKeyWrapper` (the vault key wrapped with the optional Passwords password: PBKDF2-HMAC-SHA256 600 000 rounds + AES-GCM), `VaultPasswordRules` |
| Types/ | Persisted enums (`CBItemType`, `ClipboardCaptureMode`, `QuickLookMode`, `QuickLookTriggerKey`, `TimeUnit`) and `ClipboardContent`, the ClipboardManager → CBViewModel handoff |

### ViewModel/CBViewModel.swift

The `CBItem` data path. `items` holds the newest rows (30 at first, 100 per
scroll page, a refresh keeps the loaded depth); `favoriteItems` and the
counts are published too. Inserts go through `insertOrBump`, which finds
duplicates anywhere in the store. It also handles edits, favorites,
two-step deletes, cleanup (item cap and memory), the read-only queries used
by the Quick Picker and search, and opening items in other apps.
Categories: new items are classified in `insertOrBump`, which also stores
the source app; `reclassifyIfNeeded` rescans items whose
`classificationStamp` differs from the current rules (at launch and when a
regex rule changes; images also when "Find QR codes, faces and
transparency" is switched or `ImageClassifier.visualVersion` bumps) in
pages of 100; images go to
`ImageClassifier` four at a time on a utility thread through a throwaway
`ModelContext`, and a new image is left unstamped for that pass; `facetCounts(ofTypes:)` shares the
cached count scan; `searchItems(filter:types:limit:)` applies an
`ItemFilter`; `recognizeTextInAllImages` / `stopTextRecognition` queue or drop OCR for
older images (`pendingTextRecognitionCount` for the progress);
`clearSourceApps` forgets every source app; `rememberRecognizedText` keeps the
user's OCR result (⌥⏎, Extract Text) on the image.

### Helper/

| File | What |
| --- | --- |
| AppEnvironment | `isRunningUnitTests`; `isDemo`, `screenshotsDirectory` and `settingsDefaults` for demo mode (docs/DEMO_MODE.md) |
| DemoData | The made-up history, categories and settings of demo mode |
| ScreenshotTour | `--screenshots`: shows each screen in dark and light and waits for `scripts/screenshots.sh` to capture it |
| AppIconCache | App icons by bundle id for source-app badges |
| AppNotifications | Every `Notification.Name` the app posts |
| SettingsSearchIndex | Every setting the Settings search finds (page, heading, keywords, the `.settingsAnchor` id of its row), plus each hotkey action and category; `search` ranks title matches first |
| ExternalOpener | Temp file + open in Preview / TextEdit / the default app |
| MainWindow | Find and bring forward the "Clipboard History" window |
| PasteSimulator | ⌘V after a delay, or the Accessibility alert |
| PasteboardFileStore | Temp files behind file items on the pasteboard |
| TextRecognizer | Vision OCR |

### View/

| Folder / file | What |
| --- | --- |
| ContentView | Main window: Recent / Favorites, whole-history search, `DetailedCardView` rows, `ClipboardHeader` |
| ZoomView/, Small/ActionsBottomButtonView | Detail pane: text/image/file preview, zoom, copy, edit, open, OCR, delete |
| Menu/ | MenuBarView (popover list of `SwipeableRow`s), MenuBarItemView, PauseTimerView |
| QuickPicker/ | QuickPickerView (keys, tabs, multi-select, paste / OCR / type-out), QPItemList, QPItemRow, QPItemEditorView + QPItemEditorModel (⌥E: title, favorite, favorite order, ⌥K Move to Passwords; renders from a snapshot), QPVaultPane + QPVaultRow (the Passwords tab: lock screen, masked rows, the eye), QPVaultEditorView + QPVaultEditorModel (⌥E on an entry: rename, ⌥↑/⌥↓, ⌥⌫ delete, ⌥R the eye), `QPTab` (raw values stored in `quickPickerTabOrder`, `ordered(_:)`), QPCategoryBar + `QPCategoryChip.chips` (category chips of the active tab), QPQuickLookCoordinator (native Quick Look through temp files), QPCustomPreviewPanel (own panel from a `QPPreviewContent` snapshot, also used over full-screen apps and always for Passwords entries, never written to disk; ⌥Space makes it 85 % of the screen) |
| Pins/ | PinContentView, PinChromeView (+ PinDragArea to move the pin), PinImageView; all render from `PinViewState` |
| Settings/ | `SettingsGroup` headings with `SettingsSection` pages: General (General, Hotkeys, Accessibility), Quick Picker (Quick Picker with QuickPickerTabOrderSection, Categories, Pins), Security (Passwords: PasswordsSettingsView + VaultPasswordSheet, Excluded Apps), About. The sidebar's search field lists `SettingsSearchResults`; a pick scrolls the page (SettingsDetailContainer) to the row's `.settingsAnchor` and highlights it. Pages: Categories (CategoriesSettingsView, CategorySettingsRow, CategoryEditorView sheet, CategoryIconPicker), Pins, Excluded Apps (`@Query` is fine here), Accessibility, About. AppPickerView is shared by Excluded Apps and app groups |
| Components/, Small/, Cells/ | Shared pieces: search bar, swipeable row, alerts, buttons, list cell, CategoryIconView, CategoryChipView |

## Cross-cutting

### Notifications (Helper/AppNotifications.swift)

| Name | Posted by | Observed by |
| --- | --- | --- |
| `.clipboardItemDeleted` | CBViewModel delete paths and cleanup; `object` is the item's `PersistentIdentifier`, `nil` for a wipe | PinManager (closes pins), ContentView (drops search results) |
| `.clearClipboardSelection` | CBViewModel, when the selected item is deleted | ContentView |
| `.selectClipboardItem` | `MainWindow.show(selecting:)` | ContentView |
| `.pinBehaviorSettingsChanged` | SettingsManager (full screen, shadow, corner radius) | PinWindowController |

QuickPickerWindowManager also observes `NSApplication.willResignActiveNotification`
to close the picker when another app takes over, except while the Touch ID
prompt is up (`VaultManager.isAuthenticating`).

### Persistent state

All under `~/Library/Application Support/StoneClipboarderTool/` (inside the
app's container for sandboxed Debug builds).

| What | Where |
| --- | --- |
| Clipboard history | `ClipboardHistory.store`, blobs in `.ClipboardHistory_SUPPORT/` |
| Hotkeys, excluded apps, pins | `Settings.store` |
| Passwords | `Vault/<uuid>.sctv`, sealed; `Vault/fingerprints` (one HMAC per entry); the keys in the login keychain (service `d3f0ld.StoneClipboarderTool.vault`, accounts `vault-key`, raw or password-wrapped, and `vault-fingerprint-key`) |
| Settings | UserDefaults through SettingsManager; keys are the property names. `enableErrorFileLogging` is also read by ErrorLogger; `itemCategories` is a JSON array of `ItemCategory` (fields a newer version wrote are written back unless edited here) |
| Error log | `StoneClipboarder_errors.log` (+ `.old.log`) |

### Temp files

| Purpose | Location | Lifetime |
| --- | --- | --- |
| File items put on the pasteboard | `$TMPDIR/StoneClipboarderTool/Pasteboard/<uuid>/` | until the next file copy; a pasted password file also when the clipboard is cleared |
| Open in Preview / TextEdit / default app | `$TMPDIR/StoneClipboarderTool/Open/<uuid>/` | 60 s |
| Quick Look previews | `Application Support/StoneClipboarderTool/Previews/Session_<uuid>/` | 10 min; all removed at quit |

### Timers

| Timer | Owner | Interval |
| --- | --- | --- |
| Clipboard poll | ClipboardManager | 0.5 s |
| End of a pause | ClipboardManager | the pause length |
| Memory cleanup | CBViewModel | `memoryCleanupInterval` minutes |
| Activation-policy re-checks | AppDelegate | 1, 3, 6, 10 and 20 s after launch |
| ⌘Q hold / double tap | AppDelegate | 1.0 s / 0.4 s |
| Pin save debounce | PinWindowController | 0.25 s |
| Vault expiry check | VaultManager | 30 s, while unlocked |
| Clear a pasted password | ClipboardManager | `vaultClipboardClearSeconds` (30 s) |
| Accessibility status refresh | AccessibilitySettingsView | 2 s, while shown |

### Event monitors

| Monitor | Where | Installed |
| --- | --- | --- |
| ⌘Q down / up (local) | AppDelegate | app lifetime / while ⌘Q is held |
| Esc cancels type-out (global + local) | TypePaster | while typing |
| Click outside, Esc (global); key re-routing (local) | QuickPickerWindowManager | while the picker is open |
| Tab, ⇧Tab, ⌘1…⌘9 (tabs), ⌥P, ⌥⏎, ⌥E, ⌥L and ⌥R (unlocked Passwords tab; ⌥ letters pass through while its password is typed), ⌥←/⌥→ and ⌥⇧←/⌥⇧→ (category chips, only while there are chips); in the ⌥E editors ⏎, Esc, ⌥F, ⌥K, ⌥R, ⌥↑/⌥↓, ⌥⌫ (local) | QuickPickerView `TabKeyInterceptor` | while the picker is open |
| Screen lock, screen saver (distributed); sleep, display sleep, session switch (workspace) | VaultManager | app lifetime |
| ⌘ held over click-through pins (global + local) | PinWindowController | while click-through is on |
| ⌘C / ⌘W in a pin (local) | PinContentView `CommandKeyHandler` | while the pin is in a window |
| Pinch zoom (local; ⌘-scroll via PinScrollView) | PinImageView | image pins |
| Shortcut recording (local + global) | HotkeySettingsView | while recording |
| Two-finger swipe (local) | SwipeableRow | while the row is in a window |

## Where to change…

- **A setting.** Property in SettingsManager (default read in `init`) →
  control in the matching Settings view, with `.settingsAnchor("page.name")`
  → an entry with that anchor in `SettingsSearchIndex` (title, heading,
  keywords) → the code that uses it, reading SettingsManager. Test it with
  `IsolatedDefaults`.
- **A Settings page.** `SettingsSection` case (group, title, subtitle,
  symbol; cases are in sidebar order) → `SettingsDetail` → its entries in
  `SettingsSearchIndex`.
- **A clipboard item type.** `CBItemType` case (symbol, color) →
  `ClipboardManager` capture and `copyItemToClipboard` → CBItem
  (`hasSameContent`, `ContentKey`, `matchesSearch`, `displayContent`,
  `thumbnail`) → rows (QPItemRow, BarNavigationCellView, MenuBarItemView)
  and the detail pane → `PinnedItemConfig` / `PinViewState` if pinnable.
- **A hotkey action.** `HotkeyAction` case (raw value, `displayName`,
  `defaultShortcut`, `index`) → the switch in
  `HotkeyManager.registerHotkey(_:for:)` → a row in HotkeySettingsView.
  Existing installs get the new row from `ensureMissingHotkeyConfigs`.
- **The Passwords vault.** Format in `VaultCrypto` (bump `version` and keep
  reading the old one), entry fields in `VaultPayload` (optional, so old
  files decode), behavior in `VaultManager`, keys in QuickPickerView's
  Passwords section and `TabKeyInterceptor`. Test with
  `InMemoryVaultKeyProvider`, a stub `VaultAuthenticator` and a scratch
  `VaultStore(root:)`.
- **A Quick Picker tab.** `QPTab` case (new raw value, `itemTypes`, title, count; stored orders get it at the end) →
  `QuickPickerView.reloadForActiveTab` → a CBViewModel query if the tab
  needs one.
- **A built-in category.** `ItemCategory.BuiltIn` case and an entry in
  `builtIns` (new installs and old ones get it via `merged(stored:)`) →
  detection in `ContentClassifier.classify` → bump
  `ContentClassifier.version` so stored items are rescanned →
  `CategorySettingsRow.builtInDescription`.
- **The landing screenshots.** Data in `DemoData`, screens in
  `ScreenshotTour` → `make screenshots` (`scripts/screenshots.sh`) →
  `docs/resources/index/sct-*.png` → the App Preview cards in
  `docs/index*.html`. See docs/DEMO_MODE.md.
- **A pin option.** Default in SettingsManager (`pin…`) → per-pin field in
  `PinnedItemConfig` → `PinViewState` → PinChromeView / PinWindowController →
  PinSettingsView.
- **A `@Model`.** Add it to the right `Schema` in `ModelContainerFactory`
  and hand that container's context to whoever uses it.
