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

Defaults: ⌃⌥1…0 last items, ⌃⇧1…0 favorites (in Favorites order: as
favorited, or as moved with ⌥E), ⌃⌥Space Quick Picker, ⌃⌥P pin the latest item, ⌃⌥⇧P dismiss
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
- [ ] Tab / ⇧Tab cycle All, Favs, Text, Images, Files, Passwords; counts
      are right (Passwords shows no count while locked). No pill is cut
      off; with six tabs they get tighter and an inactive Passwords pill
      shows only its lock.
- [ ] ⌘1…⌘6 jump to the tabs (also on a Ukrainian layout); tooltips name
      the shortcut. Settings → Quick Picker → Tabs: moving a tab changes the
      pills, ⌘ numbers, Tab cycling and the tab the picker opens on; Reset
      Order restores it.
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
- [ ] ⌥E (also on a Ukrainian layout, and from the row's context menu)
      opens the editor over the list: type a title with spaces and arrows
      (the list and preview don't react), ⏎ saves, Esc discards. The title
      shows above the content in the picker, menu bar and main window, and
      search finds it. Clearing it removes it.
- [ ] In the editor on a favorite, ⌥↑/⌥↓ move it (the Favs list behind
      follows, and so do ⌃⇧1…0); ⌥F asks before removing, ⏎ confirms, Esc
      keeps it. On a non-favorite ⌥F adds it at once.

## Passwords (Quick Picker tab, Settings → Quick Picker)

- [ ] Fresh launch: the Passwords tab is locked. ⏎ or the button shows
      Touch ID (password fallback); the picker stays open behind it and the
      cursor is back in the search afterwards. Cancel keeps it locked.
- [ ] ⌥E on a history item, then ⌥K (or Move to Passwords): asks Touch ID
      if locked, the item disappears from the history (and its pin closes)
      and shows on the Passwords tab with the typed title.
- [ ] Moving the same content again adds no second entry; the history copy
      still goes.
- [ ] Text rows are masked; the eye (or ⌥R) reveals a row, moving the
      cursor hides it again. Images stay hidden until revealed. The ⌥E
      editor has the eye too.
- [ ] Space / → previews the entry the way Settings → Quick Picker says:
      Apple Quick Look (⌥Space: full screen), the custom panel (⌥Space or
      its button: 85 % of the screen) or nothing when disabled. ↑/↓ follow;
      Esc, locking, leaving the tab or closing the picker closes it. With
      Apple Quick Look, `Previews/Secret_…` exists only while the preview is
      open; the custom panel writes nothing.
- [ ] Copying a saved password again (another app, a site), with the tab
      locked or not: it doesn't appear in the history. After an unlock, old
      history copies of saved entries are gone.
- [ ] Clean Up Now, auto-cleanup and Delete All History leave Passwords
      as they were; the Passwords page shows the "Not your main password
      manager" notice.
- [ ] Settings → Security → Passwords → Require a Password: Save stays off
      until the passwords match, are 6+ characters, the hint doesn't contain
      it and the warning is confirmed. Then the locked tab's search field
      asks for the password (spaces and ⌥ letters type into it), shows the
      hint, Touch ID isn't offered; a wrong password says so. Change and
      Remove ask to unlock first; Remove brings Touch ID back. Delete All
      clears it.
- [ ] ⏎ pastes text, an image, a file and text + image; nothing of it shows
      up in the history. After 30 s the clipboard is empty, unless something
      else was copied in the meantime.
- [ ] ⌘⇧⏎ types a password into a field that blocks paste.
- [ ] The lock button next to the search field and "⌥L Lock" in the footer
      lock the tab. ⌃⌥L locks it from any app with the picker closed; it
      can be changed or turned off in Settings → Hotkeys → Passwords, and
      an existing install gets the new row.
- [ ] Searching on another tab (vault unlocked) shows "N in Passwords: …"
      for matching titles or file names, never for the secret itself; a
      click or its ⌘ number opens Passwords with the same search. Locked:
      no bar.
- [ ] ⌥E on an entry: the icon button opens SF Symbols / emoji, the color
      well changes the color, Default goes back; the row shows it after ⏎
      and after a relaunch. Entries from before keep the type's icon.
- [ ] ⌥E on an entry: rename, ⌥↑/⌥↓ reorder, ⌃⌥⌫ (or ⌃⌥⌦; also straight from the list) asks, ⏎ deletes, Esc keeps it; pressing it twice only asks again, ⌥⌫ deletes a word of the title. ⌥L locks.
- [ ] Locking the screen (⌃⌘Q), sleep and the screen saver lock the tab.
      Reopening the picker within the relock time (default 1 h after the
      last use) needs no Touch ID; after it, it does. Quit and relaunch:
      locked.
- [ ] ⌥P, ⌥Space and OCR do nothing on the Passwords tab.
- [ ] Settings: hiding the tab removes it from the Tab cycle and the ⌥K
      option; Delete All Passwords empties it and asks Touch ID for a new
      key next time.
- [ ] After installing an update, macOS may ask once to let the new build
      use the "Stone Clipboarder Passwords" Keychain item; Always Allow.
- [ ] Keychain Access shows the item `d3f0ld.StoneClipboarderTool.vault`;
      `Application Support/StoneClipboarderTool/Vault/*.sctv` files contain
      no readable text.

## Settings

- [ ] The sidebar shows General, Quick Picker, Security and About headings
      with their pages; Passwords and Excluded Apps sit under Security.
- [ ] The search field filters to settings: "shadow", "touch id", "dock",
      "regex", "security", a hotkey name, a category name. ⏎ opens the first
      result. A pick opens the page, scrolls to the row and highlights it;
      a row behind an off toggle brings the toggle into view.

## Categories (Quick Picker chips, Settings → Categories)

- [ ] Copy a bare URL, a sentence with a URL, an email, a phone number, a
      date, JSON, Swift/shell code, a path (/Users/…, ~/…) and long
      Ukrainian and English sentences. The chip row under the tabs shows
      Link, Email, Phone, Date, Code, JSON, Path, Ukrainian, English with
      the right counts; a chip lists only its items, clicking it again
      clears it.
- [ ] Chips follow the tab: Images/Files show only categories they have
      items for; a chip the new tab lacks is cleared.
- [ ] ⌥←/⌥→ step through the chips and back to none (also on a Ukrainian
      layout); the search field doesn't move by a word. ⌥⇧←/→ select a
      run of chips, ⇧-click adds or removes one; items in any selected
      chip show. In the ⌥E editor ⌥←/→ move the cursor.
- [ ] Image chips (Text in Image, QR & Barcode, People, Transparent) show
      only on the Images tab, first in the row.
- [ ] Search: is:link, is:email, is:fav, app:safari, app:"Visual Studio
      Code", lang:uk, lang:ukrainian, and tokens with text (is:link
      invoice) on All and Favs.
- [ ] Rows show up to three category icons, the language code and the
      source app's icon; hovering names them.
- [ ] Settings → Categories: turning a built-in off hides its chip and
      badges at once (no rescan); Edit changes its icon (symbol from the
      grid, a typed name, or an emoji via "Emoji & Symbols…") and color.
      Link set to "Entire text" counts only bare URLs. Reset… restores
      the built-ins and keeps custom ones.
- [ ] Add Rule…: an invalid pattern can't be saved; the test field says
      Matches / No match. Saving №\s*\d+/\d{4} gives existing document
      numbers a chip within seconds (background rescan).
- [ ] OCR: a new screenshot gets its text read right away; older images
      don't until Settings → Categories → "Recognize Text in All
      Images…", which shows "N images left" and stops on Stop (a new
      screenshot waiting for its own OCR still gets it). "Recognize text
      in new images" off: new images get no text (QR/faces still), and the
      "N images not read yet" count updates at once.
- [ ] Images: a screenshot with text gets Text in Image (and Link/Email
      when they're in it, plus a language), a QR code gets QR & Barcode
      (and Link for a URL), a photo of a person gets People, a PNG icon
      with a clear background gets Transparent. A capture doesn't stall
      the picker; badges appear within seconds. "Find QR codes, faces and
      transparency" off removes QR & Barcode, People and Transparent
      after the rescan (text from OCR stays); on brings them back.
- [ ] Searching a word that is only inside a screenshot finds the
      screenshot; its row shows the text under "[Image - W×H]". After ⌥⏎
      (or Extract Text) on an image, the image is found by that text too.
      The three switches (find by text, text in rows, row icons) each
      take effect on the next Quick Picker open.
- [ ] Add App Group… (e.g. Telegram + Slack): items copied in those apps
      show under its chip and with app:.
- [ ] "Remember the source app" off: new copies get no app icon.
      "Forget Recorded Apps…" removes every app icon and empties app
      groups.
- [ ] "Show the category bar" off hides the row; is:/app:/lang: still work,
      and ⌥←/⌥→ move the cursor by word again (⌥→ doesn't open the
      preview).
- [ ] `make demo` with the installed app running: the demo opens with the
      made-up history; the installed app's hotkeys, clipboard capture and
      history are unaffected, and its settings unchanged after quitting
      the demo.
- [ ] Updating from 1.9.0: existing items (hundreds of images too) get
      categories after launch without a freeze or a memory spike; titles, favorites and their order are unchanged.

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
