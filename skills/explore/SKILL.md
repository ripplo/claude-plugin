---
name: explore
description: "Guided codebase crawl to plan Ripplo tests: map the app's user-facing surface, model the state it touches as entities + worlds, and enumerate the flows worth testing. Use when setting up Ripplo for a new project, adding tests for new features, or planning tests for recent changes."
---

# Ripplo Explore

Map the app's user-facing surface area, model the state behind it, and produce a list of flows worth verifying. Implementation happens in `/ripplo:create`.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`.

## Setup

Skim `.ripplo/{entities,worlds,tests}/` for existing patterns to reuse. `/ripplo:create` carries the DSL reference (entities, worlds, tests, oracle) — load it when you start authoring.

## Phase 1: Discover the surface

**Map the app:**

- Routes, route guards, layouts, redirects, dynamic segments and the entities they reference.
- Auth: provider, session storage, role/permission model, and the **programmatic** session-creation path (not UI login) — the engine impl for the `user`/`session` entities will use it.
- Data model: the DB tables/entities, their relationships (foreign keys), and what's required to reach what.

**Inventory every state-mutating interaction.** Miss nothing — dialogs, forms (incl. filters/search), inline editing, action menus, mutating toggles, drag-and-drop, bulk actions, confirmations, wizards, tabbed panels with distinct data, file upload/import/export, settings saves, toast actions, keyboard shortcuts.

**Inventory distinct render states per route:** empty/first-time, conditional (data/feature-flag/plan), error, loading-gated, pagination boundaries, before/after submission. Each distinct branch is a candidate test with its own world.

## Phase 2: Model the state

For the flows you found, work out the **entities** and **worlds** they need — this is the modeling step that makes tests writable.

- **Entities** — for each DB row a flow seeds or asserts, there should be an `entity(...)` in `.ripplo/entities/` and a `seed`/`read` impl in the app's engine funnel. List the ones that already exist and the ones you'll add.
- **Worlds** — the starting states flows need (logged-in user, a project they own, an org with a member, an empty list). Identify reusable builders in `.ripplo/worlds/`; note new ones to add, composed from existing bases.
- **The assertion per flow** — for each mutation flow, name the entity change that proves it (`Task.created`, `Member.deleted`, `Organization.updated`). If you can't name the row that changes, trace the mutation to its resolver/handler first.

Entity + world mechanics live in `/ripplo:create` → "Adding an entity" / "Adding a world."

## Phase 3: Plan the flows

**Worth testing:** state mutations, multi-step UI flows, CRUD per entity, dialog flows, inline actions, bulk ops, import/export, role-specific behavior, distinct render states.

**Skip:** navigation-only clicks (tests the router), read-only views with no interaction, third-party OAuth redirects.

**Target:** CRUD per core entity; role-specific actions if multi-role; empty/conditional states represented.

Produce a concrete list — one line per flow, with the world it starts from and the entity assertion that proves it. Present the list to the user for confirmation before implementing.

## Phase 4: Implement

Hand each confirmed flow to `/ripplo:create`. Pre-flight per flow: read the actual component source for every form field, validation rule, error/success state, loading state, mutation, conditional render, and edge case (disabled states, character limits, duplicate detection).
