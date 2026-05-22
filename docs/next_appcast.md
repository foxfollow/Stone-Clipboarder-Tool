
# appcast.xml `<new>` block template

The release workflow (`.github/workflows/release.yml`) reads the bullets
from a `<new>…</new>` block in `docs/appcast.xml`, then builds both the
Sparkle `<item>` and the GitHub release notes from them. You only write the
`<li>` lines — everything else (version, signature, size, pubDate, URL) is
filled in by the workflow.

See `docs/git-release-hint-note.md` for the full procedure.

## list of changes

- notes...

## block to paste after `</language>` in docs/appcast.xml

```xml
        <new>
            <li>🪟 NEW: First headline change…</li>
            <li>✨ NEW: Another change…</li>
            <li>🛠️ FIXED: A bug fix…</li>
        </new>
```

### Bullet-prefix conventions

| Prefix      | Use for                                          |
| ----------- | ------------------------------------------------ |
| 🪟 NEW      | brand-new user-facing capability                 |
| ✨ NEW      | smaller feature addition                         |
| 🎨 IMPROVED | UI / layout improvement                          |
| ⌨️ IMPROVED | keyboard / focus / interaction                   |
| 🛠️ FIXED   | bug fix                                          |
| 🐛 FIXED    | smaller bug fix                                  |
| 🛡️ NEW     | privacy / security / permission related          |
| 🧹 IMPROVED | code quality / refactor (no user-visible effect) |

Source of truth for bullet content = `git log --oneline <previous-tag>..HEAD`.
