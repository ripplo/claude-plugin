---
name: debug
description: "Debug a failing Ripplo test using browser logs, DOM snapshots, and network traces from .ripplo/debug/."
---

# Debug Ripplo Test

## Steps

1. Browse `.ripplo/tests/` (including subfolders) to find the test. Each test declares its id via `.test("<id>")`.
2. Run `npx ripplo run <id>` if the test hasn't been run recently.
3. Read debug artifacts from `.ripplo/debug/<runId>/`:
   - `steps/<failedIndex>/dom.html` — inspect the actual DOM at the failing step
   - `steps/<failedIndex>/accessibility-tree.txt` — find correct ARIA roles and locators
   - `steps/<failedIndex>/storage.json` — check auth state and session data
   - Compare with `steps/<failedIndex - 1>/` to see what changed
   - `console.log` — grep for errors/warnings around the failure timestamp
   - `network.jsonl` — check for failed requests or unexpected responses
   - `page-errors.log` — uncaught JavaScript exceptions

## Common root causes

- **Wrong locator**: element not found — check accessibility tree, re-read component source
- **Race condition**: action fires before page transition — add assertion before the action
- **Precondition issue**: state not set up correctly — check storage.json for auth/session
- **Parallel collision**: unique constraint error — precondition creates shared data instead of unique-per-run
- **App bug**: the application itself is broken — report to the user, don't work around it
