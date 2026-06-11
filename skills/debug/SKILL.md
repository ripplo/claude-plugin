---
name: debug
description: "Debug a failing Ripplo test using the run output and the captured behavior stream in .ripplo/debug/. Also handles exploration findings: invoke with 'findings' (or when asked to triage exploration findings) to triage what the background explorer caught."
---

# Debug Ripplo Test

## Prerequisite

Re-running needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`. Reading artifacts doesn't need either.

## Read artifacts first, re-run last

A run takes ~30–60s. The run's output already names the failed step and the oracle's findings, and `.ripplo/debug/<runId>/behavior.jsonl` holds the full causal stream. **Re-running tells you nothing new unless you've changed something.**

Loop: read findings + behavior stream → form a specific hypothesis (cite an event) → make ONE targeted change → re-run once to verify.

## What you get

Each run writes one file: `.ripplo/debug/<runId>/behavior.jsonl` — a sorted, line-delimited causal stream. One event per line, discriminated by `kind`:

- `action` — a test step that fired (`click`/`fill`/`goto`/…) with its target.
- `assertion` — a `.expect(...)` check, with `outcome: "passed" | "failed"`.
- `rrweb` — browser DOM snapshots/mutations (the replay; tells you what the page actually showed).
- `network` — fetch/xhr responses (method, url, status).
- `console` / `error` — page console + uncaught page errors.
- `span` — server-side spans (when the OTLP receiver is up), linked to the browser fetch that caused them.

Slice it with Bash, don't dump the whole file:

```sh
grep '"outcome":"failed"' .ripplo/debug/<runId>/behavior.jsonl     # the failing assertion
grep '"kind":"error"'   .ripplo/debug/<runId>/behavior.jsonl       # page errors
grep '"kind":"network"' .ripplo/debug/<runId>/behavior.jsonl       # 4xx/5xx around the failure
```

The run output itself renders the oracle's **findings** — the structured reason a step failed. Read those first; the behavior stream is the corroborating detail.

To **see** the page at any moment, render a screenshot from the rrweb stream and Read the printed PNG:

```sh
npx ripplo snapshot <runId> --at <timestamp>      # epoch-ms timestamp from any behavior.jsonl event
npx ripplo snapshot <runId> --offset <ms>         # ms from the start of the recording (0–duration)
```

Grep the failing event's `"timestamp"` first, then snapshot at it — the jsonl tells you _why_, the PNG shows _what it looked like_. Use `--offset` when you think in "N ms into the recording" (e.g. bracketing early-load frames: `--offset 0`, `--offset 100`, `--offset 250`) — no epoch arithmetic needed. An out-of-range moment prints the recording's span and duration.

## The decision: app bug vs model gap

Every finding forces one of four moves. The run output's `decide:` line names the likely branch — confirm it against behavior.jsonl before acting:

1. **App bug** — the model describes the promised behavior and the app diverged. Fix the app. Never weaken the test to match broken behavior. **File it**: `npx ripplo report-bug` with the run id and evidence. Kind: broken behavior was built this session → `--kind new_feature_bug`; it worked before a recent change broke it → `--kind regression`; it was already broken and new coverage exposed it → `--kind latent_bug`. File only confirmed functionality bugs in the app under test — never test gaps, locator/race issues, or infra flakes. Full bar + field guidance in `/ripplo:report`.
2. **Strengthen the assertion** — the app is right and the test under-specified the outcome (e.g. a mutation with no backend effect declared, a `ghost-write` for a side effect the flow really does perform). Add the missing `created/updated/deleted` or UI check.
3. **Restrict the `given`** — the expected behavior only holds from a narrower starting state (e.g. the flow behaves differently when a row already exists). Tighten this test's world so it always starts in the state its assertions assume.
4. **Split into a new test** — the case you just excluded by restricting `given` is real behavior the model should cover. Stub a new test for it with its own world and click path, and put it in scope. Restriction without a covering test is a coverage hole, not a fix.

Moves 3 and 4 almost always pair: every `given` you tighten implies a state you stopped covering. Ask "what flow now owns that state?" before moving on.

## One failing test at a time

Multiple failures: pick the most upstream one (a world/seed or shared-entity issue over a test-specific selector), own that one test through fix and verify, then move on. Verify with `npx ripplo run <test-id>` (the slug from the failure output) until green, then bare `npx ripplo run` once before moving on so cross-test breakage surfaces. Don't batch edits across tests and re-run the suite — when it lights up red you can't tell which edit broke what.

## Procedure

1. Find the test in `.ripplo/tests/` — id is the intent string passed to `test("<intent>")`, not the filename.
2. **Use the existing run's output + `behavior.jsonl`.** Only `npx ripplo run <test-id>` if there's no recent run, or you've made a fix and need to verify. Never pipe `npx ripplo run` through `grep`/`tail`/`head` — Read the output.
3. Read the finding, then the failing `assertion` event, then the surrounding `action`/`network`/`error`/`rrweb` events to see what the page and backend actually did.

## Common root causes

- **Wrong locator** — element not found / action couldn't target. Check the `rrweb` DOM around the step, re-read the component source for the real ARIA role/name.
- **Race** — the action fired before the page settled. Add a `visible(...)` (or other) predicate to the prior step's `.expect(...)` so the run waits.
- **Consistency divergence** — an `Entity.created/updated/deleted` assertion didn't match. The finding names the entity/field and the expected-vs-observed values:
  - **field-mismatch / absent / ghost-write** → the DB didn't reach the expected state. Either the app dropped/mis-wrote the value (app bug — check `network`/`span` for the mutation), or the assertion expects the wrong value.
  - **"write never landed within the Ns ... settle budget"** → the app still showed the _pre-step_ value at the deadline — a slow write, not a wrong one. Declare `wait: "slow"` (or `"async"`) on that expectation; do NOT switch the field to `consistency: "eventual"` (that would also tolerate wrong intermediate values).
  - A _wrong_ intermediate value under strict consistency fails fast by design — that's an app bug (the UI/DB showed a value that should never appear), not a timing issue.
  - If the value is server-chosen, the assertion should use `changed()` rather than pin a literal.
  - If it's genuine flicker-through-wrong-values (rare), the field may need `consistency: "eventual"`.
- **View law violation** — `view law never held` with a `law from:` line naming the originating test/trigger. Ripplo generalizes assertions like "at URL X, heading Y is visible" into laws enforced across tests. If your test legitimately reaches that URL in a different state (e.g. seeded rows vs empty state), fix the _originating_ test's assertion to be conditional: `when([count(Entity).is(0), visible(heading("No items"))])`.
- **Duplicate locator (strict mode)** — Playwright `resolved to 2 elements`. Two identically-named elements (header CTA + empty-state CTA, one icon button per row). Scope the target: `inside(main(), button("New"))`, `inside(row(schedule.name), button("Delete"))`, `inside(dialog("Edit"), button("Save"))`. Container rows usually need an `aria-label` in the app — add it; don't fall back to `testId`.
- **World / seed wrong** — the starting state isn't what the test assumes. The engine impl's `seed` produced the wrong row, or its `read` isn't scoped to the run. Check the impl, not the test.
- **Parallel collision** — unique-constraint error, 401 mid-run, or rows vanishing while a test runs. The engine impl isn't isolating per-run (run-scoped ids in `seed`, `runPrefix(runId)` in `read`/cleanup). Fix the impl (see `/ripplo:create` → "Parallel safety").
- **App bug** — file via `npx ripplo report-bug` (kind tree in "The decision" above; full bar in `/ripplo:report`), then report to the user with the finding + the failing step + relevant `network`/`error`/source excerpt. Don't work around.
- **Stale lockfile** (422 on push / "unsupported lockfile version") — `npx ripplo compile` and commit. Never hand-edit the lockfile.
- **Server out of sync** — `npx ripplo run` reports `Test "<slug>" was synced but the server didn't return it`. Run `npx ripplo sync` to re-push.

## Findings mode (exploration triage)

Invoked as `/ripplo:debug findings` (or any ask to triage exploration findings). The daemon's background explorer (P3) composes action sequences no test author wrote and records oracle violations as **findings** in a local ledger. Your job is the refine step: confirm each finding, classify it, fix, and verify.

**List:** `npx ripplo explore findings` — pending findings sorted in triage order (oracle layer ascending: crash → invariant → law → frame; occurrence count descending within a layer), plus recurrent flaky-candidates (same divergence 3+ times, never deterministically reproduced — triage these last; they usually indicate a race). Each entry shows a `diverged:` summary — findings with the same diverging step usually share one root cause; fix the shared cause once, then replay the siblings. `--json` for machine-readable output. Scope to what the user asked for — default is all pending; a count or a specific id narrows it.

**Detail:** `npx ripplo explore findings <id>` — one finding's full evidence: the oracle's rendered divergence lines (expected vs observed), trail, occurrence window, captured run + behavior.jsonl path. Read this before opening the behavior stream.

**Per finding, one at a time:**

1. **Evidence.** Start with `npx ripplo explore findings <id>`. The finding's `run <runId>` is a captured exploration run — read `.ripplo/debug/<runId>/behavior.jsonl` with the same grep/snapshot recipes above. The trail line shows the minimal action sequence (`test#step` labels) that triggers it.
2. **Classify** — same decision as above, sharper stakes:
   - **App bug** — the model is right, the app breaks when actions compose this way. Fix the app. File it: `npx ripplo report-bug` with the exploration run id (`--test` omitted — there is no test); kind per the decision tree above (usually `latent_bug` — exploration finds territory no author covered).
   - **Model gap** — the oracle fired because a declaration is missing or wrong (an effect the transition really has but never declared, a view-law scoped too broadly, a world builder producing an unintended state). Fix the declaration in `.ripplo/`.
3. **Verify + resolve:** `npx ripplo explore replay <findingId>` — replay is the only way any fix (app or model) gets re-validated. A clean replay resolves the finding and marks its targets covered under the current model. If the model edit made the witnessed composition unplannable (e.g. a narrowed `given`), replay reports it **unreachable** and resolves the finding — make sure a test covers the state you excluded. Still-reproduces means the fix didn't land; diverged means the behavior changed but is still wrong — re-read evidence.
4. **After any fix, replay the other pending findings before deep-diving them** — one root cause often resolves siblings with different signatures.

**Add-vs-weaken guardrail.** Model edits that ADD declarations (a missing effect, a narrowing `when` condition, a new covering test) are normal fixes. Model edits that DELETE or WEAKEN declarations (dropping a law, removing a declared effect, coarsening a vocabulary) make the oracle permanently blind there — only do this after proving from app source that the current behavior is intended, and cite that proof to the user. Never silence a finding by loosening the model when the app is wrong.

## Discipline

Don't weaken assertions to pass. App bugs go to the user with the failing step + expected/actual + relevant evidence from the behavior stream.
