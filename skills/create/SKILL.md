---
name: create
description: "Create a new Ripplo e2e workflow: model the state it touches as entities, build its starting world, write the action/assertion steps, and run it. Use when adding an e2e workflow for a user flow."
---

# Create Ripplo Workflow

If the flow doesn't work yet, fix the app first or in lockstep — never weaken the workflow to paper over an app bug. Confirmed real app bug while authoring? File it with `npx ripplo report-bug` (kind tree, bar, and fields in `/ripplo:run`). New scaffolding the workflow needs (a new entity + engine impl, a new world builder) is in-scope work, not a follow-up.

Backend verification is automatic: declare expected backend state inline (`Entity.created/updated/deleted`) and Ripplo checks your app's actual state against what the test declared after each step.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`.

## The model (read before writing)

This skill covers the common path. The **full primitive catalog** — every action, locator, predicate, field axis, value-space, and the relational `within`/`where` assertions — is at `node_modules/@ripplo/testing/DSL.md`; read it for less-common primitives (`select`/`upload`/`check`, singleton state, optional fields, relational selection). Skim `.ripplo/{entities,worlds,tests}/` for this project's real patterns. Three layers:

- **Entities** (`.ripplo/entities/`) — the state model: `entity("name", { fields, identity, source })`. `source` is where the state persists: `"backend"` (default — server-side state; impl in the server engine) vs `"client"` (browser-only state: localStorage/IndexedDB/in-memory; impl in the client engine via `mountClientEngine(ripplo, impls, { enabled })`, gated by a build-time flag mirroring the server's — Vite: `VITE_ENABLE_RIPPLO_TESTING`; Next.js: `NEXT_PUBLIC_ENABLE_RIPPLO_TESTING`). Unsure → backend; a browser cache of server-owned data is backend. A field is a free, seedable state dimension with a value-space (`field({ value: v.email() })`). A foreign key is just `field({ value: v.id() })` wired to a parent's id at setup. Derived values (`slug = slugify(name)`) and server-defaulted values (`createdAt`) are **not fields** — drop them. `{ optional: true }` = nullable.
- **Worlds** (`.ripplo/worlds/`) — pure builder functions returning a flat record of entity handles, composed from other worlds. A world must return every handle it creates.
- **Workflows** (`.ripplo/workflows/`) — `workflow("Intent", () => ({ given, steps }))`. `given` is the setup (one array of all handles); `steps` is the act + assert. The compiler enumerates one concrete test per `when` branch at `ripplo compile`/`lint` time — a workflow with no when blocks compiles to a single test named "main". Runs are per test.

## Procedure

1. **Name the regression in one sentence** ("user clicks Save, UI shows success, but the DB write silently dropped"). That sentence dictates the assertions — if the workflow would pass against that bug, it's not deep enough.
2. **Trace the mutation end-to-end** (component → resolver/route → DB). The entity to assert and the world to seed fall out of the trace.
3. **Pick or build the world.** Browse `.ripplo/worlds/index.ts`; reuse a builder if one fits, else compose a new one on an existing base — don't re-seed auth/org/project.
4. **Ensure the entities exist.** Every seeded row and asserted state needs an `entity(...)` in `.ripplo/entities/` and a matching engine impl (TS errors if missing).
5. **Read the real component/route source** for ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, add them to the app — don't fall back to `testId()`.
6. **Write the workflow** (the intent string is the identity, not the filename):

   ```ts
   import {
     arbitrary,
     button,
     click,
     fill,
     goto,
     heading,
     role,
     text,
     textbox,
     visible,
     workflow,
   } from "@ripplo/testing";
   import { Task } from "../../entities/index.js";
   import { ownedProject } from "../../worlds/index.js";

   export const createTask = workflow("Create a task in a project", () => {
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

7. **Register it** — add the export to the `workflows` array in `.ripplo/workflows/index.ts` (funneled into `createRipplo({ entities, singletons, workflows })`). The subfolder under `.ripplo/workflows/` is the sidebar group. Unregistered workflows don't exist.
8. `npx ripplo lint` — fix all errors. Lint also enumerates each workflow's tests and fails on unreachable when branches.
9. `npx ripplo run <workflow-slug>` runs every enumerated test of the workflow; `<workflow-slug>/<test-slug>` runs one branch (slugs from run output; the quoted intent string also works). On failure, `/ripplo:run`.
10. `npx ripplo compile` and **stage `.ripplo/ripplo.lock`** alongside the `.ripplo/*.ts` changes.

## What makes a good workflow

Cover each mutation in three phases:

- **Before:** the world seeds a known value (via `arbitrary(...)` or a literal), so an after-assertion can't pass by coincidence.
- **Action:** the user-facing step.
- **After:** both **UI evidence** (`visible(...)`/`text(...)`/`value(...)`) **and state evidence** (`Entity.created/updated/deleted`) on the same step's `.expect(...)`. A toast can lie — the state record can't.

Assert the negatives: `not(visible(role("dialog")))` after a save, errors absent, prior values gone. Regression-revealing assertions are usually negative.

Branch coverage: outcome depends on state (empty vs populated, first vs last item)? Express it as a `when` block — the compiler enumerates a test per branch. Different actors or flows (admin vs member) are separate workflows with their own worlds.

## Branching with `when`

`when` takes named `branch(...)` builders, each guarded by `.if(condition)` and asserted with `.expect(...)`:

```ts
when(
  branch("deleting the last project")
    .if(count(Project).is(0))
    .expect(url.is`/connect`),
  branch("deleting the first project, onboarding pending")
    .if(and(count(Project).is(1), onboardingDismissed.is(false)))
    .expect(url.is`/onboarding?projectId=${other.id}`),
  branch("deleting one of several projects").expect(url.is`/projects`),
);
```

- Every branch is named. At most one unconditional branch, last. Names unique within a workflow.
- No nested whens — a `when` inside a branch's `.expect(...)` is an error ("whens are one level deep"). A scenario that wants a second level is its own workflow.
- The name labels the test, not the condition — describe the scenario from the user's point of view, including the state that drives the different outcome. Two failure modes to avoid: post-state names ("no projects left" describes the result, not the scenario) and seed-mechanics names ("first project, onboarding pending" describes how the world was built). Test: it should read as a sentence under the workflow name, and someone seeing the name as a failed-test label should know which situation broke. "Delete project → deleting the last project" works. "Delete project → deleting a project when the remaining project still needs onboarding" works. "Delete project → no projects left" and "Delete project → first project, onboarding pending" do not.
- The compiler solves a seed per branch: it picks which `maybe(...)` entities to seed and pins `arbitrary()` singleton values so the condition holds after the steps' declared effects. `maybe()` entities are compile-time degrees of freedom, never randomly chosen at run time.
- "branch X is unreachable" at compile = no seed can satisfy the condition — fix the condition or widen the world with `maybe` entities.
- "too many optional entities and singleton values to solve" at compile = candidate seeds exceed the 4096 cap (maybe subsets × singleton pin combinations) — split the workflow or convert `maybe(...)` entities to `of(...)`.

## Backend assertions — Ripplo verifies backend state

Every mutation step carries an entity assertion in its `.expect(...)`. After each step Ripplo compares your app's state against what the test declared and flags any mismatch. You declare expected state; you never poll.

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
- **`read`** returns all this run's rows. Scope every query by the run (`runPrefix(runId)` / run-scoped id) so Ripplo only sees this run's data.
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

- `Entity.of(props)` — guaranteed. `Entity.only(props)` — exactly one. `Entity.maybe(props)` — optional, a compile-time degree of freedom the compiler solves per test. `Entity.none(where)` — asserts absence (returns a handle; include it in `given`).
- `arbitrary(Entity.field.x)` is the only param source — a fresh draw each call. Wire FKs from a parent handle's id.
- The builder must return every handle it creates (a dropped const → `no-unused-vars` or a dangling-ref throw at finalize).

## Parallel safety

Tests run concurrently. Isolation lives in the **engine impl**, not the workflow: seed with run-scoped ids (`testId(runId, "task")`), scope `read`/cleanup to `runPrefix(runId)`, never touch rows your run didn't create. Symptoms of leakage — unique-constraint errors, 401 mid-test, vanishing rows — are impl bugs, not workflow bugs.

## Determinism

- `role`-based locators (`button("Save")`, `textbox("Title")`, `heading(...)`, `link(...)`, `dialog(...)`, `row(...)`, `menuitem(...)`, …); `testId\`...\``only when no ARIA role exists. Exact text — no`contains`/regex.
- Every locator name is a tagged template: `button\`Edit ${schedule.name}\``, `row(schedule.name)` — bindings work anywhere a name does.
- Scope into rows/dialogs with `inside(scope, target)`: `click(inside(row(schedule.name), button("Delete")))`, `inside(main(), button("New"))` for duplicate CTAs. Container rows usually need an `aria-label` in the app — add it rather than reaching for `testId`.
- `arbitrary(...)` for seeded values; reference handles (`project.id`, `task.title`) directly — never hardcode ids.
- The setup/act boundary is `given:` vs `steps:` — everything a step needs traces to a handle in `given`.

## Parallelizing multi-workflow sessions

Implementing more than ~3 workflows: fan out subagents (~5 per batch, one per workflow or per 2–3 sharing a world). **Every Agent prompt must instruct the subagent to first invoke the Skill tool with `ripplo:create`** — subagents don't inherit skill context and will hallucinate DSL without it. Keep lint/run/debug and entity+impl wiring on the main agent.
