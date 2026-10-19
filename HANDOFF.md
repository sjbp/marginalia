# Handoff

Read this first. Updated at every milestone.

## Status (2026-10-19, overnight run in progress)

| Milestone | State |
|---|---|
| M0 skeleton, CLI, bundle, screenshot, perf flags | done |
| M1 typography, hybrid styling, 3 themes, light/dark | done |
| M2 smart editing, autosave, window memory, scripted edit test | done |
| M3 file watching, reload with caret+scroll preservation, 3-way merge, change bars, status line | done |
| M4 comments as margin cards | next |
| M5 reading mode, palette, outline, recents, print | pending |
| M6 polish, perf pass | pending |

## How to run

    make run                 # debug build, bundle, open Fixtures/tour.md
    make smoke               # four screenshots into _build/smoke/
    make test                # Core unit tests (parser, smart edits, diff/merge)
    make edit-test           # scripted editing session, byte-exact diff
    make install             # release build to /Applications + ~/.local/bin/md

Diagnostics on the installed CLI:

    md --screenshot out.png [--light|--dark] [--reading] [--line N] [--theme flex|newsreader|quattro] file.md
    md --perf file.md
    md --edit-script script.txt file.md      # see Sources/MarginaliaApp/EditScript.swift for commands

## What works

- `md file.md` opens in ~220 ms debug build (first paint, measured from process start). Existing window is focused if already open.
- Hybrid source view: markers hang in the gutter, text edge is flush, code panels, aligned tables (kern on pipes), quote rules, hairline rules, CriticMarkup colored.
- Themes: Flex (Google Sans Flex + Google Sans Code), Newsreader (+ Geist Mono), Quattro (iA Writer). ⌘⇧T cycles. ⌘+/- sizes. Persisted.
- Editing: smart lists (bullets, numbers increment, tasks, nested indent), quote continuation, Tab/⇧Tab, ⌘B/I/E/K, ⌘⇧]/[, ⌘⏎ task toggle, ⌥↑/↓ move lines, ⇧⏎ plain newline. Autosave 250 ms atomic. Undo native.
- External changes: directory FSEvents + vnode source, self-writes ignored, three-way merge when the buffer is dirty (conflicts keep ours and are marked red), caret and scroll anchored to surviving lines, green change bars fade after 8 s (Esc clears, ⌃↓/⌃↑ jump), status line bottom-right.
- Per-file window frame and first-visible-line restored on reopen.

## Known issues

- iA Writer Quattro Italic logs "Faulty glyph (id:772)" from CoreText at load. Harmless, noisy on stderr.
- Google Fonts' Flex build has no GRAD axis. Dark mode uses +40 weight instead.
- Reload of a 25 KB doc takes 25 to 50 ms in debug. Release not yet measured.
- Reading mode, comments as cards, palette, outline, recents, settings window: not built yet (menu items exist, some are stubs).

## Perf (debug build, M-series, 25 KB tour.md)

    launch_to_first_paint_ms ≈ 220    parse_ms ≈ 5    style_ms ≈ 3    reload ≈ 25–50 ms

## Next three things

1. M4: comment cards in the right margin (create ⌘⇧M, reply, resolve, next/prev, palette entries).
2. M5: reading mode (hide markers, native tables), ⌘K palette with `#` headings, outline popover, recents, print.
3. Release-build perf pass against SPEC §9 and `make install`.
