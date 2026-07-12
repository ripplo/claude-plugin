---
name: run
description: "Run Ripplo e2e tests, diagnose failures, manage Testing Scope, and file caught app bugs — the whole run→diagnose→file loop. Use when executing tests, when a run fails, when a drift nudge fires, when the user says 'in scope' / 'out of scope', when they want to teleport / open a live browser at a step in a test, or the moment you confirm a real app bug. For triaging background-explorer findings, use /ripplo:tasks."
---

# Run Ripplo Tests

```sh
npx ripplo run                          # auto-scopes dirty workflows + runs scope (default)
npx ripplo run <workflow-slug> ...      # one workflow — runs all its enumerated tests
npx ripplo run <workflow-slug>/<test-slug>  # one test path (one when branch; "main" when no branches)
npx ripplo run --all                    # full suite — minutes of compute, use sparingly
```

**Scope is the unit of iteration.** Bare `npx ripplo run` auto-adds dirty `.ripplo/workflows/*.ts` files to scope, then runs every runnable scope item — the right default while iterating. Explicit ids only for a one-off rerun (workflow slug = all its tests, workflow/test = one branch); `--all` only when the user explicitly asks.

## Requirements

Needs the app dev server + `npx ripplo daemon` (run refuses to dispatch otherwise). `npx ripplo doctor` checks both; if red, `/ripplo:start`. Run compiles + syncs `.ripplo/` on demand. If it reports `"<slug>" was synced but the server didn't return it`, run `npx ripplo sync`. Reading artifacts needs neither process.

## The background explorer — the third gate

A green `npx ripplo run` (no failures, nothing not-run) auto-enables the background explorer. It's the third gate — it walks composed paths no workflow author wrote, fills coverage gaps, and catches bugs that only surface when actions combine. Leave it on. Findings arrive as tasks of kind `finding` — triage them via `/ripplo:tasks`.

```sh
npx ripplo explore                     # show explorer state
npx ripplo explore on | off            # toggle (needs a live daemon session)
npx ripplo explore --trail <n>         # path depth (default 12)
npx ripplo explore --workers <n>       # concurrency (default 2)
```

It runs on either executor — cloud explores over the tunnel, and `explore on` never switches where runs execute. A manual `npx ripplo explore off` is momentary — the next green run re-enables it. The only durable off switch is `npx ripplo hooks pause`, which also silences the other Ripplo gates.

## On failure — read artifacts first, re-run last

The CLI prints the failed step, the findings, and `Debug artifacts: .ripplo/debug/<runId>/`. A run takes ~30–60s and re-running tells you nothing new unless you've changed something. Don't pipe `npx ripplo run` through `grep`/`tail`/`head`, and don't re-run to reshape stdout. Only rerun after a fix.

Loop: explain the run → form a specific hypothesis (cite an event) → make one targeted change → re-run once to verify.

### Start with explain

`npx ripplo explain <runId>` is the first move on any failed run — it reads `behavior.jsonl` back to you instead of making you grep it. For each failing check, grouped by step: the check that failed, the expected vs actual values for a backend mismatch, where a fact was learned from (and a nudge when it fired in a different flow than it was learned in), the network/console/span events around the failure, and the exact `snapshot --at` for the failing frame. The runId is in the run output (`Debug artifacts: .ripplo/debug/<runId>/`); `explain` auto-pulls the stream on demand — runs aren't kept on local disk, so this happens for local and cloud runs alike. Drop to the raw stream below only when you need detail `explain` didn't surface.

### The behavior stream

One file per run: `.ripplo/debug/<runId>/behavior.jsonl` — a sorted causal stream, one event per line, discriminated by `kind`. `explain`, `snapshot`, and `tasks show` auto-pull this file when it's missing (a cloud run, or the folder was cleaned up); to fetch it on its own, `npx ripplo pull <runId>`. Events:

- `action` — a test step that ran (`click`/`fill`/`goto`/…) with its target.
- `assertion` — a `.expect(...)` check, with `outcome: "passed" | "failed"`.
- `finding` — a backend/state mismatch or crash, with `subject`, `expected`, `actual` (surfaced by `explain`).
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

Alongside the PNG, `snapshot` writes `snapshot-<ms>ms.html` — the same frame's DOM with every element tagged `data-rrweb-id` and carrying its real attributes/roles. Grep it for an element's class or text to read the real ARIA role/name (locator debugging) or its rrweb id. Prefer this over hand-reading `rrweb` events in the stream.

### When a static frame isn't enough — teleport into a live app

`snapshot` is a dead PNG. When you need to actually poke the app from the failing point — open a dropdown, watch a live request, try a different input — hand the user a live browser seeded with the run up to that step:

```sh
npx ripplo teleport <workflow-slug>/<test-slug> --step <n>
```

It re-drives the real test against the real app/backend through the first `n` steps, then leaves the browser open for the user to drive. State is real (the run genuinely performed those actions); it tears down when the user closes the window.

- **`--step` is a 1-based count of steps to run.** behavior.jsonl/timeline `index` is 0-based, so to land at the step shown as `index k`, pass `--step (k+1)`.
- **It blocks until the window closes.** Never run it as a plain foreground call — you'll hang the turn. Either run it with `run_in_background`, or tell the user to launch it themselves with `! npx ripplo teleport …`.
- **Prereqs differ from `run`:** needs the app dev server reachable and a signed-in token, but **not** `npx ripplo daemon`.
- Fails before step `n` (an action errors or an assertion fails on the way) → it reports that finding and exits without handing over. That finding is your bug — debug it like any other.
- It's for human exploration, not assertions. Don't teleport to verify a fix — re-run the test.

### The decision: app bug vs test gap

Every finding forces one of four moves. The run output's `decide:` line names the likely branch — confirm it against behavior.jsonl before acting:

1. **App bug** — the workflows describe the promised behavior and the app broke it. Fix the app; never weaken the workflow to match broken behavior. File it (see "Filing a caught bug" below).
2. **Strengthen the assertion** — the app is right and the workflow under-specified the outcome. Two common gaps: a mutation with no `created/updated/deleted`, and a mutation whose UI delta went undeclared — the row that leaves a filtered list, a toggle label that swaps, a section that unmounts. Declare what appeared and what disappeared on the mutation step itself.
3. **Restrict the `given`** — the expected behavior only holds from a narrower starting state. Tighten this workflow's givens so it always starts in the state its assertions assume. If the behavior diverges by state rather than disappearing, add a named `when` branch instead — the compiler enumerates a test per branch.
4. **Split into a new workflow** — the case excluded by restricting `given` is real behavior the workflows should cover. Stub a new workflow with its own givens and put it in scope.

Moves 3 and 4 almost always pair: every `given` you tighten implies a state you stopped covering. Ask "what flow now owns that state?" before moving on.

### One failing test at a time

Multiple failures: pick the most upstream one (given/seed or shared-entity over a test-specific selector), own it through fix and verify, then move on. Verify with `npx ripplo run <workflow-slug>/<test-slug>` (just the workflow slug reruns every branch) until green, then bare `npx ripplo run` once so cross-test breakage surfaces. Don't batch edits across workflows — when the suite lights up red you can't tell which edit broke what.

### Procedure

1. Find the workflow in `.ripplo/workflows/` — its identity is the intent string passed to `workflow("<intent>")`, not the filename. A failing test is one enumerated path of that workflow (one when branch, or "main").
2. Use the existing run's output + behavior.jsonl. Only re-run if there's no recent run or you've made a fix.
3. Read the finding, then the failing `assertion` event, then the surrounding `action`/`network`/`error`/`rrweb` events.

### Common root causes

- **Wrong locator** — element not found. Snapshot the step's frame and grep the `snapshot-<ms>ms.html` for the real ARIA role/name; re-read the component source to confirm.
- **Race** — the action ran before the page was ready. Add a `visible(...)` predicate to the prior step's `.expect(...)`.
- **Backend mismatch** — an `Entity.created/updated/deleted` didn't match. The finding names the entity/field and expected-vs-actual:
  - **wrong-value / missing-row / unexpected-row** → the app's state didn't reach what the test declared: app dropped/mis-wrote the value (check `network`/`span`), or the assertion expects the wrong value.
  - **"never changed within the Ns wait window"** → the app still showed the pre-step value at the deadline — slow write, not wrong. Declare `wait: "slow"` (or `"async"`) on that expectation; don't switch the field to `consistency: "eventual"` (that also tolerates wrong intermediate values).
  - Consistency flags: `strict` means the field must match immediately after the step, `eventual` means it may lag briefly and Ripplo waits for it. A wrong intermediate value under `strict` fails fast by design — app bug, not timing.
  - Server-chosen value → assert `changed()` instead of pinning a literal, or `increased()`/`decreased()` when the direction matters (a bumped counter, a touched timestamp).
  - Genuine flicker-through-wrong-values (rare) → the field may need `consistency: "eventual"`.
- **Fact violation** — "A fact learned from <workflow> ... never held here", naming the originating workflow. Ripplo generalizes assertions like "at URL X, heading Y is visible" into facts enforced across tests. If your workflow legitimately reaches that URL in a different state, make the originating assertion conditional: `when(branch("no items yet").if(count(Entity).is(0)).expect(visible(heading("No items"))))`.
- **Duplicate locator (strict mode)** — `resolved to 2 elements`. Scope the target: `inside(main(), button("New"))`, `inside(row(schedule.name), button("Delete"))`. Container rows usually need an `aria-label` in the app — add it; don't fall back to `testId`.
- **Given / seed wrong** — the starting state isn't what the workflow assumes. Check the engine impl's `seed`/`read`, not the workflow.
- **Seed exists but the action does nothing** — the click runs, but no mutation lands and the step made no network request. The row is there, yet the button is dead because the app needs more state first (a booking that can be cancelled, a confirmed status, a toggle that unlocks the action). Snapshot the frame (`npx ripplo snapshot <runId> --at <timestamp>`) to see the disabled or no-op control, then add the missing state to the seed in the engine impl. Working out which state the handler needs is usually the hard part, not the test.
- **Parallel collision** — unique-constraint error, 401 mid-run, rows vanishing. The engine impl isn't isolating per-run (run-scoped ids in `seed`, `runPrefix(runId)` in `read`/cleanup). See `/ripplo:create` → "Parallel safety".
- **App bug** — file it (see below), then report to the user with the finding + failing step + evidence. Don't work around.
- **App never signaled ready** (`appNotReady` — "the app never called ready() within 30s") — the app didn't call `ready()` from `@ripplo/testing` after loading. Either it's not wired at all (see `/ripplo:setup` step 5), or the call sits behind a condition that never becomes true / a screen that never renders. Wire it at the app's genuine interactive point, gated behind the build-time testing flag. Not a test bug — don't touch the workflow.
- **Stale lockfile** (422 on push / "unsupported lockfile version") — `npx ripplo compile` and commit. Never hand-edit the lockfile.
- **Server out of sync** — `"<slug>" was synced but the server didn't return it` → `npx ripplo sync`.

## Filing a caught bug

When a run surfaces a **real application bug**, file it so it lands on the project's Caught Bugs dashboard:

```sh
npx ripplo report-bug \
  --kind <new_feature_bug|regression|latent_bug> \
  --title "Short bug name" \
  --root-cause "What was actually wrong in the app code" \
  --surfaced-by "How the test/run exposed it — cite the failing assertion or behavior.jsonl evidence" \
  --run <runId>
```

`--run` is required — it's the catching run, and it links the bug to its replay on the dashboard. For an exploration finding, pass its repro `explore-…` run id (shown on the finding in the Issues dashboard): the bug links straight to the finding.

### The bar for filing

Only **functionality bugs in the app under test** — behavior a user would hit and call broken. Every dashboard entry should be something the team is glad the tests caught.

Do not file:

- Test gaps, wrong locators, races, under-specified assertions, given/seed problems — those are model fixes.
- Flaky infrastructure, daemon/sync issues, stale lockfiles.
- Style, copy, or cosmetic issues with no functional impact.
- Anything unconfirmed against evidence (failing assertion, network/span trace, page error).

### Picking the kind

- Broken behavior was built **this session** → `new_feature_bug`.
- It **worked before** a recent change broke it → `regression`.
- It was **already broken** and new coverage exposed it → `latent_bug`.

### When to file

- The moment a run's decision lands on app bug — file before reporting back to the user.
- In `/ripplo:create`, when a new test fails against an existing flow and the app is confirmed wrong → `latent_bug`.
- After any run that caught broken behavior you then fixed — file with the run id of the catching (red) run.

One report per distinct root cause. A bug breaking five tests is one report; cite the most direct test/run.

### Writing the fields

- `--title` — name the broken behavior, not the test: "Checkout total ignores applied coupon", not "checkout test failed".
- `--root-cause` — the actual defect: function, file, missing branch, dropped call.
- `--surfaced-by` — one or two sentences of evidence: which assertion failed, what behavior.jsonl showed.

Filing doesn't replace telling the user — still surface it in your response with the evidence.

## Testing Scope

Scope is the session's success contract: the e2e flows that must pass for the work to count as done. It lives in the dev-session DB (visible in Developer Mode → Testing Scope) and dies with the PR; the durable artifacts are the workflows in `.ripplo/workflows/`. **Scope is intent; a passing test is proof.** Scope a flow → write its workflow (`/ripplo:create`) → run it green.

Accurate, sufficiently broad scope is **your** job, not the user's. They describe what they're building; you translate to the flows that must pass. For any non-trivial change:

- Enumerate every flow it could affect — new flows and existing flows whose behavior might shift.
- Scope them all: write missing workflows, `scope add` existing ones.
- Err toward breadth. Under-scoping is the default failure mode.

Upper bound: ~50 workflows in scope. Hitting it means split the work into phases with the user, not narrow coverage.

### Commands

```sh
npx ripplo scope status                              # list current scope
npx ripplo scope add "<intent>" ["<intent>"...]      # bind existing workflows (variadic — one call, no shell loops)
npx ripplo scope link <scope-item-id> "<intent>"     # link a user free-text item to a workflow you wrote
npx ripplo scope remove <scope-item-id> [<id>...]    # remove (variadic)
```

### Rules

- **Edited workflows auto-scope once lint-clean.** Don't `scope add` workflows you're actively editing — only previously-existing workflows you didn't touch, or to reverse a remove.
- **`scope add` references existing workflows only.** Free-text intents come from the user — write a matching workflow and `scope link` it.
- **`scope remove` is not a shortcut to clear the gate.** Valid: wrong flow, duplicate, user said "not this session," feature cut. Size, effort, and session length are never valid reasons.
- **Flow list too large? Parallelize, don't trim.** See `/ripplo:create` → "Parallelizing multi-workflow sessions."
- **Scope persists across CLI restarts** — items return on next start.
- **Current scope auto-injects into every prompt** — don't run `scope status` reflexively.

### When to add

- Any task that could affect an e2e flow (frontend, backend, schema, infra, config) → `scope add` an existing workflow or write a new one per affected flow.
- Mid-task discovery — a new flow surfaces, write its workflow.
- Drift nudge — user-facing code changed without a matching workflow; add the missing flow or revert the change.
- User-added free-text item — write the workflow and `scope link` it.
