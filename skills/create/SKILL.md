---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

## Prerequisites — load these skills first

Before running the procedure below, make sure you have these skills in context — they own concerns this skill assumes:

- **`/ripplo:setup`** — dev session, hooks, project wiring, `pnpm dev`. Re-read if `npx ripplo status` errors, the dev server isn't running, or you're unsure whether the session is active.
- **`/ripplo:scope`** — what scope is, the bulk `add`/`remove` commands, and the rule that `remove` is **not** a gate-clearing shortcut. Step 3 below depends on this.
- **`/ripplo:debug`** — invoke when a run fails (step 9).

**A scope item is "done" only when the app code delivers the user-facing behavior AND a passing test proves it.** Authoring a test against a broken UI/API is not done — the test exists to prove the feature works, not to be the feature. If the flow doesn't work yet, build/fix the app code first (or in lockstep), then make the test pass. Never weaken the test to paper over an app bug.

## Procedure

1. Read `packages/testing/README.md` for DSL reference and determinism rules.
2. **Stub first.** Add the test with `.notImplemented()` so it surfaces in `npx ripplo status` and the stub→implementation transition is trackable.
3. **Scope it.** `npx ripplo scope status` — if a free-text user item describes this flow, `npx ripplo scope link <scope-item-id> <test-id>`. Otherwise `npx ripplo scope add <test-id>`. Bulk-add when stubbing several at once: `npx ripplo scope add <id1> <id2> <id3>`. See `/ripplo:scope`.
4. **Register the file.** Each test file under `.ripplo/tests/<id>.ts` exports a `TestDefinition` value. Add it to the `tests` array in `.ripplo/tests/index.ts`:

   ```ts
   // .ripplo/tests/index.ts
   import { myNewTest } from "./my-new-test.js";
   export const tests = [myNewTest /* , ...others */] as const;
   ```

   The `tests` array is passed as the `tests` registry argument to `createRipplo(config, { preconditions, observers, tests })` in `.ripplo/ripplo.ts`. A test not present in this array is never registered.

5. Browse `.ripplo/preconditions/index.ts` for available preconditions. If none fits, add one there (see below).
6. Read the relevant component/route source to find real ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, **add them to the app first** rather than falling back to `testId()`.
7. Write the test in `.ripplo/tests/<id>.ts` using the top-level `test()` factory. The id comes from `test("<id>")`, not the filename.

   ```ts
   import { test } from "@ripplo/testing";
   import { click, fill } from "@ripplo/testing/actions";
   import { assert } from "@ripplo/testing/assert";
   import { role } from "@ripplo/testing/locators";
   import { dataProject } from "../preconditions/index.js";
   import { orgNameIs } from "../observers/index.js";

   export const myNewTest = test("update-org-name")
     .name("Update organization name")
     .requires({ project: dataProject })
     .expectedOutcome("Org name persisted in DB")
     .startsAt(({ project }) => `/projects/${project.projectId}/settings`)
     .steps(({ project }) => [
       fill(role("textbox", "Organization name"), "New Name").as("fill new name"),
       click(role("button", "Save")).as("click save"),
       assert
         .backend(orgNameIs, { orgId: project.orgId, expectedName: "New Name" })
         .as("assert org name in db"),
     ]);
   ```

8. `npx ripplo lint` — fix all errors.
9. `npx ripplo run <id>` — on failure, invoke `/ripplo:debug`.
10. **Stage `.ripplo/ripplo.lock`** alongside test changes (lint writes it; pre-commit blocks stale).

## Adding a new precondition or observer

Both are declared in `.ripplo/` and **must be included in the registry objects** that `.ripplo/ripplo.ts` passes to `createRipplo`. Otherwise they are unknown at runtime.

```ts
// .ripplo/preconditions/index.ts
import { precondition } from "@ripplo/testing";

export const newPrecondition = precondition("data:thing")
  .description("A thing exists")
  .requires({ auth: authLoggedIn })
  .contract<{ thingId: string }>();

// add to the registry:
export const preconditions = {
  authLoggedIn,
  newPrecondition /* , ... */,
};
```

```ts
// .ripplo/observers/index.ts
import { observer } from "@ripplo/testing";

export const newObserver = observer("thing:is")
  .description("Thing has the expected state")
  .input<{ thingId: string; expectedValue: string }>()
  .contract();

export const observers = { newObserver /* , ... */ };
```

After adding, **implement it in the app's `engine.ts`** — that file's `createEngine(ripplo, {...})` call is exhaustiveness-checked, so TypeScript will flag the new handle as missing until you provide an impl.

```ts
// <app>/src/test/engine.ts (excerpt)
export const engine = createEngine(ripplo, {
  preconditions: {
    newPrecondition: { setup: async (ctx, { auth }) => ..., teardown: async () => ... },
    // ...
  },
  observers: {
    newObserver: async (ctx, { thingId, expectedValue }) => {
      // ctx.pass() | ctx.retry(reason) | ctx.fail(reason)
    },
    // ...
  },
});
```

Never declare `precondition(...)` or `observer(...)` in app code. Handles live in `.ripplo/` and are imported from there.

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

Use `assert.backend(observer, params)` when the UI is optimistic, the effect is async (jobs, webhooks, pubsub), or the write-path is load-bearing. Declare observers in `.ripplo/observers/index.ts` with `observer(name).input<T>().budget("fast" | "slow" | "async").contract()`, add the handle to the `observers` registry, then implement server-side in the app's `engine.ts` as an async function.

- **Budget tiers:** `"fast"` (5s, default) for sync DB reads; `"slow"` (30s) for queue drains; `"async"` (120s) for webhooks, workers, LLM calls. Pick the smallest tier that fits.
- **`ctx.retry(reason)` — default.** Any condition that may resolve on a later poll: not-yet-committed row, status in transition, queue draining, side effect in flight. Runtime polls until budget; the last retry reason surfaces in the failure detail when the budget exhausts. When in doubt, use `retry`.
- **`ctx.fail(reason)` — rare.** Only when further polling cannot succeed (invariant violated, contradictory/forbidden state). Stops immediately after one poll, which produces a confusing "failed after 1 poll" result if used for a transient. Everything that isn't a hard invariant is `retry`.
- Observers return a boolean outcome only — if a test needs to _read_ state for reuse, that's a precondition, not an observer.
- Import the observer handle in the test and use it: `assert.backend(orgNameIs, { orgId, expectedName }).as("assert org persisted")`.

**Lint enforces observers on backend mutations.** The `mutation-without-observer-coverage` rule flags any step that looks like it mutates server state (save/create/delete/update/etc. clicks, uploads, dialog accepts) if no `assert.backend(...)` follows before the next mutation or end of test. Fix by adding a real observer — do NOT silence the rule unless the step genuinely has zero backend effect. For truly client-only steps (cancel a dialog, toggle a display-only control, pick a sort option), pass `{ uiOnly: true }` to the step factory or, for whole-test presentation flows, `test(id, { uiOnly: true })`. Always prefer an observer over `uiOnly`.

The `observer-params-reference-variables` rule flags observers whose params are all static strings while the test declares precondition variables — fix by referencing the precondition data (e.g. `expectedName: project.name`).

## Determinism (non-negotiable)

- `role()` locators only; `testId()` only when no ARIA role exists.
- Exact text matching — no `contains`, `startsWith`, regex.
- Destructure precondition data in `steps()` — never hardcode.
- Every step has `.as("description")`.

If a run fails, `/ripplo:debug`. Never weaken assertions to make a test pass — if it's an app bug, report with evidence.
