---
name: create
description: "Create a new Ripplo e2e test: model the state it touches as entities, build its starting world, write the action/assertion steps, and run it. Use when adding an e2e test for a user flow."
---

# Create Ripplo Test

If the flow doesn't work yet, fix the app first or in lockstep — never weaken the test to paper over an app bug. Confirmed real app bug while authoring? File it with `npx ripplo report-bug`: pre-existing bug in an **existing** flow exposed by your new coverage → `--kind latent_bug`; bug in the thing being built this session → `--kind new_feature_bug`; previously-working behavior broken by a recent change → `--kind regression`. Only confirmed functionality bugs — not locator/world/test problems. Full bar + field guidance in `/ripplo:report`. New scaffolding the test needs (a new entity + its engine impl, a new world builder) is in-scope work, not a follow-up.

Backend verification is automatic: you declare expected DB state inline (`Entity.created/updated/deleted`) and the **oracle** checks observed-vs-model after each step.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`.

## The model (read before writing)

This skill covers the common path. The **full primitive catalog** — every action, locator, predicate, field axis, value-space, and the relational `within`/`where` assertions — ships at **`@ripplo/testing/DSL.md`** (find it in `node_modules/@ripplo/testing/DSL.md`); read it when you need a less-common primitive (`select`/`upload`/`check`, singleton state, optional/stable fields, relational selection). Skim `.ripplo/{entities,worlds,tests}/` for real patterns in this project. Three layers:

- **Entities** (`.ripplo/entities/`) — the **state model**: `entity("name", { fields, identity, source })`. `source` is where the state is _persisted_: `"backend"` (default — DB rows, anything the server owns; impl lives in the server engine) vs `"client"` (browser-only state: localStorage/IndexedDB/in-memory; impl lives in the client engine via `mountClientEngine(ripplo, impls, { enabled })`, gated by a targeted build-time flag mirroring the server's ENABLE_RIPPLO_TESTING (Vite: VITE_ENABLE_RIPPLO_TESTING; Next.js: NEXT_PUBLIC_ENABLE_RIPPLO_TESTING) so the mount stays out of untested production bundles). Unsure → backend; a browser cache of server-owned data is backend. A field is a free, seedable state dimension with a value-space (`field({ value: v.email() })`). A foreign key is just `field({ value: v.id() })` wired to a parent's id at setup. Functionally-derived values (`slug = slugify(name)`) and server-defaulted values (`createdAt`) are **not fields** — drop them. `{ optional: true }` = nullable; `{ stable: false }` = adopt-only (drift unchecked).
- **Worlds** (`.ripplo/worlds/`) — **pure builder functions** that return a flat record of entity handles, composed from other worlds. A world MUST return every handle it creates.
- **Tests** (`.ripplo/tests/`) — `test("Intent", () => ({ given, steps }))`. `given` is one array of all the handles (the arrange); `steps` is the script (the act + assert).

## Procedure

1. **Name the regression in one sentence** ("user clicks Save, UI shows success, but the DB write silently dropped"). That sentence dictates the assertions. If the test would pass against that bug, it's not deep enough.
2. **Trace the mutation end-to-end** (component → resolver/route → DB). The entity to assert and the world to seed both fall out of the trace.
3. **Pick or build the world.** Browse `.ripplo/worlds/index.ts` — reuse a builder if one fits. If not, write a new pure builder (see "Adding a world"). Compose, don't duplicate — layer on an existing base rather than re-seeding auth/org/project.
4. **Ensure the entities exist.** Every row the world seeds and every state the test asserts needs an `entity(...)` in `.ripplo/entities/` **and** a matching impl in the engine funnel in your app (TS errors if missing — see "Adding an entity").
5. **Read the real component/route source** for ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, add them to the app first — don't fall back to `testId()`.
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

7. **Register it** — add the export to the `tests` array in `.ripplo/tests/index.ts`. Place the file in the most relevant subfolder under `.ripplo/tests/`; the folder is the sidebar group. Unregistered tests don't exist.
8. `npx ripplo lint` — fix all errors.
9. `npx ripplo run <test-id>` (the slug printed by compile/run output; the quoted intent string also works) — on failure, `/ripplo:debug`.
10. `npx ripplo compile` and **stage `.ripplo/ripplo.lock`** alongside the `.ripplo/*.ts` changes.

## What makes a good test

Cover each mutation in three phases:

- **Before:** the world seeds a _known_ value (via `arbitrary(...)` or a literal), so an after-assertion can't pass by coincidence.
- **Action:** the user-facing step (`click`/`fill`/`goto`/…).
- **After:** both **UI evidence** (a `visible(...)`/`text(...)`/`value(...)` predicate) **and DB evidence** via an entity assertion (`Entity.created/updated/deleted`) on the same step's `.expect(...)`. A toast can lie; the row can't.

Assert the negatives: `not(visible(role("dialog")))` after a save, errors absent, prior values gone. Regression-revealing assertions are usually negative.

Branch coverage: if a route renders differently for admin vs member, empty vs populated — each branch is its own test with its own world.

## Backend assertions = the oracle

Every mutation step must carry an entity assertion in its `.expect(...)`. These ARE the backend verification — the oracle does a 3-way compare (model-before / predicted-after / observed) and flags any divergence. You declare expected state; you never poll.

- `Entity.created({ field: value, ... })` — a row with these fields now exists.
- `Entity.updated({ id: handle.id }, { field: newValue })` — the keyed row changed to this. Use `changed()` as the value when the new value is server-chosen (e.g. a rotated token): `{ token: changed() }` asserts it differs from before without pinning the value.
- `Entity.deleted({ id: handle.id })` — the keyed row is gone.

Consistency timing is automatic: a field declared `consistency: "eventual"` (or a `changed()` baseline) tolerates propagation lag; the default `strict` fails fast on a wrong intermediate value.

## Adding an entity

A row your world seeds or your test asserts needs (a) a definition and (b) an impl. TS flags a missing impl at compile time.

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

- **`seed`** creates one row from `fields` and returns `{ row, session }` (`session` is an auth session for identity entities like `user`/`session`; `undefined` otherwise). Return the exact field shape the entity declares.
- **`read`** returns all this run's rows of that entity. Scope every query by the run (`runPrefix(runId)` / a run-scoped id) so the oracle only sees this run's data.
- Entities live in `.ripplo/`, impls in your app's engine funnel — never declare `entity(...)` in app code.

## Adding a world

Worlds are pure functions in `.ripplo/worlds/index.ts` returning a flat record of handles. Compose from an existing base:

```ts
export const projectWithTasks = () => {
  const base = ownedProject(); // reuse, don't re-seed auth/project
  const task = Task.of({ title: arbitrary(Task.field.title), projectId: base.project.id });
  return { ...base, task };
};
```

- `Entity.of(props)` — guaranteed in the world. `Entity.only(props)` — exactly one. `Entity.maybe(props)` — optional. `Entity.none(where)` — asserts absence (returns an absence handle; include it in `given`).
- `arbitrary(Entity.field.x)` is the only param source — a fresh draw each call. Wire FKs by passing a parent handle's id (`projectId: base.project.id`).
- The builder MUST return every handle it creates (a dropped const → `no-unused-vars`, or a dangling-ref throw at finalize).

## Parallel safety

Tests run concurrently. Isolation lives in the **engine impl**, not the test: seed with a run-scoped id (`testId(runId, "task")`), and `read`/cleanup scoped to `runPrefix(runId)`. Never `update`/`delete` rows your run didn't create. Symptoms of leakage — unique-constraint errors, 401 mid-test, rows vanishing — are impl bugs, not test bugs.

## Determinism

- `role`-based locators (`button("Save")`, `textbox("Title")`, `heading(...)`, `link(...)`, `dialog(...)`, `row(...)`, `menuitem(...)`, …); `testId\`...\``only when no ARIA role exists. Exact text — no`contains`/regex. Full catalog in `DSL.md`.
- Every locator name is a tagged template too: `button\`Edit ${schedule.name}\``, `row(schedule.name)` — bindings work anywhere a name does, same as `goto\`/projects/${project.id}/tasks\``.
- Scope into list rows/dialogs with `inside(scope, target)`: `click(inside(row(schedule.name), button("Delete")))`, `click(inside(main(), button("New")))` for duplicate CTAs. Container rows usually need an `aria-label` in the app — add it rather than reaching for `testId`.
- Use `arbitrary(...)` for seeded values; reference handles (`project.id`, `task.title`) directly — never hardcode ids.
- The arrange/act boundary is `given:` vs `steps:`. Everything a step needs must trace to a handle in `given`.

## Parallelizing multi-test sessions

When implementing more than ~3 tests, fan out subagents (~5 per batch, one per test or per 2–3 sharing a world). **Every Agent prompt must instruct the subagent to first invoke the Skill tool with `ripplo:create`** — subagents don't inherit skill context and will hallucinate DSL without it. Keep lint/run/debug and entity+impl wiring on the main agent.
