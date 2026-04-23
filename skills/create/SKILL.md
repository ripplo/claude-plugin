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
- **`/ripplo:explore`** — if you're creating more than one test, start from explore to enumerate flows first.

**A scope item is "done" only when the app code delivers the user-facing behavior AND a passing test proves it.** Authoring a test against a broken UI/API is not done — the test exists to prove the feature works, not to be the feature. If the flow doesn't work yet, build/fix the app code first (or in lockstep), then make the test pass. Never weaken the test to paper over an app bug.

**Observer coverage is part of "done," not follow-up.** If the flow mutates backend state (DB write, job enqueue, external call, even optimistic UI), the test is not implemented until `assert.backend(observer, ...)` validates the effect. A test with `uiOnly: true` or a `// TODO: add observer` comment on a mutation step is **not implemented** — it's a false green that ships a click without proof the server did the right thing. Don't report scope complete with such tests in the set. See "`uiOnly: true` is not a stub" below.

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
7. **Trace the mutation to the backend.** For every click/submit/upload in the flow, follow it to the mutation resolver or route handler. Identify what server state changes: DB rows written, job queue entries, external API calls, file uploads. For each backend effect, pick an existing observer from `.ripplo/observers/index.ts` or declare a new one _now_ — before writing the steps array. Do not defer observer selection to "I'll see what lint says." If there is no backend effect at all (pure view transition), note that explicitly — it's the only condition under which `uiOnly: true` is valid later.
8. Write the test in `.ripplo/tests/<id>.ts` using the top-level `test()` factory. The id comes from `test("<id>")`, not the filename.

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
     ])
     .coverage(
       "apps/web/src/components/settings/OrgNameForm.tsx#OrgNameForm.input[Organization name]",
       "apps/web/src/components/settings/OrgNameForm.tsx#OrgNameForm.click[Save]",
     );
   ```

9. `npx ripplo lint` — fix all errors.
10. `npx ripplo run <id>` — on failure, invoke `/ripplo:debug`.
11. **Stage `.ripplo/ripplo.lock`** alongside test changes (lint writes it; pre-commit blocks stale).

## Parallelizing multi-stub sessions

When you have more than ~3 stubs to implement in one session (common after `/ripplo:explore` enumerates a feature's flows), **fan out with subagents. Do not author them serially.**

Why this matters: serial authoring burns wall-clock time and creates psychological pressure to narrow scope — that's where "let me just remove some of these to unblock Stop" thinking comes from. Each stub is an independent file with an independent flow; there is no reason to serialize them. The "this is a lot of work" feeling is an artifact of doing it wrong, not a signal to trim.

**How to fan out:**

- One subagent per stub, or per cluster of 2–3 stubs that share a component/route (so they can share the component read).
- Batch in groups of ~5 parallel agents per message to keep output reviewable.
- Each subagent prompt includes:
  - The stub file path (`.ripplo/tests/<id>.ts`)
  - The component/route source paths it should read for real locators (never fabricate)
  - Relevant precondition and observer handles from `.ripplo/preconditions/index.ts` and `.ripplo/observers/index.ts`
  - The coverage ID prefix to search in `.ripplo/coverage.d.ts`
  - Explicit instruction: return the implemented test body, don't run `ripplo lint` or `ripplo run`
- Review each returned test before accepting — subagents can hallucinate locators or coverage IDs.

**Keep on the main agent:**

- `npx ripplo lint` and `npx ripplo run` (serial, after all stubs are authored)
- `/ripplo:debug` on failures
- New precondition/observer declarations and `apps/server/src/test/engine.ts` wiring (exhaustiveness-checked — must stay coherent across stubs)

**Non-negotiable:** never cite "there are too many stubs" or "subagents might get it wrong" as justification for `scope remove`. Subagents are available, and reviewing their output is faster than authoring serially. See `/ripplo:scope` for why trimming is forbidden.

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

## Coverage (load-bearing — not optional)

**Every implemented test must end with `.coverage(...ids)` listing every user-facing interaction the test exercises.** The `stop-enforce` gate errors on any net-new interaction in the diff that no test claims. Without `.coverage()`, net-new buttons and inputs ship uncovered and block the gate.

- **IDs come from `.ripplo/coverage.d.ts`** — a generated, committed file listing every AST-visible user interaction. Shape: `<file>#<Component>.<kind>[<label>]` where `kind ∈ { click, drag, input, navigate, select, submit, upload }`. Import the type for autocomplete/typo-checking:

  ```ts
  import type { BranchId } from "../coverage";
  const ids: ReadonlyArray<BranchId> = [
    "apps/web/src/components/settings/OrgNameForm.tsx#OrgNameForm.click[Save]",
  ];
  ```

- **Stubs via `.notImplemented()` skip `.coverage()`.** Acknowledgement happens at implementation time.
- **Claim only what the test actually exercises.** `.coverage("...click[Save]")` is a claim the test clicks that Save button. Stale claims (IDs that no longer exist in the tree) are flagged by `stop-enforce` and `npx ripplo cover`.
- **When `stop-enforce` says "new interactions were introduced without test coverage":** read the IDs it lists, find the test that most naturally covers each, and add them to that test's `.coverage(...)` array. If no existing test covers the interaction, stub a new one (same flow as above).
- **Audit at any time:** `npx ripplo cover` prints all unacknowledged branches and stale claims across the whole tree.

## What makes a good test

Don't just assert the URL changed or that the button you clicked is still visible. Assert:

- **New** elements that appear post-action (dialog opened, success message, page heading)
- Text content (`assert.text` / `assert.value` / `assert.url` / `assert.count` — not just `assert.visible`)
- The mutation result reflected in UI (new list item, counter delta, status change)
- **Backend state on every mutation.** If the step writes to the DB, enqueues a job, fires a webhook, or triggers any async side effect — even one the UI optimistically reflects — `assert.backend(observerHandle, params)` is required. The server can accept your click and still fail the write; a UI-only check ships that bug as green. Default to "this needs an observer" and only skip if you've proven the step has zero backend effect.
- Things that should be gone (`assert.not.visible` for closed dialogs, cleared spinners)

A test that clicks a button and asserts the same button still exists verifies nothing. The `tautological-post-click-assert` lint rule catches this — fix by asserting the actual effect, not by adding another `assert.visible` of the same element.

Re-read each test against its `expectedOutcome` before declaring done.

## Observers (backend state assertions)

**When to use:** every time a step mutates backend state — see "What makes a good test" above. This section is the _mechanics_ of declaring and wiring observers; the "when" is not conditional.

Declare observers in `.ripplo/observers/index.ts` with `observer(name).input<T>().budget("fast" | "slow" | "async").contract()`, add the handle to the `observers` registry, then implement server-side in the app's `engine.ts` as an async function.

- **Budget tiers:** `"fast"` (5s, default) for sync DB reads; `"slow"` (30s) for queue drains; `"async"` (120s) for webhooks, workers, LLM calls. Pick the smallest tier that fits.
- **`ctx.retry(reason)` — default.** Any condition that may resolve on a later poll: not-yet-committed row, status in transition, queue draining, side effect in flight. Runtime polls until budget; the last retry reason surfaces in the failure detail when the budget exhausts. When in doubt, use `retry`.
- **`ctx.fail(reason)` — rare.** Only when further polling cannot succeed (invariant violated, contradictory/forbidden state). Stops immediately after one poll, which produces a confusing "failed after 1 poll" result if used for a transient. Everything that isn't a hard invariant is `retry`.
- Observers return a boolean outcome only — if a test needs to _read_ state for reuse, that's a precondition, not an observer.
- Import the observer handle in the test and use it: `assert.backend(orgNameIs, { orgId, expectedName }).as("assert org persisted")`.

**Lint enforces observers on backend mutations.** The `mutation-without-observer-coverage` rule flags any step that looks like it mutates server state (save/create/delete/update/etc. clicks, uploads, dialog accepts) if no `assert.backend(...)` follows before the next mutation or end of test. **Fix by writing the observer.** The lint rule is a backstop, not a ceiling — a test without backend assertions on a mutation flow is wrong regardless of whether lint catches this particular click label.

The `observer-params-reference-variables` rule flags observers whose params are all static strings while the test declares precondition variables — fix by referencing the precondition data (e.g. `expectedName: project.name`).

### `uiOnly: true` is not a stub

**`uiOnly: true` exists for steps with zero backend effect — nothing else.** Valid uses: cancel a dialog, toggle a display-only control (sort direction, sidebar collapse), switch tabs, open a modal that renders purely from client state. That's the whole list.

**Invalid, regardless of `// TODO` comments or lint status:**

- Any step that triggers a network request that mutates state (writes, updates, deletes).
- Optimistic UI updates — the server call still happens, and the test must verify it succeeded.
- Enqueues, uploads, webhook fires, external API calls.
- "I'll wire the observer later" — later never comes, and the test ships as a false green in the meantime.

**Using `uiOnly: true` with a `// TODO: add observer` comment to clear lint and call a scope item "implemented" is forbidden.** It is the same anti-pattern as `scope remove` — silence enforcement, defer validation, declare done. Observer wiring is **in-scope, not follow-up**. Do not tell the user "task #N, non-blocking" about missing observers on mutation flows; that work is part of the current scope item.

**If many tests need new observers,** parallelize the wiring with subagents the same way you parallelize stub authoring (see "Parallelizing multi-stub sessions" above). One subagent per observer: declare in `.ripplo/observers/index.ts`, add to the registry, wire in `apps/server/src/test/engine.ts`. Large observer surface is never a valid justification for deferring.

## Determinism (non-negotiable)

- `role()` locators only; `testId()` only when no ARIA role exists.
- Exact text matching — no `contains`, `startsWith`, regex.
- Destructure precondition data in `steps()` — never hardcode.
- **Never write `"{{ns.key}}"` as a string literal.** Pass the destructured proxy value directly (e.g. `assert.value(locator, table.name)`, not `assert.value(locator, "{{table.name}}")`). The `no-literal-template-strings` lint rule will flag this — it bypasses type-checking so typos like `"{{tabel.name}}"` silently compile.
- **Runtime variables use `variable()` tokens, not template strings.** For `clipboard`/`extract` outputs, call `variable("name")` and pass the token to both the writer (`target:`) and readers (`assert.value`, `fill`, etc.):
  ```ts
  import { variable } from "@ripplo/testing/control";
  const copied = variable("copied");
  clipboard({ action: "read", target: copied, value: undefined }).as("read");
  assert.value(role("button", "Copy"), copied).as("matches clipboard");
  ```
  Never write `"{{vars.copied}}"` as a literal.
- Every step has `.as("description")`.

If a run fails, `/ripplo:debug`. Never weaken assertions to make a test pass — if it's an app bug, report with evidence.
