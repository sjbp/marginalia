# Architecture

One window per file. One `NSTextView` (TextKit 2) holds the raw Markdown; everything you see is attributes on that text plus a few views floating over it. Nothing is ever rewritten in the storage for display, so every subsystem can key on source offsets.

## Data flow per edit

1. `NSTextStorage` changes → `DocumentWindowController.textStorage(_:didProcessEditing:)` records the edited range and schedules one restyle on the next run-loop turn.
2. `reparseAndStyle` → `MarkdownParser.parse` (MarginaliaCore) builds a `DocumentModel`: per-line info (kind, list depth, hanging prefix length, heading level), inline spans (strong, code, link, CriticMarkup…), tables, code blocks, comments, headings. Parsing runs on a background queue above 200 k characters.
3. `Styler.paintFlags` turns inline spans into one `UInt32` of flags per UTF-16 unit.
4. `Styler.apply` writes attributes line by line: font, color, paragraph style (indents give the hanging gutter), hidden runs (0.1 pt clear font) in rendered mode, kern for table pipes in source mode. After an edit only lines whose signature changed are touched (`dirtyLines`), so TextKit keeps its layout for the rest.
5. `EditorTextView.drawBackground` paints what attributes cannot: selection on text extents, code panels, quote rules, hairlines, list bullets and checkboxes in rendered mode, change bars.
6. `viewWillDraw` positions the floating views (comment cards, table and image overlays) from the real layout, after forcing viewport layout and contiguous layout from the viewport start.

## Modes

`Styler.mode` is `.rendered` (default, syntax hidden) or `.source` (everything visible). Rendered mode never reveals syntax under the caret; instead `EditorTextView` makes hidden runs behave: arrow keys skip them, backspace on a marker unwraps the span, the caret never rests inside one (`DocumentWindowController.textViewDidChangeSelection`).

## Files

| Area | Where |
|---|---|
| Parser, source map (UTF-8 columns → UTF-16), CriticMarkup, line kinds | `Sources/MarginaliaCore/Parser.swift`, `SourceMap.swift`, `CriticMarkup.swift`, `Model.swift` |
| Editing rules (lists, wraps, headings, tasks, block toggles), pure and tested | `Sources/MarginaliaCore/SmartEdit.swift` |
| Line diff and three-way merge for external changes | `Sources/MarginaliaCore/LineDiff.swift` |
| Window, layout column, scrolling, external reload, comments actions, typing attributes | `Sources/MarginaliaApp/DocumentWindowController.swift` |
| Attributes, themes, metrics, hidden runs | `Sources/MarginaliaApp/Styler.swift`, `Theme.swift`, `FontCache.swift` |
| Key handling, selection drawing, background drawing | `Sources/MarginaliaApp/EditorTextView.swift` |
| Comment thread cards | `Sources/MarginaliaApp/CommentMargin.swift` |
| Native tables and images in rendered mode | `Sources/MarginaliaApp/ReadingOverlays.swift` |
| Format bar, mode toggle, title band, status line | `FormatBar.swift`, `StatusLine.swift` |
| Palette, outline, quick open | `Palette.swift` |
| File watching (FSEvents + vnode) | `FileWatcher.swift` |
| Headless driving for tests and screenshots | `EditScript.swift`, `Screenshot.swift`, `Launch.swift` |
| CLI | `Sources/md/main.swift` |
| Brand mark (code) and icon generator | `BrandMark.swift`, `Scripts/make-icon.py` |

## Scrolling and TextKit 2

TextKit 2 estimates the geometry of text it has not laid out, and those estimates drift after edits. Rules that follow from that, all in `DocumentWindowController`:

- Programmatic scrolls bring the range into view, verify by hit test, align with the on-screen rect, and re-check on later turns (`scroll(toOffset:)`, `settle`).
- Floating views are positioned only after `ensureLayout` from the viewport start to the anchor.
- Measurements use whole-line rects, because a line's first characters may be hidden runs.

## Tests

- `swift test`: Core unit tests (parser, smart edits, diff/merge, block formatting).
- `make edit-test`: a scripted editing session must produce exact bytes.
- `make overlay-test`: real key and mouse events; floating views must stay on their lines after every keystroke. `MARGINALIA_FULL_RESTYLE=1 MARGINALIA_NO_ENSURE=1` reproduces the old behaviour and fails it.
- `Fixtures/*.script` cover external changes, scroll preservation, and comment threads. Run them with `md --edit-script`.
- `make smoke`: screenshots for a human look.
