---
name: explore
description: "Guided codebase crawl to plan and stub Ripplo tests. Use when setting up Ripplo for a new project, adding coverage for new features, or scoping tests to recent code changes."
---

# Ripplo Explore

Build comprehensive e2e test coverage for this app.

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

**Inventory distinct render states for each route**: empty/first-time, conditional based on data or feature flags or plans, error states, loading-gated interactions, pagination boundaries, before/after submission.

## Phase 2: Filter to real flows

Worth a test (state mutation or multi-step UI):

- CRUD per entity, form submissions, dialog flows, multi-step flows, state changes, inline actions, bulk ops, import/export.

Skip:

- Navigation-only clicks (tests the router, not the app).
- Read-only page views with no interaction.
- Third-party OAuth redirects (can't automate).

Coverage check: every interactive component covered or explicitly excluded; CRUD per core entity; role-specific actions if multi-role; empty/conditional states represented.

## Phase 3: Stub

For each flow, create a `.notImplemented()` stub in `.ripplo/tests/` and add `import "./tests/<id>.js";` to `.ripplo/index.ts`. The CLI only sees what's imported there.

```typescript
ripplo
  .test("my-flow")
  .name("My user flow")
  .requires({ project: dataProject })
  .expectedOutcome("Description of expected result")
  .notImplemented();
```

After each stub, `npx ripplo scope add <test-id>` so it's visible to the user. See `/ripplo:scope`.

**Plan-mode requirement**: before `ExitPlanMode`, every flow this plan touches must have a stub, and the plan file must include a "Tests to implement" section listing the stub ids — the gate hook blocks otherwise.

Present the stub list to the user for confirmation before implementing.

## Phase 4: Implement

For each confirmed flow, invoke `/ripplo:create` — it owns the per-test workflow (read source → write steps → lint → run).

**Pre-flight before handing off**: read the actual component source. Find every form field, validation rule, error/success state, loading state. Trace the component tree. Find the mutation/API call and its responses. Find conditional renders. Find edge cases (disabled states, character limits, duplicate detection).

## Parallel safety for preconditions

Tests run in parallel. Every `setup()` must produce isolated, non-conflicting data:

- **Unique identifiers** via setup `ctx`:
  - `ctx.uniqueId(prefix)` — per-run unique string for names, slugs, IDs.
  - `ctx.uniqueEmail()` — per-run email for test users.
  - `ctx.runId` — raw run id.
  - `ctx.fixed(value)` — only for genuinely shared constants (e.g. test password). Never for names/emails/ids.
- **Return dynamic IDs.** `setup()` return value flows into `requires()` destructuring — return created entity IDs so tests reference them by id, not hardcoded slug.
- **Scoped teardown.** Delete only entities created by _this_ setup invocation, by id. Never `deleteMany` by prefix or `TRUNCATE` — that wipes parallel runs' data.
- **Independent sessions.** Each setup creates its own auth session. No singleton test user.

Symptoms when flake surfaces: unique-constraint errors, 401/403 mid-test, vanishing session cookies. Fix the precondition, not the test.

## Determinism (non-negotiable)

- `role()` only; `testId()` only when no ARIA role exists.
- Exact text matching — no `contains`, `startsWith`, regex.
- Destructure precondition data in `steps()` — never hardcode.
- Every step has `.as("description")`.
