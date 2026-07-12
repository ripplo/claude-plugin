---
name: create
description: "Create a new Ripplo e2e workflow: model the state it touches as entities, compose its starting givens, write the action/assertion steps, and run it. Use when adding an e2e workflow for a user flow."
---

# Create Ripplo Workflow

If the flow doesn't work yet, fix the app first or in lockstep — never weaken the workflow to paper over an app bug. Confirmed real app bug while authoring? File it with `npx ripplo report-bug` (kind tree, bar, and fields in `/ripplo:run`). New scaffolding the workflow needs (a new entity + engine impl, a new given) is in-scope work, not a follow-up.

Backend verification is automatic: declare expected backend state inline (`Entity.created/updated/deleted`) and Ripplo checks your app's actual state against what the test declared after each step.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`.

## The model (read before writing)

This skill covers the common path. The **full primitive catalog** — every action, locator, predicate, field axis, value-space, and the relational `within`/`where` assertions — is at `node_modules/@ripplo/testing/DSL.md`; read it for less-common primitives (`select`/`upload`/`check`, singleton state, optional fields, relational selection). Skim `.ripplo/entities/`, `.ripplo/givens.ts`, and `.ripplo/workflows/` for this project's real patterns. Three layers:

- **Entities** (`.ripplo/entities/`) — the state model: `entity("name", { fields, identity, source })`. `source` is where the state persists: `"backend"` (default — server-side state; impl in the server engine) vs `"client"` (browser-only state: localStorage/IndexedDB/in-memory; impl in the client engine via `mountClientEngine(ripplo, impls, { enabled })`, gated by a build-time flag mirroring the server's — Vite: `VITE_ENABLE_RIPPLO_TESTING`; Next.js: `NEXT_PUBLIC_ENABLE_RIPPLO_TESTING`). Unsure → backend; a browser cache of server-owned data is backend. A field is a free, seedable state dimension with a value-space (`field({ value: v.email() })`). A foreign key is just `field({ value: v.id() })` wired to a parent's id at setup. Derived values (`slug = slugify(name)`) and server-defaulted values (`createdAt`) are **not fields** — drop them. `{ optional: true }` = nullable.
- **Givens** (`.ripplo/givens.ts` + per-feature `givens.ts`) — small pure functions, each returning one entity handle (or a tight cluster). A given takes its parents as arguments and wires foreign keys from their handles. Cross-feature givens (user, org, member, project, session, subscription) live in `.ripplo/givens.ts`; feature-specific ones live in a `givens.ts` colocated with the workflows that use them. No big shared bundles that workflows spread and override — compose the pieces each workflow needs.
- **Workflows** (`.ripplo/workflows/`) — `workflow("Intent", () => ({ given, steps }))`. `given` is the setup (one array of all handles); `steps` is the act + assert. The compiler enumerates one concrete test per `when` branch at `ripplo compile`/`lint` time — a workflow with no when blocks compiles to a single test named "main". Runs are per test.

A workflow is a **user journey**: one thing the user set out to accomplish, traced as the real click path from a natural entry point, however many steps and mutations that takes. "Set up my project's first task board" is one workflow — navigate in, create the board, add a task, verify it stuck. A single button click with one assertion is almost never a whole journey. A different intent ("also delete the project") is a separate workflow.

Two primitives you'll reach for often (full detail in DSL.md):

- **Who's signed in — `actor`.** `actor.set(handle)` in `given` = the test starts signed in as that seeded principal; as a _step_ = a mid-run switch (signs in, reloads). `actor.anonymous` = signed out. Sign-out is declared, not performed: assert `actor.is(actor.anonymous)` on the step that logs out / revokes the current session / deactivates the account. Ripplo observes the real signed-in identity every frame, so `actor.set` is self-verifying and an undeclared sign-out is caught on its own.
- **Mutually-exclusive UI — `exclusive`.** Tabs, a toggle, settings sections where one state hides the others: declare the group once with `exclusive({ open: visible(a), closed: visible(b) })` (usually in `.ripplo/surfaces/`). Asserting one member auto-negates its siblings — skip the hand-written `not(visible(...))`.

## Procedure

1. **Name the user intent in one sentence** ("a user sets up their first task and marks it done"). That sentence is the workflow — everything the user does to accomplish it belongs in this one workflow's steps.
2. **Walk the click path like a user.** Start at a natural entry point (dashboard, root, the page a real user lands on) and navigate through nav, lists, and menus to the target. `goto` a deep URL only when the journey genuinely starts from a link — an email invite, a shared URL. Navigation steps are free coverage, and a path a user can't click is a bug worth catching.
3. **Name the regression each mutation would catch** ("user clicks Save, UI shows success, but the DB write silently dropped"). Those sentences dictate the assertions — if a step would pass against its bug, it's not deep enough. Trace each mutation end-to-end (component → resolver/route → DB); the entities to assert fall out of the trace.
4. **Sweep the path for branches.** For every step, ask: what seeded state would change this step's outcome? Empty vs populated list, first vs last item, a pending state, a role difference. Each answer becomes a named `when` branch or gets explicitly ruled out — write the list down before writing code. A journey with zero whens usually means the sweep was skipped, not that the path has no state-dependent outcomes.
5. **Compose the givens — seed only what the path can't reach.** Earlier journey steps produce the state later steps need, so prefer creating state through the UI within the journey over seeding it. Browse `.ripplo/givens.ts` (and the feature's `givens.ts`); reuse existing givens, add a new one only when a piece of state has no given yet. Extra `given` constraints narrow the starting state and stop tests from compounding — keep it to the minimal set.
6. **Ensure the entities exist.** Every seeded row and asserted state needs an `entity(...)` in `.ripplo/entities/` and a matching engine impl (TS errors if missing).
7. **Read the real component/route source** for ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, add them to the app — don't fall back to `testId()`.
8. **Write the workflow** (the intent string is the identity, not the filename):

   ```ts
   import {
     actor,
     arbitrary,
     branch,
     button,
     click,
     count,
     fill,
     goto,
     heading,
     inside,
     link,
     not,
     role,
     row,
     text,
     textbox,
     visible,
     when,
     workflow,
   } from "@ripplo/testing";
   import { Task } from "../../entities/index.js";
   import * as given from "../../givens.js";

   export const createAndCompleteTask = workflow("Create a task and mark it done", () => {
     const me = given.user();
     const signedIn = actor.set(me);
     const organization = given.organization();
     const membership = given.member(organization, me, "owner");
     const subscription = given.subscription(organization);
     const project = given.project(organization);
     const existing = Task.maybe({
       title: arbitrary(Task.field.title),
       status: "open",
       projectId: project.id,
     });
     const title = arbitrary(Task.field.title);
     return {
       given: [me, signedIn, organization, membership, subscription, project, existing],
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
           visible(row(title)),
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

   The shape to copy: entry at `/`, navigation clicked like a user, a `when` where seeded state changes what the page shows, two mutations each carrying UI plus backend evidence, and the second mutation acting on state the first one created — nothing seeded that the path could produce. Note every clicked element was declared `visible(...)` by an earlier step — lint rejects touching anything no step has shown exists, so each step's `.expect(...)` declares exhaustively what appeared (and, with `not(visible(...))`, what disappeared).

9. **Register it** — add the export to the `workflows` array in `.ripplo/workflows/index.ts` (funneled into `createRipplo({ entities, singletons, workflows })`). The subfolder under `.ripplo/workflows/` is the sidebar group. Unregistered workflows don't exist.
10. `npx ripplo compile` — fix all errors. Compile runs static model analysis, enumerates each workflow's tests, and fails on unreachable when branches (and writes the lockfile only when the model is sound).
11. `npx ripplo run <workflow-slug>` runs every enumerated test of the workflow; `<workflow-slug>/<test-slug>` runs one branch (slugs from run output; the quoted intent string also works). On failure, `/ripplo:run`.
12. `npx ripplo compile` and **stage `.ripplo/ripplo.lock`** alongside the `.ripplo/*.ts` changes.

## What makes a good workflow

It reads like a user session. Entry at a natural landing page, navigation clicked not teleported, several mutations along one intent, later steps consuming what earlier steps created. If the steps are goto → click → assert, the journey is missing — go back to the click path.

Cover each mutation in three phases:

- **Before:** the given seeds a known value (via `arbitrary(...)` or a literal), so an after-assertion can't pass by coincidence.
- **Action:** the user-facing step.
- **After:** both **UI evidence** (`visible(...)`/`text(...)`/`value(...)`) **and state evidence** (`Entity.created/updated/deleted`) on the same step's `.expect(...)`. A toast can lie — the state record can't.

Assert the negatives: `not(visible(role("dialog")))` after a save, errors absent, prior values gone. Regression-revealing assertions are usually negative.

Every mutation step declares its full UI delta — what appeared and, with `not(visible(...))`, what disappeared. The commonest gap: the mutation moves a row out of the current filter, swaps a button label (Reveal → Hide), or unmounts a section, and the step never says so — the model keeps the old element as a fact and fails a later step.

`text(...)`/`value(...)` assert content, not presence — the model never infers visibility from them. When two page states differ by whether something is shown, distinguish them with `visible(...)`/`not(visible(...))`, not by text alone.

Branch coverage: outcome depends on state (empty vs populated, first vs last item)? Express it as a `when` block — the compiler enumerates a test per branch. Different actors or flows (admin vs member) are separate workflows with their own givens.

## Branching with `when`

`when` takes named `branch(...)` builders, each guarded by `.if(condition)` and asserted with `.expect(...)`:

```ts
when(
  branch("deleting the last project")
    .if(count(Project).is(0))
    .expect(url.path.is`/connect`),
  branch("deleting the first project, onboarding pending")
    .if(and(count(Project).is(1), onboardingDismissed.is(false)))
    .expect(url.path.is`/onboarding`, url.query.is({ projectId: other.id })),
  branch("deleting one of several projects").expect(url.path.is`/projects`),
);
```

- Every branch is named. At most one unconditional branch, last. Names unique within a workflow.
- No nested whens — a `when` inside a branch's `.expect(...)` is an error ("whens are one level deep"). A scenario that wants a second level is its own workflow.
- The name labels the test, not the condition — describe the scenario from the user's point of view, including the state that drives the different outcome. Two failure modes to avoid: post-state names ("no projects left" describes the result, not the scenario) and seed-mechanics names ("first project, onboarding pending" describes how the state was seeded). Test: it should read as a sentence under the workflow name, and someone seeing the name as a failed-test label should know which situation broke. "Delete project → deleting the last project" works. "Delete project → deleting a project when the remaining project still needs onboarding" works. "Delete project → no projects left" and "Delete project → first project, onboarding pending" do not.
- The compiler solves a seed per branch: it picks which `maybe(...)` entities to seed and pins `arbitrary()` singleton values so the condition holds after the steps' declared effects. `maybe()` entities are compile-time degrees of freedom, never randomly chosen at run time.
- `.if(...)` gates on modeled state only — entity conditions (`count(Task.where({ status: "open" })).is(0)`, `exists(Run)`), client singletons, URL-visible state. `or(...)` combines conditions. Transient DOM (a dialog mid-flight, a hover) is not conditionable by design — if a branch seems to need it, model the cause as a URL param or client singleton.
- "branch X is unreachable" at compile = no seed can satisfy the condition — fix the condition or widen the given set with `maybe` entities.
- "too many optional entities and singleton values to solve" at compile = candidate seeds exceed the 4096 cap (maybe subsets × singleton pin combinations) — split the workflow or convert `maybe(...)` entities to `of(...)`.

## Backend assertions — Ripplo verifies backend state

Every mutation step carries an entity assertion in its `.expect(...)`. After each step Ripplo compares your app's state against what the test declared and flags any mismatch. You declare expected state; you never poll.

- `Entity.created({ field: value, ... })` — a row with these fields now exists.
- `Entity.updated({ id: handle.id }, { field: newValue })` — the keyed row changed. Use `changed()` when the new value is server-chosen: `{ token: changed() }` asserts it differs without pinning it. `increased()`/`decreased()` additionally assert the direction — `{ lastSeenAt: increased() }` requires the new value strictly above the old one.
- `Entity.deleted({ id: handle.id })` — the keyed row is gone.

Consistency timing is automatic: `consistency: "eventual"` (or a `changed()` baseline) tolerates propagation lag; the default `strict` fails fast on a wrong intermediate value.

Pair every backend assertion with the user-visible outcome. A mutation step's `.expect(...)` asserts what the user now sees — the new item rendered in the list, the updated value on screen — never just a proxy like a closed dialog or a toast. A green toast over a dropped write is exactly the bug class backend assertions catch, and a backend row the user can't see is the inverse.

## Adding an entity

A seeded or asserted row needs (a) a definition and (b) an impl; TS flags a missing impl.

```ts
// .ripplo/entities/index.ts
export const Task = entity("task", {
  description: "A task under a project",
  fields: {
    title: field({ value: v.word() }),
    status: field({ value: v.oneOf(["open", "done"]) }),
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
    await db.task.create({ data: { id, ...fields } });
    return { id, ...fields };                           // just the row — no session
  },
  read: async ({ runId }) => {
    const rows = await db.task.findMany({ where: { projectId: { startsWith: runPrefix(runId) } } });
    return rows.map((t) => ({ id: t.id, title: t.title, status: t.status, projectId: t.projectId }));
  },
},
```

- **`seed`** creates one row from `fields` and returns just that row — no session, no auth. Return the exact field shape the entity declares. Signing in is a separate concern: mark a principal entity `principal: true` and give it a `signIn` impl (mints a browser session) plus the global `currentActor(session)` impl (resolves live cookies → the signed-in id). See `/ripplo:setup` and DSL.md for the auth impls.
- **`read`** returns all this run's rows. Scope every query by the run (`runPrefix(runId)` / run-scoped id) so Ripplo only sees this run's data.
- Entities live in `.ripplo/`, impls in the app's engine funnel — never declare `entity(...)` in app code.
- **Adding an entity obligates every flow that writes it.** Once an entity has a `read` impl, Ripplo checks its rows after every step — including rows the app creates as a side effect (creating a dataset that auto-creates default columns, for example). Before wiring the impl, search the app for every mutation that writes this table and declare those effects with `Entity.created(...)` in the affected workflows. An undeclared side-effect row surfaces as an unexpected-row finding with the row's fields ready to paste into a declaration.

## Adding a given

A given is a small pure function returning one handle (or a tight cluster), taking its parents as arguments and wiring foreign keys from their handles:

```ts
export function task(project: ProjectHandle): ReturnType<typeof Task.of> {
  return Task.of({ projectId: project.id, title: arbitrary(Task.field.title) });
}
```

Cross-feature givens go in `.ripplo/givens.ts`; feature-specific ones in a `givens.ts` next to the workflows that use them. Deep graphs (parent → children → grandchildren) seed flat: a given that flatMaps each level, wiring every FK from the parent handle — each row keeps a real handle and the compiler sees a flat `given` it can solve.

- `Entity.of(props)` — guaranteed. `Entity.only(props)` — exactly one. `Entity.maybe(props)` — optional, a compile-time degree of freedom the compiler solves per test. `Entity.none(where)` — asserts absence (returns a handle; include it in `given`).
- `arbitrary(Entity.field.x)` is the only param source — a fresh draw each call. Wire FKs from a parent handle's id.
- Every handle a given creates must reach the `given:` array (a dropped const → `no-unused-vars` or a dangling-ref throw at finalize).

## Parallel safety

Tests run concurrently. Isolation lives in the **engine impl**, not the workflow: seed with run-scoped ids (`testId(runId, "task")`), scope `read`/cleanup to `runPrefix(runId)`, never touch rows your run didn't create. Symptoms of leakage — unique-constraint errors, 401 mid-test, vanishing rows — are impl bugs, not workflow bugs.

## Determinism

- `role`-based locators (`button("Save")`, `textbox("Title")`, `heading(...)`, `link(...)`, `dialog(...)`, `row(...)`, `menuitem(...)`, …); `testId\`...\``only when no ARIA role exists. Locator names are exact — no matcher form, no regex.
- `text(el, x)`/`value(el, x)` assert the whole normalized text exactly. Substring or prefix intent is explicit: `text(el, contains("frag"))`, `value(el, startsWith("tmp-"))`. Matcher-valued assertions check at their own step but do not carry as facts — only exact claims do.
- Numeric copy asserts the formula, not a literal: `text(pill, s\`Open tasks ${count(Task.where({ status: "open" }))}\`)` — the expected number resolves from the predicted model state and carries as one parametric fact instead of a pile of count-guarded branches.
- Every locator name is a tagged template: `button\`Edit ${schedule.name}\``, `row(schedule.name)` — bindings work anywhere a name does.
- Scope into rows/dialogs with `inside(scope, target)`: `click(inside(row(schedule.name), button("Delete")))`, `inside(main(), button("New"))` for duplicate CTAs. Container rows usually need an `aria-label` in the app — add it rather than reaching for `testId`.
- `arbitrary(...)` for seeded values; reference handles (`project.id`, `task.title`) directly — never hardcode ids.
- The setup/act boundary is `given:` vs `steps:` — everything a step needs traces to a handle in `given`.

## Facts — how a `visible`/`text` assertion carries forward

Every `visible(...)`/`text(...)`/`value(...)` you assert becomes a **fact**: a `when ⇒ consequence` rule the model keeps and re-checks on every later step whose state matches `when`. That is the point of the model — assert `visible(button("Save"))` once and Ripplo holds you to it wherever that state recurs, catching real inconsistencies the explorer walks into. Facts are keyed by their **consequence** (the predicate), and grouped across the whole suite by it.

Facts and element declarations are also what the background explorer composes paths from — the deeper each workflow declares, the more the explorer has to walk. Once your workflows run green it probes beyond them automatically, walking composed paths no author wrote and filing what it finds as tasks (triage via `/ripplo:tasks`).

When the same consequence is asserted by two or more workflows, the model **generalizes**: it keeps only the conditions those assertions share and drops the rest. If they were on different URLs, the URL drops out — the fact now holds under bare entity-state and is enforced on every page with that state. So `visible(button("Save"))` asserted on two pages is read as a global claim "Save is available in this state," and fails on a third page that has no Save. Locator kind is irrelevant — a `testId` consequence generalizes identically.

This is intended strictness, not a bug. A fact is global unless its **consequence is page-specific**:

- Global capability (present everywhere in that state) → assert it bare. Correct and wanted.
- Page-specific element → give the consequence a page-unique identity so it can't group with another page's. Scope inside a named container — `visible(inside(dialog("Duplicate event type"), button("Continue")))`, `inside(region("Availability"), button("Save"))`. Different container name → different consequence → stays single-producer → stays local. Add the `aria-label`/landmark to the app when none exists — it is real accessibility markup, not test scaffolding.

Debug at compile time: a `fact` violation from `npx ripplo compile` prints both contradicting consequences and, under each, every producing test with its full condition set. Read the two producer lists side by side — the one missing a pin the others share is what broadened the fact. Add that pin to the short producer, or split the outcome with a when branch.

Debug at run time: a run fails on a check the step never wrote, on an unrelated page. `npx ripplo explain <runId>` names the workflows that taught the fact and prints `at (any view)` when the URL was generalized away. It tags each fact `inferred` (one workflow asserted it, re-checked here because the state matches), `learned` (generalized from two or more, conditions intersected), or `declared` (a standalone fact you wrote — see below) — `learned` on `(any view)` is the classic over-broad fact.

### Declared facts — a rule without a workflow

The three tiers form one promotion pipeline: a workflow assertion is `inferred` (one producer), the same consequence from two or more workflows generalizes to `learned` (shared conditions only), and a `declared` fact sits above both — you author it directly, and it is always enforced without any workflow producing it. A more specific fact overrides a more general one, so a declared or inferred fact wins over a broad `learned` one on the pages it covers.

Reach for a declared fact when a rule spans the whole app and no single workflow owns it — an invariant ("the crash screen never shows") or a permission boundary ("members can't see the rotate-secret button"). Write them in `.ripplo/facts.ts` and wire the array into `createRipplo({ ..., facts })`:

```ts
export const noCrashScreen = fact("the app never shows the crash screen").expect(
  not(visible(heading("Something went wrong"))),
);

export const membersCannotManageWebhookSecret = fact("members cannot manage the webhook secret")
  .if(exists(Member.where({ role: "member", userId: actor.id })))
  .expect(not(visible(button("Rotate secret"))));
```

`fact(name).expect(...)` is unconditional — it holds on every page. `fact(name).if(...conditions).expect(...)` holds only where the conditions match. An `.if()` that references `actor.id` needs exactly one `principal: true` entity or compile throws. Don't reach for declared facts to paper over a leaky generalized fact — the fix for that is a page-scoped consequence, above. Declared facts are for genuine app-wide rules.

### Scoping conventions

Named containers cover most leaks. The rest fall to these:

- **Groupings that open and close (modal, drawer, menu, tab, accordion section)** — model these as a **surface**, never by hand-listing the background they hide. A step that hides 2+ elements at once is a `surface` compile error. `const editRepo = surface(dialog("Edit repository"), { overlay: true })`; open with `visible(editRepo)` (background auto-suppresses — no `not(visible(...))` for it), scope contents with `inside(editRepo, ...)`, close with `not(visible(editRepo))` — the background page resumes automatically, but the surface's own contents are forgotten on close. Reopening does not bring them back: re-assert `visible(inside(surface, ...))` for anything a later step interacts with. Use `{ overlay: true }` for anything that covers the page (modal, backdropped drawer, occluding menu) and `{ overlay: false }` for a panel that coexists (tab panel, accordion section) — panels gate only their own `inside(...)` content and always need it. Registration is inferred from usage; the same container can't be both overlay and panel. Full reference: `surface` in `node_modules/@ripplo/testing/DSL.md`.
- **Transient toast/spinner** — wrap it in `ephemeral(...)`: `ephemeral(text(testId("toast-success"), "Saved"))`. It's checked at that step (waiting to appear on the normal timeout) but never promoted to a fact, so it can't leak onto later steps. Still carry the durable proof as `Entity.updated` — a toast can lie. A success toast asserted at page load is always wrong. `ephemeral(...)` also fits step-local exact-value evidence that should not carry as a fact — a validation alert shown mid-edit, an exact `value(...)` the flow changes a step later. If the claim is only true at this step, wrap it. `ephemeral(...)` wraps UI predicates only, and grants no reachability — to click something, assert a normal `visible(...)`.
- **Post-delete absence** — assert `not(visible(...))` on the delete step itself, where the row is confirmed gone. Don't leave a `visible(row)` fact that a later page re-checks.
- **Generic shared name** — a `button("Save")`/`button("Update")` that appears on many settings pages under the same name is inherently global. Scope it inside the page `main(...)` (or a region) to make the consequence page-local.
- **Duplicate accessible name on one page** — two elements share a name (two "Dark" radios: app theme + booking theme). Disambiguate with `inside(region(...), ...)` or a more specific role — never a bare name that matches both, which also trips strict-mode locator errors.

## Parallelizing multi-workflow sessions

Implementing more than ~3 workflows: fan out subagents (~5 per batch, one per workflow or per 2–3 sharing givens). **Every Agent prompt must instruct the subagent to first invoke the Skill tool with `ripplo:create`** — subagents don't inherit skill context and will hallucinate DSL without it. Keep lint/run/debug and entity+impl wiring on the main agent.
