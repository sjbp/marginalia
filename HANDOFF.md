# Handoff

Read this first. Last updated 2026-10-19 after the overnight build.

## Status

| Milestone | State |
|---|---|
| M0 skeleton, CLI, bundle, screenshot and perf flags | done |
| M1 typography, hybrid styling, 3 themes, light/dark | done |
| M2 smart editing, autosave, window memory, scripted edit test | done |
| M3 file watching, reload with caret and scroll preservation, 3-way merge, change bars, status line | done |
| M4 comment cards: create, reply, resolve, navigate, copy | done |
| M5 reading mode, palette, outline, quick open, settings, print | done |
| M6 perf pass against SPEC §9 | done, numbers below |
| M6 nice-to-haves | `md -w` and `md -` done. Typewriter/focus, rich copy, CriticMarkup accept/reject not started |

## How to run

    make run                 # debug build, bundle, open Fixtures/tour.md
    make smoke               # four screenshots into _build/smoke/
    make test                # 27 Core unit tests (parser, smart edits, diff/merge)
    make edit-test           # scripted editing session, byte-exact diff
    make install             # release build to /Applications + ~/.local/bin/md

Installed CLI:

    md file.md [more.md]                      open (creates the file if missing), focuses an existing window
    md -w file.md                             wait until that window closes (works as $EDITOR, e.g. for git commit)
    echo text | md -                          stdin into a new file under ~/Library/Application Support/Marginalia/stdin/
    md --screenshot out.png [--light|--dark] [--reading] [--line N] [--theme flex|newsreader|quattro] file.md
    md --perf file.md                         launch, parse, style, font timings and phase breakdown
    md --edit-script script.txt file.md       drive the editor headlessly, see Sources/MarginaliaApp/EditScript.swift

Scripted regression flows live in `Fixtures/*.script` (editing, external changes, scroll preservation, comments).

## Keyboard

| Keys | Action |
|---|---|
| ⌘K | Command palette (type `#` for headings) |
| ⌘⇧O | Outline (palette in heading mode, current section preselected) |
| ⌘O | Quick open: recents + Markdown siblings of the current file |
| ⌘⇧R | Show Markdown (full source) / back to rendered text |
| ⌘⇧T | Next theme (Geist → Flex → Newsreader → Quattro) |
| ⌘⇧M, or the comment button in the format bar | Add comment on the selection (or standalone at paragraph end); the card opens a composer, ⏎ commits, ⎋ cancels |
| ⌥⌘↓ / ⌥⌘↑ | Next / previous comment |
| ⌃↓ / ⌃↑ | Next / previous change after an external update, ⎋ clears the marks |
| ⌘B ⌘I ⌘E ⌘⇧K | Bold, italic, inline code, link (uses a clipboard URL if there is one) |
| ⌘1 ⌘2 ⌘3, ⌥⌘0 | Heading 1, 2, 3, paragraph |
| ⌘⇧] ⌘⇧[ | Raise / lower heading |
| ⌘⇧8 ⌘⇧7 ⌘⇧9 ⌘⇧. | Bulleted, numbered, task list, quote |
| ⌘⏎ | Toggle task |
| ⌥↑ ⌥↓ | Move line |
| Tab ⇧Tab | Indent / outdent list item |
| ⇧⏎ | Plain newline (no list continuation) |
| ⌘+ ⌘− ⌘0 | Text size |
| ⌘, | Settings (theme, size, author tag, change-mark fade, keep running) |

## Views

Rendered text is the default and fully editable; Markdown syntax is never shown in it. The Text | Markdown toggle sits bottom-right (also ⌘⇧R). Screenshots: `--source` forces the Markdown view.

Editing rendered text: arrow keys move one visible character (hidden markers are skipped; moving right past the end of bold lands outside it, moving left back in lands inside), backspace on a marker unwraps the span, backspace at the start of a list item or heading turns it into a paragraph, clicking a checkbox toggles it, pasting a URL over a selection makes a link, typing `**x**`, `# `, `- ` converts live. Tables and images are rendered natively; double-click one to edit it as Markdown.

Selecting text shows the format bar: heading menu, bold, italic, strikethrough, code, link, bullet, numbered, task, quote, comment.

## Comment format

    {==anchored text==}{>>@sebo: comment<<}
    {>>@sebo: standalone comment<<}
    {>>@sebo: first<<}{>>@claude: reply<<}        adjacent comments share the anchor

Adjacent comments are one thread and render in one card with a reply box. Resolve removes the whole thread and unwraps the highlight. "Resolve All Comments by @claude" is in the palette. The author tag is in Settings.

## Perf, release build, M-series, measured with `md --perf`

| Metric | Budget | Measured |
|---|---|---|
| Cold launch to first paint, 25 KB | 200 ms | 145–180 ms (82 ms of that is dyld + NSApplication before any app code runs) |
| Cold launch, 1 MB | 500 ms | 250 ms (visible region styled first, rest in slices) |
| External change to paint, 25 KB | 50 ms | 20–30 ms |
| External change to paint, 100 KB | 50 ms | 44 ms |
| Parse 1 MB | — | 83 ms on a background queue above 200 KB |
| App bundle | 25 MB | 8.5 MB |
| Open 1 MB rendered (default) | 500 ms | ~2 s when the file has 40 tables, each is measured up front. Known issue |

Keystroke latency was not instrumented. Styling per edit is ~5 ms at 25 KB; above 200 KB the parse runs off the main thread.

## Design review (2026-10-19)

Ran the gstack design-review flow against screenshots. Fixed and committed one per finding: selection on text extents, format bar hover/pressed states, list marker alignment on the x-height, left-biased column with wider cards when a document has comments, uniform code panels with wrapping. Open: typography direction, see the Marginalia Type Board artifact and `DECISIONS.md`.

## Known issues and rough edges

- Rendered view on very large files with many tables is slow to open (every table overlay is measured up front because its height affects layout). Lazy estimation would fix it.
- iA Writer Quattro Italic logs "Faulty glyph (id:772)" from CoreText at registration. Harmless, noisy on stderr.
- Google Fonts' Flex build has no GRAD axis. Dark mode uses +40 weight instead.
- Comments in a narrow window (under ~1040 pt) render inline in the text, not as cards. The status line says so when you add one.
- Keyboard focus after committing a card goes back to the text view, but the caret is wherever it was, not at the comment.
- Print uses the current view. In source view that includes markers.
- Window memory restores the first visible line, not the exact pixel offset.
- No Settings for the fonts themselves. The three themes are fixed by design (SPEC §5.2).

## Where things are

    Sources/MarginaliaCore      parser (swift-markdown + source map), CriticMarkup, SmartEdit rules, LineDiff + ThreeWayMerge, Document
    Sources/MarginaliaApp       AppDelegate, DocumentWindowController (the hub), Styler (attributes from flags), EditorTextView (smart keys, background drawing),
                                CommentMargin (cards), ReadingOverlays (tables, images), Palette, SettingsWindow, StatusLine, FileWatcher, Screenshot, EditScript
    Sources/md                  the CLI; finds the app relative to its own binary
    Fixtures                    tour.md (every construct), large.md (1 MB), edit/external/comment scripts, mark.png
    DECISIONS.md                one line per decision with the reason

## Next three things

1. Accept / reject CriticMarkup `{++ ++}` `{-- --}` `{~~ ~> ~~}` from the margin, so Claude can propose edits as track changes.
2. Lazy table measurement in reading mode, and a typewriter / focus mode toggle.
3. Copy as rich text (⌘⇧C) for pasting into Slack, Gmail, Notion.
