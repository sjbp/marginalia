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
| M6 nice-to-haves (`md -w`, `md -`, typewriter/focus, rich copy, CriticMarkup accept/reject) | not started |

## How to run

    make run                 # debug build, bundle, open Fixtures/tour.md
    make smoke               # four screenshots into _build/smoke/
    make test                # 27 Core unit tests (parser, smart edits, diff/merge)
    make edit-test           # scripted editing session, byte-exact diff
    make install             # release build to /Applications + ~/.local/bin/md

Installed CLI:

    md file.md [more.md]                      open (creates the file if missing), focuses an existing window
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
| ⌘⇧R | Reading mode |
| ⌘⇧T | Next theme (Flex → Newsreader → Quattro) |
| ⌘⇧M | Add comment on the selection (or standalone at paragraph end); the card opens for typing, ⏎ commits, ⎋ cancels |
| ⌥⌘↓ / ⌥⌘↑ | Next / previous comment |
| ⌃↓ / ⌃↑ | Next / previous change after an external update, ⎋ clears the marks |
| ⌘B ⌘I ⌘E ⌘⇧K | Bold, italic, inline code, link (uses a clipboard URL if there is one) |
| ⌘⇧] ⌘⇧[ | Raise / lower heading |
| ⌘⏎ | Toggle task |
| ⌥↑ ⌥↓ | Move line |
| Tab ⇧Tab | Indent / outdent list item |
| ⇧⏎ | Plain newline (no list continuation) |
| ⌘+ ⌘− ⌘0 | Text size |
| ⌘, | Settings (theme, size, author tag, change-mark fade, keep running) |

## Comment format

    {==anchored text==}{>>@sebo: comment<<}
    {>>@sebo: standalone comment<<}
    {>>@sebo: first<<}{>>@claude: reply<<}        adjacent comments share the anchor

Resolve removes the comment and unwraps the highlight once no other comment hangs off it. "Resolve All Comments by @claude" is in the palette. The author tag is in Settings.

## Perf, release build, M-series, measured with `md --perf`

| Metric | Budget | Measured |
|---|---|---|
| Cold launch to first paint, 25 KB | 200 ms | 145–180 ms (82 ms of that is dyld + NSApplication before any app code runs) |
| Cold launch, 1 MB | 500 ms | 250 ms (visible region styled first, rest in slices) |
| External change to paint, 25 KB | 50 ms | 20–30 ms |
| External change to paint, 100 KB | 50 ms | 44 ms |
| Parse 1 MB | — | 83 ms on a background queue above 200 KB |
| App bundle | 25 MB | 8.5 MB |
| Reading mode on 1 MB | 100 ms toggle | ~2 s on first entry: 40 tables get measured and rendered. Known issue, see below |

Keystroke latency was not instrumented. Styling per edit is ~5 ms at 25 KB; above 200 KB the parse runs off the main thread.

## Known issues and rough edges

- Reading mode on very large files with many tables is slow on entry (every table overlay is measured up front because its height affects layout). Lazy estimation would fix it.
- iA Writer Quattro Italic logs "Faulty glyph (id:772)" from CoreText at registration. Harmless, noisy on stderr.
- Google Fonts' Flex build has no GRAD axis. Dark mode uses +40 weight instead.
- Comments in a narrow window (under ~1040 pt) render inline in the text, not as cards. The status line says so when you add one.
- Keyboard focus after committing a card goes back to the text view, but the caret is wherever it was, not at the comment.
- Print uses the current mode's styling. In edit mode that includes markers; switch to reading mode first.
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

1. `md -w` (block until the window closes, for `$EDITOR`) and `md -` (stdin to an untitled buffer). Both are CLI plumbing plus one `DocumentWindowController` path for a temp file.
2. Accept / reject CriticMarkup `{++ ++}` `{-- --}` `{~~ ~> ~~}` from the margin, so Claude can propose edits as track changes.
3. Lazy table measurement in reading mode, and a typewriter / focus mode toggle.
