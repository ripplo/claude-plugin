---
name: create
description: "Create a new Ripplo e2e workflow: model the state it touches as entities, compose its starting givens, write the action/assertion steps, and run it. Use when adding an e2e workflow for a user flow."
---

# Create Ripplo Workflow

Flow broken? Fix the app, never weaken the workflow. Confirmed app bug? File with `npx ripplo report-bug` (see `/ripplo:run`). New entity/impl/given the workflow needs is in-scope. Backend verification is automatic: declare `Entity.created/updated/deleted` inline; Ripplo checks actual state after each step.

## Prerequisite

App dev server + `npx ripplo daemon`. Check `npx ripplo doctor`; if missing, `/ripplo:start`.

## The model

Full primitive catalog at `node_modules/@ripplo/testing/DSL.md` — read for less-common primitives (`select`/`upload`/`check`, singletons, optional/relational, `within`/`where`). Skim `.ripplo/entities/`, `.ripplo/givens.ts`, `.ripplo/workflows/` for project patterns. Three layers:

- **Entities** (`.ripplo/entities/`) — `entity("name", { fields, identity, source })`. `source`: `"backend"` (default, server engine impl) or `"client"` (browser-only: localStorage/IndexedDB/in-memory, client engine via `mountClientEngine(ripplo, impls, { enabled })`, gated by a build-time flag — Vite `VITE_ENABLE_RIPPLO_TESTING`, Next.js `NEXT_PUBLIC_ENABLE_RIPPLO_TESTING`). Unsure → backend. A field is a seedable state dimension with a value type (`field({ value: v.email() })`); a foreign key is `field({ value: v.id() })` wired to a parent id. Derived (`slug`) and server-defaulted (`createdAt`) values are not fields. `{ optional: true }` = nullable.
- **Givens** (`.ripplo/givens.ts` + per-feature `givens.ts`) — small pure functions returning one entity handle (or a tight cluster), taking parents as args, wiring foreign keys from their handles. Cross-feature → `.ripplo/givens.ts`; feature-specific → colocated with their workflows. No big shared bundles.
- **Workflows** (`.ripplo/workflows/`) — `workflow("Intent", () => ({ given, steps }))`. `given` = setup (one array of handles); `steps` = act + assert. One test per `when` branch; no whens → single test "main".

A workflow is a **user journey**: one user intent, the real click path from a natural entry point, however many steps/mutations it takes. A different intent is a separate workflow.

Two primitives:

- **`actor`** — who's signed in. `actor.set(handle)` in `given` = start signed in as that principal; as a _step_ = a mid-run switch (signs in, reloads). `actor.anonymous` = signed out. Sign-out is declared: assert `actor.is(actor.anonymous)` on the logout/revoke/deactivate step. `actor.set` is self-verifying.
- **`exclusive`** — mutually-exclusive UI (tabs, toggle, settings sections). Declare once: `exclusive({ open: visible(a), closed: visible(b) })` (usually `.ripplo/surfaces/`). Asserting one member auto-negates its siblings — skip hand-written `not(visible(...))`.

## Declare up front — or eat a red run

- **A page-changing step asserts the new url:** `url.path.is("/new-path")` on any navigation.
- **Number inputs are `spinbutton`, not `textbox`:** `<input type="number">` → `spinbutton("Amount")`.
- **Siblings that appear/disappear together are an `exclusive` group** — declaring them as independent `visible`/`not(visible)` = fact conflict at compile.
- **Two of the same entity on one page need page-unique locators** — scope inside a named container (`inside(region("Owner"), ...)`) or use a distinguishing accessible name. Same locator, same page, two meanings = compile error.
- **A display backed by a record you change must declare the change:** `Entity.updated({ id }, { field: newValue })` on the acting step (badge, count, title). Asserting the new text alone leaves the model predicting the old value. No durable record backs it? Wrap in `ephemeral(...)`.

## Procedure

1. **Name the user intent in one sentence** — that is the workflow.
2. **Walk the click path like a user** from a natural entry point. `goto` a deep URL only when the journey genuinely starts from a link (email invite, shared URL).
3. **Name the regression each mutation catches.** Trace each end-to-end (component → resolver/route → DB); the entities to assert fall out of the trace.
4. **Sweep for branches.** Per step: what seeded state changes this outcome (empty vs populated, first vs last, pending, role)? Each answer → a named `when` branch or explicitly ruled out.
5. **Compose givens — seed only what the path can't reach.** Prefer creating state through the UI. Reuse existing givens; add one only when a piece of state has none. Keep `given` minimal.
6. **Ensure entities exist** — every seeded/asserted row needs an `entity(...)` + engine impl (TS errors if missing).
7. **Read real component/route source** for ARIA roles, button text, form fields. **Never fabricate locators.** No accessible name? Add it to the app — don't fall back to `testId()`.
8. **Write the workflow** (intent string is the identity, not the filename):

   ```ts
   // imports { actor, arbitrary, branch, button, click, count, fill, goto,
   //   heading, inside, link, not, role, row, text, textbox, visible, when,
   //   workflow } from "@ripplo/testing"; entities + `import * as given`
   export const createAndCompleteTask = workflow("Create a task and mark it done", () => {
     const me = given.user();
     const signedIn = actor.set(me);
     const project = given.project(given.organization());
     const existing = Task.maybe({
       title: arbitrary(Task.field.title),
       status: "open",
       projectId: project.id,
     });
     const title = arbitrary(Task.field.title);
     return {
       given: [me, signedIn, project, existing],
       steps: [
         goto`/`.expect(visible(link(project.name))),
         click(link(project.name)).expect(visible(link("Tasks"))),
         click(link("Tasks")).expect(
           visible(button("New task")),
           when(
             branch("starting from an empty task list")
               .if(count(Task).is(0))
               .expect(text(role("main"), "No tasks yet")),
             branch("starting from a list that already has tasks").expect(
               visible(row(existing.title)),
             ),
           ),
         ),
         click(button("New task")).expect(
           visible(heading("New task")),
           visible(textbox("Title")),
           visible(button("Create")),
         ),
         fill(textbox("Title"), title),
         click(button("Create")).expect(
           not(visible(role("dialog"))),
           visible(inside(row(title), button("Mark done"))),
           Task.created({ title, projectId: project.id }),
         ),
         click(inside(row(title), button("Mark done"))).expect(
           text(row(title), "Done"),
           Task.updated({ title, projectId: project.id }, { status: "done" }),
         ),
       ],
     };
   });
   ```

   Shape: entry at `/`, navigation clicked, a `when` where seeded state changes the page, two mutations each carrying UI + backend evidence, the second acting on state the first created. Every clicked element was declared `visible(...)` by an earlier step — compile rejects touching anything no step showed. Each `.expect(...)` declares exhaustively what appeared and (via `not(visible(...))`) what disappeared.

9. **Register it** — add the export to the `workflows` array in `.ripplo/workflows/index.ts`. Subfolder = sidebar group. Unregistered workflows don't exist.
10. `npx ripplo compile` — fix all errors. Fails on unreachable when branches; writes the lockfile only when sound.
11. `npx ripplo run <workflow-slug>` runs all its tests; `<workflow-slug>/<test-slug>` runs one branch. On failure, `/ripplo:run`.
12. `npx ripplo compile` and **stage `.ripplo/ripplo.lock`** alongside the `.ripplo/*.ts` changes.

## Good workflow — cover each mutation in three phases

- **Before:** the given seeds a known value (`arbitrary(...)` or a literal) so an after-assertion can't pass by coincidence.
- **Action:** the user-facing step.
- **After:** both **UI evidence** (`visible`/`text`/`value`) and **state evidence** (`Entity.created/updated/deleted`) on the same `.expect(...)`. A toast can lie.

- Assert negatives: `not(visible(role("dialog")))` after a save, errors absent, prior values gone.
- Every mutation step declares its full UI delta — what appeared and (via `not(visible(...))`) what disappeared (a row leaves a filter, a label swaps, a section unmounts).
- `text(...)`/`value(...)` assert content not presence — distinguish shown/not-shown with `visible`/`not(visible)`, never text alone.
- Different actors or flows (admin vs member) are separate workflows.

## Branching with `when`

`when` takes named `branch(...)` builders, each guarded by `.if(condition)` and asserted with `.expect(...)`.

- Every branch named, unique within the workflow. At most one unconditional branch, last.
- No nested whens ("whens are one level deep") — a second level is its own workflow.
- Name = the scenario from the user's POV including the driving state. Avoid post-state names ("no projects left") and seed-mechanics names ("first project, onboarding pending"). Must read as a sentence under the workflow name.
- The compiler solves a seed per branch: picks which `maybe(...)` to seed, pins `arbitrary()` singleton values so the condition holds after declared effects. `maybe()` = a compile-time choice, never random at run time.
- `.if(...)` gates on modeled state only — entity conditions (`count(Task.where({ status: "open" })).is(0)`, `exists(Run)`), client singletons, URL state. `or(...)`/`and(...)` combine. Transient DOM isn't conditionable — model the cause as a URL param or singleton.
- "branch X unreachable" = no seed satisfies the condition — fix it or widen the given set with `maybe`.
- "too many optional entities…" = candidate seeds exceed the 4096 cap — split the workflow or convert `maybe(...)` to `of(...)`.

## Backend assertions

Every mutation step carries an entity assertion; Ripplo compares actual state after each step. Pair every one with the user-visible outcome — never just a closed dialog or a toast.

- `Entity.created({ field: value })` — a row with these fields now exists.
- `Entity.updated({ id: handle.id }, { field: newValue })` — the keyed row changed. `changed()` = differs without pinning; `increased()`/`decreased()` also assert direction.
- `Entity.deleted({ id: handle.id })` — the keyed row is gone.

Timing: default `strict` fails fast on a wrong intermediate value; `consistency: "eventual"` (or a `changed()` baseline) tolerates lag.

## Adding an entity

A seeded/asserted row needs a definition (`.ripplo/entities/index.ts`) + an app engine impl (TS flags a missing impl).

```ts
export const Task = entity("task", {
  fields: {
    title: field({ value: v.word() }),
    status: field({ value: v.oneOf(["open", "done"]) }),
    projectId: field({ value: v.id() }), // FK = a plain id field wired at setup
  },
  identity: { id: id() },
  source: "backend",
}); // add Task to the exported `entities` array
```

```ts
task: {
  seed: async ({ fields, runId }) => {
    const id = testId(runId, "task"); // run-scoped id => parallel isolation
    await db.task.create({ data: { id, ...fields } });
    return { id, ...fields }; // just the row — no session
  },
  read: async ({ runId }) =>
    (await db.task.findMany({ where: { projectId: { startsWith: runPrefix(runId) } } }))
      .map((t) => ({ id: t.id, title: t.title, status: t.status, projectId: t.projectId })),
},
```

- **`seed`** creates one row from `fields`, returns just that row. Sign-in is separate: mark a principal entity `principal: true` + a `signIn` impl + the global `currentActor(session)` impl (see `/ripplo:setup`, DSL.md).
- **`read`** returns all this run's rows; scope every query by the run (`runPrefix(runId)`).
- Entities in `.ripplo/`, impls in the app engine — never `entity(...)` in app code.
- **Adding an entity obligates every flow that writes it.** Once it has a `read` impl, Ripplo checks its rows after every step — including side-effect rows. Search the app for every mutation writing this table and declare those with `Entity.created(...)`.

## Adding a given

A small pure function returning one handle (or a tight cluster), taking parents as args, wiring foreign keys:

```ts
export function task(project: ProjectHandle): ReturnType<typeof Task.of> {
  return Task.of({ projectId: project.id, title: arbitrary(Task.field.title) });
}
```

- Cross-feature → `.ripplo/givens.ts`; feature-specific → colocated `givens.ts`. Deep graphs seed flat: flatMap each level, wiring every FK from the parent handle.
- `Entity.of(props)` guaranteed; `Entity.only(props)` exactly one; `Entity.maybe(props)` optional compile-time choice; `Entity.none(where)` asserts absence (returns a handle — include it in `given`).
- `arbitrary(Entity.field.x)` is the only param source (a fresh draw each call). Wire FKs from a parent handle's id.
- Every handle a given creates must reach the `given:` array.

## Parallel safety

Isolation lives in the **engine impl**: seed run-scoped ids (`testId(runId, "task")`), scope `read`/cleanup to `runPrefix(runId)`, never touch other runs' rows. Leakage symptoms (unique-constraint errors, 401 mid-test, vanishing rows) are impl bugs.

## Determinism

- `role` locators (`button`, `textbox`, `heading`, `link`, `dialog`, `row`, `menuitem`, …); `testId\`...\`` only when no ARIA role exists. Names exact — no matcher/regex.
- `text(el, x)`/`value(el, x)` assert the whole normalized text exactly. Substring/prefix explicit: `contains(...)`, `startsWith(...)`. Matcher-valued assertions check at their step but don't carry as facts.
- Numeric copy asserts the formula: `text(pill, s\`Open tasks ${count(Task.where({ status: "open" }))}\`)`.
- Every locator name is a tagged template: `button\`Edit ${schedule.name}\``.
- Scope with `inside(scope, target)`: `inside(row(schedule.name), button("Delete"))`, `inside(main(), button("New"))` for duplicate CTAs. Container rows usually need an app `aria-label`.
- `arbitrary(...)` for seeded values; reference handles directly (`project.id`) — never hardcode ids.
- The setup/act boundary is `given:` vs `steps:`.

## Facts

Every `visible`/`text`/`value` assertion becomes a **fact**: a `when ⇒ consequence` rule re-checked on every later step whose state matches. Facts are keyed by their consequence and grouped across the suite by it — this is what the background explorer composes paths from.

When two+ workflows assert the same consequence the model **generalizes**, keeping only shared conditions. `visible(button("Save"))` on two pages becomes a global claim and fails on a third page with no Save. Intended strictness. A fact is global unless its consequence is page-specific:

- Global capability → assert it bare.
- Page-specific element → give the consequence a page-unique identity: `visible(inside(dialog("Duplicate event type"), button("Continue")))`. Add the `aria-label`/landmark to the app when none exists.

Debug: a `fact` violation from `npx ripplo compile` prints both contradicting consequences and every producing test with its conditions — the producer missing a shared pin broadened the fact; add that pin or split with a when branch. At run time, `npx ripplo explain <runId>` names the workflows that taught the fact and tags each `inferred` (one producer), `learned` (generalized from 2+), or `declared`.

### Declared facts

Author a rule directly, always enforced without any workflow; a more specific fact overrides a broad `learned` one. For app-wide rules or permission boundaries. Write in `.ripplo/facts.ts`, wire into `createRipplo({ ..., facts })`:

```ts
export const noCrashScreen = fact("the app never shows the crash screen").expect(
  not(visible(heading("Something went wrong"))),
);

export const membersCannotManageWebhookSecret = fact("members cannot manage the webhook secret")
  .if(exists(Member.where({ role: "member", userId: actor.id })))
  .expect(not(visible(button("Rotate secret"))));
```

`fact(name).expect(...)` holds everywhere; `.if(...conditions).expect(...)` only where conditions match. An `.if()` referencing `actor.id` needs exactly one `principal: true` entity. Don't use declared facts to paper over a leaky generalized fact — page-scope the consequence instead.

### Scoping conventions

- **Groupings that open/close (modal, drawer, menu, tab, accordion)** — model as a **surface**, never hand-list the hidden background (hiding 2+ elements at once is a `surface` compile error). `const editRepo = surface(dialog("Edit repository"), { overlay: true })`; open with `visible(editRepo)`, scope contents with `inside(editRepo, ...)`, close with `not(visible(editRepo))`. Contents are forgotten on close — re-assert `visible(inside(surface, ...))` after reopening anything a later step touches. `{ overlay: true }` = covers the page (modal, backdropped drawer, occluding menu); `{ overlay: false }` = a coexisting panel (tab, accordion) that always needs `inside(...)`. Same container can't be both. Full ref: DSL.md.
- **Transient toast/spinner** — `ephemeral(...)`: `ephemeral(text(testId("toast-success"), "Saved"))`. Checked at that step, never promoted to a fact. Still carry the durable proof as `Entity.updated`. Also fits step-local exact-value evidence that shouldn't carry (a mid-edit validation alert, a `value(...)` the flow changes next step). Wraps UI predicates only, grants no reachability — to click, assert a normal `visible(...)`.
- **Post-delete absence** — assert `not(visible(...))` on the delete step itself.
- **Generic shared name** — a `button("Save")` on many pages is global; scope inside `main(...)` or a region.
- **Duplicate accessible name on one page** — disambiguate with `inside(region(...), ...)` or a more specific role, never a bare name matching both.

## Parallelizing multi-workflow sessions

More than ~3 workflows: fan out subagents (~5/batch, one per workflow or per 2–3 sharing givens). **Every Agent prompt must instruct the subagent to first invoke the Skill tool with `ripplo:create`** — subagents don't inherit skill context. Keep compile/run/debug + entity/impl wiring on the main agent.
