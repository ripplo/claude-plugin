---
name: explore
description: "Guided codebase crawl to plan and stub Ripplo tests. Use when setting up Ripplo for a new project, adding coverage for new features, or scoping tests to recent code changes."
---

# Ripplo Explore

Map the app's user-facing surface area and define the success criteria (tests) that prove each interaction works end-to-end. Coverage is not a metric for its own sake — it's the contract that every flow the app exposes has a test backing it, closing the loop between what the app claims to do and what's actually verified.

## Setup

1. Read `packages/testing/README.md` for the DSL, precondition system, determinism rules.
2. Check `.ripplo/ripplo.ts` for project config. Run `npx ripplo doctor`.

## Phase 1: Discover

Inventory every testable surface. Use sub-agents for deep file reads — keep raw contents out of main context.

**Map the app**:

- Routes, route guards, layouts, redirects, dynamic segments and the entities they reference.
- Auth: provider, session storage, role/permission model, programmatic session creation paths (not UI login).
- Data model: entities, relationships, what's required to reach what, factory/seed utilities.

**Inventory every interaction that mutates state.** Miss nothing — dialogs/modals/sheets, forms (including filters and search), inline editing, action menus, toggles that mutate, drag-and-drop, bulk actions, confirmations, wizards, tab panels with distinct data, file upload/import/export, settings saves, toast actions, keyboard shortcuts, real-time-driven UI changes.

**Start from `.ripplo/coverage.d.ts`.** This generated file enumerates every AST-visible user-facing interaction as typed branch IDs. Every ID not referenced by some test's `.coverage(...)` is uncovered. `npx ripplo cover` prints the current unacknowledged set. Augment with manual inspection for things AST can't see (keyboard shortcuts in effects, canvas interactions, imperative dialog triggers).

**Inventory distinct render states per route**: empty/first-time, conditional (data/feature-flag/plan), error, loading-gated, pagination boundaries, before/after submission.

## Phase 2: Filter to real flows

Worth a test (state mutation or multi-step UI): CRUD per entity, form submissions, dialog flows, multi-step flows, state changes, inline actions, bulk ops, import/export.

Skip: navigation-only clicks (tests the router), read-only page views with no interaction, third-party OAuth redirects.

Coverage target: CRUD per core entity; role-specific actions if multi-role; empty/conditional states represented. `npx ripplo cover` is ground truth.

**For each mutation flow, name the observer before stubbing** — even if the handle doesn't exist yet (`workflowNameIs`, `subscriptionCanceled`). If you can't name the backend effect the test should verify, go back to the component source and trace the mutation. Observer mechanics and the `uiOnly` rules live in `/ripplo:create`.

## Phase 3: Stub

For each flow, create a `.notImplemented()` stub in `.ripplo/tests/<id>.ts` and add the exported value to the `tests` array in `.ripplo/tests/index.ts`. The CLI only sees what that registry contains.

```typescript
// .ripplo/tests/my-flow.ts
import { test } from "@ripplo/testing";
import { dataProject } from "../preconditions/index.js";

export const myFlow = test("my-flow")
  .name("My user flow")
  .requires({ project: dataProject })
  // TODO(observer): name the backend effect to verify (e.g. workflowNameIs, runStatusIs).
  .expectedOutcome("Description of expected result")
  .notImplemented();
```

```typescript
// .ripplo/tests/index.ts
import { myFlow } from "./my-flow.js";
export const tests = [myFlow /* , ... */] as const;
```

After stubbing, bulk scope-add: `npx ripplo scope add <id1> <id2> <id3>` (variadic — one call, not a shell loop). See `/ripplo:scope`.

Each scope item is a commitment that the app delivers the behavior AND a passing test proves it. Don't scope flows you aren't going to make work end-to-end this session.

**Plan-mode requirement**: before `ExitPlanMode`, every flow the plan touches must have a stub, and the plan file must include a "Tests to implement" section listing the stub ids — the gate hook blocks otherwise.

Present the stub list to the user for confirmation before implementing.

## Phase 4: Implement

For each confirmed flow, invoke `/ripplo:create` — it owns the per-test workflow and the multi-stub parallelization pattern. Pre-flight before handing off: read the actual component source, find every form field, validation rule, error/success state, loading state, mutation/API call, conditional render, and edge case (disabled states, character limits, duplicate detection).

## Parallel safety for preconditions

Tests run in parallel. Every `setup()` must produce isolated, non-conflicting data:

- **Unique identifiers** via setup `ctx`: `ctx.uniqueId(prefix)`, `ctx.uniqueEmail()`, `ctx.runId`. `ctx.fixed(value)` is only for genuinely shared constants (e.g. test password) — never for names/emails/ids.
- **Return dynamic IDs.** `setup()` return flows into `requires()` destructuring — return created entity IDs so tests reference them by id, not hardcoded slug.
- **Scoped teardown.** Delete only entities created by _this_ setup invocation, by id. Never `deleteMany` by prefix or `TRUNCATE`.
- **Independent sessions.** Each setup creates its own auth session. No singleton test user.

Symptoms of leakage: unique-constraint errors, 401/403 mid-test, vanishing session cookies. Fix the precondition, not the test.
