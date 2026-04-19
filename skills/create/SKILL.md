---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

## Procedure

1. Read `packages/testing/README.md` for DSL reference and determinism rules.
2. **Stub first.** Add the test as `.notImplemented()` so it surfaces in `npx ripplo status` and the stub→implementation transition is trackable.
3. **Scope it.** `npx ripplo scope status` — if a free-text user item describes this flow, `npx ripplo scope link <scope-item-id> <test-id>`. Otherwise `npx ripplo scope add <test-id>`. See `/ripplo:scope`.
4. **Register the file.** `.ripplo/index.ts` imports every test/precondition file explicitly. Add `import "./tests/<id>.js";` after creating `.ripplo/tests/<id>.ts` — the CLI only sees what's imported.
5. Browse `.ripplo/preconditions/` for available preconditions. If none fits, add one (and import it from `.ripplo/index.ts`).
6. Read the relevant component/route source to find real ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, **add them to the app first** rather than falling back to `testId()`.
7. Write the test in `.ripplo/tests/`. Id comes from `.test("<id>")`, not the filename.
8. `npx ripplo lint` — fix all errors.
9. `npx ripplo run <id>` — on failure, invoke `/ripplo:debug`.
10. **Stage `.ripplo/ripplo.lock`** alongside test changes (lint writes it; pre-commit blocks stale).

## What makes a good test

Don't just assert the URL changed or that the button you clicked is still visible. Assert:

- **New** elements that appear post-action (dialog opened, success message, page heading)
- Text content (`assert.text` / `assert.value` / `assert.url` / `assert.count` — not just `assert.visible`)
- The mutation result reflected in UI (new list item, counter delta, status change)
- **Backend state** when a UI-only check would miss async side effects (`assert.backend(observerHandle, params)` — see "Observers" below)
- Things that should be gone (`assert.not.visible` for closed dialogs, cleared spinners)

A test that clicks a button and asserts the same button still exists verifies nothing. The `tautological-post-click-assert` lint rule catches this — fix by asserting the actual effect, not by adding another `assert.visible` of the same element.

Re-read each test against its `expectedOutcome` before declaring done.

## Observers (backend state assertions)

Use `assert.backend(observer, params)` when the UI is optimistic, the effect is async (jobs, webhooks, pubsub), or the write-path is load-bearing. Declare observers under `.ripplo/observers/<name>.ts` as shells with `.input<T>().budget("fast" | "slow" | "async").contract()`, then implement server-side with `ripplo.implementObserver(handle, async (ctx, params) => ctx.pass() | ctx.retry(reason) | ctx.fail(reason))`.

- **Budget tiers:** `"fast"` (5s, default) for sync DB reads; `"slow"` (30s) for queue drains; `"async"` (120s) for webhooks, workers, LLM calls. Pick the smallest tier that fits.
- **`ctx.retry(reason)` — default.** Any condition that may resolve on a later poll: not-yet-committed row, status in transition, queue draining, side effect in flight. Runtime polls until budget; the last retry reason surfaces in the failure detail when the budget exhausts. When in doubt, use `retry`.
- **`ctx.fail(reason)` — rare.** Only when further polling cannot succeed (invariant violated, contradictory/forbidden state). Stops immediately after one poll, which produces a confusing "failed after 1 poll" result if used for a transient. Everything that isn't a hard invariant is `retry`.
- Observers return a boolean outcome only — if a test needs to _read_ state for reuse, that's a precondition, not an observer.
- Import the observer handle in the test and use it: `assert.backend(orgNameIs, { orgId, expectedName }).as("assert org persisted")`.

**Lint enforces observers on backend mutations.** The `mutation-without-observer-coverage` rule flags any step that looks like it mutates server state (save/create/delete/update/etc. clicks, uploads, dialog accepts) if no `assert.backend(...)` follows before the next mutation or end of test. Fix by adding a real observer — do NOT silence the rule unless the step genuinely has zero backend effect. For truly client-only steps (cancel a dialog, toggle a display-only control, pick a sort option), pass `{ uiOnly: true }` to the step factory or, for whole-test presentation flows, `ripplo.test(id, { uiOnly: true })`. Always prefer an observer over `uiOnly`.

The `observer-params-reference-variables` rule flags observers whose params are all static strings while the test declares precondition variables — fix by referencing the precondition data (e.g. `expectedName: project.name`).

## Determinism (non-negotiable)

- `role()` locators only; `testId()` only when no ARIA role exists.
- Exact text matching — no `contains`, `startsWith`, regex.
- Destructure precondition data in `steps()` — never hardcode.
- Every step has `.as("description")`.

If a run fails, `/ripplo:debug`. Never weaken assertions to make a test pass — if it's an app bug, report with evidence.
