---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

If the flow doesn't work yet, fix the app first or in lockstep — never weaken the test to paper over an app bug. Observer wiring on mutation flows is in-scope work, not follow-up. Same for upload fixtures: `upload(loc, fixture("name"))` requires the file to exist at `.ripplo/fixtures/<name>` (committed bytes; LFS allowed); adding it is part of writing the test, not a follow-up.

## Prerequisite — dev session must be live

This skill needs two background processes running: the app's dev server, and `npx ripplo watch`. Run `npx ripplo doctor` first — if either is missing, run `/ripplo:start` (or spawn `npx ripplo watch` directly via `Bash` with `run_in_background`) and start the app dev server the same way if it isn't up. Without watch, scope/coverage hooks don't arm and `ripplo run` refuses to dispatch.

## Canonical builder chains

```ts
// Precondition — single chain shape (stub vs implemented is decided by engine.ts wiring, not the DSL)
precondition("ns:name")
  .description("…")
  .requires({ dep }) // optional
  .contract<{ fooId: string }>();
```

```ts
// Observer — single chain shape (stub vs implemented is decided by engine.ts wiring, not the DSL)
observer("ns:name")
  .description("…")
  .budget("fast") // "fast" | "slow" | "async"
  .input<{ … }>()
  .contract();
```

```ts
// Test — implemented
test("id")
  .name("…")
  .requires({ dep })
  .expectedOutcome("…")
  .startsAt(({ dep }) => "/path")
  .steps(({ dep }) => [
    /* … */
  ])
  .coverage("file#Component.kind[label]");

// Test — stub (terminates early; no startsAt/steps/coverage)
test("id").name("…").requires({ dep }).expectedOutcome("…").notImplemented();
```

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

Declared in `.ripplo/`; **must be in the registry** that `.ripplo/index.ts` passes to `createRipplo`. Chain order is fixed — see "Canonical builder chains" above.

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

export const orgOverageCapIs = observer("org:overage-cap-is")
  .input<{ orgId: string; expectedCapCents: number }>()
  .contract();

export const orgHasLogo = observer("org:has-logo")
  .input<{ orgId: string; expectLogo: boolean }>()
  .contract();

export const observers = { thingIs, orgOverageCapIs, orgHasLogo };
```

```ts
// .ripplo/preconditions/index.ts
export const dataInvoice = precondition("data:invoice")
  .requires({ auth: authLoggedIn })
  .contract<{ invoiceId: string; amountCents: number; isPaid: boolean }>();
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
    orgOverageCapIs: async (ctx, { orgId, expectedCapCents }) =>
      org.overageCapCents === expectedCapCents ? ctx.pass() : ctx.retry("..."),
    orgHasLogo: async (ctx, { orgId, expectLogo }) =>
      hasLogo === expectLogo ? ctx.pass() : ctx.retry("..."),
  },
});
```

Never declare `precondition(...)` or `observer(...)` in app code.

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
