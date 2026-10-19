# Marginalia, a Markdown workbench for one person

Working name: **Marginalia** (notes in the margins). CLI command: `md`. Both are placeholders, rename freely.

Version: spec v0.1, 2026-10-18. Author: Sebastián, drafted with Claude.

---

## 1. What this is

A native macOS app for reading, lightly editing, and annotating `.md` files. It is the human half of a loop where Claude writes and edits files from the terminal and Sebastián reads, reacts, and steers.

The loop it must make effortless:

1. Claude writes or edits a `.md` file.
2. The file is already open in Marginalia (or `md file.md` opens it in under 200 ms). The app repaints instantly and shows *what changed*.
3. Sebastián reads, selects a passage, drops a margin comment, maybe fixes a sentence.
4. Comments are saved **inside the file** as CriticMarkup, so Claude reads them with a plain `cat`.
5. Claude addresses the comments. Repeat.

Not a notes app. Not a knowledge base. Not a Markdown IDE. One file at a time, done beautifully.

## 2. Principles, in priority order

1. **Speed is the product.** No spinners, no splash, no perceptible latency anywhere. Budgets in §9 are requirements, not aspirations.
2. **The file is the only truth.** No database, no sidecar, no index. Everything the app knows is in the `.md`. Quit, delete the app, the work is intact.
3. **Typography first.** The reading experience should rival a well-set book. Measure, leading, rhythm, and optical details get engineering time.
4. **Chrome disappears.** No toolbar, no sidebar by default, no icons. Keyboard driven, with a command palette for everything else.
5. **Native, not web.** AppKit and TextKit 2. No WKWebView anywhere in v1, including reading mode.
6. **Honest editing.** What you see is Markdown. Syntax is styled and tucked into the margins, never hidden or rewritten.

## 3. Decisions

### Made

| Topic | Decision | Why |
|---|---|---|
| Stack | Swift 6, AppKit, TextKit 2 (`NSTextLayoutManager`), SwiftUI only for Settings | Fastest cold start, best text rendering, viewport-only layout for large files |
| Deployment target | macOS 14.0 (this machine is 14.8) | No macOS 15-only APIs |
| Markdown parser | `swift-markdown` (Apple, cmark-gfm) for structure + source ranges, full reparse per edit, debounced, off main thread above 200 KB | Sub-millisecond on typical docs, correct GFM, no incremental complexity |
| Flavor | GitHub Flavored Markdown + YAML frontmatter (rendered as a dimmed block) + CriticMarkup | Matches what Claude writes |
| Editing model | **Hybrid source**: always the Markdown source, styled live. Syntax markers hang in the left gutter so text stays flush. Plus a read-only **Reading mode** toggle | iA Writer proved this. One mental model, zero mode confusion, always Claude-compatible |
| Comments | **CriticMarkup inline**: `{==anchored text==}{>>@sebo: comment<<}` and standalone `{>>@sebo: comment<<}` | Lives in the file, Claude reads it natively, and CriticMarkup's `{++ ++}` `{-- --}` `{~~ ~> ~~}` opens the door to Claude proposing track-changes in v2 |
| Windows | One window per file, no tabs. App stays running after last window closes | Instant reopen, simple state |
| Saving | Autosave, debounced 250 ms, atomic write. No dirty state, no save dialogs. ⌘S forces a flush | Removes a whole class of conflicts with external edits |
| Build | Must build, run, test, and screenshot **from the terminal** without opening Xcode: `make build`, `make run`, `make test`, `make install` | The overnight session has no GUI |
| Install | `make install` copies `Marginalia.app` to `/Applications` and symlinks the CLI to `~/.local/bin/md` | Already on PATH |
| Signing | Ad-hoc codesign, no notarization, no sandbox | Personal use |

### Open, with defaults the build should assume

| # | Question | Default for v1 | Alternatives |
|---|---|---|---|
| 1 | Name and CLI | Marginalia, `md` | Margin / `margin`, Folio, Lector |
| 2 | Default type theme | **Flex** (Google Sans Flex + Google Sans Code) | Newsreader (Newsreader + Geist Mono), Quattro (iA Writer Quattro + iA Writer Mono) |
| 3 | Chrome typeface (palette, cards, status) | **Google Sans Flex** at opsz 12 to 13 | System font only as a load-failure fallback |
| 4 | Comment author tag | `@sebo` | `@s`, no tag |
| 5 | Change marks persistence | Fade after 8 s, or on `Esc` | Persist until click |
| 6 | Reading mode tables | Native `NSView` attachments via TextKit 2 view providers | Monospace grid fallback if attachments prove slow |

Ship three type themes behind a picker, default Flex. No arbitrary font panel: the app is opinionated and every face it uses is open-licensed (see §5.2).

## 4. Scope

### v1, in order of importance

1. **Open fast** from CLI, Finder, drag, `open`. Focus the existing window if the file is already open.
2. **Hybrid source editor** with live styling, hanging gutter markers, smart list continuation, ⌘B / ⌘I / ⌘K wrapping, Tab/⇧Tab list indent, ⌘⇧] / ⌘⇧[ heading level.
3. **External change handling**: instant reload, scroll and caret preserved, changed lines marked, three-way merge when the buffer is mid-edit.
4. **Margin comments** in CriticMarkup, shown as cards in the right margin, keyboard first.
5. **Reading mode** (⌘⇧R): markers collapse, tables render as tables, images inline, code highlighted, links clickable. Read-only. Same NSTextView, different attribute pass.
6. **Navigation**: command palette ⌘K, go-to-heading inside it with `#` prefix, outline ⌘⇧O as a popover, native find ⌘F restyled, recent files ⌘O.
7. **Status line**: appears on scroll end, fades out: `1,240 words · 6 min · saved 2 s ago`. Shows `edited outside, merged` for 3 s after an external change.
8. **Print / PDF** via ⌘P using the reading-mode style. Cheap with NSTextView, worth it.

### Nice if time allows

- Typewriter scrolling and focus (dim non-current paragraph).
- `md -w file.md` blocks until the window closes, usable as `$EDITOR`.
- `md -` reads stdin into an untitled buffer.
- Accept / reject CriticMarkup `{++ ++}` `{-- --}` `{~~ ~> ~~}` suggestions with one key.
- Copy as rich text (⌘⇧C) for pasting into Slack, Gmail, Notion.

### Non-goals for v1

No sync, no cloud, no accounts, no plugins, no WYSIWYG, no vault or folder tree, no tabs, no split view, no Mermaid, no math, no Windows or iOS, no frontmatter UI, no spellcheck beyond the system one, no sandbox, no App Store.

## 5. Experience

### 5.1 Window

- Transparent title bar, full-size content view. Title is the file name, proxy icon kept (drag the file out of the title bar, that is native and free).
- Default size 860 × 980, centered. Remember per-file size and scroll position in `UserDefaults` keyed by path.
- Three horizontal zones: left gutter (hanging markers, change bars), text column (max measure 68 ch), right margin (comment cards when the window is ≥ 1100 pt wide, otherwise comments render inline below their paragraph as a card).
- Content centered. Side padding never below 48 pt.
- Light and dark follow the system. Both are warm, not pure white or pure black.

### 5.2 Typography

**Typefaces.** Only open-licensed faces (SIL OFL), bundled in the app with their license files copied from the upstream repos. No proprietary fonts, and system fonts only as a fallback if a bundled font fails to load. The lineup favors the most advanced open faces available in 2026 over the 2017 to 2021 canon. Three themes:

| Theme | Body and headings | Code | Why it earns a place |
|---|---|---|---|
| **Geist** (default since 2026-10-19) | Geist, variable `wght`, true italic | Geist Mono | Chosen from the type board. Swiss, neutral, warm terminals; headings at 600 with negative tracking carry the hierarchy |
| **Flex** | Google Sans Flex, variable: `wght`, `wdth`, `opsz`, `GRAD`, `slnt`, `ROND` | Google Sans Code | Released open in 2025, drawn by David Berlow. The most technically complete open sans ever shipped. The optical size axis gives headings a true display cut, and the grade axis lets dark mode thicken strokes without changing widths. Google Sans Code (2025) is its matched mono, used for code in Gemini |
| **Newsreader** | Newsreader, variable: `wght` 200 to 800, `opsz` 6 to 72 | Geist Mono | Production Type for Google Fonts, built for long-form screen reading, D&AD awarded, L'Obs set its identity in it. The most contemporary open text serif, more editorial than Source Serif 4 and less bookish than Literata |
| **Quattro** | iA Writer Quattro | iA Writer Mono | The reading-purist option. Designed for exactly this kind of app, warm, even texture at 17 pt. Older cut (2018), kept because nothing open has replaced it for hours of prose |

Chrome (palette, comment cards, status line, outline) always uses Google Sans Flex at 12 to 13 pt with `opsz` matched to size, regardless of theme, so the app voice stays constant and the document voice changes with the theme.

Dark mode: on the Flex theme raise `GRAD` by about 20 to 30 units to counter halation on dark backgrounds. On the other themes step weight up one notch (400 to 450 on variable faces) for the same reason.

Alternatives considered and rejected: Inter (excellent, but it is now the default look of every web app), Source Serif 4 (canonical, slightly dated next to Newsreader), Literata (built for e-books, softer than needed), JetBrains Mono (the 2020 standard, Geist Mono and Google Sans Code are cleaner in prose), Instrument Sans + Instrument Serif (the current startup pairing, will age fast), Commit Mono and Monaspace (good, but license files not verified during spec writing). Berkeley Mono, Söhne, Tiempos are proprietary and out.

Type scale at the default 17 pt body, leading 1.55 (26.4 pt). Rhythm unit = one leading.

| Element | Size | Weight | Notes |
|---|---|---|---|
| Body | 17 | 400 | Ragged right, no hyphenation, no justification |
| H1 | 36 (2.1×) | 600 | tracking −0.025 em, line height 1.1 |
| H2 | 26 (1.55×) | 600 | tracking −0.015 em, 0.7 unit + blank above |
| H3 | 20 (1.2×) | 600 | tracking −0.005 em, 0.45 unit + blank above |
| H4 to H6 | 17 | 600 | H5 and H6 also in muted color |
| Code inline | 0.9em mono | 400 | Soft background, 2 pt radius, 1 pt horizontal padding, no border |
| Code block | 0.9em mono | 400 | Soft background, 6 pt radius, 12 pt padding, fence markers dimmed in reading mode and hidden there |
| Blockquote | 17 | 400 | 2 pt left rule in accent at 40%, indented 1 unit. Not italic |
| Table (source) | 0.9em mono | 400 | Aligned by cell in a mono grid so pipes line up visually |
| Caption / status | 12 | 400 | Muted |

Details that are required, not optional:

- Markers hang: `#`, `-`, `*`, `1.`, `>` sit in the gutter right-aligned to the text edge. Body text and heading text share the same left edge. This is the single most important typographic move in the app.
- Syntax markers (`**`, `_`, `` ` ``, `[`, `](url)`, `{>>`) render in muted color at full width in edit mode. On the caret's line they render at full color. In reading mode they collapse to zero width.
- Link URLs in edit mode render muted and at 0.85em so long URLs do not dominate. In reading mode only the link text shows.
- Enable `kern`, `liga`, `calt` for body via `NSFontDescriptor` feature settings. Old-style numerals `onum` in body where the face has them (Newsreader does, check Flex at build time), lining and tabular `tnum` in tables. For the variable faces, set the `opsz` axis to the rendered point size so headings get the display cut and chrome gets the small cut. Set variation axes through `kCTFontVariationAttribute`, never by picking static instances.
- Paragraph spacing is one half unit, never first-line indent.
- Selection color is the accent at 25% alpha. Caret is 2 pt wide in accent.
- Reading mode widens leading to 1.6 and increases body to 18 pt.

### 5.3 Color tokens

Define once, both modes.

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#FBFAF7` | `#1C1B19` | Window |
| `bgElevated` | `#FFFFFF` | `#24231F` | Cards, code blocks |
| `fg` | `#1A1A1A` | `#E8E6E1` | Body text |
| `fgMuted` | `#8A867E` | `#8E8A82` | Markers, URLs, status |
| `fgFaint` | `#C9C5BC` | `#3A3833` | Hairlines, gutter rules |
| `accent` | `#4A25AA` | `#A199FF` | Caret, selection, links, focus |
| `comment` | `#EBB80A` at 22% fill, `#8C6A00` text | `#EBB80A` at 18% fill, `#F2D77A` text | CriticMarkup highlight and card edge |
| `added` | `#35974F` | `#5FBF78` | Change bar for new or changed lines |
| `removed` | `#B9283C` | `#E0606F` | Change bar for lines removed (shown as a 2 pt rule between lines) |

Accent is a deep violet (`#4A25AA` in light, `#A199FF` in dark). It is a token and can be swapped in one place.

### 5.4 Editing model, precisely

- The `NSTextStorage` holds the raw Markdown. Styling is attributes only, never text mutation.
- After each edit, reparse (debounced 16 ms, so effectively per frame) and reapply attributes only to paragraphs whose ranges intersect the edit plus one paragraph each side. Full reapply on load.
- Smart behaviors, all cancelable with ⇧⏎ for a plain newline:
  - Return inside a list continues it, numbering increments, Return on an empty item removes it.
  - Return inside a blockquote continues `> `.
  - Tab / ⇧Tab indent and outdent list items (two spaces).
  - Typing `- [ ] ` yields a task item, ⌘⏎ toggles `[ ]` / `[x]` on the current line.
  - ⌘B, ⌘I wrap or unwrap the selection with `**` and `_`. ⌘K wraps as `[selection](url)` with the caret inside the parentheses, or if the clipboard holds a URL, fills it in.
  - ⌘⇧] / ⌘⇧[ raise or lower the heading level of the current line.
  - ⌥↑ / ⌥↓ move the current line or selection up or down.
  - Typographic quotes, dashes, and text replacement from the system are **off**. The file must contain exactly what was typed.
- Undo is per keystroke group, native NSTextView undo, survives autosave.

### 5.5 Comments

Format, exactly:

```
Anchored:   {==the text being commented on==}{>>@sebo: what I think<<}
Standalone: {>>@sebo: a note about this section<<}
Reply:      {>>@sebo: first<<}{>>@claude: reply<<}   (adjacent comments form a thread)
```

- ⌘⇧M with a selection creates an anchored comment and opens its card for typing. Without a selection it creates a standalone comment at the caret's paragraph end.
- Cards live in the right margin, top-aligned to the first line of their anchor, with a hairline connector. Overlapping cards push down, like Google Docs.
- Card shows the author tag as a small label, the text, and on hover two ghost buttons: Resolve (⌘⇧⌫ when focused) and Reply (⌘⇧R when focused, prefills `@sebo:`).
- Resolve removes the `{>> <<}` and unwraps the `{== ==}`, leaving the anchor text intact. It is a normal undoable edit.
- Click the card to select its anchor. Click the highlighted anchor to focus the card.
- ⌥⌘↓ / ⌥⌘↑ jump to next / previous comment. The palette lists `Next comment`, `Resolve all by @claude`, `Copy all comments as Markdown list`.
- Comments by `@claude` render with a slightly different label color so the conversation is visible at a glance. Author colors are a small table, default muted for unknown tags.
- In reading mode comments remain visible in the margin. This is the review surface.

### 5.6 External changes

- Watch the **parent directory** with FSEvents (Claude's `Write` and most editors do atomic rename, which changes the inode) plus a `DispatchSource` on the file descriptor as a fast path.
- Ignore events whose content hash equals what the app last wrote.
- On change:
  1. Read the new content. Compute a line diff against the last loaded content with `CollectionDifference` (Myers).
  2. If the buffer equals the last saved content, replace the text, restore the caret by anchoring to the nearest unchanged line, and restore the scroll offset so the first visible unchanged line stays put.
  3. If the buffer has unsaved edits, three-way merge at line level: base = last saved, ours = buffer, theirs = disk. Non-conflicting hunks apply. Conflicts keep ours, mark the line with `removed` + `added` bars, and the status line reads `conflict on N lines, yours kept`. Never block with a dialog.
  4. Paint `added` bars on changed lines in the gutter, a thin `removed` rule where lines were deleted. Fade over 8 s or on `Esc`. ⌃↓ / ⌃↑ jump between changes while they are visible.
  5. Status line: `updated · 12 lines` for 3 s. If the change is below the fold, the status line is clickable and scrolls to the first change.
- Target: a change on disk is visible on screen within 50 ms for files up to 100 KB.

### 5.7 CLI

```
md file.md [more.md ...]   open each in its own window, focus if already open
md .                        open the quick switcher scoped to this folder (nice to have)
md -w file.md               block until that window closes (nice to have, enables $EDITOR)
md -                        read stdin into an untitled buffer (nice to have)
md --screenshot out.png file.md   render the window offscreen at 1600×1200@2x and quit
md --version
```

- The CLI is a tiny separate Swift executable, under 5 ms to run. It launches the app if needed via `NSWorkspace` with the bundle id, and passes paths through a `marginalia://open?path=` URL or `NSAppleEventDescriptor`, builder's choice. It must handle relative paths and `~`.
- Exit code 0 on success, 1 with a one-line message on failure. No chatter on stdout.

### 5.8 Navigation and palette

- ⌘K opens the palette, a 560 pt wide floating panel. Fuzzy over commands. Prefix `#` lists headings and jumps on Enter. Prefix `>` is the default command list. Arrow keys, Enter, Esc.
- ⌘⇧O shows the outline as a popover anchored to the title. Current section highlighted and kept in sync with scroll.
- ⌘O lists the last 30 files plus siblings of the current file, fuzzy, Enter opens.
- ⌘F uses the native find bar restyled to the theme. ⌘G / ⌘⇧G next / previous.
- ⌘+ / ⌘- / ⌘0 change body size in 1 pt steps, persisted.
- ⌘⇧R toggles reading mode. ⌘⇧T cycles type theme. ⌘, opens Settings (SwiftUI, one pane: theme, body font, mono font, size, author tag, change-mark fade).

### 5.9 Micro-interactions that make it delightful

- Opening animation: none. The window appears with text already laid out.
- Reading mode toggle: markers collapse with a 120 ms ease, text reflows once. No fade-through-white.
- Change bars draw at full opacity then ease out over the last 2 s of their 8 s life.
- Comment card appears with a 100 ms scale from 0.98, no bounce.
- Status line fades in 150 ms, holds 2 s after scroll end, fades out 400 ms.
- Every sound is off. Every animation respects Reduce Motion.

## 6. Architecture

```
Marginalia/
  Package.swift                 SwiftPM, two products: Marginalia (app), md (cli)
  Sources/
    MarginaliaCore/             pure Swift, no AppKit: parser bridge, CriticMarkup, diff, merge, themes
    MarginaliaApp/              AppKit: AppDelegate, DocumentWindow, EditorTextView, Gutter, MarginView, Palette, Settings
    md/                         CLI
  Tests/
    MarginaliaCoreTests/        parser ranges, CriticMarkup round trips, diff, merge, list continuation
    MarginaliaAppTests/         screenshot-based smoke tests (see §8)
  Resources/
    Fonts/                      Google Sans Flex (variable), Google Sans Code (variable), Newsreader (variable, roman + italic), Geist Mono (variable), iA Writer Quattro, iA Writer Mono. All SIL OFL, license files alongside. Sources: github.com/googlefonts (google-sans-flex, googlesans-code), github.com/productiontype/Newsreader, github.com/vercel/geist-font, github.com/iaolo/iA-Fonts
    Info.plist, Marginalia.entitlements (none), AppIcon
  Scripts/
    bundle.sh                   assemble Marginalia.app from the SwiftPM binary, codesign --sign -
    install.sh
  Makefile                      build, run, test, screenshot, install, clean
  SPEC.md  KICKOFF.md  HANDOFF.md  DECISIONS.md
```

- `MarginaliaCore` has zero UI dependencies so it is fully unit-testable and fast to iterate.
- A `Document` object owns: path, last-loaded text, last-saved hash, parsed tree, comment list, change marks. One per window.
- Styling is a pure function `(tree, theme, mode, caretParagraph) -> [AttributeRun]`, applied to the text storage inside `beginEditing` / `endEditing`.
- TextKit 2 only. If any feature forces a fallback to TextKit 1 (which happens silently when some legacy APIs are touched), that is a bug. Assert `textView.textLayoutManager != nil` in debug after setup.
- Fonts load via `CTFontManagerRegisterFontsForURL` at launch from the bundle, scope `.process`.
- No third-party dependencies except `swift-markdown`. If a syntax highlighter for code blocks is wanted, write a small one for the 8 most common languages (swift, python, ts/js, json, yaml, bash, sql, html) or skip highlighting. Do not pull in a web highlighter.

## 7. Settings and persistence

`UserDefaults` only. Keys: theme, bodyFont, monoFont, bodySize, authorTag, changeFade, keepRunning, recentFiles (30), per-file `{frame, scrollY}` keyed by canonical path (cap 200 entries, LRU).

## 8. Self-verification for an autonomous build

The overnight session cannot see the screen, so the app must make itself observable.

- `md --screenshot out.png file.md` renders a real window offscreen and writes a PNG. Claude reads the PNG after every visual change. A `Fixtures/` folder holds `tour.md` (every Markdown construct, several comments, a long table, a 200-line section) and `large.md` (1 MB generated).
- `make test` runs unit tests headless. `make smoke` builds, screenshots `tour.md` in light and dark, edit and reading mode, and writes four PNGs to `_build/smoke/`.
- `make perf` launches with `--perf file.md` which prints `launch_to_first_paint_ms`, `parse_ms`, `style_ms`, `reload_ms` to stdout and exits. Numbers go into HANDOFF.md every milestone.
- Every window logs to `~/Library/Logs/Marginalia/app.log` with timing lines for open, reload, save. Use `os_signpost` too so Instruments works later.

## 9. Performance budgets, measured on this machine (M-series, macOS 14.8)

| Metric | Budget |
|---|---|
| Cold launch to first painted text, 10 KB file | ≤ 200 ms |
| Open another file while running | ≤ 50 ms |
| Keystroke to paint | ≤ 8 ms (one 120 Hz frame) |
| External change to paint, 100 KB | ≤ 50 ms |
| Open 1 MB file | ≤ 500 ms, scroll stays at 120 Hz |
| Reading mode toggle, 100 KB | ≤ 100 ms |
| Memory, one 100 KB document | ≤ 80 MB |
| App binary + resources | ≤ 25 MB (six font families, variable where available, subset nothing) |

Anything over budget is a bug with the same priority as a crash.

## 10. Milestones and acceptance

Each milestone ends with: tests green, `make smoke` PNGs reviewed, a commit, a HANDOFF.md update.

**M0, Skeleton (first 2 hours).** SwiftPM package, app bundle script, `make run` opens a window with the file in a plain NSTextView, CLI opens files, `--screenshot` works. Accept: `md Fixtures/tour.md` shows text in under 300 ms, PNG produced.

**M1, Typography and hybrid styling.** Themes, bundled fonts, type scale, hanging gutter markers, muted syntax, caret-line reveal, code and table styling, light and dark. Accept: `tour.md` screenshot looks like a finished product. Paragraph edges are flush with heading text. This milestone deserves the most iteration, screenshot after every change.

**M2, Editing.** Smart lists, wraps, heading shortcuts, autosave, undo, per-file window memory. Accept: unit tests for list continuation and wrapping, a 10-minute manual-style scripted edit session produces the exact expected file bytes.

**M3, External changes.** Watching, reload with caret and scroll preservation, change bars, three-way merge, status line. Accept: a test script appends, rewrites, and atomically replaces `tour.md` while open, screenshots show bars on the right lines, and a merge test with a concurrent buffer edit keeps both.

**M4, Comments.** CriticMarkup parse and render, cards in the margin, create, reply, resolve, navigation, palette entries. Accept: round-trip tests (parse → edit → serialize is byte-identical for untouched regions), screenshot with 5 overlapping comments laid out without collisions.

**M5, Reading mode, navigation, print.** Marker collapse, native tables, images, palette, outline, recents, ⌘P. Accept: table in `tour.md` renders as a real table in reading mode, palette jumps to headings, PDF export of `tour.md` looks right.

**M6, Polish and nice-to-haves.** Focus mode, `-w`, stdin, rich copy, perf pass against §9 with numbers in HANDOFF.md.

## 11. Build protocol for the overnight session

- Work in `~/codetmp/marginalia`. Commit after every green milestone and at least hourly, with messages that say what changed for the user, not for the compiler.
- Never ask a question. When a decision is needed, take the default from §3, record it in `DECISIONS.md` with one line of reasoning, and continue. If a decision could waste more than an hour if wrong, implement the default behind a one-line switch.
- When stuck on one problem for more than 45 minutes, stop, write the dead end in HANDOFF.md, implement the simplest fallback, and move on.
- Keep `HANDOFF.md` current: what works, what does not, how to run, perf numbers, screenshots path, the next three things to do. Sebastián reads this first in the morning.
- Do not install anything globally. SwiftPM and system tools only. No Homebrew packages, no npm.
- Do not open Xcode. SwiftPM builds the binaries and `Scripts/bundle.sh` assembles the `.app` by hand. `swift package generate-xcodeproj` no longer exists, so do not plan on an `.xcodeproj` at all.
- Look at your screenshots. If a screenshot would make a designer wince, fix it before adding features. Typography bugs outrank missing features.
- Final step of the night: `make install`, then open `Fixtures/tour.md` with `md` and take one last screenshot of the installed app, so the morning starts with a double-click.
