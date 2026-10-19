# Decisions log

One line each, newest first. Defaults from SPEC §3 unless noted.

- 2026-10-18 Google Fonts' build of Google Sans Flex has no `GRAD` axis (axes: opsz, wdth, wght, ROND, slnt). Dark mode compensates with +40 weight on every theme instead.
- 2026-10-18 CLI finds the app relative to its own binary (`Marginalia.app/Contents/MacOS/md`), so `~/.local/bin/md` is a symlink into the bundle. No bundle-id lookup needed, works for dev builds too.
- 2026-10-18 Swift tools 5.10, language mode 5. Strict concurrency of Swift 6 mode adds nothing for a single-window AppKit app and costs hours.
- 2026-10-19 TextKit 2 geometry: fragment frames and `firstRect(forCharacterRange:)` are estimates for text outside the viewport and drift after display passes. Programmatic scrolling therefore (1) brings the range into view with `scrollRangeToVisible`, (2) verifies visibility by hit test (`characterIndexForInsertion`), (3) aligns with the on-screen rect, and (4) re-checks at 20/80/200/450/800 ms. Only user gestures cancel the re-checks.
- 2026-10-19 Modified lines show only the green bar. A red deletion rule appears only for pure removals, so a replaced line is not double-marked.
- 2026-10-19 Change bars sit at the far left of the column (not next to the text edge) so they never collide with hanging `######` markers.
- 2026-10-19 Edit-script mode manages undo groups per step because no real events flow, so event-based grouping never closes.
- 2026-10-19 Reading mode keeps one NSTextView and one text storage. Syntax that should disappear is rendered in a 0.1 pt clear font (offsets never change, so cards, change bars, and scroll anchoring keep working). Tables and images reserve paragraph height and get native overlay views. Chosen over a second rendered attributed string because every other subsystem keys on source offsets.
- 2026-10-19 Outline (⌘⇧O) is the command palette in heading mode with the current section preselected, not a separate popover. One UI, same keyboard model.
- 2026-10-19 ⌘K is the palette, so Link moved to ⌘⇧K.
- 2026-10-19 Default window is 1180 pt wide when the screen allows, not 860 as the spec said, because margin cards need about 1040 pt and comments are the point of the app.
- 2026-10-19 Perf: card and overlay positioning is gated to the viewport range ± 12k characters. Positioning a far anchor forces TextKit 2 to lay out everything before it, which was the single largest cost on large files.
- 2026-10-19 Perf: NSTextStorage.string is a bridged NSString; `makeContiguousUTF8()` once per parse or reload makes the diff and parser 5 to 10× faster.
- 2026-10-19 Perf: styling is applied to the visible region first and the rest in 600-line slices above 800 lines; parsing moves to a background queue above 200 k characters. The main menu installs one turn after the first window.
