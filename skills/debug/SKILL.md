---
name: debug
description: "Debug a failing Ripplo test using browser logs, DOM snapshots, and network traces from .ripplo/debug/."
---

# Debug Ripplo Test

## Read artifacts first, re-run last

A run takes ~30-60s. Artifacts in `.ripplo/debug/<runId>/` already contain everything the run produced — DOM, a11y tree, console, network, screenshots. **Re-running tells you nothing new unless you've changed something.** The default loop is: read artifacts → form a specific hypothesis (cite a line) → make ONE targeted change → re-run once to verify.

Anti-patterns:

- Re-running because "maybe it'll pass this time" — flakes are the exception, not the diagnosis. If you suspect a flake, use `/ripplo:flake-detect` (it parallelizes), don't manually re-run.
- Re-running before reading any artifact.
- Reading only `summary.txt` and re-running. Always open the failed step's `dom.html` + `accessibility-tree.txt` before the next action.

## Procedure

1. Find the test in `.ripplo/tests/` — id is the string passed to `test("<id>")`, not the filename.
2. **Use the existing run's artifacts.** Only `npx ripplo run <id>` if there's no recent run, OR you've made a fix and need to verify. **Never pipe through `grep`/`tail`/`head`** to find the failed step — Read the artifacts.
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
- **Observer failure** — `assert.backend(...)` step failed. The detail line reports the shape clearly:
  - `failed (invariant): <reason> (after N poll(s))` → observer returned `ctx.fail(...)`. This only terminates polling — so if N is 1, first check whether the observer implementation should have used `ctx.retry(reason)` instead (anything "not yet committed" / "not found yet" / "status not yet X" is a retry, not a fail). Only if the condition is a true invariant, investigate the backend state.
  - `budget "fast|slow|async" exhausted after N poll(s); last: <reason>` → observer stayed in `ctx.retry(...)` the whole budget — the async work never finished, OR the budget tier is too short for this pipeline. Check whether the write actually happened (logs, DB), then decide: fix the app, or bump the observer's `.budget(...)` to a longer tier.
  - `transport error: <reason>` → engine adapter unreachable / 4xx / 5xx — config issue, not an app bug.
- **App bug** — report to the user with evidence; don't work around.
- **Stale lockfile** (422 on push, "unsupported lockfile version") — `npx ripplo compile` and commit. Never hand-edit the lockfile.

## Exhaustiveness (coverage) errors

These surface at `stop-enforce`, not at test runtime. Fix the `.coverage(...)` array, don't re-run the test.

- **"New user-facing interactions were introduced without test coverage"** — the diff added a button/input/etc. that no test's `.coverage(...)` claims. Read the listed coverage statement IDs, locate the owning component, decide which test should exercise each interaction, and add the ID to that test's `.coverage(...)` array. If no existing test is a natural fit, stub a new one (see `/ripplo:create`).
- **"`.coverage(...)` claims reference coverage statements that don't exist"** — a claimed ID no longer resolves to any coverage statement in the tree (component was renamed/deleted/refactored). Remove the stale ID from the test's `.coverage(...)`. If the test was covering something real that moved, update the ID to the new one (check `.ripplo/coverage.d.ts`).
- **Full-tree audit:** `npx ripplo cover` lists every unacknowledged coverage statement and every stale claim across the codebase, independent of diff.

## Discipline

- **Text first, screenshots second.** Grep `console.log`/`network.jsonl` before opening any image.
- **Evidence before changes.** Cite a specific artifact line. "I think the locator is wrong" isn't evidence; "accessibility-tree line 42 shows role=link not button" is.
- **Don't weaken assertions to pass.** If it's an app bug, report with the failing step + expected/actual + relevant log/source excerpt.
- **3-strike rule.** Same failure after 3 targeted fixes → stop and report. Repeated failure on the same step almost always means the diagnosis is wrong.

If you suspect intermittent behavior, `/ripplo:flake-detect` reproduces flakes under parallel load.
