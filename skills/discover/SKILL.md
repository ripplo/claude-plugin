---
name: discover
description: "Guided codebase crawl to plan Ripplo workflows: map the app's surface, model its state as entities + givens, list the flows worth testing. Use when setting up Ripplo, adding workflows for new features, or planning coverage for recent changes."
---

# Ripplo Discover

Map the app's surface, model the state behind it, list flows worth verifying. Implementation is `/ripplo:create`.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`. Skim `.ripplo/{entities,workflows}/`, `.ripplo/givens.ts`, and feature `givens.ts` for patterns to reuse.

## Phase 1: Discover the surface

- **Routes:** guards, layouts, redirects, dynamic segments and the entities they reference.
- **Auth:** provider, session storage, role model, and the programmatic session-creation path (not UI login) — powers the `signIn` + `currentActor` impls on the `principal: true` entity.
- **Data model:** tables, relationships, what's required to reach what.
- **Every state-mutating interaction:** dialogs, forms (incl. filters/search), inline editing, action menus, mutating toggles, drag-and-drop, bulk actions, confirmations, wizards, tabbed panels with distinct data, upload/import/export, settings saves, toast actions, keyboard shortcuts.
- **Distinct render states per route:** empty, conditional (data/flag/plan), error, loading-gated, pagination boundaries, before/after submission. State-dependent outcomes in one flow become named `when` branches (compiler generates a test per branch); distinct flows are separate workflows.

## Phase 2: Model the state

Per flow:

- **Entities** — each record it seeds or asserts needs an `entity(...)` in `.ripplo/entities/` + a `seed`/`read` impl. List what exists, what you'll add.
- **Givens** — starting state (signed-in user, owned project, empty list). Cross-feature in `.ripplo/givens.ts`; feature givens colocate with workflows.
- **Assertion per flow** — the entity change that proves it (`Task.created`, `Member.deleted`). Can't name the record? Trace the mutation to its handler first.

Mechanics: `/ripplo:create` → "Adding an entity" / "Adding a given."

## Phase 3: Plan the journeys

One journey = one user intent, traced as the real click path from a natural entry point — usually several mutations. One journey = one workflow; later steps consume earlier state, so the given set stays minimal.

List the journeys first, then check coverage:

- **Every Phase-1 mutation appears in some journey.** Orphan mutation = missing journey, not a one-click workflow.
- **Every distinct render state appears** — as a `when` branch, or its own journey when the flow differs.

**Skip:** read-only views, third-party OAuth redirects. Navigation is covered inside journeys.

Produce one line per journey: entry point, click path, composed givens, entity assertions. Confirm with the user before implementing.

## Phase 4: Implement

Hand each confirmed flow to `/ripplo:create`. Pre-flight per flow: read the actual component source for every field, validation rule, error/success/loading state, mutation, conditional render, edge case.
