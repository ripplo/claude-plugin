---
name: debug
description: "Debug a failing Ripplo test using the run output and the captured behavior stream in .ripplo/debug/. Use when a test you ran failed. For triaging background-explorer findings, use /ripplo:fuzz instead."
---

# Debug Ripplo Test

## Prerequisite

Re-running needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`. Reading artifacts needs neither.

## Read artifacts first, re-run last

A run takes ~30–60s and re-running tells you nothing new unless you've changed something. The run output already names the failed step and the findings; `.ripplo/debug/<runId>/behavior.jsonl` holds the full causal stream.

Loop: read findings + behavior stream → form a specific hypothesis (cite an event) → make one targeted change → re-run once to verify.

## The behavior stream

One file per run: `.ripplo/debug/<runId>/behavior.jsonl` — a sorted causal stream, one event per line, discriminated by `kind`:

- `action` — a test step that ran (`click`/`fill`/`goto`/…) with its target.
- `assertion` — a `.expect(...)` check, with `outcome: "passed" | "failed"`.
- `rrweb` — DOM snapshots/mutations (what the page actually showed).
- `network` — fetch/xhr responses (method, url, status).
- `console` / `error` — page console + uncaught page errors.
- `span` — server-side spans, linked to the browser fetch that caused them.

Slice it with grep, don't dump the whole file:

```sh
grep '"outcome":"failed"' .ripplo/debug/<runId>/behavior.jsonl     # the failing assertion
grep '"kind":"error"'   .ripplo/debug/<runId>/behavior.jsonl       # page errors
grep '"kind":"network"' .ripplo/debug/<runId>/behavior.jsonl       # 4xx/5xx around the failure
```

Read the run output's findings first; the stream is the corroborating detail.

To see the page at a moment, render a PNG from the rrweb stream and Read it:

```sh
npx ripplo snapshot <runId> --at <timestamp>      # epoch-ms from any behavior.jsonl event
npx ripplo snapshot <runId> --offset <ms>         # ms from the start of the recording
```

Grep the failing event's `"timestamp"`, then snapshot at it — the jsonl says why, the PNG shows what it looked like. `--offset` brackets early-load frames without epoch arithmetic (`--offset 0`, `--offset 100`, `--offset 250`).

## The decision: app bug vs test gap

Every finding forces one of four moves. The run output's `decide:` line names the likely branch — confirm it against behavior.jsonl before acting:

1. **App bug** — the workflows describe the promised behavior and the app broke it. Fix the app; never weaken the workflow to match broken behavior. File it with `npx ripplo report-bug` (kind tree, bar, and fields in `/ripplo:report`).
2. **Strengthen the assertion** — the app is right and the workflow under-specified the outcome (e.g. a mutation with no backend effect declared). Add the missing `created/updated/deleted` or UI check.
3. **Restrict the `given`** — the expected behavior only holds from a narrower starting state. Tighten this workflow's world so it always starts in the state its assertions assume. If the behavior diverges by state rather than disappearing, add a named `when` branch instead — the compiler enumerates a test per branch.
4. **Split into a new workflow** — the case excluded by restricting `given` is real behavior the workflows should cover. Stub a new workflow with its own world and put it in scope.

Moves 3 and 4 almost always pair: every `given` you tighten implies a state you stopped covering. Ask "what flow now owns that state?" before moving on.

## One failing test at a time

Multiple failures: pick the most upstream one (world/seed or shared-entity over a test-specific selector), own it through fix and verify, then move on. Verify with `npx ripplo run <workflow-slug>/<test-slug>` (just the workflow slug reruns every branch) until green, then bare `npx ripplo run` once so cross-test breakage surfaces. Don't batch edits across workflows — when the suite lights up red you can't tell which edit broke what.

## Procedure

1. Find the workflow in `.ripplo/workflows/` — its identity is the intent string passed to `workflow("<intent>")`, not the filename. A failing test is one enumerated path of that workflow (one when branch, or "main").
2. Use the existing run's output + behavior.jsonl. Only re-run if there's no recent run or you've made a fix. Never pipe `npx ripplo run` through `grep`/`tail`/`head` — Read the output.
3. Read the finding, then the failing `assertion` event, then the surrounding `action`/`network`/`error`/`rrweb` events.

## Common root causes

- **Wrong locator** — element not found. Check the `rrweb` DOM around the step; re-read the component source for the real ARIA role/name.
- **Race** — the action ran before the page was ready. Add a `visible(...)` predicate to the prior step's `.expect(...)`.
- **Backend mismatch** — an `Entity.created/updated/deleted` didn't match. The finding names the entity/field and expected-vs-actual:
  - **wrong-value / missing-row / unexpected-row** → the app's state didn't reach what the test declared: app dropped/mis-wrote the value (check `network`/`span`), or the assertion expects the wrong value.
  - **"never changed within the Ns wait window"** → the app still showed the pre-step value at the deadline — slow write, not wrong. Declare `wait: "slow"` (or `"async"`) on that expectation; don't switch the field to `consistency: "eventual"` (that also tolerates wrong intermediate values).
  - Consistency flags: `strict` means the field must match immediately after the step, `eventual` means it may lag briefly and Ripplo waits for it. A wrong intermediate value under `strict` fails fast by design — app bug, not timing.
  - Server-chosen value → assert `changed()` instead of pinning a literal.
  - Genuine flicker-through-wrong-values (rare) → the field may need `consistency: "eventual"`.
- **Page rule violation** — "A page rule learned from <workflow> ... never held here", naming the originating workflow. Ripplo generalizes assertions like "at URL X, heading Y is visible" into page rules enforced across tests. If your workflow legitimately reaches that URL in a different state, make the originating assertion conditional: `when(branch("no items yet").if(count(Entity).is(0)).expect(visible(heading("No items"))))`.
- **Duplicate locator (strict mode)** — `resolved to 2 elements`. Scope the target: `inside(main(), button("New"))`, `inside(row(schedule.name), button("Delete"))`. Container rows usually need an `aria-label` in the app — add it; don't fall back to `testId`.
- **World / seed wrong** — the starting state isn't what the workflow assumes. Check the engine impl's `seed`/`read`, not the workflow.
- **Parallel collision** — unique-constraint error, 401 mid-run, rows vanishing. The engine impl isn't isolating per-run (run-scoped ids in `seed`, `runPrefix(runId)` in `read`/cleanup). See `/ripplo:create` → "Parallel safety".
- **App bug** — file via `npx ripplo report-bug` (see `/ripplo:report`), then report to the user with the finding + failing step + evidence. Don't work around.
- **Stale lockfile** (422 on push / "unsupported lockfile version") — `npx ripplo compile` and commit. Never hand-edit the lockfile.
- **Server out of sync** — `"<slug>" was synced but the server didn't return it` → `npx ripplo sync`.
