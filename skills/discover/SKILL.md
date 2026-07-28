---
name: discover
description: "Guided codebase crawl to plan Ripplo workflows: map the app's surface, extend its typed state schema and starting-state constraints, and identify the critical user journeys worth testing. Use when setting up Ripplo, adding workflows for new features, or planning coverage for recent changes."
---

# Ripplo Discover

Map the app's surface, model the state behind it, and identify critical user journeys worth
verifying. Implementation is `/ripplo:create`.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`. Skim
`.ripplo/state.ts`, `.ripplo/workflows/`, and any shared or feature starting-state helpers.

## Phase 1: Discover the surface

- **Routes:** guards, layouts, redirects, dynamic segments, and the state they reference.
- **Sign-in:** provider, session storage, role model, programmatic session creation, and live actor
  lookup.
- **Data model:** tables, relationships, what's required to reach what.
- **Every state-mutating interaction:** dialogs, forms (incl. filters/search), inline editing, action menus, mutating toggles, drag-and-drop, bulk actions, confirmations, wizards, tabbed panels with distinct data, upload/import/export, settings saves, toast actions, keyboard shortcuts.
- **Distinct render states per route:** empty, conditional (data/flag/plan), error, loading-gated, pagination boundaries, before/after submission. State-dependent outcomes in one journey become named `when` branches when the intent and click path stay the same. Different intents or paths become separate workflows.

## Phase 2: Model the state

Per flow:

- **Schema paths and records** — each value a workflow sets up, changes, or checks needs a typed
  path in `.ripplo/state.ts`. Mark setup inputs with `setup.value()`, generated fields with
  `setup.generated()`, and setup-capable collections with `setup.record()`.
- **Sources** — assign each top-level state fragment to the process that owns its source of truth.
  The schema supports at most one HTTP source and one browser source. Each implements one
  full-fragment `read`, schema-derived setup, and teardown when needed. HTTP state runs behind the
  server adapter. Browser state runs through `connect(engine)` before render.
- **Sign-in** — identify each HTTP record collection that may act as a signed-in user. Each needs a
  matching authentication engine with `signIn` and a fresh `currentActor` lookup. Signed-out-only
  journeys need no authentication engine.
- **Starting-state constraints** — the least-specific state required for the full journey.
  Cross-feature helpers live in `.ripplo/givens.ts`; feature helpers colocate with workflows.
- **Effects across the journey** — each mutation declares its visible result and complete typed
  state effects, such as `created(tasks, input)`, `updated(selection, changes)`, or
  `deleted(selection)`. Include cascades.

Mechanics: `/ripplo:create` covers schema, source, given, selection, and effect authoring.

## Phase 3: Plan the journeys

One journey is one user intent traced through the real click path from a natural entry point. It
usually includes several mutations. One journey is one workflow. Later steps consume state created
by earlier steps, so starting state contains only what the path cannot establish.

List the journeys first, then check coverage:

- **Every Phase-1 mutation appears in some journey.** Orphan mutation = missing journey, not a one-click workflow.
- **Every state-dependent outcome appears** — as a `when` branch when the journey stays the same, or
  its own workflow when the intent or path differs.
- **Every journey starts as wide as possible** — note only structural presence, absence, relations,
  permissions, and other preconditions that the complete path truly needs.
- **Every browser value stays connected to state** — record names, ids, slugs, amounts, and counts
  come from handles or expressions rather than repeated literals.
- **Every mutation has a complete effect** — include indirect changes and cascades. An undeclared
  observed change is a frame violation.
- **Every effect definitely changes state** — use a relation that excludes equality or the
  least-specific true precondition. Never fix a convenient prior literal.

**Skip:** read-only views, third-party OAuth redirects. Navigation is covered inside journeys.

Produce one line per journey: user intent, natural entry point, click path, widest valid
starting-state constraints, state-dependent branches, and complete effects. Flag every proposed
exact string or number with why it is behaviorally significant. Confirm with the user before
implementing.

## Phase 4: Implement

Hand each confirmed journey to `/ripplo:create`. Before implementation, read the actual component
and mutation source for every field, validation rule, error/success/loading state, conditional
render, and cascade. End with the generality audit from `/ripplo:create`.
