---
name: explore
description: "Guided codebase crawl to plan and stub Ripplo tests. Use when setting up Ripplo for a new project, adding coverage for new features, or scoping tests to recent code changes."
---

# Ripplo Explore

Map the app's user-facing surface area; stub a `.notImplemented()` test for every flow that should ship with verification. Implementation happens in `/ripplo:create`.

## Setup

1. Read `packages/testing/README.md` (DSL, preconditions, determinism rules).
2. Verify project state: `.ripplo/index.ts` and `.ripplo/project.json` exist; run `npx ripplo doctor`.

## Phase 1: Discover

Use sub-agents for deep file reads — keep raw contents out of main context.

**Map the app:**

- Routes, route guards, layouts, redirects, dynamic segments and the entities they reference.
- Auth: provider, session storage, role/permission model, programmatic session creation paths (not UI login).
- Data model: entities, relationships, what's required to reach what, factory/seed utilities.

**Inventory every state-mutating interaction.** Miss nothing — dialogs, forms (incl. filters/search), inline editing, action menus, mutating toggles, drag-and-drop, bulk actions, confirmations, wizards, tab panels with distinct data, file upload/import/export, settings saves, toast actions, keyboard shortcuts, real-time-driven UI changes.

**Start from `.ripplo/coverage.d.ts`** — generated, enumerates every AST-visible interaction as typed branch IDs. `npx ripplo cover` prints the unacknowledged set. Augment manually for things the AST can't see (keyboard shortcuts in effects, canvas, imperative dialog triggers).

**Inventory distinct render states per route:** empty/first-time, conditional (data/feature-flag/plan), error, loading-gated, pagination boundaries, before/after submission.

## Phase 2: Filter to real flows

**Worth testing:** state mutations, multi-step UI flows, CRUD per entity, dialog flows, inline actions, bulk ops, import/export.

**Skip:** navigation-only clicks (tests the router), read-only views with no interaction, third-party OAuth redirects.

**Coverage target:** CRUD per core entity; role-specific actions if multi-role; empty/conditional states represented. `npx ripplo cover` is ground truth.

**Name the observer for each mutation flow before stubbing** (`workflowNameIs`, `subscriptionCanceled` — even if the handle doesn't exist yet). If you can't name the backend effect, trace the mutation in the component source first. Observer mechanics: `/ripplo:create`.

## Phase 3: Stub

For each flow, create a `.notImplemented()` stub in `.ripplo/tests/<id>.ts` and add it to the `tests` array in `.ripplo/tests/index.ts` (the CLI only sees what's in that registry).

```ts
// .ripplo/tests/my-flow.ts
import { test } from "@ripplo/testing";
import { dataProject } from "../preconditions/index.js";

export const myFlow = test("my-flow")
  .name("My user flow")
  .requires({ project: dataProject })
  // TODO(observer): name the backend effect to verify (e.g. workflowNameIs).
  .expectedOutcome("Description of expected result")
  .notImplemented();
```

```ts
// .ripplo/tests/index.ts
import { myFlow } from "./my-flow.js";
export const tests = [myFlow] as const;
```

Stubs auto-scope on save (post-edit hook, **after lint passes** — fix lint errors first). For tests not edited this session, bulk: `npx ripplo scope add <id1> <id2> <id3>` (variadic — one call, never a shell loop).

**Plan-mode requirement:** before `ExitPlanMode`, every flow the plan touches must have a stub, and the plan file must include a "Tests to implement" section with the stub ids — the gate hook blocks otherwise.

Present the stub list to the user for confirmation before implementing.

## Phase 4: Implement

Hand off each confirmed flow to `/ripplo:create`. Pre-flight: read the actual component source for every form field, validation rule, error/success state, loading state, mutation, conditional render, edge case (disabled states, character limits, duplicate detection).
