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

It symbolically plans valid composed journeys no author wrote, then runs the most meaningfully
different plans first. The planner proves the whole trail against workflow declarations before it
opens a browser. Local and cloud workers use the same planner. Leave it on.

Application crashes and confirmed declaration contradictions arrive as finding tasks. A confirmed
explicit carried visibility contradiction arrives as a separate workflow coverage gap. Both route
through `/ripplo:tasks`.

```sh
npx ripplo explore                     # show state
npx ripplo explore on                  # enable (needs a live daemon session)
npx ripplo explore off                 # disable
npx ripplo explore on --trail <n>      # enable and set path depth (default 12)
npx ripplo explore on --workers <n>    # enable and set concurrency (default 2)
npx ripplo explore analyze             # show how useful the current model is for exploration
npx ripplo explore analyze --json      # machine-readable analysis
```

Exploration stays in the selected state until another explicit toggle. `npx ripplo hooks pause`
silences all Ripplo gates.

`analyze` uses the exact production planner without running the app. Use it when exploration is
waiting for workflow coverage or keeps finding few useful plans. Fix the highest-impact missing
declarations and shallow journeys it reports.

## On failure — read artifacts first, re-run last

Re-running tells you nothing unless you changed something. Don't pipe `npx ripplo run` through `grep`/`tail`/`head`. Loop: explain → form a specific hypothesis (cite an event) → one targeted change → re-run once.

### Start with explain

`npx ripplo explain <runId>` — first move on any failed run. Per failing check, grouped by step: the
failed check, expected vs actual for a state-source mismatch, where a fact was declared, the
surrounding network/console/span events, and the exact `snapshot --at` frame. The runId is in the
run output. Auto-pulls the stream on demand (local and cloud alike). Drop to the raw stream only for
detail `explain` didn't surface.

### The behavior stream

`.ripplo/debug/<runId>/behavior.jsonl` starts with a format header, then contains one causal event
per line. `explain`, `snapshot`, and `tasks show` pull it when missing. Check events carry typed
outcomes for browser assertions, declared state effects, and frame violations. Step errors preserve
structured engine diagnostics.

Slice it, don't dump it:

```sh
grep '"kind":"failed"'    .ripplo/debug/<runId>/behavior.jsonl     # failed checks (outcome.kind)
grep '"kind":"stepError"' .ripplo/debug/<runId>/behavior.jsonl     # infrastructure errors
grep '"kind":"error"'     .ripplo/debug/<runId>/behavior.jsonl     # page errors
grep '"kind":"network"'   .ripplo/debug/<runId>/behavior.jsonl     # 4xx/5xx
```

Render a frame to PNG and Read it:

```sh
npx ripplo snapshot <runId> --at <timestamp>      # epoch-ms from any event
npx ripplo snapshot <runId> --offset <ms>         # ms from recording start
```

Grep the failing event's `"timestamp"`, snapshot at it. `snapshot` also writes `snapshot-<ms>ms.html` — the DOM with every element tagged `data-rrweb-id` + real attrs/roles; grep it for the real ARIA role/name (locator debugging).

### Teleport into a live app

When a static PNG isn't enough, hand the user a live browser set up and replayed through step `n`:

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
3. **Model the real precondition** — the action only has the declared result from a behaviorally
   meaningful subset of state. Add the least-specific relation, presence, absence, or permission
   constraint that proves it. If the same intent and click path diverge by state, use `optional()`
   plus named `when` branches.
4. **Split a different journey** — the excluded case has a different user intent or click path.
   Give it its own workflow and put it in scope.

Do not hardcode a convenient starting value to turn a failure green. Every added constraint excludes
state. Name the behavior that requires it, then make sure a branch or another journey owns the
excluded behavior.

### One failing test at a time

Pick the most upstream failure (starting-state setup before a test-specific selector), fix and
verify, then move on. Verify with `npx ripplo run <workflow-slug>/<test-slug>` until green, then bare
`npx ripplo run` once so cross-test breakage surfaces. Don't batch edits across workflows.

### Procedure

1. Find the workflow in `.ripplo/workflows/` — identity is the `workflow("<intent>")` string, not the filename.
2. Use the existing run's output + behavior.jsonl. Re-run only after a fix.
3. Read the failing `check` event (and any `stepError`), then the surrounding `action`/`network`/`error`/`rrweb`.

### Common root causes

- **Wrong locator** — element not found. Snapshot the frame, grep `snapshot-<ms>ms.html` for the real ARIA role/name, re-read the component.
- **Race** — the action ran before the page was ready. Add a `visible(...)` to the prior step's `.expect(...)`.
- **Application-state mismatch** — a typed state effect did not match. The failure names the source,
  path or collection, expected value, and observed value:
  - **wrong-value / missing-row / unexpected-row** → app dropped/mis-wrote the value (check `network`/`span`) or the assertion is wrong.
  - **"never changed within the Ns wait window"** → first determine whether the source is
    legitimately eventually consistent. If it is, annotate that schema path with
    `consistency.eventual(...)`. If the UI alone is slow, use `.wait("slow")` on the UI predicate.
    Do not hide a wrong value behind a longer wait.
  - App-chosen value → `transform(({ before, after }) => not(equals(after, before)))`.
  - Known direction or formula → an ordered or exact `transform()` relation.
- **Fact violation** — a declaration from another workflow contradicted here. If your workflow legitimately reaches that state with a different outcome, the originating step is under-declared (missing a `checked`, `not(visible(...))`, or typed state relation that distinguishes the two states) or needs a `when` branch. Harden the declaration, never weaken it.
- **Duplicate locator (strict mode)** — `resolved to 2 elements`. Scope: `inside(main(), button("New"))`, `inside(row(schedule.name), button("Delete"))`. Add an app `aria-label`; don't fall back to `testId`.
- **Starting state wrong** — inspect the synthesized input, source setup implementation, and full
  source read.
- **Setup succeeds but the action does nothing** — the click runs, no mutation lands, and no network request fires. Inspect the app source for the real precondition, then model that precondition without fixing unrelated values. Cover state-dependent outcomes with `when`.
- **Parallel collision** — unique-constraint, 401 mid-run, vanishing rows. A source setup, read, or teardown implementation is not isolated by `runId`. Scope every source operation to the current run.
- **App bug** — file it (below), report to the user with evidence. Don't work around.
- **App never signaled ready** (`appNotReady`) — the app did not call the connection's `ready()`
  after loading. Wire `connect(browserEngine)` from `@ripplo/testing/browser` before render when
  the schema has browser state, or `connect()` when it does not. Then call `connection.ready()` at
  the genuine interactive point behind the build-time browser flag. `connect` mounts and gates
  browser state setup. `ready()` only marks the page interactive. See `/ripplo:setup` step 5. Not a
  test bug.
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

**The bar:** only functionality bugs in the app under test — behavior a user would call broken. Do not file: test gaps / wrong locators / races / under-specified assertions / starting-state model problems; flaky infra / daemon / sync / stale lockfiles; style / copy / cosmetic; anything unconfirmed against evidence.

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
