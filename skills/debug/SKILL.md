---
name: debug
description: "Debug a failing Ripplo test using browser logs, DOM snapshots, and network traces from .ripplo/debug/."
---

# Debug Ripplo Test

## Prerequisite

Re-running needs the app dev server + `npx ripplo watch`. Run `npx ripplo doctor`; if missing, `/ripplo:start`. Reading artifacts doesn't need either.

## Read artifacts first, re-run last

A run takes ~30–60s. Artifacts in `.ripplo/debug/<runId>/` already contain everything the run produced. **Re-running tells you nothing new unless you've changed something.**

Loop: read artifacts → form a specific hypothesis (cite a line) → make ONE targeted change → re-run once to verify. Suspect a flake instead → `/ripplo:flake-detect`, never manually re-run.

## One failing test at a time

Multiple failures: skim every `summary.txt`, pick the most upstream one (precondition/engine/shared-infra over test-specific selector/copy), then own that one test through fix and verify before touching the next. Shared-file edits are fine if that's the real root cause.

Verify with `npx ripplo run <id>` until green, then bare `npx ripplo run` once before moving on so cross-test breakage surfaces immediately. New failure queues as the next iteration. Do one more bare `ripplo run` after the last fix to close out.

Don't batch edits across tests and re-run the suite — when it lights up red you can't tell which edit broke what.

## Procedure

1. Find the test in `.ripplo/tests/` — id is the string passed to `test("<id>")`, not the filename.
2. **Use the existing run's artifacts.** Only `npx ripplo run <id>` if there's no recent run, or you've made a fix and need to verify. **Never pipe through `grep`/`tail`/`head`** to find the failed step — Read the artifacts.
3. Open `manifest.md` — it indexes every artifact with sizes and slicing recipes. Typical read order: `summary.txt` (locate failed step index) → `error.txt` → `steps/<failedIndex>/accessibility-tree.json` → `dom.html` → `storage.json` → run-level logs (`console.log`, `page-errors.log`, `network.jsonl`, `events.jsonl`) → `screenshot.png` last. Diff against `steps/<failedIndex - 1>/` when behavior changed mid-run.

## Common root causes

- **Wrong locator** — element not found. Check accessibility tree, re-read component source.
- **Race condition** — action fires before page settles. Add an assertion before the action.
- **Precondition issue** — state not set up. Check `storage.json`.
- **Parallel collision** — unique-constraint or 401 mid-run, or rows vanishing while a test is still running. Precondition isn't isolating per-run, teardown deletes globally, or a `setup()` is using `update`/`delete` on rows produced elsewhere. Preconditions must be create-only — fix the precondition, not the symptom (see `/ripplo:create` → "Parallel safety").
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

Don't weaken assertions to pass. App bugs go to the user with failing step + expected/actual + relevant log/source excerpt.

For intermittent behavior, `/ripplo:flake-detect` reproduces flakes under parallel load.
