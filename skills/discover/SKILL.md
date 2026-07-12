---
name: discover
description: "Guided codebase crawl to plan Ripplo workflows: map the app's user-facing surface, model the state it touches as entities + givens, and enumerate the flows worth testing. Use when setting up Ripplo for a new project, adding workflows for new features, or planning coverage for recent changes."
---

# Ripplo Discover

Map the app's user-facing surface, model the state behind it, and produce a list of flows worth verifying. Implementation happens in `/ripplo:create`.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`. Skim `.ripplo/{entities,workflows}/ plus `.ripplo/givens.ts`and feature`givens.ts`` for existing patterns to reuse.

## Phase 1: Discover the surface

**Map the app:**

- Routes, guards, layouts, redirects, dynamic segments and the entities they reference.
- Auth: provider, session storage, role model, and the **programmatic** session-creation path (not UI login) — the `signIn` + `currentActor` engine impls (on the `principal: true` entity) will use it.
- Data model: tables/entities, relationships, what's required to reach what.

**Inventory every state-mutating interaction** — miss nothing: dialogs, forms (incl. filters/search), inline editing, action menus, mutating toggles, drag-and-drop, bulk actions, confirmations, wizards, tabbed panels with distinct data, upload/import/export, settings saves, toast actions, keyboard shortcuts.

**Inventory distinct render states per route:** empty/first-time, conditional (data/feature-flag/plan), error, loading-gated, pagination boundaries, before/after submission. State-dependent outcomes within one flow become named `when` branches of a workflow — the compiler enumerates a test per branch. Distinct flows are separate workflows composing their own givens.

## Phase 2: Model the state

For each flow, work out the entities and givens it needs:

- **Entities** — each record of state a flow seeds or asserts needs an `entity(...)` in `.ripplo/entities/` and a `seed`/`read` impl in the engine funnel. List what exists and what you'll add.
- **Givens** — the starting state each flow composes (signed-in user, owned project, empty list). Cross-feature givens live in `.ripplo/givens.ts`; feature givens colocate with their workflows.
- **The assertion per flow** — the entity change that proves it (`Task.created`, `Member.deleted`). Can't name the record that changes? Trace the mutation to its handler first.

Mechanics live in `/ripplo:create` → "Adding an entity" / "Adding a given."

## Phase 3: Plan the journeys

Plan **user journeys**, not per-mutation snippets. A journey is one thing a user sets out to accomplish, traced as the real click path from a natural entry point — usually several mutations ("sign up → create a project → invite a teammate", "find an overdue invoice → edit it → send the reminder"). One journey = one workflow. Later steps consume state earlier steps created, so the starting given set stays minimal.

Enumerate the journeys first: for each core thing a user comes to the app to do, write the path they'd actually click. Then check coverage against the inventories as a completeness net:

- **Every mutation from Phase 1 appears in some journey** — CRUD per core entity, dialog flows, inline actions, bulk ops, import/export, role-specific behavior. An orphan mutation means a missing journey, not a one-click workflow.
- **Every distinct render state appears** — as a `when` branch where seeded state changes an outcome along a journey's path, or as its own journey when the flow itself differs.

**Skip:** read-only views with no interaction, third-party OAuth redirects. Navigation is covered inside journeys, not as standalone workflows.

Produce a concrete list — one line per journey, with its entry point, click path, composed givens, and the entity assertions that prove it. Confirm with the user before implementing.

## Phase 4: Implement

Hand each confirmed flow to `/ripplo:create`. Pre-flight per flow: read the actual component source for every form field, validation rule, error/success/loading state, mutation, conditional render, and edge case.
