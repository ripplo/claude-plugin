---
name: create
description: "Create a Ripplo end-to-end workflow from the app's typed state schema, starting-state constraints, user actions, and complete declared effects. Use when adding or extending workflow coverage."
---

# Create a Ripplo workflow

Fix broken app behavior in the app. Strengthen incomplete workflow declarations in the workflow.
Read `node_modules/@ripplo/testing/DSL.md` before using an unfamiliar primitive.

A workflow is a durable model of a critical user journey, not a script for one fixture. Its
`given` must describe the widest set of starting states from which the whole journey is valid.
Preserve that generality in URLs, locators, inputs, branch conditions, and effects.

## Prerequisite

Run `npx ripplo doctor`. The app dev server and `npx ripplo daemon` must be running.

Inspect:

- `.ripplo/state.ts` for schema-derived state handles
- `.ripplo/givens.ts`, when present, and feature givens for starting-state helpers
- `.ripplo/workflows/` for local authoring patterns
- The app component, route, mutation, and data model for the journey

## State model

One root Zod schema defines all application state. Its top level contains at most one HTTP source
and one browser source. Each source returns its whole validated fragment in one read.

```ts
export const state = defineState(
  z.object({
    core: source.http(z.object({
      organizations: setup.record(
        z.object({
          id: setup.generated(z.string()),
          name: setup.value(z.string()),
        }),
      ),
      projects: setup.record(
        z.object({
          id: setup.generated(z.string()),
          name: setup.value(z.string()),
          organizationId: setup.value(z.string()),
        }),
      ),
      runs: setup.record(
        z.object({
          id: setup.generated(z.string()),
          status: setup.value(z.enum(["passed", "failed"])),
          workflowId: setup.value(z.string()),
        }),
      ),
      tasks: setup.record(
        z.object({
          id: setup.generated(z.string()),
          projectId: setup.value(z.string()),
          status: setup.value(z.enum(["open", "done"])),
          title: setup.value(z.string()),
        }),
      ),
      workflows: setup.record(
        z.object({
          id: setup.generated(z.string()),
          name: setup.value(z.string()),
          projectId: setup.value(z.string()),
        }),
      ),
    })),
    frontend: source.browser(z.object({
      enabled: setup.value(z.boolean()),
      note: setup.value(z.string().optional()),
      selectedTaskId: setup.value(z.string().nullable()),
    })),
  }),
);

export const { organizations, projects, runs, tasks, workflows } = state.core;
```

- `setup.value()` means a workflow can supply the value.
- `setup.generated()` means setup generates and returns the value.
- `setup.record()` means setup can create rows.
- Plain Zod fields are observable only.
- Wrap each source schema with `source.http()` or `source.browser()`.
- HTTP and browser sources use the same `read`, `setup.fields`, `setup.records`, and `teardown`
  contract.
- Implement `source.http()` in the server process and mount its framework adapter.
- Implement `source.browser()` in the browser bundle and pass its engine to `connect(engine)`
  before rendering.
- A read-only source implements only `read`. A setup-capable source also implements `setup` and
  `teardown`.
- Attach `createAuthenticationEngine()` directly to an HTTP record handle when a workflow needs to
  sign in. See `/ripplo:setup` for integration and ordering.

## Workflow shape

One workflow is one user intent along the real click path from a natural entry point. Earlier steps
create state later steps use. Set up only what the path cannot create.

```ts
const organizationActions = surface(menu("Organization actions"), { overlay: true });
const deleteOrganizationDialog = surface(dialog("Delete organization"), { overlay: true });

export const deleteOrganization = workflow("Delete an organization", () => {
  const organization = required(organizations, {});
  const remainingOrganization = optional(organizations, {});
  const project = required(projects, { organizationId: organization.id });
  const projectWorkflow = required(workflows, { projectId: project.id });
  const projectRun = required(runs, { workflowId: projectWorkflow.id });
  const organizationProjects = select(projects, {
    organizationId: organization.id,
  });
  const organizationWorkflows = select(workflows, (candidate) =>
    exists(select(organizationProjects, { id: candidate.projectId })),
  );
  const organizationRuns = select(runs, (candidate) =>
    exists(select(organizationWorkflows, { id: candidate.workflowId })),
  );

  return {
    given: [
      viewport.desktop,
      organization,
      remainingOrganization,
      project,
      projectWorkflow,
      projectRun,
      closed(organizations),
    ],
    steps: [
      goto`/organizations/${organization.id}/overview`.expect(
        visible(heading(organization.name)),
        visible(button("Organization actions")),
      ),
      click(button("Organization actions")).expect(
        visible(organizationActions),
        visible(inside(organizationActions, link("Settings"))),
      ),
      click(inside(organizationActions, link("Settings"))).expect(
        not(visible(organizationActions)),
        url.path.is`/organizations/${organization.id}/settings`,
        visible(heading("Organization settings")),
        visible(button("Show danger zone")),
      ),
      click(button("Show danger zone")).expect(visible(button("Delete organization"))),
      click(button("Delete organization")).expect(
        visible(deleteOrganizationDialog),
        visible(inside(deleteOrganizationDialog, textbox("Organization name"))),
        visible(inside(deleteOrganizationDialog, button("Delete organization"))),
      ),
      fill(
        inside(deleteOrganizationDialog, textbox("Organization name")),
        organization.name,
      ).expect(
        value(inside(deleteOrganizationDialog, textbox("Organization name")), organization.name),
        enabled(inside(deleteOrganizationDialog, button("Delete organization"))),
      ),
      click(inside(deleteOrganizationDialog, button("Delete organization"))).expect(
        not(visible(deleteOrganizationDialog)),
        deleted(organizationRuns),
        deleted(organizationWorkflows),
        deleted(organizationProjects),
        deleted(select(organizations, { id: organization.id })),
        when(
          branch("deleting the last organization")
            .if(equals(count(select(organizations, {})), exact(0)))
            .expect(url.path.is`/organizations/new`, visible(heading("Create an organization"))),
          branch("deleting one of several organizations").expect(
            url.path.is`/organizations`,
            visible(link(remainingOrganization.name)),
          ),
        ),
      ),
    ],
  };
});
```

Every clicked element must be declared reachable by an earlier durable `visible()` assertion.
Every mutation step declares its user-visible result and complete application-state effect.

Before authoring, state the journey in plain language:

- Intent: what the user is trying to accomplish
- Entry point: where that intent naturally begins
- Path: the real clicks and inputs, including intermediate mutations
- Preconditions: only state required for every step to remain valid
- Outcomes: every UI change and application-state effect, including cascades

If the description is “load this page and click this button,” zoom out until it captures the user’s
actual goal. If two cases follow the same intent and click path but differ by starting state, keep
them in one workflow with `when`. If the intent or path differs, use another workflow.

## Starting state

Use the schema handles directly:

```ts
const task = required(tasks, { projectId: project.id, status: "open" });
const candidate = optional(tasks, { projectId: project.id, status: "open" });
const note = optional(state.frontend.note, arbitrary(state.frontend.note));

absent(tasks, { projectId: project.id, status: "archived" });
absent(state.frontend.note);
closed(tasks);
equals(state.frontend.selectedTaskId, task.id);
```

- `required()` guarantees a matching row and returns typed field handles.
- `optional()` lets the solver choose presence to cover branches.
- `absent()` forbids a path or matching row.
- `closed()` says setup created every row in that collection.
- `equals()` requires a relationship or value at a path.
- `arbitrary(field)` creates a typed workflow input from the field's Zod domain.
- Omit record fields when their generated values are not shared. Use the returned record field.
- Reuse one arbitrary binding across fields only when setup must make their values equal.
- Interpolate record fields in workflow URLs and element locators. Don't repeat exact setup values
  in actions or expectations.
- Build locator numbers from live state with an `s` template. Mark fixed product copy with
  `exact(...)`.
- Record references establish setup order. Missing dependencies and cycles are compile errors.

`required`, `optional`, `absent`, and `closed` describe meaningful state shape. Presence alone can
change what the UI renders, so keep a constraint when the journey depends on that shape even if no
later state assertion names it.

Start broad:

- Omit setup-capable record fields that do not affect the journey. Setup generates them from the
  schema, and the returned record exposes their values.
- Use `arbitrary(field)` when a workflow input may be any schema-valid value. Reuse the binding in
  the browser action and the effect.
- Use `exact(value)` only when that concrete string or number causes the behavior under test.
  Enums, booleans, and `null` already have closed domains and stay bare.
- Use a relationship such as `gt`, `lte`, or `not(equals(...))` when behavior depends on a range or
  change rather than one literal.
- Add `closed(record)` only when the journey needs complete collection knowledge, usually for a
  count or existence branch.

`exact(...)` is an explicit claim of behavioral significance, not an escape hatch for the compiler.
Ask: would the journey still be valid with another schema-valid value? If yes, use a generated
binding or a relation. If no, make the exact value’s role clear in the workflow.

Keep state-derived browser values connected to state:

```ts
const nextTitle = arbitrary(tasks.title);
const selectedTask = select(tasks, { id: task.id });

fill(textbox("Title"), nextTitle);
click(button("Save")).expect(
  text(row(nextTitle), nextTitle),
  updated(selectedTask, {
    title: transform(({ after, before }) =>
      and(equals(after, nextTitle), not(equals(after, before))),
    ),
  }),
);
```

Fixed application copy such as `button("Save")` is fine. A record name, count, amount, slug, URL
segment, or other value rendered from state must come from its handle or expression. For example,
use `button(s\`Scope ${count(scopedWorkflows)}\`)`, not `button(exact("Scope 2"))`.

## Branch sweep

At each step ask which starting state can change the result while preserving the same user intent
and click path. Model that state with `optional()` or another broad constraint, then cover each
reachable outcome with a named branch.

```ts
const maybeOpenTask = optional(tasks, {
  projectId: project.id,
  status: "open",
});
const openTasks = select(tasks, { projectId: project.id, status: "open" });

when(
  branch("opening a project with tasks")
    .if(gt(count(openTasks), exact(0)))
    .expect(visible(list("Tasks"))),
  branch("opening an empty project").expect(text(main(), "No open tasks")),
);
```

A selection used by a branch condition requires `closed()` for every queried collection. Otherwise
unknown rows could change the answer. Branches are ordered. One unconditional fallback may appear
last. Nested `when()` calls are invalid. Branch conditions constrain synthesis directly. Do not
duplicate them as fixed starting-state values.

Include `maybeOpenTask` and `closed(tasks)` in `given`. The optional record gives synthesis a
presence choice, while `closed(tasks)` makes the count complete.

## State effects

`select()` is the only record filter:

```ts
const projectTasks = select(tasks, { projectId: project.id });
const openProjectTasks = select(projectTasks, { status: "open" });

updated(openProjectTasks, { status: "done" });
deleted(projectTasks);
```

Use `choose(locator, value)` to select an option in a browser control.

Selection membership is frozen before the action. Every selected row receives the effect. A
selection used by `updated()` or `deleted()` must be provably nonempty at that step. Select through
required or previously created records when one row must change. Use nested selection callbacks for
relational cascades.

Creation is exhaustive:

```ts
const newTitle = arbitrary(tasks.title);
const task = created(tasks, {
  projectId: project.id,
  status: "open",
  title: newTitle,
});
```

Supply every setup-capable field. Schema-generated fields are implicit. Use `generated()` when this
action generates a field that the schema otherwise marks `setup.value()`. Use the zero-argument
`absent()` value for an optional creation field that must be missing. The result exposes the
complete observed row.

Scalar and record field transforms are relational:

```ts
transform(state.frontend.enabled, ({ after, before }) => equals(after, invert(before)));

updated(selectedTask, {
  title: transform(({ after, before }) => not(equals(after, before))),
});
```

Use exact relations when the next value is known. Use broader relations only when the app chooses
the value. Every effect must be provably changing from the state known at that step. Compilation
rejects a possible no-op. Fix the model from the behavior:

- If the action chooses a new value, use a transform that excludes equality.
- If an earlier state decides whether the action changes anything, cover those cases with `when`.
- If the action is valid only under a real precondition, add the least-specific constraint that
  proves it and preserve excluded behavior in another branch or journey.
- Do not hardcode a convenient previous value merely to make the proof pass.

Every observed change outside declared effects is a frame failure.

For a cascade, declare every affected collection:

```ts
const projectWorkflows = select(workflows, { projectId: project.id });
const workflowRuns = select(runs, (run) =>
  exists(select(projectWorkflows, { id: run.workflowId })),
);

deleted(workflowRuns);
deleted(projectWorkflows);
deleted(select(projects, { id: project.id }));
```

## Browser declarations

- Assert the new URL after navigation.
- Use accessible roles and app-owned names from source.
- Scope duplicate names with `inside()`.
- Model modal, drawer, menu, tab, and accordion containers with `surface()`.
- Use `exclusive()` for mutually exclusive UI.
- Declare both directions of stateful UI, such as Save appearing on edit and disappearing on save.
- Before `fill`, `choose`, `clear`, `check`, or `uncheck` claims another outcome, declare whether
  the action changes the control. Use `value(...)` or `not(value(...))` for value actions and
  `checked(...)` or `not(checked(...))` for check actions. Add branches when the outcomes differ.
- Use `ephemeral()` only for step-local evidence such as a toast.
- Pair every application-state effect with user-visible evidence.
- Reuse state handles and expressions for state-rendered names, values, counts, and URL parts.

## Authentication

`actor.set(requiredActor)` signs in at start or switches actors as a step. `actor.anonymous` starts
signed out. The required record itself is actor identity. `actor.is(requiredActor)` and
`actor.is(actor.anonymous)` declare explicit actor changes. Sign-in actions are self-verifying. An
actor must come from an HTTP record collection with a matching authentication engine. Browser
records cannot act as signed-in actors.

## App-wide facts

Use `fact()` only for a true invariant or permission boundary that no single journey owns:

```ts
export const noCrashScreen = fact("the app never shows the crash screen").expect(
  not(visible(heading("Something went wrong"))),
);
```

Workflow assertions already carry as facts under the full state declared at their step. Ripplo does
not generalize them beyond those conditions. Do not replace a journey, branch, or missing effect
with a broad `fact()`.

## Procedure

1. Name one user intent.
2. Trace the real click path and every mutation in app source.
3. Write the widest starting-state constraints consistent with the entire path.
4. Sweep state-dependent outcomes into named branches.
5. Add missing state schema fields and source implementations.
6. Write the workflow with exhaustive UI and state effects. Place the file in a feature folder — `.ripplo/workflows/<feature>/<workflow>.ts`, never flat under `.ripplo/workflows/`. The folder name groups workflows on the dashboard; flat files all land in "Ungrouped". Reuse an existing feature folder when one fits.
7. Audit every string and number for unnecessary specificity.
8. Verify every effect is complete and provably changing.
9. Register it in `.ripplo/workflows/index.ts`.
10. Run `npx ripplo compile` and fix every authoring diagnostic.
11. Run `npx ripplo run <workflow-slug>/<test-slug>` until green.
12. Run bare `npx ripplo run` once for cross-workflow regressions.
13. Stage `.ripplo/ripplo.lock` with the workflow changes.

Do not hand-edit the lockfile. Do not weaken a declaration to silence an app bug.

## Final generality audit

Before calling the workflow complete:

- Does `given` contain only preconditions needed by the full journey?
- Could any exact string or number become an arbitrary binding or a wider relation?
- Does every state-rendered locator, input, URL, and expected value derive from state?
- Do optional presence and collection cardinality cases have named branches where they alter the
  same journey?
- Does each action build on state created or established by earlier steps?
- Is every application-state change declared, including cascades?
- Is every effect guaranteed to change the known state?
- Would a schema-valid value outside today’s fixtures still make the workflow meaningful?
