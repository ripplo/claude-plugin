---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

If the flow doesn't work yet, fix the app first or in lockstep — never weaken the test to paper over an app bug. Observer wiring on mutation flows is in-scope work, not follow-up. Same for upload fixtures: `upload(loc, fixture("name"))` requires the file to exist at `.ripplo/fixtures/<name>` (committed bytes; LFS allowed); adding it is part of writing the test, not a follow-up.

## Prerequisite

Needs the app dev server + `npx ripplo watch`. Run `npx ripplo doctor`; if missing, `/ripplo:start`. Without watch, scope/coverage hooks don't arm and `ripplo run` refuses to dispatch.

## Procedure

1. Read `packages/testing/README.md` for DSL reference and determinism rules.
2. **Stub first** with `.notImplemented()` so the stub→implementation transition shows in `npx ripplo status`.
3. **Scope it.** `npx ripplo scope status`; link if a user item matches, else `scope add <id>` (variadic). See `/ripplo:scope`.
4. **Register the file** — add the exported `TestDefinition` to the `tests` array in `.ripplo/tests/index.ts`. Unregistered tests don't exist.
   - **Place the file in the most relevant existing subfolder** under `.ripplo/tests/` (e.g. `billing/`, `agents/`, `dev-mode/`). The folder is the test's group in the sidebar — keeping related tests together is what makes a growing list scannable. Create a new folder only if no existing one fits and at least 2–3 related tests would land there together. When placing in a subfolder, imports use `../../observers/index` and `../../preconditions/index` (one extra `..` per level of nesting).
5. Browse `.ripplo/preconditions/index.ts`; declare a new precondition there if none fits (see "Adding a precondition or observer" below).
6. Read the relevant component/route source for real ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, add them to the app first — don't fall back to `testId()`.
7. **Trace every mutation to the backend.** For each click/submit/upload, follow it to the resolver or route handler. Pick an existing observer or declare a new one _now_, before writing steps.
8. Write the test — id is the string passed to `test("<id>")`, not the filename:

   ```ts
   import { test } from "@ripplo/testing";
   import { click, fill } from "@ripplo/testing/actions";
   import { assert } from "@ripplo/testing/assert";
   import { role } from "@ripplo/testing/locators";
   import { dataProject } from "../preconditions/index";
   import { orgNameIs } from "../observers/index";

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

A test exists to catch a specific regression. Before writing steps, name the failure mode in plain language: "user clicks Save, UI shows success, but the DB write silently dropped." That sentence dictates the assertions — if your test would pass against that bug, it's not deep enough.

Trace the mutation end-to-end first (component → resolver/handler → DB). Steps and observers fall out of the trace; without it, tests assert the click happened, not that the intent succeeded.

Cover each mutation in three phases:

- **Before:** precondition seeds a _known_ value (not just existence), so an after-assertion can't pass by coincidence.
- **Action:** the user-facing step.
- **After:** both UI evidence (new element, text, counter delta) _and_ DB evidence via `assert.backend`. A toast can lie; the row can't.

Assert the negatives. Errors absent, spinners cleared, dialogs closed, duplicate rows not created, prior values gone. Regression-revealing assertions are usually negative — positive ones often pass by accident.

Branch coverage: if a route renders differently for admin vs member, empty vs populated, first run vs Nth — each branch needs its own test or variant. A single happy-path test ships green while the other branch silently regresses.

The `tautological-post-click-assert` lint rule catches "clicked X, assert X still visible." Re-read each test against the failure mode you named — would it actually fail if that regression shipped?

## Observers & `uiOnly`

**Every mutation step requires `assert.backend(observerHandle, params)`.** A server can accept a click and still fail the write; UI-only checks ship that bug as green.

Declare in `.ripplo/observers/index.ts` and implement in `engine.ts` — see "Adding a precondition or observer" for the full chain.

- **Budgets:** `"fast"` (5s, default) sync DB reads; `"slow"` (30s) queue drains; `"async"` (120s) webhooks/workers/LLM. Pick the smallest that fits.
- **`ctx.retry(reason)` is the default.** Anything that may resolve on a later poll — uncommitted row, status transition, draining queue, in-flight side effect.
- **`ctx.fail(reason)` is rare.** Only invariant violations (contradictory/forbidden state). Stops polling immediately — wrong choice for transients produces "failed after 1 poll."
- Observers return boolean only. If a test needs to _read_ state for reuse, that's a precondition.

**Lint rules:**

- `mutation-without-observer-coverage` flags mutation-looking steps lacking a following `assert.backend(...)`. Fix by writing the observer.
- `observer-params-reference-variables` flags observers whose params are all static while the test has precondition variables — pass the real data (e.g. `expectedName: project.name`).

### Stop-enforce stubs and `uiOnly`

Stop-enforce stubs are in-scope work. Don't ask the user to defer; don't propose pausing hooks. New scaffolding the test needs (precondition, observer, engine impl) is part of the fix, not a follow-up.

`uiOnly: true` is valid only for steps with **zero** backend effect (cancel a dialog, switch tabs, open a client-state modal). Never use it to silence observer lint on a mutation step — that's the same anti-pattern as `scope remove`.

## Parallelizing multi-stub sessions

When implementing more than ~3 stubs, fan out subagents (one per stub or per 2–3 sharing a component, ~5 per batch). **Every Agent prompt must instruct the subagent to first invoke the Skill tool with `ripplo:create`** — subagents don't inherit skill context and will hallucinate DSL without it. Keep lint/run/debug and precondition/observer/engine wiring on the main agent. "Too many stubs" is never a justification for `scope remove`.

## Adding a precondition or observer

Declared in `.ripplo/`; **must be in the registry** that `.ripplo/index.ts` passes to `createRipplo`.

**Compose, don't duplicate.** Before writing a `setup()`, name what it shares with other preconditions. Shared steps belong in their own precondition that downstream ones declare via `.requires(...)` — not inlined into each setup. The canonical case is auth: an authenticated app gets one `authLoggedIn` precondition, and every data precondition does `.requires({ auth: authLoggedIn })`. If your `setup()` description starts with "Authenticated …", that's the smell — extract the auth step.

```ts
// .ripplo/preconditions/index.ts
export const dataThing = precondition("data:thing")
  .description("A thing exists")
  .requires({ auth: authLoggedIn })
  .contract<{ thingId: string }>();

export const preconditions = { authLoggedIn, dataThing };
```

Observer `.input<T>()` and precondition `.contract<T>()` accept any primitive (`string | number | boolean`):

```ts
// .ripplo/observers/index.ts
export const thingIs = observer("thing:is")
  .description("Thing has the expected state")
  .input<{ thingId: string; expectedValue: string }>()
  .contract();

export const observers = { thingIs };
```

Implement in `<app>/src/test/engine.ts` — `createEngine(ripplo, {...})` is exhaustiveness-checked. **Precondition `setup` and `teardown` are batched**: the runtime collects every concurrent run that needs the precondition within a short window and calls the impl once with `items: ReadonlyArray<{ ctx, deps }>`. Return a result array with the same length and order as the input. Issue one bulk write for the whole batch (e.g. `createMany` / `deleteMany`) so DB round-trips scale with wall-clock time, not run count. Observer impls remain per-call and receive params at the declared primitive type with no coercion:

```ts
export const engine = createEngine(ripplo, {
  preconditions: {
    dataThing: {
      setup: async (items) => {
        const seeds = items.map(({ ctx, deps }) => ({
          thingId: ctx.uniqueId("thing"),
          userId: deps.auth.userId,
        }));
        await db.things.bulkInsert(seeds); // one round-trip for the whole batch
        return seeds.map(({ thingId }) => ({ thingId }));
      },
      teardown: async (items) => {
        await db.things.bulkDeleteByIds(items.map((it) => it.ctx.data.thingId));
      },
    },
  },
  observers: {
    thingIs: async (ctx, { thingId, expectedValue }) => ...,
  },
});
```

Never declare `precondition(...)` or `observer(...)` in app code.

**Organize by domain from the start, consistently across all four locations.** Pick one set of domain names (e.g. `auth`, `billing`, `workflows`) and use it for `engine/<domain>.ts` (impls), `.ripplo/tests/<domain>/` (test folders), `.ripplo/preconditions/<domain>.ts` + `.ripplo/observers/<domain>.ts` (declarations, re-exported through their `index.ts`). One mental map, four mirrored layouts. Don't let declarations stay in a single index file while impls and tests split — they all grow together.

Engine split shape — each module exports a plain object of impls keyed by handle, and `engine.ts` spreads them into one `createEngine` call:

```ts
import { authImpls } from "./engine/auth";
import { billingImpls } from "./engine/billing";

export const engine = createEngine(ripplo, {
  preconditions: { ...authImpls.preconditions, ...billingImpls.preconditions },
  observers: { ...authImpls.observers, ...billingImpls.observers },
});
```

### Parallel safety

Tests run in parallel. Every `setup()` must produce isolated, non-conflicting data:

- **Unique identifiers** via `ctx`: `ctx.uniqueId(prefix)`, `ctx.uniqueEmail()`, `ctx.runId`. `ctx.fixed(value)` only for shared constants (e.g. test password) — never names/emails/ids. Accepts any primitive (`string | number | boolean`).
- ctx helpers return plain primitives — use them directly in templates and observer params. Hardcoded literals in `setup()` returns are rejected at compile time.
- **Return dynamic IDs** — `setup()` return flows into `requires()` destructuring; tests reference by id, not hardcoded slug.
- **Create-only setups.** `setup()` may insert new rows but must not `update` or `delete` existing ones. Mutating shared state — even with a `WHERE` clause that looks scoped — can match rows from another in-flight run, and creates ordering coupling between preconditions. If a test needs a non-default state, the precondition that creates the row should accept that state as input; don't seed a default and mutate it from a downstream precondition. Exception: `upsert` on a per-run 1:1 settings record (e.g. `(userId, resourceId)` view).
- **Scoped teardown.** Delete only entities created by _this_ setup invocation, by id. Never `deleteMany` by prefix or `TRUNCATE`.
- **Independent sessions.** Each setup creates its own auth session.

Symptoms of leakage: unique-constraint errors, 401/403 mid-test, vanishing session cookies, rows disappearing while a test is still running. Fix the precondition, not the test.

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
