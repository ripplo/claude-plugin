---
name: explore
description: "Guided codebase crawl to plan and stub Ripplo tests. Use when setting up Ripplo for a new project, adding coverage for new features, or scoping tests to recent code changes."
---

# Ripplo Explore

Build comprehensive e2e test coverage for this application.

## Setup

1. Read `packages/testing/README.md` for the full DSL reference, precondition system, and determinism rules.
2. Check `.ripplo/ripplo.ts` for project config (`createRipplo({ appUrl, preconditionsUrl, projectId })`). Run `npx ripplo doctor` to verify setup.

## Phased approach

### Phase 1: Discover

Explore the codebase to find every testable surface. Use sub-agents for deep exploration — the main context should orchestrate, not hold raw file contents.

**Routes & navigation**: every route, route guards/auth middleware, layout wrappers, redirects, nested hierarchies, dynamic segments and what entities they reference.

**Auth & sessions**: provider type, session storage, role/permission model, how roles gate UI, programmatic session creation paths (not UI login).

**Data model & entities**: every entity, relationships, which entities are required to reach which pages, cascade behavior, factory/seed utilities.

**Interactive components — exhaustive inventory.** Find every UI element that triggers state changes. Miss nothing:

- Dialogs, modals, drawers, sheets, popovers with forms or actions
- Forms (create, edit, filter, search) — note every field, validation, and submit mechanism
- Inline editing (click-to-edit, editable cells, contentEditable)
- Action menus, context menus, dropdown actions (delete, duplicate, archive, rename)
- Toggle switches and checkboxes that trigger mutations (not just local state)
- Drag-and-drop interactions
- Bulk selection + bulk action patterns
- Confirmation dialogs (delete confirmations, unsaved-changes warnings)
- Wizards, multi-step flows, onboarding sequences
- Tab panels where switching tabs loads different data or shows different actions
- File upload/import/export flows
- Settings pages with save/update actions
- Notification/toast actions (undo, dismiss, retry)
- Keyboard shortcuts that trigger actions
- Real-time/WebSocket-driven UI updates that change available actions

**Conditional UI & distinct states**. Same route can render fundamentally different UI:

- Empty states (zero items, first-time user, no search results)
- Conditional renders based on data (list vs empty, enabled vs disabled features)
- Error states (failed loads, permission denied, not found, rate limited)
- Loading states that gate interactions
- Feature flags or plan-based gating
- Pagination boundaries (first vs last page behavior)
- Before/after states (pre-submission vs post-submission, draft vs published)

### Phase 1.5: Filter to real user flows

Not every interaction is worth a test. Apply this filter before stubbing:

**Worth a test** (user flow that mutates state or traverses a multi-step UI):

- CRUD operations: create, update, delete for every entity
- Form submissions: any form with a submit button
- Dialog flows: open → fill → submit → assert result
- Multi-step flows: wizards, onboarding, checkout
- State changes: draft → published, pending → approved, enable → disable
- Inline actions: role changes via dropdown, toggle switches, inline edits
- Bulk operations
- Import/export flows

**Not worth a test** (skip):

- **Navigation-only clicks** — clicking a sidebar link and asserting URL changed tests the router, not the app. Don't write these.
- **Read-only page views** — landing on a page and asserting content is visible with no interaction. The lint rules will let these through, but they have no test value.
- **Third-party OAuth redirects** — cannot be automated without the provider.

### Phase 1.6: Coverage verification

Before stubbing, verify completeness:

- **Component coverage**: is every interactive component from the inventory covered by at least one test? If not, add one or note explicitly why excluded.
- **Entity coverage**: for every core entity, is there a create, update, and delete test? Missing CRUD = coverage gap.
- **Role coverage**: if the app has multiple roles, are role-specific actions covered? (e.g., "admin can invite members" vs "member cannot")
- **Empty/conditional state coverage**: are empty states and conditional branches covered? (e.g., "first project from empty state" vs "additional project from populated list")

### Phase 2: Stub the coverage

**Required** when running under the Ripplo plugin: before exiting plan mode, commit a `.notImplemented()` stub for every user flow this plan touches, plus any new precondition chain also marked `.notImplemented()`. The plan file must include a **"Tests to implement"** section listing the stub ids — the `ExitPlanMode` hook blocks exit otherwise.

For each discovered user flow, create a `.notImplemented()` test stub in `.ripplo/tests/` **and add `import "./tests/<id>.js";` to `.ripplo/index.ts`** (the CLI only sees what that file imports):

```typescript
ripplo
  .test("my-flow")
  .name("My user flow")
  .requires({ project: dataProject })
  .expectedOutcome("Description of expected result")
  .notImplemented();
```

Present the list to the user for confirmation before implementing.

### Phase 3: Implement

For each confirmed flow, invoke `/ripplo:create` to implement it — that skill owns the per-test workflow (stub → source read → write steps → lint → run → flake-detect). The guidance below is the pre-flight for `/ripplo:create`: understand the component before you hand off.

**Before writing steps, deeply understand the component you're testing:**

- Read the actual component source code — find every form field, validation rule, error message, success state, loading state.
- Trace through the component tree — if a dialog renders a form which renders fields, read all of them.
- Find the mutation/API call — what does submit actually do? What are the success/error responses?
- Find conditional renders — validation failure, success state, toasts, redirects, inline messages.
- Find edge cases in the code — disabled states, character limits, duplicate detection.

Then:

1. Read relevant source files to find real ARIA roles, button text, form fields
2. Write the test steps using the DSL
3. Run `npx ripplo lint` — fix all errors (this also regenerates `.ripplo/ripplo.lock`; you can also run `npx ripplo compile` explicitly)
4. Run `npx ripplo run <id>` — if it fails, invoke `/ripplo:debug` for the full diagnosis checklist
5. Commit the updated `.ripplo/ripplo.lock` alongside your test changes — the server reads the lockfile on push to sync workflows, and the pre-commit hook will block commits that skip the regeneration
6. Invoke `/ripplo:flake-detect` — verify determinism with parallel runs

## Parallel safety for preconditions

Tests run in parallel. Every precondition `setup()` must produce isolated, non-conflicting data:

- **Unique identifiers per run.** Use the built-in helpers on the setup `ctx`:
  - `ctx.uniqueId(prefix)` — unique string keyed to the current `runId` (e.g., `ctx.uniqueId("project")` → `"project-<runId>"`). Use for names, slugs, and IDs the app accepts.
  - `ctx.uniqueEmail()` — unique email address for the current run. Use for test user accounts.
  - `ctx.runId` — the raw run id if you need to embed it somewhere custom.
  - `ctx.fixed(value)` — only for genuinely shared/constant values (e.g., a test password). Do **not** use `ctx.fixed()` for names, emails, or entity ids — two parallel runs will collide on unique constraints.
- **Return dynamic IDs.** The setup return value flows into `requires()` destructuring. Return created entity IDs so tests reference them dynamically (`{ projectId: created.id }`), not by hardcoded slug.
- **Scoped teardown.** `teardown()` must only delete entities created by _this_ setup invocation — typically by capturing IDs in setup and deleting them by ID. Never `deleteMany` by prefix or `TRUNCATE` — that destroys other parallel runs' data.
- **Independent sessions.** Each setup creates its own auth session. Never assume a singleton test user exists.

Symptoms of parallel-safety violations show up in `npx ripplo flake-detect`: unique constraint errors, 401/403 mid-test, session cookies disappearing. Fix the precondition, not the test.

## Determinism Rules (non-negotiable)

- Use `role()` locators exclusively. Only use `testId()` when no ARIA role exists.
- All text assertions use exact matching. No `contains`, `startsWith`, or regex.
- Destructure precondition data in `steps()` — never hardcode values from preconditions.
- Every step must have `.as("description")`.
- After a test passes, run `npx ripplo flake-detect <id>` to verify determinism.
