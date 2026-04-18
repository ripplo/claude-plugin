---
name: debug
description: "Debug a failing Ripplo test using browser logs, DOM snapshots, and network traces from .ripplo/debug/."
---

# Debug Ripplo Test

## Procedure

1. Find the test in `.ripplo/tests/` — id is `.test("<id>")`, not the filename.
2. `npx ripplo run <id>` if not run recently. **Never pipe through `grep`/`tail`/`head`** to find the failed step — Read the artifacts.
3. Read `.ripplo/debug/<runId>/` in this order:
   1. `summary.txt` — locate the failed step index
   2. `error.txt` — top-level errors (server unreachable, config)
   3. `steps/<failedIndex>/dom.html` — actual DOM at failure
   4. `steps/<failedIndex>/accessibility-tree.txt` — correct ARIA roles/locators
   5. `steps/<failedIndex>/storage.json` — auth/session
   6. Diff against `steps/<failedIndex - 1>/` to see what changed
   7. `console.log`, `network.jsonl`, `page-errors.log`
   8. `steps/<failedIndex>/screenshot.png` — last resort, confirms not diagnoses

## Common root causes

- **Wrong locator** — element not found; check accessibility tree, re-read component source.
- **Race condition** — action fires before page settles; add an assertion before the action.
- **Precondition issue** — state not set up; check `storage.json`.
- **Parallel collision** — unique-constraint or 401 mid-run; precondition isn't isolating per-run, or teardown deletes globally. Fix the precondition.
- **App bug** — report to the user with evidence; don't work around.
- **Stale lockfile** (422 on push, "unsupported lockfile version") — `npx ripplo compile` and commit. Never hand-edit the lockfile.

## Discipline

- **Text first, screenshots second.** Grep `console.log`/`network.jsonl` before opening any image.
- **Evidence before changes.** Cite a specific artifact line. "I think the locator is wrong" isn't evidence; "accessibility-tree line 42 shows role=link not button" is.
- **Don't weaken assertions to pass.** If it's an app bug, report with the failing step + expected/actual + relevant log/source excerpt.
- **3-strike rule.** Same failure after 3 targeted fixes → stop and report. Repeated failure on the same step almost always means the diagnosis is wrong.

If you suspect intermittent behavior, `/ripplo:flake-detect` reproduces flakes under parallel load.
