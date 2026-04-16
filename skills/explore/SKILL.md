---
name: explore
description: "Guided codebase crawl to build test specs and state graph. Use when setting up Ripplo for a new project, adding coverage for new features, or scoping tests to recent code changes."
user-invokable: true
---

# Ripplo Explore

Build comprehensive e2e test coverage for this application.

## Setup

1. Read `packages/testing/README.md` for the full DSL reference, precondition system, and determinism rules.
2. Check `.ripplo/ripplo.ts` for project config (`createRipplo({ appUrl, preconditionsUrl, projectId })`). Run `npx ripplo doctor` to verify setup.

## Phased approach

### Phase 1: Discover

Explore the codebase to find every testable surface:

- Routes, auth system, data model, interactive components
- Use sub-agents for deep exploration — the main context should orchestrate, not hold raw file contents

### Phase 2: Plan tests

For each discovered user flow, create a `.notImplemented()` test stub in `.ripplo/tests/`:

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

For each confirmed flow, implement the test:

1. Read relevant source files to find real ARIA roles, button text, form fields
2. Write the test steps using the DSL
3. Run `npx ripplo lint` — fix all errors
4. Run `npx ripplo run <slug>` — iterate on failures using `.ripplo/debug/` artifacts
5. Run `npx ripplo flake-detect <slug>` — verify determinism with 10 parallel runs

## Determinism Rules (non-negotiable)

- Use `role()` locators exclusively. Only use `testId()` when no ARIA role exists.
- All text assertions use exact matching. No `contains`, `startsWith`, or regex.
- Destructure precondition data in `steps()` — never hardcode values from preconditions.
- Every step must have `.as("description")`.
- After a test passes, run `npx ripplo flake-detect <slug>` to verify determinism.
