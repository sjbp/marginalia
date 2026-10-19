# Kickoff prompt for the overnight build

Paste this into a fresh Claude Code session started in `~/codetmp/marginalia`:

---

Build Marginalia, the native macOS Markdown workbench specified in `SPEC.md`. Read the whole spec first, then `DECISIONS.md` if it exists.

Operate autonomously all night under the build protocol in SPEC.md §11: never ask me anything, take the defaults in §3 for open decisions and log them in `DECISIONS.md`, commit after each milestone and at least hourly, keep `HANDOFF.md` current as the first thing I will read in the morning.

Work the milestones in order, M0 through M5, then M6 if time remains. Do not skip ahead. M1 (typography) deserves the most iteration: screenshot with `md --screenshot` after every visual change and look at the PNG before moving on. The performance budgets in §9 are requirements.

Everything must build, test, run, and screenshot from the terminal with the Makefile. Do not open Xcode, do not install global packages. When done for the night, run `make install` so `md Fixtures/tour.md` works from any terminal, take a final screenshot of the installed app, and finish `HANDOFF.md` with perf numbers and the next three things to do.

---

Suggested invocation:

```
cd ~/codetmp/marginalia && claude --permission-mode bypassPermissions "$(cat KICKOFF.md | sed -n '/^---$/,/^---$/p' | sed '1d;$d')"
```

Or just open `claude` in the folder and paste the block between the rules.
