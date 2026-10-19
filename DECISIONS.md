# Decisions log

One line each, newest first. Defaults from SPEC §3 unless noted.

- 2026-10-18 Google Fonts' build of Google Sans Flex has no `GRAD` axis (axes: opsz, wdth, wght, ROND, slnt). Dark mode compensates with +40 weight on every theme instead.
- 2026-10-18 CLI finds the app relative to its own binary (`Marginalia.app/Contents/MacOS/md`), so `~/.local/bin/md` is a symlink into the bundle. No bundle-id lookup needed, works for dev builds too.
- 2026-10-18 Swift tools 5.10, language mode 5. Strict concurrency of Swift 6 mode adds nothing for a single-window AppKit app and costs hours.
