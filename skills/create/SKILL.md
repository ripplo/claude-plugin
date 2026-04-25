---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

If the flow doesn't work yet, fix the app first or in lockstep — never weaken the test to paper over an app bug. Observer wiring on mutation flows is in-scope work, not follow-up.

## Procedure

1. Read `packages/testing/README.md` for DSL reference and determinism rules.
2. **Stub first** with `.notImplemented()` so the stub→implementation transition shows in `npx ripplo status`.
3. **Scope it.** `npx ripplo scope status`; link if a user item matches, else `scope add <id>` (variadic). See `/ripplo:scope`.
4. **Register the file** — add the exported `TestDefinition` to the `tests` array in `.ripplo/tests/index.ts`. Unregistered tests don't exist.
5. Browse `.ripplo/preconditions/index.ts`; declare a new precondition there if none fits (see "Adding a precondition or observer" below).
6. Read the relevant component/route source for real ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, add them to the app first — don't fall back to `testId()`.
7. **Trace every mutation to the backend.** For each click/submit/upload, follow it to the resolver or route handler. Pick an existing observer or declare a new one _now_, before writing steps.
8. Write the test — id is the string passed to `test("<id>")`, not the filename:

   ```ts
   import { test } from "@ripplo/testing";
   import { click, fill } from "@ripplo/testing/actions";
   import { assert } from "@ripplo/testing/assert";
   import { role } from "@ripplo/testing/locators";
   import { dataProject } from "../preconditions/index.js";
   import { orgNameIs } from "../observers/index.js";

   export const updateOrgName = test("update-org-name")
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

## What makes a good test

Don't just assert the URL changed or the clicked button still exists. Assert:

- New elements post-action (dialog, success message, heading).
- Text content (`assert.text` / `assert.value` / `assert.url` / `assert.count`).
- Mutations reflected in UI (new list item, counter delta, status change).
- **Backend state on every mutation** (observer below).
- Things that should be gone (`assert.not.visible` for closed dialogs, cleared spinners).

The `tautological-post-click-assert` lint rule catches "clicked X, assert X still visible." Re-read each test against its `expectedOutcome` before declaring done.

## Observers & `uiOnly`

**Every mutation step requires `assert.backend(observerHandle, params)`.** A server can accept a click and still fail the write; UI-only checks ship that bug as green.

**Declaring:** `observer(name).input<T>().budget("fast" | "slow" | "async").contract()` in `.ripplo/observers/index.ts`, add to the `observers` registry, implement server-side in `engine.ts`.

- **Budgets:** `"fast"` (5s, default) sync DB reads; `"slow"` (30s) queue drains; `"async"` (120s) webhooks/workers/LLM. Pick the smallest that fits.
- **`ctx.retry(reason)` is the default.** Anything that may resolve on a later poll — uncommitted row, status transition, draining queue, in-flight side effect.
- **`ctx.fail(reason)` is rare.** Only invariant violations (contradictory/forbidden state). Stops polling immediately — wrong choice for transients produces "failed after 1 poll."
- Observers return boolean only. If a test needs to _read_ state for reuse, that's a precondition.

**Lint rules:**

- `mutation-without-observer-coverage` flags mutation-looking steps lacking a following `assert.backend(...)`. Fix by writing the observer.
- `observer-params-reference-variables` flags observers whose params are all static while the test has precondition variables — pass the real data (e.g. `expectedName: project.name`).

### Stop-enforce stubs are not a question

When `stop-enforce` blocks on an unimplemented stub, complete it. Don't ask the user "implement now or defer?" — that framing presents skipping validation as a legitimate option. It isn't.

- **Size is never a valid reason to ask.** Same rule as `scope remove`.
- **Pausing hooks via the web UI is the user's escape hatch, not yours.** Don't propose it as an alternative path; don't surface it as option B in an A/B.
- **The fix isn't done until the test is.** A landed app change with a still-stubbed test is not "the fix shipped + a follow-up" — it's an incomplete fix that the gate is correctly blocking.
- **If the test needs new scaffolding** (precondition, observer, engine impl), that scaffolding is in-scope. Same as observer wiring — see "uiOnly is not a stub" below.

### `uiOnly: true` is not a stub

Valid only for steps with **zero** backend effect: cancel a dialog, toggle a display-only control, switch tabs, open a modal that renders purely from client state.

**Invalid regardless of `// TODO` or lint status:** any step that triggers a mutating network request, optimistic UI updates, enqueues, uploads, webhook fires, external API calls. Using `uiOnly: true` + `// TODO: add observer` to clear lint and call a stub "implemented" is forbidden — same anti-pattern as `scope remove`. Parallelize observer wiring across stubs (below); don't take the shortcut.

## Parallelizing multi-stub sessions

When implementing more than ~3 stubs, fan out subagents — don't author serially. Stubs are independent files with no reason to serialize.

- One subagent per stub (or per 2–3 sharing a component).
- Batch ~5 parallel agents per message.
- Each prompt: stub path, component source paths, relevant precondition/observer handles, coverage ID prefix to search in `.ripplo/coverage.d.ts`. Instruct: return the test body only, don't run lint/run.
- Review each returned test — subagents hallucinate locators and coverage IDs.
- Keep on the main agent: `npx ripplo lint`, `npx ripplo run`, `/ripplo:debug` on failures, and new precondition/observer declarations + `engine.ts` wiring (exhaustiveness must stay coherent).

"Too many stubs" is never a justification for `scope remove`.

## Adding a precondition or observer

Declared in `.ripplo/`; **must be in the registry** that `.ripplo/index.ts` passes to `createRipplo`.

```ts
// .ripplo/preconditions/index.ts
export const dataThing = precondition("data:thing")
  .description("A thing exists")
  .requires({ auth: authLoggedIn })
  .contract<{ thingId: string }>();

export const preconditions = { authLoggedIn, dataThing };
```

```ts
// .ripplo/observers/index.ts
export const thingIs = observer("thing:is")
  .description("Thing has the expected state")
  .input<{ thingId: string; expectedValue: string }>()
  .contract();

export const observers = { thingIs };
```

Then implement in `<app>/src/test/engine.ts` — `createEngine(ripplo, {...})` is exhaustiveness-checked, so TS flags missing impls:

```ts
export const engine = createEngine(ripplo, {
  preconditions: {
    dataThing: { setup: async (ctx, { auth }) => ..., teardown: async () => ... },
  },
  observers: {
    thingIs: async (ctx, { thingId, expectedValue }) => {
      // ctx.pass() | ctx.retry(reason) | ctx.fail(reason)
    },
  },
});
```

Never declare `precondition(...)` or `observer(...)` in app code.

### Parallel safety

Tests run in parallel. Every `setup()` must produce isolated, non-conflicting data:

- **Unique identifiers** via `ctx`: `ctx.uniqueId(prefix)`, `ctx.uniqueEmail()`, `ctx.runId`. `ctx.fixed(value)` only for shared constants (e.g. test password) — never names/emails/ids.
- **Return dynamic IDs** — `setup()` return flows into `requires()` destructuring; tests reference by id, not hardcoded slug.
- **Scoped teardown.** Delete only entities created by _this_ setup invocation, by id. Never `deleteMany` by prefix or `TRUNCATE`.
- **Independent sessions.** Each setup creates its own auth session.

Symptoms of leakage: unique-constraint errors, 401/403 mid-test, vanishing session cookies. Fix the precondition, not the test.

## Coverage (load-bearing)

**Every implemented test ends with `.coverage(...ids)`** listing every user-facing interaction it exercises. `stop-enforce` errors on net-new interactions in the diff that no test claims.

- IDs come from `.ripplo/coverage.d.ts`: `<file>#<Component>.<kind>[<label>]` where `kind ∈ { click, drag, input, navigate, select, submit, upload }`. The file ambiently augments `CoverageRegistry`, so `.coverage(...)` autocompletes and type-errors on stale/typo'd IDs.
- `.notImplemented()` stubs skip `.coverage()` — acknowledgement happens at implementation.
- Claim only what the test actually exercises. Stale claims are flagged by `stop-enforce` and `npx ripplo cover`.
- When `stop-enforce` reports "new interactions without test coverage," read the listed IDs, pick the natural owning test, add them to its `.coverage(...)`. If none fits, stub a new test.

## Determinism (full list in `packages/testing/README.md`)

- `role()` locators; `testId()` only when no ARIA role exists. Exact text matching — no `contains`/`startsWith`/regex.
- Destructure precondition data in `steps()`; never hardcode.
- **Never write `"{{ns.key}}"` as a literal string** — pass the destructured proxy directly (`assert.value(locator, table.name)`). The literal bypasses type-checking so typos silently compile.
- **Runtime variables use `variable()` tokens, not template strings:**
  ```ts
  const copied = variable("copied");
  clipboard({ action: "read", target: copied, value: undefined }).as("read");
  assert.value(role("button", "Copy"), copied).as("matches clipboard");
  ```
- Every step has `.as("description")`. No duplicates within a test.
