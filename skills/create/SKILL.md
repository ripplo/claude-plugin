---
name: create
description: "Create a new Ripplo e2e test: model the state it touches as entities, build its starting world, write the action/assertion steps, and run it. Use when adding an e2e test for a user flow."
---

# Create Ripplo Test

If the flow doesn't work yet, fix the app first or in lockstep — never weaken the test to paper over an app bug. Confirmed real app bug while authoring? File it with `npx ripplo report-bug` (kind tree, bar, and fields in `/ripplo:report`). New scaffolding the test needs (a new entity + engine impl, a new world builder) is in-scope work, not a follow-up.

Backend verification is automatic: declare expected DB state inline (`Entity.created/updated/deleted`) and the **oracle** checks observed-vs-model after each step.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`.

## The model (read before writing)

This skill covers the common path. The **full primitive catalog** — every action, locator, predicate, field axis, value-space, and the relational `within`/`where` assertions — is at `node_modules/@ripplo/testing/DSL.md`; read it for less-common primitives (`select`/`upload`/`check`, singleton state, optional/stable fields, relational selection). Skim `.ripplo/{entities,worlds,tests}/` for this project's real patterns. Three layers:

- **Entities** (`.ripplo/entities/`) — the state model: `entity("name", { fields, identity, source })`. `source` is where the state persists: `"backend"` (default — DB rows; impl in the server engine) vs `"client"` (browser-only state: localStorage/IndexedDB/in-memory; impl in the client engine via `mountClientEngine(ripplo, impls, { enabled })`, gated by a build-time flag mirroring the server's — Vite: `VITE_ENABLE_RIPPLO_TESTING`; Next.js: `NEXT_PUBLIC_ENABLE_RIPPLO_TESTING`). Unsure → backend; a browser cache of server-owned data is backend. A field is a free, seedable state dimension with a value-space (`field({ value: v.email() })`). A foreign key is just `field({ value: v.id() })` wired to a parent's id at setup. Derived values (`slug = slugify(name)`) and server-defaulted values (`createdAt`) are **not fields** — drop them. `{ optional: true }` = nullable; `{ stable: false }` = adopt-only.
- **Worlds** (`.ripplo/worlds/`) — pure builder functions returning a flat record of entity handles, composed from other worlds. A world must return every handle it creates.
- **Tests** (`.ripplo/tests/`) — `test("Intent", () => ({ given, steps }))`. `given` is the arrange (one array of all handles); `steps` is the act + assert.

## Procedure

1. **Name the regression in one sentence** ("user clicks Save, UI shows success, but the DB write silently dropped"). That sentence dictates the assertions — if the test would pass against that bug, it's not deep enough.
2. **Trace the mutation end-to-end** (component → resolver/route → DB). The entity to assert and the world to seed fall out of the trace.
3. **Pick or build the world.** Browse `.ripplo/worlds/index.ts`; reuse a builder if one fits, else compose a new one on an existing base — don't re-seed auth/org/project.
4. **Ensure the entities exist.** Every seeded row and asserted state needs an `entity(...)` in `.ripplo/entities/` and a matching engine impl (TS errors if missing).
5. **Read the real component/route source** for ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, add them to the app — don't fall back to `testId()`.
6. **Write the test** (the intent string is the identity, not the filename):

   ```ts
   import {
     arbitrary,
     button,
     click,
     fill,
     goto,
     heading,
     role,
     test,
     text,
     textbox,
     visible,
   } from "@ripplo/testing";
   import { Task } from "../../entities/index.js";
   import { ownedProject } from "../../worlds/index.js";

   export const createTask = test("Create a task in a project", () => {
     const { me, project, session } = ownedProject();
     const title = arbitrary(Task.field.title);
     return {
       given: [me, project, session],
       steps: [
         goto`/projects/${project.id}/tasks`.expect(visible(button("New task"))),
         click(button("New task")).expect(visible(heading("New task")), visible(textbox("Title"))),
         fill(textbox("Title"), title),
         click(button("Create")).expect(
           visible(text(role("listitem"), title)),
           Task.created({ title, projectId: project.id }),
         ),
       ],
     };
   });
   ```

7. **Register it** — add the export to the `tests` array in `.ripplo/tests/index.ts`. The subfolder under `.ripplo/tests/` is the sidebar group. Unregistered tests don't exist.
8. `npx ripplo lint` — fix all errors.
9. `npx ripplo run <test-id>` (the slug from compile/run output; the quoted intent string also works). On failure, `/ripplo:debug`.
10. `npx ripplo compile` and **stage `.ripplo/ripplo.lock`** alongside the `.ripplo/*.ts` changes.

## What makes a good test

Cover each mutation in three phases:

- **Before:** the world seeds a known value (via `arbitrary(...)` or a literal), so an after-assertion can't pass by coincidence.
- **Action:** the user-facing step.
- **After:** both **UI evidence** (`visible(...)`/`text(...)`/`value(...)`) **and DB evidence** (`Entity.created/updated/deleted`) on the same step's `.expect(...)`. A toast can lie; the row can't.

Assert the negatives: `not(visible(role("dialog")))` after a save, errors absent, prior values gone. Regression-revealing assertions are usually negative.

Branch coverage: admin vs member, empty vs populated — each branch is its own test with its own world.

## Backend assertions = the oracle

Every mutation step carries an entity assertion in its `.expect(...)`. The oracle does a 3-way compare (model-before / predicted-after / observed) and flags divergence. You declare expected state; you never poll.

- `Entity.created({ field: value, ... })` — a row with these fields now exists.
- `Entity.updated({ id: handle.id }, { field: newValue })` — the keyed row changed. Use `changed()` when the new value is server-chosen: `{ token: changed() }` asserts it differs without pinning it.
- `Entity.deleted({ id: handle.id })` — the keyed row is gone.

Consistency timing is automatic: `consistency: "eventual"` (or a `changed()` baseline) tolerates propagation lag; the default `strict` fails fast on a wrong intermediate value.

## Adding an entity

A seeded or asserted row needs (a) a definition and (b) an impl; TS flags a missing impl.

```ts
// .ripplo/entities/index.ts
export const Task = entity("task", {
  description: "A task under a project",
  fields: {
    title: field({ value: v.word() }),
    projectId: field({ value: v.id() }), // FK = a plain id field wired at setup
  },
  identity: { id: id() },
  source: "backend",
});
// add Task to the exported `entities` array
```

```ts
// the engine impl funnel in your app — one entry per entity, keyed by name
task: {
  seed: async ({ fields, runId }) => {
    const id = testId(runId, "task");                  // run-scoped id => parallel isolation
    await db.task.create({ data: { id, title: fields.title, projectId: fields.projectId } });
    return { row: { id, title: fields.title, projectId: fields.projectId }, session: undefined };
  },
  read: async ({ runId }) => {
    const rows = await db.task.findMany({ where: { projectId: { startsWith: runPrefix(runId) } } });
    return rows.map((t) => ({ id: t.id, title: t.title, projectId: t.projectId }));
  },
},
```

- **`seed`** creates one row from `fields`, returns `{ row, session }` (`session` only for identity entities like `user`/`session`). Return the exact field shape the entity declares.
- **`read`** returns all this run's rows. Scope every query by the run (`runPrefix(runId)` / run-scoped id) so the oracle only sees this run's data.
- Entities live in `.ripplo/`, impls in the app's engine funnel — never declare `entity(...)` in app code.

## Adding a world

Pure functions in `.ripplo/worlds/index.ts` returning a flat record of handles. Compose from an existing base:

```ts
export const projectWithTasks = () => {
  const base = ownedProject(); // reuse, don't re-seed auth/project
  const task = Task.of({ title: arbitrary(Task.field.title), projectId: base.project.id });
  return { ...base, task };
};
```

- `Entity.of(props)` — guaranteed. `Entity.only(props)` — exactly one. `Entity.maybe(props)` — optional. `Entity.none(where)` — asserts absence (returns a handle; include it in `given`).
- `arbitrary(Entity.field.x)` is the only param source — a fresh draw each call. Wire FKs from a parent handle's id.
- The builder must return every handle it creates (a dropped const → `no-unused-vars` or a dangling-ref throw at finalize).

## Parallel safety

Tests run concurrently. Isolation lives in the **engine impl**, not the test: seed with run-scoped ids (`testId(runId, "task")`), scope `read`/cleanup to `runPrefix(runId)`, never touch rows your run didn't create. Symptoms of leakage — unique-constraint errors, 401 mid-test, vanishing rows — are impl bugs, not test bugs.

## Determinism

- `role`-based locators (`button("Save")`, `textbox("Title")`, `heading(...)`, `link(...)`, `dialog(...)`, `row(...)`, `menuitem(...)`, …); `testId\`...\``only when no ARIA role exists. Exact text — no`contains`/regex.
- Every locator name is a tagged template: `button\`Edit ${schedule.name}\``, `row(schedule.name)` — bindings work anywhere a name does.
- Scope into rows/dialogs with `inside(scope, target)`: `click(inside(row(schedule.name), button("Delete")))`, `inside(main(), button("New"))` for duplicate CTAs. Container rows usually need an `aria-label` in the app — add it rather than reaching for `testId`.
- `arbitrary(...)` for seeded values; reference handles (`project.id`, `task.title`) directly — never hardcode ids.
- The arrange/act boundary is `given:` vs `steps:` — everything a step needs traces to a handle in `given`.

## Parallelizing multi-test sessions

Implementing more than ~3 tests: fan out subagents (~5 per batch, one per test or per 2–3 sharing a world). **Every Agent prompt must instruct the subagent to first invoke the Skill tool with `ripplo:create`** — subagents don't inherit skill context and will hallucinate DSL without it. Keep lint/run/debug and entity+impl wiring on the main agent.
