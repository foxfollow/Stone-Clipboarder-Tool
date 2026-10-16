# Manual Testing Guide

Unit tests cover models, settings and the view model's data path
(`xcodebuild test …`, see the README). Everything that needs the real
clipboard, windows, global hotkeys or synthetic key events is checked by
hand with this list.

## Before you start

1. Build and run the app. A Debug build signed by Xcode runs sandboxed and
   keeps its own data; an unsigned build shares the installed app's history.
2. Grant Accessibility in System Settings → Privacy & Security →
   Accessibility. Without it hotkeys still copy, but pasting (⌘V and
   type-out) shows an alert instead.
3. Have some text, an image (a screenshot copied with ⌃⇧⌘4) and a file
   (copy one in Finder) ready.

## Capture

- [ ] Copied text appears at the top of Recent within a second.
- [ ] A copied screenshot appears as an image with a thumbnail.
- [ ] A file copied in Finder appears as a file item (not as its path).
- [ ] A folder or a file over 100 MB copied in Finder is skipped, and the
      app stays responsive while it's checked.
- [ ] Capture modes (Settings → General): with Word-style content (text +
      picture), "Text Only" saves the text, "Image Only" the image, "Both"
      two items, "Both as One" one combined item.
- [ ] Re-copying something already in the history, even an old item far
      down the list, moves that item to the top instead of adding a second
      one.
- [ ] Pause (menu bar → pause timer): nothing is captured until it ends or
      you resume; the menu bar icon changes while paused.
- [ ] Excluded apps (Settings → Excluded Apps): nothing copied in an
      excluded app is saved.

## Main window

- [ ] Recent and Favorites tabs; the heart toggles a favorite.
- [ ] Scroll far down, copy something new in another app: the list keeps
      its length and the new item shows on top.
- [ ] Search finds items that were never scrolled into view.
- [ ] While searching, deleting a result deletes that result (not another
      item).
- [ ] Detail pane: copy, edit text, "Open in Preview" for images and image
      files, "Extract Text" (OCR) adds a text item.
- [ ] Settings → General → "Show Main Window" off: the window hides and
      the Dock icon goes away; menu bar → "Show Main Window" brings both
      back. Quit and relaunch with it off (also as a login item): no Dock
      icon.

## Global hotkeys

Defaults: ⌃⌥1…0 last items, ⌃⇧1…0 favorites (in the order they were
favorited), ⌃⌥Space Quick Picker, ⌃⌥P pin the latest item, ⌃⌥⇧P dismiss
all pins.

- [ ] Each hotkey pastes into TextEdit, Notes and a browser field, and the
      pasted item moves to the top. Pasting an image by hotkey doesn't add
      a duplicate image.
- [ ] Settings → Hotkeys: record new shortcuts, including Return, arrows,
      F-keys and punctuation (⌃⌥-); they work after recording and after a
      relaunch.
- [ ] System shortcuts (⌘C, ⇧⌘Z, ⌘Space…) are refused while recording.
- [ ] Recording a shortcut used by another action clears it there.
- [ ] "Enable Global Hotkeys" off: none fire.

## Quick Picker (⌃⌥Space)

- [ ] Opens centered on first use, then where you left it (until relaunch);
      also over a full-screen app without switching Spaces.
- [ ] ↑/↓ select, ⏎ pastes into the previous app, Esc closes, clicking
      outside closes.
- [ ] Tab / ⇧Tab cycle All, Favs, Text, Images, Files; counts are right.
- [ ] Scrolling All keeps loading past 150 items.
- [ ] Search finds old items; switching tabs keeps the search.
- [ ] ⇧↑/⇧↓ multi-select: ⏎ pastes texts joined by newlines (and doesn't
      save the joined text as a new item); mixed items paste one by one.
- [ ] ⌥⏎ on an image pastes its recognized text (OCR).
- [ ] ⌘⇧⏎ types text out key by key; Esc stops it. Try a terminal, a
      remote desktop, and a Ukrainian keyboard layout: Latin letters,
      capitals and !@# arrive correctly.
- [ ] Space (or →, per settings) toggles Quick Look / the custom preview;
      "Open with…" from Quick Look works.
- [ ] ⌥Space toggles favorite, ⌥P pins the selection.

## Pins

- [ ] ⌃⌥P and "Pin to Screen" open floating pins; they stay on top and
      appear over full-screen apps when enabled.
- [ ] Pin controls: opacity, lock, click-through (hold ⌘ to reach the
      controls), collapse, copy (⌘C), close (⌘W / Esc).
- [ ] An unlocked pin moves by dragging its header (and a fit image by
      dragging the image); a locked pin doesn't move or resize.
- [ ] Image pin: the image is centered and grows/shrinks with the window;
      pinch (also with another app active) and ⌘-scroll zoom toward the
      cursor, a zoomed image pans on drag, double-click fits it again.
- [ ] Copying a pinned file and pasting it in Finder a minute later works.
- [ ] Settings → Pins → Active Pins lists every open pin, including pins of
      items no longer in the history, and updates immediately.
- [ ] With "Persist pins across launches" on, pins come back after a
      relaunch, the pinned rows show the pin badge again, and deleting such
      an item closes its pin.
- [ ] Limit (e.g. 2 pins): a third pin closes the oldest.

## Menu bar

- [ ] Shows the configured number of recent items (Settings → General).
- [ ] Click copies; two-finger swipe left deletes, right opens the item in
      the main window; context menu offers the same.
- [ ] Copying a file from history and pasting it in Finder later than five
      seconds afterwards still works.

## Cleanup and memory

- [ ] "Keep maximum items" (e.g. 100): the oldest non-favorites are removed
      as new items arrive; favorites are never removed.
- [ ] "Clean Up Now" and "Delete All" ask first and do what they say.
- [ ] With memory cleanup on, leaving the app idle past "Max inactive
      time" and coming back: the main list is back to its first rows and
      scrolling loads more again.

## Quit

- [ ] "Hold or double-tap ⌘Q to quit" on: a single short ⌘Q shows the HUD
      and doesn't quit; holding 1 s or double-tapping quits.

## Reporting issues

Include steps to reproduce, expected vs. actual behavior, the macOS and app
version, and — with Settings → General → "Save errors to log file" on —
the log from `~/Library/Application Support/StoneClipboarderTool/`. The log
holds no clipboard content.
