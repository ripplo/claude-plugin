---
name: debug
description: "Debug a failing Ripplo test using browser logs, DOM snapshots, and network traces from .ripplo/debug/."
---

# Debug Ripplo Test

## Steps

1. Browse `.ripplo/tests/` (including subfolders) to find the test. Each test declares its id via `.test("<id>")`.
2. Run `npx ripplo run <id>` if the test hasn't been run recently. **Do not re-run to reshape stdout** — never pipe `npx ripplo run` through `grep`/`tail`/`head`/`paste` to find the failed step or pair ids with results. The failure data is already on disk; Read it.
3. Read debug artifacts from `.ripplo/debug/<runId>/` in this order:
   - `summary.txt` — per-step pass/fail with durations; start here to locate the failed step index
   - `error.txt` — top-level error (dev server unreachable, config issues, etc.)
   - `steps/<failedIndex>/dom.html` — inspect the actual DOM at the failing step
   - `steps/<failedIndex>/accessibility-tree.txt` — find correct ARIA roles and locators
   - `steps/<failedIndex>/storage.json` — check auth state and session data
   - Compare with `steps/<failedIndex - 1>/` to see what changed
   - `console.log` — errors/warnings around the failure timestamp
   - `network.jsonl` — failed requests or unexpected responses
   - `page-errors.log` — uncaught JavaScript exceptions
   - `steps/<failedIndex>/screenshot.png` — last resort. Only open after the text artifacts above; screenshots confirm, they don't diagnose

## Common root causes

- **Wrong locator**: element not found — check accessibility tree, re-read component source
- **Race condition**: action fires before page transition — add assertion before the action
- **Precondition issue**: state not set up correctly — check storage.json for auth/session
- **Parallel collision**: unique constraint error or "not authorized" mid-run — precondition creates shared data instead of unique-per-run, or teardown globally deletes all test data instead of only that run's. Fix the executor.
- **App bug**: the application itself is broken — report to the user, don't work around it
- **Stale lockfile** (server-side 422 on push, or "unsupported lockfile version" error): `.ripplo/ripplo.lock` is missing, stale, or newer than the server supports. Run `npx ripplo compile` locally and commit the result — do not hand-edit the lockfile.

## Diagnosis discipline

- **Text first, screenshots second.** Always grep `console.log` and `network.jsonl` before opening any image. Text is faster to search and usually more informative — screenshots only confirm what the logs already told you.
- **Evidence before changes.** Never modify the spec without citing a specific line from a debug artifact. "I think the locator is wrong" isn't evidence; "accessibility-tree.txt line 42 shows the button has role=link not button" is.
- **Don't weaken assertions to make a test pass.** If the failure is an app bug (unexpected API response, JS exception, broken UI), report it to the user with the evidence — failing step, expected vs actual, the relevant log/network excerpt, and source code if applicable. Removing the assertion that catches the bug is never the right fix.
- **3-strike escape hatch.** If the same failure repeats after 3 targeted fixes informed by debug artifacts, stop and report the root cause to the user. Do not silently keep retrying — repeated failure on the same step almost always means the diagnosis is wrong, not that one more tweak will work.

## Once the fix passes

A single green run isn't enough — many failure classes (precondition sharing, race conditions, non-exact text) only surface under parallel load. After your fix, invoke `/ripplo:flake-detect` to verify determinism. If flakes appear, see the "Parallel safety for preconditions" section in `/ripplo:explore` — most flakes trace back to non-isolated precondition data.
