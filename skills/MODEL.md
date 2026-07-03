# How Ripplo thinks

The mental model behind every Ripplo skill. Read this once and the lint errors, run findings, and explorer behavior all follow from it. Every skill assumes it.

**Done means both halves.** An app change without a passing workflow that proves it isn't done, and a workflow written against broken app behavior isn't done either. Every user-facing change ships with the workflow that demonstrates it working end to end.

## A workflow is a declaration, not a script

A workflow step says two things: what the user does, and what becomes true afterward. "Click Save, and now the success heading is visible, the url is /projects/123, and a project row exists in the database." Ripplo checks all of it — it doesn't just replay clicks and hope.

Because steps declare state instead of scripting waits and retries, Ripplo can do things a script runner can't: predict what every step should produce, compare that prediction against the live app, and reuse what one workflow proved inside every other workflow.

One vocabulary rule: you author **workflows**. A **test** is a workflow with its input parameters pinned — the compiler derives one test per `when` branch (or a single "main" test when there are none). Runs execute tests; you edit workflows.

## Two kinds of state

- **Data** — rows in your app: users, projects, invoices. Declared as entities, seeded by worlds, asserted with `Entity.created / updated / deleted`. Ripplo reads your app's real state through the engine and compares.
- **Page state** — what's on screen right now: the url, what's visible or enabled, what a field contains, and global variables (declared with `singleton(...)` in the DSL, shown as "Global variables" in the dashboard — one concept, and it can live in the backend or the browser). Asserted with `visible(...)`, `url.path.is(...)`, `text(...)`, and friends. Locators are semantic — `button("Save")`, `textbox("Email")` — because they assert accessibility too; `testId` is a last resort for elements with no ARIA role.

New backend state to assert means a new `entity(...)` declaration plus a matching engine impl in the app — the type system flags the missing half. This is the **two-funnel** rule: all definitions flow through one `createRipplo(...)` in `.ripplo/index.ts`, all implementations through one `createEngine(...)` in the app — never a second call site of either.

Every assertion pins one piece of one of these. A mutation step with only page-state assertions ships the "toast said saved, DB didn't" bug as green — that's why backend assertions on mutations are mandatory.

## You can only touch what you've shown exists

A step cannot click a button no earlier step declared visible. Lint enforces this before anything runs.

This is not pedantry. Declarations are how Ripplo learns what's reachable from where — which is what lets the explorer compose paths no workflow author wrote and still know what should be on the page when it gets there. An undeclared button is invisible to the model even when it renders fine; the fix is one `visible(...)` on the step that first shows it.

Corollary: when the same page can show a thing or not (a collapsed group, a toggled panel), the two states need a distinguishing declaration — assert `expanded(...)` on the toggle, not just the disappearance. Otherwise the model sees one page asserting two contradictory things.

## Assertions become facts

What one workflow proves about a page becomes a fact — something Ripplo now knows about that page and enforces everywhere. If the settings workflow shows "at /settings, the Save button is visible," every other workflow that reaches /settings inherits that fact — and so does the explorer, on paths nobody wrote. Negations count too: "the spinner is not visible" is a fact just like "the heading is visible."

Two workflows asserting opposite things about the same page under the same conditions is a contradiction, and lint reports it before any run. One of them is wrong — usually the page has a state dimension neither workflow declared.

Two practical notes:

- `text(locator, "x")` means _contains_ — several `text(...)` assertions on one element can all be true at once.
- Exact-value checks (`value(...)`, `url.query`) are exact. A stray difference is a finding, not noise.

## What is enforced where

| Gate              | When              | Catches                                                                                                                                               |
| ----------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `npx ripplo lint` | before any run    | structure, unreachable interactions, contradicting facts, unreachable `when` branches, stale lockfile                                                 |
| `npx ripplo run`  | live, per step    | every declared expectation vs the real app — page state and backend rows, with a wait window that tolerates propagation lag but fails on wrong values |
| explorer          | in the background | learned facts and backend state on composed paths no workflow author wrote                                                                            |

A failed check is a **finding** — the unit every red run and every explorer catch produces. If lint is red, the model is inconsistent — fix the declarations, don't run around it. If a run is red, read the artifacts first (`npx ripplo explain <runId>`, then raw `behavior.jsonl`), form one hypothesis, make one change, re-run once — never re-run hoping.

Two different timing knobs, often confused: `.wait("slow")` on an assertion lengthens _how long_ Ripplo polls before calling it failed (slow page, long job). `consistency: "eventual"` on a field or variable tolerates _wrong in-between values_ while converging (a flickering redirect, a denormalized counter). Slow is not the same as flickering — reach for `.wait` first.

`.ripplo/ripplo.lock` is the compiled model — committed, regenerated by `ripplo lint`/`compile`, never hand-edited.

## Scope and stubs

**Testing Scope** is the session's contract: the set of workflows this session is responsible for leaving green. Any change that could affect a flow adds its workflow to scope; a flow with no workflow yet gets a **stub** — `workflow("Intent")` with no body — which is a gated promise: hooks won't let the session end with it unimplemented. Scope items are removed only when genuinely out of scope, never because they're work.

## The prime directive

Never weaken a workflow to make it pass. No swapping exact text for contains, no deleting assertions, no fabricated locators, no `testId()` because the accessible name is missing — add the accessible name to the app. A weakened declaration doesn't just soften one workflow; it teaches Ripplo a weaker fact everywhere.
