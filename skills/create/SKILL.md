---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

**A scope item is "done" only when the app code delivers the behavior AND a passing test proves it.** If the flow doesn't work yet, fix the app first (or in lockstep). Never weaken the test to paper over an app bug. Observer wiring on mutation flows is part of "done," not follow-up — see "Observers & `uiOnly`" below.

## Procedure

1. Read `packages/testing/README.md` for DSL reference and determinism rules.
2. **Stub first** with `.notImplemented()` so the stub→implementation transition shows in `npx ripplo status`.
3. **Scope it.** `npx ripplo scope status`; link if a user item matches, else `npx ripplo scope add <id...>` (variadic). See `/ripplo:scope`.
4. **Register the file** — add the exported `TestDefinition` to the `tests` array in `.ripplo/tests/index.ts`. A test not in that array is never registered.
5. Browse `.ripplo/preconditions/index.ts`; add a new precondition there if none fits (see "Adding preconditions/observers" below).
6. Read the relevant component/route source for real ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, add them to the app first — don't fall back to `testId()`.
7. **Trace every mutation to the backend.** For each click/submit/upload, follow it to the resolver or route handler. Pick an existing observer or declare a new one _now_ — before writing steps. If a step has zero backend effect (pure view transition), note that explicitly — it's the only condition under which `uiOnly: true` is valid.
8. Write the test — id comes from `test("<id>")`, not the filename:

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
11. **Stage `.ripplo/ripplo.lock`** alongside test changes.

## Parallelizing multi-stub sessions

When implementing more than ~3 stubs in one session, fan out with subagents — don't author serially. Serial authoring creates pressure to narrow scope; stubs are independent files with no reason to serialize.

- One subagent per stub (or per 2–3 sharing a component).
- Batch ~5 parallel agents per message.
- Each prompt: stub path, component source paths, relevant precondition/observer handles, coverage ID prefix to search in `.ripplo/coverage.d.ts`. Instruct: return the test body only, don't run lint/run.
- Review each returned test — subagents can hallucinate locators or coverage IDs.
- Keep on the main agent: `npx ripplo lint`, `npx ripplo run`, `/ripplo:debug` on failures, and new precondition/observer declarations + `engine.ts` wiring (exhaustiveness must stay coherent).

"Too many stubs" is never a justification for `scope remove`. See `/ripplo:scope`.

## What makes a good test

Don't just assert the URL changed or the clicked button still exists. Assert:

- New elements post-action (dialog opened, success message, heading).
- Text content (`assert.text` / `assert.value` / `assert.url` / `assert.count` — not just `assert.visible`).
- Mutation reflected in UI (new list item, counter delta, status change).
- Backend state on every mutation (see Observers below).
- Things that should be gone (`assert.not.visible` for closed dialogs, cleared spinners).

The `tautological-post-click-assert` lint rule catches "clicked X, assert X still visible" — fix by asserting the actual effect. Re-read each test against its `expectedOutcome` before declaring done.

## Observers & `uiOnly`

**Every mutation step requires `assert.backend(observerHandle, params)`.** A server can accept a click and still fail the write; UI-only checks ship that bug as green. Default to "this needs an observer"; only skip if you've proven zero backend effect.

**Declaring:** `observer(name).input<T>().budget("fast" | "slow" | "async").contract()` in `.ripplo/observers/index.ts`, add to the `observers` registry, implement server-side in `engine.ts` as an async function.

- **Budget tiers:** `"fast"` (5s, default) sync DB reads; `"slow"` (30s) queue drains; `"async"` (120s) webhooks/workers/LLM. Pick the smallest that fits.
- **`ctx.retry(reason)` is the default.** Anything that may resolve on a later poll — uncommitted row, status transition, draining queue, in-flight side effect. When in doubt, retry. The last retry reason surfaces when the budget exhausts.
- **`ctx.fail(reason)` is rare.** Only true invariant violations (contradictory/forbidden state). `fail` stops immediately — if used for a transient, produces a confusing "failed after 1 poll" result.
- Observers return boolean only. If a test needs to _read_ state for reuse, that's a precondition, not an observer.

**Lint rules:**

- `mutation-without-observer-coverage` flags mutation-looking steps (save/create/delete/update, uploads, dialog accepts) lacking a following `assert.backend(...)`. Fix by writing the observer — the rule is a backstop, not a ceiling.
- `observer-params-reference-variables` flags observers whose params are all static strings while the test has precondition variables — reference the real data (e.g. `expectedName: project.name`).

### `uiOnly: true` is not a stub

Valid only for steps with **zero** backend effect: cancel a dialog, toggle a display-only control, switch tabs, open a modal that renders purely from client state. That's the whole list.

**Invalid regardless of `// TODO` comments or lint status:** any step that triggers a mutating network request, optimistic UI updates (the server call still happens), enqueues, uploads, webhook fires, external API calls, or "I'll wire the observer later."

Using `uiOnly: true` + `// TODO: add observer` to clear lint and call a scope item "implemented" is forbidden — same anti-pattern as `scope remove`. If many tests need observers, parallelize with subagents (same pattern as multi-stub authoring above).

## Adding a new precondition or observer

Declared in `.ripplo/` and **must be included in the registry object** that `.ripplo/ripplo.ts` passes to `createRipplo`.

```ts
// .ripplo/preconditions/index.ts
export const newPrecondition = precondition("data:thing")
  .description("A thing exists")
  .requires({ auth: authLoggedIn })
  .contract<{ thingId: string }>();

export const preconditions = { authLoggedIn, newPrecondition };
```

```ts
// .ripplo/observers/index.ts
export const newObserver = observer("thing:is")
  .description("Thing has the expected state")
  .input<{ thingId: string; expectedValue: string }>()
  .contract();

export const observers = { newObserver };
```

Then implement in `<app>/src/test/engine.ts` — `createEngine(ripplo, {...})` is exhaustiveness-checked, so TS flags missing impls:

```ts
export const engine = createEngine(ripplo, {
  preconditions: {
    newPrecondition: { setup: async (ctx, { auth }) => ..., teardown: async () => ... },
  },
  observers: {
    newObserver: async (ctx, { thingId, expectedValue }) => {
      // ctx.pass() | ctx.retry(reason) | ctx.fail(reason)
    },
  },
});
```

Never declare `precondition(...)` or `observer(...)` in app code.

## Coverage (load-bearing)

**Every implemented test ends with `.coverage(...ids)`** listing every user-facing interaction it exercises. `stop-enforce` errors on any net-new interaction in the diff that no test claims.

- IDs come from the generated `.ripplo/coverage.d.ts`: `<file>#<Component>.<kind>[<label>]` where `kind ∈ { click, drag, input, navigate, select, submit, upload }`. The file ambiently augments `@ripplo/testing`'s `CoverageRegistry`, so `.coverage(...)` autocompletes and type-errors on stale/typo'd IDs.
- `.notImplemented()` stubs skip `.coverage()` — acknowledgement happens at implementation.
- Claim only what the test actually exercises. Stale claims are flagged by `stop-enforce` and `npx ripplo cover`.
- When `stop-enforce` reports "new interactions without test coverage," read the listed IDs, pick the natural owning test, add them to its `.coverage(...)`. If none fits, stub a new test.
- `npx ripplo cover` audits the whole tree: unacknowledged statements + stale claims.

## Determinism (key rules — full list in `packages/testing/README.md`)

- `role()` locators; `testId()` only when no ARIA role exists. Exact text matching — no `contains`/`startsWith`/regex.
- Destructure precondition data in `steps()`; never hardcode.
- **Never write `"{{ns.key}}"` as a literal string** — pass the destructured proxy directly (`assert.value(locator, table.name)`). The `no-literal-template-strings` rule bypasses type-checking so typos silently compile.
- **Runtime variables use `variable()` tokens, not template strings:**
  ```ts
  const copied = variable("copied");
  clipboard({ action: "read", target: copied, value: undefined }).as("read");
  assert.value(role("button", "Copy"), copied).as("matches clipboard");
  ```
- Every step has `.as("description")`.
