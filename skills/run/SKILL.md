---
name: run
description: "Run Ripplo e2e tests, diagnose failures, manage Testing Scope, and file caught app bugs — the whole run→diagnose→file loop. Use when executing tests, when a run fails, when a drift nudge fires, when the user says 'in scope' / 'out of scope', when they want to teleport / open a live browser at a step in a test, or the moment you confirm a real app bug. For triaging background-explorer findings, use /ripplo:tasks."
---

# Run Ripplo Tests

```sh
npx ripplo run                          # auto-scopes dirty workflows + runs scope (default)
npx ripplo run <workflow-slug> ...      # one workflow — all its tests
npx ripplo run <workflow-slug>/<test-slug>  # one test path (one when branch; "main" when none)
npx ripplo run --all                    # full suite — minutes, use sparingly
```

**Scope is the unit of iteration.** Bare `npx ripplo run` auto-adds dirty `.ripplo/workflows/*.ts` to scope then runs it. Explicit ids for a one-off rerun; `--all` only when the user asks.

## Requirements

App dev server + `npx ripplo daemon` (run refuses otherwise). `npx ripplo doctor` checks both; if red, `/ripplo:start`. If it reports `"<slug>" was synced but the server didn't return it`, run `npx ripplo sync`. Reading artifacts needs neither process.

## Background explorer — the third gate

It walks composed paths no author wrote, catches combine-only bugs. Leave it on. Findings arrive as `finding` tasks → `/ripplo:tasks`.

```sh
npx ripplo explore                     # show state
npx ripplo explore on | off            # toggle (needs a live daemon session)
npx ripplo explore --trail <n>         # path depth (default 12)
npx ripplo explore --workers <n>       # concurrency (default 2)
```

`explore off` is momentary — the next green run re-enables it. Durable off = `npx ripplo hooks pause` (silences all Ripplo gates).

## On failure — read artifacts first, re-run last

Re-running tells you nothing unless you changed something. Don't pipe `npx ripplo run` through `grep`/`tail`/`head`. Loop: explain → form a specific hypothesis (cite an event) → one targeted change → re-run once.

### Start with explain

`npx ripplo explain <runId>` — first move on any failed run. Per failing check, grouped by step: the failed check, expected vs actual for a backend mismatch, where a fact was declared, the surrounding network/console/span events, and the exact `snapshot --at` frame. The runId is in the run output. Auto-pulls the stream on demand (local and cloud alike). Drop to the raw stream only for detail `explain` didn't surface.

### The behavior stream

`.ripplo/debug/<runId>/behavior.jsonl` — one causal event per line, discriminated by `kind`. `explain`/`snapshot`/`tasks show` auto-pull it when missing; fetch alone with `npx ripplo pull <runId>`. Kinds: `action`, `assertion` (`outcome`), `finding` (`subject`/`expected`/`actual`), `rrweb`, `network`, `console`/`error`, `span`.

Slice it, don't dump it:

```sh
grep '"outcome":"failed"' .ripplo/debug/<runId>/behavior.jsonl     # failing assertion
grep '"kind":"error"'   .ripplo/debug/<runId>/behavior.jsonl       # page errors
grep '"kind":"network"' .ripplo/debug/<runId>/behavior.jsonl       # 4xx/5xx
```

Render a frame to PNG and Read it:

```sh
npx ripplo snapshot <runId> --at <timestamp>      # epoch-ms from any event
npx ripplo snapshot <runId> --offset <ms>         # ms from recording start
```

Grep the failing event's `"timestamp"`, snapshot at it. `snapshot` also writes `snapshot-<ms>ms.html` — the DOM with every element tagged `data-rrweb-id` + real attrs/roles; grep it for the real ARIA role/name (locator debugging).

### Teleport into a live app

When a static PNG isn't enough, hand the user a live browser seeded through step `n`:

```sh
npx ripplo teleport <workflow-slug>/<test-slug> --step <n>
```

- **`--step` is a 1-based count.** behavior.jsonl `index` is 0-based → to land at `index k`, pass `--step (k+1)`.
- **Blocks until the window closes.** Never a plain foreground call — use `run_in_background`, or tell the user to run `! npx ripplo teleport …`.
- **Prereqs:** app dev server + a signed-in token, **not** `npx ripplo daemon`.
- Fails before step `n` → it reports the finding and exits; that finding is your bug.
- For human exploration, not verifying a fix — re-run to verify.

### App bug vs test gap — four moves

The run output's `decide:` line names the likely branch — confirm against behavior.jsonl.

1. **App bug** — the app broke promised behavior. Fix the app, never weaken the workflow. File it (below).
2. **Strengthen the assertion** — app right, workflow under-specified. Common gaps: a mutation with no `created/updated/deleted`; an undeclared UI delta (a row leaves a filter, a label swaps, a section unmounts). Declare what appeared/disappeared on the mutation step.
3. **Restrict the `given`** — the behavior only holds from a narrower state. Tighten givens. If it diverges by state rather than disappearing, add a `when` branch.
4. **Split into a new workflow** — the excluded case is real behavior. Stub a new workflow with its own givens, put it in scope.

Moves 3 and 4 pair: every `given` you tighten implies a state you stopped covering — ask "what flow owns that state?"

### One failing test at a time

Pick the most upstream failure (given/seed over a test-specific selector), fix + verify, move on. Verify with `npx ripplo run <workflow-slug>/<test-slug>` until green, then bare `npx ripplo run` once so cross-test breakage surfaces. Don't batch edits across workflows.

### Procedure

1. Find the workflow in `.ripplo/workflows/` — identity is the `workflow("<intent>")` string, not the filename.
2. Use the existing run's output + behavior.jsonl. Re-run only after a fix.
3. Read the finding, then the failing `assertion` event, then the surrounding `action`/`network`/`error`/`rrweb`.

### Common root causes

- **Wrong locator** — element not found. Snapshot the frame, grep `snapshot-<ms>ms.html` for the real ARIA role/name, re-read the component.
- **Race** — the action ran before the page was ready. Add a `visible(...)` to the prior step's `.expect(...)`.
- **Backend mismatch** — an `Entity.created/updated/deleted` didn't match; the finding names entity/field + expected-vs-actual:
  - **wrong-value / missing-row / unexpected-row** → app dropped/mis-wrote the value (check `network`/`span`) or the assertion is wrong.
  - **"never changed within the Ns wait window"** → slow write, not wrong. Declare `wait: "slow"` (or `"async"`); don't switch to `consistency: "eventual"`.
  - `strict` = must match immediately; `eventual` = may lag, Ripplo waits. A wrong intermediate value under `strict` = app bug.
  - Server-chosen value → `changed()`, or `increased()`/`decreased()` when the direction matters.
  - Genuine flicker through wrong values (rare) → `consistency: "eventual"`.
- **Fact violation** — a declaration from another workflow contradicted here. If your workflow legitimately reaches that state with a different outcome, the originating step is under-declared (missing a `checked`/`not(visible(...))`/state pin that distinguishes the two states) or needs a `when` branch — harden the declaration, never weaken it.
- **Duplicate locator (strict mode)** — `resolved to 2 elements`. Scope: `inside(main(), button("New"))`, `inside(row(schedule.name), button("Delete"))`. Add an app `aria-label`; don't fall back to `testId`.
- **Given / seed wrong** — check the engine impl's `seed`/`read`, not the workflow.
- **Seed exists but action does nothing** — the click runs, no mutation lands, no network request; the button is dead because the app needs more state (a cancellable booking, a confirmed status, an unlocking toggle). Snapshot the frame, add the missing state to the seed impl.
- **Parallel collision** — unique-constraint, 401 mid-run, vanishing rows. The impl isn't isolating per-run (run-scoped ids in `seed`, `runPrefix(runId)` in `read`/cleanup). See `/ripplo:create` → "Parallel safety".
- **App bug** — file it (below), report to the user with evidence. Don't work around.
- **App never signaled ready** (`appNotReady`) — the app didn't call `ready()` from `@ripplo/testing` after loading. Wire it at the genuine interactive point behind the build-time testing flag (see `/ripplo:setup` step 5). Not a test bug.
- **Stale lockfile** (422 / "unsupported lockfile version") — `npx ripplo compile` and commit. Never hand-edit.
- **Server out of sync** — `npx ripplo sync`.

## Filing a caught bug

When a run surfaces a **real app bug**, file it for the Caught Bugs dashboard:

```sh
npx ripplo report-bug \
  --kind <new_feature_bug|regression|latent_bug> \
  --title "Short bug name" \
  --root-cause "What was actually wrong in the app code" \
  --surfaced-by "How the run exposed it — cite the failing assertion or behavior.jsonl evidence" \
  --run <runId>
```

`--run` is required — the catching run, links the bug to its replay. For an exploration finding, pass its repro `explore-…` run id.

**The bar:** only functionality bugs in the app under test — behavior a user would call broken. Do not file: test gaps / wrong locators / races / under-specified assertions / given-seed problems (model fixes); flaky infra / daemon / sync / stale lockfiles; style / copy / cosmetic; anything unconfirmed against evidence.

**Kind:** built this session → `new_feature_bug`; worked before a recent change → `regression`; already broken, new coverage exposed it → `latent_bug`.

**When:** the moment a decision lands on app bug, before reporting back. One report per distinct root cause (cite the most direct test/run). Filing doesn't replace telling the user — surface it with evidence.

**Fields:** `--title` names the broken behavior not the test; `--root-cause` the actual defect (function, file, missing branch, dropped call); `--surfaced-by` one or two sentences of evidence.

## Testing Scope

Scope = the session's success contract: the e2e flows that must pass for the work to count as done. Lives in the dev-session DB (Developer Mode → Testing Scope), dies with the PR; the durable artifacts are the workflows. Scope a flow → write its workflow (`/ripplo:create`) → run it green.

Accurate, broad scope is **your** job. For any non-trivial change: list every flow it could affect, scope them all (write missing, `scope add` existing), err toward breadth. Upper bound ~50 workflows — hitting it means split into phases with the user, not narrow coverage.

```sh
npx ripplo scope status                              # list current scope
npx ripplo scope add <slug> [<slug>...]              # bind existing workflows by slug (variadic)
npx ripplo scope link <scope-item-id> <slug>         # link a user free-text item to a workflow you wrote
npx ripplo scope remove <scope-item-id> [<id>...]    # remove (variadic)
```

- **Edited workflows auto-scope once they compile clean.** Don't `scope add` workflows you're editing — only untouched existing ones, or to reverse a remove.
- **`scope add` references existing workflows only.** Free-text intents → write a matching workflow and `scope link` it.
- **`scope remove` is not a shortcut to clear the gate.** Valid: wrong flow, duplicate, "not this session," feature cut. Size / effort / length never valid.
- **Flow list too large? Parallelize, don't trim** — `/ripplo:create` → "Parallelizing multi-workflow sessions."
- **Scope persists across CLI restarts** and auto-injects into every prompt — don't run `scope status` reflexively.

### When to add

- Any task that could affect an e2e flow (frontend, backend, schema, infra, config) → `scope add` an existing workflow or write one per affected flow.
- Mid-task discovery → write its workflow.
- Drift nudge (user-facing code changed without a matching workflow) → add the flow or revert.
- User-added free-text item → write the workflow and `scope link` it.
