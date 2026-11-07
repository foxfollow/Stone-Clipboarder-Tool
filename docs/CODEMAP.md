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

Then it cleans old Quick Look sessions, loads hotkeys, applies menu bar and
window visibility, installs the ⌘Q monitor, and on the next main-queue turn
loads the first history rows. Under unit tests it returns before all of
this (`AppEnvironment.isRunningUnitTests`).

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
| ErrorLogger | The only singleton: unified log, optional plaintext file with 5 MB rotation | — |

### Model/

| File | What |
| --- | --- |
| CBItem | `@Model`, clipboard container. External storage: `content`, `imageData`, `fileData`, `thumbnailData`. Inline: `timestamp`, `itemType`, `fileName`, `fileUTI`, `isFavorite`, `orderIndex`, `title` (user-given, optional), `contentPreview` (first 100 characters), `imageSize` ("W×H"), `fileSize`, `categoryKeys` (",link,link.full,…"), `languageCode`, `classificationStamp`, `sourceAppBundleID` / `sourceAppName`. Also the thumbnail cache (never written during render), `ContentKey` / `hasSameContent` for deduplication, `matchesSearch`, `classify(with:)` |
| ContentClassifier | Finds links, emails, phones, addresses, dates (NSDataDetector), code, JSON, paths, the language (NaturalLanguage) and regex-rule matches in the first 4000 characters; `key` for a match, `key.full` when it covers the whole text. `Ruleset` compiles the rules once and carries the `stamp` |
| ItemCategory | A chip: built-in (stable ids `link` … `language`), regex rule or app group, with match mode, SF Symbol or emoji, color. `builtIns`, `merged(stored:)`, `matches(_:)`, `count(in:)`. JSON in UserDefaults, not a `@Model` |
| ItemFilter | `QPSearchQuery` (is:/app:/lang: tokens + free text), `CategorySelection` (the active chip), `ItemFilter.matches`, `FacetCounts` (per-key / language / app counts) |
| HotkeyConfig | `@Model` per `HotkeyAction` (23 actions and their default shortcuts), settings container |
| HotkeyShortcut | Parses and formats shortcut strings; the key table; reserved system shortcuts; Carbon modifier mask |
| PinnedItemConfig | `@Model` pin: content snapshot plus layout and flags, settings container; `contentKey` |
| ExcludedApp | `@Model` bundle id whose copies are ignored, settings container |
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
regex rule changes) in pages of 100; `facetCounts(ofTypes:)` shares the
cached count scan; `searchItems(filter:types:limit:)` applies an
`ItemFilter`; `clearSourceApps` forgets every source app.

### Helper/

| File | What |
| --- | --- |
| AppEnvironment | `isRunningUnitTests` |
| AppIconCache | App icons by bundle id for source-app badges |
| AppNotifications | Every `Notification.Name` the app posts |
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
| QuickPicker/ | QuickPickerView (keys, tabs, multi-select, paste / OCR / type-out), QPItemList, QPItemRow, QPItemEditorView + QPItemEditorModel (⌥E: title, favorite, favorite order; renders from a snapshot), QPCategoryBar + `QPCategoryChip.chips` (category chips of the active tab), QPQuickLookCoordinator (native Quick Look through temp files), QPCustomPreviewPanel (own panel, also used over full-screen apps) |
| Pins/ | PinContentView, PinChromeView (+ PinDragArea to move the pin), PinImageView; all render from `PinViewState` |
| Settings/ | Sidebar + General, Hotkeys, Quick Picker, Categories (CategoriesSettingsView, CategorySettingsRow, CategoryEditorView sheet, CategoryIconPicker), Pins, Excluded Apps (`@Query` is fine here), Accessibility, About. AppPickerView is shared by Excluded Apps and app groups |
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
to close the picker when another app takes over.

### Persistent state

All under `~/Library/Application Support/StoneClipboarderTool/` (inside the
app's container for sandboxed Debug builds).

| What | Where |
| --- | --- |
| Clipboard history | `ClipboardHistory.store`, blobs in `.ClipboardHistory_SUPPORT/` |
| Hotkeys, excluded apps, pins | `Settings.store` |
| Settings | UserDefaults through SettingsManager; keys are the property names. `enableErrorFileLogging` is also read by ErrorLogger; `itemCategories` is a JSON array of `ItemCategory` |
| Error log | `StoneClipboarder_errors.log` (+ `.old.log`) |

### Temp files

| Purpose | Location | Lifetime |
| --- | --- | --- |
| File items put on the pasteboard | `$TMPDIR/StoneClipboarderTool/Pasteboard/<uuid>/` | until the next file copy |
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
| Accessibility status refresh | AccessibilitySettingsView | 2 s, while shown |

### Event monitors

| Monitor | Where | Installed |
| --- | --- | --- |
| ⌘Q down / up (local) | AppDelegate | app lifetime / while ⌘Q is held |
| Esc cancels type-out (global + local) | TypePaster | while typing |
| Click outside, Esc (global); key re-routing (local) | QuickPickerWindowManager | while the picker is open |
| Tab, ⇧Tab, ⌥P, ⌥⏎, ⌥E, ⌥←/⌥→ (category chips); in the ⌥E editor ⏎, Esc, ⌥F, ⌥↑/⌥↓ (local) | QuickPickerView `TabKeyInterceptor` | while the picker is open |
| ⌘ held over click-through pins (global + local) | PinWindowController | while click-through is on |
| ⌘C / ⌘W in a pin (local) | PinContentView `CommandKeyHandler` | while the pin is in a window |
| Pinch zoom (local; ⌘-scroll via PinScrollView) | PinImageView | image pins |
| Shortcut recording (local + global) | HotkeySettingsView | while recording |
| Two-finger swipe (local) | SwipeableRow | while the row is in a window |

## Where to change…

- **A setting.** Property in SettingsManager (default read in `init`) →
  control in the matching Settings view → the code that uses it, reading
  SettingsManager. Test it with `IsolatedDefaults`.
- **A clipboard item type.** `CBItemType` case (symbol, color) →
  `ClipboardManager` capture and `copyItemToClipboard` → CBItem
  (`hasSameContent`, `ContentKey`, `matchesSearch`, `displayContent`,
  `thumbnail`) → rows (QPItemRow, BarNavigationCellView, MenuBarItemView)
  and the detail pane → `PinnedItemConfig` / `PinViewState` if pinnable.
- **A hotkey action.** `HotkeyAction` case (raw value, `displayName`,
  `defaultShortcut`, `index`) → the switch in
  `HotkeyManager.registerHotkey(_:for:)` → a row in HotkeySettingsView.
  Existing installs get the new row from `ensureMissingHotkeyConfigs`.
- **A Quick Picker tab.** `QPTab` case (`itemTypes`, title, count) →
  `QuickPickerView.reloadForActiveTab` → a CBViewModel query if the tab
  needs one.
- **A built-in category.** `ItemCategory.BuiltIn` case and an entry in
  `builtIns` (new installs and old ones get it via `merged(stored:)`) →
  detection in `ContentClassifier.classify` → bump
  `ContentClassifier.version` so stored items are rescanned →
  `CategorySettingsRow.builtInDescription`.
- **A pin option.** Default in SettingsManager (`pin…`) → per-pin field in
  `PinnedItemConfig` → `PinViewState` → PinChromeView / PinWindowController →
  PinSettingsView.
- **A `@Model`.** Add it to the right `Schema` in `ModelContainerFactory`
  and hand that container's context to whoever uses it.
