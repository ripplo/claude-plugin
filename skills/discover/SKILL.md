---
name: discover
description: "Guided codebase crawl to plan Ripplo workflows: map the app's user-facing surface, model the state it touches as entities + worlds, and enumerate the flows worth testing. Use when setting up Ripplo for a new project, adding workflows for new features, or planning coverage for recent changes."
---

# Ripplo Discover

Read `../MODEL.md` (relative to this skill's base directory) first if you haven't this session — the one-page mental model this skill assumes: workflows declare state, facts carry across workflows, and lint/run/explorer each enforce a layer of it.

Map the app's user-facing surface, model the state behind it, and produce a list of flows worth verifying. Implementation happens in `/ripplo:create`.

## Prerequisite

Needs the app dev server + `npx ripplo daemon`. Run `npx ripplo doctor`; if missing, `/ripplo:start`. Skim `.ripplo/{entities,worlds,workflows}/` for existing patterns to reuse.

## Phase 1: Discover the surface

**Map the app:**

- Routes, guards, layouts, redirects, dynamic segments and the entities they reference.
- Auth: provider, session storage, role model, and the **programmatic** session-creation path (not UI login) — the `user`/`session` engine impls will use it.
- Data model: tables/entities, relationships, what's required to reach what.

**Inventory every state-mutating interaction** — miss nothing: dialogs, forms (incl. filters/search), inline editing, action menus, mutating toggles, drag-and-drop, bulk actions, confirmations, wizards, tabbed panels with distinct data, upload/import/export, settings saves, toast actions, keyboard shortcuts.

**Inventory distinct render states per route:** empty/first-time, conditional (data/feature-flag/plan), error, loading-gated, pagination boundaries, before/after submission. State-dependent outcomes within one flow become named `when` branches of a workflow — the compiler enumerates a test per branch. Distinct flows are separate workflows with their own worlds.

## Phase 2: Model the state

For each flow, work out the entities and worlds it needs:

- **Entities** — each record of state a flow seeds or asserts needs an `entity(...)` in `.ripplo/entities/` and a `seed`/`read` impl in the engine funnel. List what exists and what you'll add.
- **Worlds** — the starting states flows need (logged-in user, owned project, empty list). Identify reusable builders in `.ripplo/worlds/`; note new ones, composed from existing bases.
- **The assertion per flow** — the entity change that proves it (`Task.created`, `Member.deleted`). Can't name the record that changes? Trace the mutation to its handler first.

Mechanics live in `/ripplo:create` → "Adding an entity" / "Adding a world."

## Phase 3: Plan the flows

**Worth testing:** state mutations, multi-step flows, CRUD per entity, dialog flows, inline actions, bulk ops, import/export, role-specific behavior, distinct render states.

**Skip:** navigation-only clicks, read-only views with no interaction, third-party OAuth redirects.

**Target:** CRUD per core entity; role-specific actions if multi-role; empty/conditional states represented.

Produce a concrete list — one line per flow, with its starting world and the entity assertion that proves it. Confirm with the user before implementing.

## Phase 4: Implement

Hand each confirmed flow to `/ripplo:create`. Pre-flight per flow: read the actual component source for every form field, validation rule, error/success/loading state, mutation, conditional render, and edge case.
