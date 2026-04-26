---
name: debug
description: "Debug a failing Ripplo test using browser logs, DOM snapshots, and network traces from .ripplo/debug/."
---

# Debug Ripplo Test

## Prerequisite — dev session must be live

Re-running a failed test (the verify step at the end of the loop) needs two background processes: the app's dev server, and `npx ripplo watch`. Run `npx ripplo doctor` first — if either is missing, run `/ripplo:start` (or spawn `npx ripplo watch` directly via `Bash` with `run_in_background`) and start the app dev server the same way if it isn't up. Without watch, `ripplo run` refuses to dispatch. (Reading artifacts under `.ripplo/debug/` does not require either.)

## Read artifacts first, re-run last

A run takes ~30–60s. Artifacts in `.ripplo/debug/<runId>/` already contain everything the run produced — DOM, a11y tree, console, network, screenshots. **Re-running tells you nothing new unless you've changed something.**

Loop: read artifacts → form a specific hypothesis (cite a line) → make ONE targeted change → re-run once to verify.

Anti-patterns:

- Re-running because "maybe it'll pass this time." Suspect a flake → use `/ripplo:flake-detect`, never manually re-run.
- Re-running before reading any artifact.
- Reading only `summary.txt` and re-running. Always open the failed step's `dom.html` + `accessibility-tree.txt` first.

## Procedure

1. Find the test in `.ripplo/tests/` — id is the string passed to `test("<id>")`, not the filename.
2. **Use the existing run's artifacts.** Only `npx ripplo run <id>` if there's no recent run, or you've made a fix and need to verify. **Never pipe through `grep`/`tail`/`head`** to find the failed step — Read the artifacts.
3. Read `.ripplo/debug/<runId>/` in this order:
   1. `summary.txt` — locate the failed step index.
   2. `error.txt` — top-level errors (server unreachable, config).
   3. `steps/<failedIndex>/dom.html` — actual DOM at failure.
   4. `steps/<failedIndex>/accessibility-tree.txt` — correct ARIA roles/locators.
   5. `steps/<failedIndex>/storage.json` — auth/session.
   6. Diff against `steps/<failedIndex - 1>/` to see what changed.
   7. `console.log`, `network.jsonl`, `page-errors.log`.
   8. `steps/<failedIndex>/screenshot.png` — last resort; confirms, doesn't diagnose.

## Common root causes

- **Wrong locator** — element not found. Check accessibility tree, re-read component source.
- **Race condition** — action fires before page settles. Add an assertion before the action.
- **Precondition issue** — state not set up. Check `storage.json`.
- **Parallel collision** — unique-constraint or 401 mid-run. Precondition isn't isolating per-run, or teardown deletes globally. Fix the precondition.
- **Observer failure** — `assert.backend(...)` step failed. The detail line tells you what to check:
  - `failed (invariant): <reason> (after N poll(s))` → observer returned `ctx.fail(...)`. If N is 1, first check whether the observer should have used `ctx.retry(reason)` instead — anything "not yet committed" / "not found yet" / "status not yet X" is a retry, not a fail.
  - `budget "fast|slow|async" exhausted after N poll(s); last: <reason>` → observer stayed in retry the whole budget. The async work never finished, OR the budget tier is too short. Check whether the write actually happened (logs, DB), then decide: fix the app, or bump `.budget(...)` to a longer tier.
  - `transport error: <reason>` → engine adapter unreachable / 4xx / 5xx. Config issue, not an app bug.
- **App bug** — report to the user with evidence; don't work around.
- **Stale lockfile** (422 on push, "unsupported lockfile version") — `npx ripplo compile` and commit. Never hand-edit the lockfile.
- **Server out of sync with local `.ripplo/` resources** — symptom: `npx ripplo run` reports `Test "<slug>" was synced but the server didn't return it`. Run `npx ripplo sync` to re-push and check the server log for the `SyncDevSession` mutation.

## Coverage errors

These surface at `stop-enforce`, not at runtime. Fix `.coverage(...)`, don't re-run.

- **"New user-facing interactions were introduced without test coverage"** — diff added a button/input/etc. that no test claims. Read the listed IDs, pick the natural owning test, add them to its `.coverage(...)`. If none fits, stub a new test (`/ripplo:create`).
- **"`.coverage(...)` claims reference coverage statements that don't exist"** — claimed ID no longer resolves (component renamed/deleted). Remove the stale ID, or update to the new one (check `.ripplo/coverage.d.ts`).
- **Full-tree audit:** `npx ripplo cover` lists every unacknowledged statement and stale claim, independent of diff.

## Discipline

- **Text first, screenshots second.** Grep `console.log`/`network.jsonl` before opening any image.
- **Evidence before changes.** Cite a specific artifact line. "I think the locator is wrong" isn't evidence; "accessibility-tree line 42 shows role=link not button" is.
- **Don't weaken assertions to pass.** App bugs go to the user with failing step + expected/actual + relevant log/source excerpt.

For intermittent behavior, `/ripplo:flake-detect` reproduces flakes under parallel load.
