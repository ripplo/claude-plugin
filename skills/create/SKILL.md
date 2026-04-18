---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

## Procedure

1. Read `packages/testing/README.md` for DSL reference and determinism rules.
2. **Stub first.** Add the test as `.notImplemented()` so it surfaces in `npx ripplo status` and the stub→implementation transition is trackable.
3. **Scope it.** `npx ripplo scope status` — if a free-text user item describes this flow, `npx ripplo scope link <scope-item-id> <test-id>`. Otherwise `npx ripplo scope add <test-id>`. See `/ripplo:scope`.
4. **Register the file.** `.ripplo/index.ts` imports every test/precondition file explicitly. Add `import "./tests/<id>.js";` after creating `.ripplo/tests/<id>.ts` — the CLI only sees what's imported.
5. Browse `.ripplo/preconditions/` for available preconditions. If none fits, add one (and import it from `.ripplo/index.ts`).
6. Read the relevant component/route source to find real ARIA roles, button text, form fields. **Never fabricate locators.** If the app lacks accessible names, **add them to the app first** rather than falling back to `testId()`.
7. Write the test in `.ripplo/tests/`. Id comes from `.test("<id>")`, not the filename.
8. `npx ripplo lint` — fix all errors.
9. `npx ripplo run <id>` — on failure, invoke `/ripplo:debug`.
10. **Stage `.ripplo/ripplo.lock`** alongside test changes (lint writes it; pre-commit blocks stale).

## What makes a good test

Don't just assert the URL changed or that the button you clicked is still visible. Assert:

- **New** elements that appear post-action (dialog opened, success message, page heading)
- Text content (`assert.text` / `assert.value` / `assert.url` / `assert.count` — not just `assert.visible`)
- The mutation result reflected in UI (new list item, counter delta, status change)
- Things that should be gone (`assert.not.visible` for closed dialogs, cleared spinners)

A test that clicks a button and asserts the same button still exists verifies nothing. The `tautological-post-click-assert` lint rule catches this — fix by asserting the actual effect, not by adding another `assert.visible` of the same element.

Re-read each test against its `expectedOutcome` before declaring done.

## Determinism (non-negotiable)

- `role()` locators only; `testId()` only when no ARIA role exists.
- Exact text matching — no `contains`, `startsWith`, regex.
- Destructure precondition data in `steps()` — never hardcode.
- Every step has `.as("description")`.

If a run fails, `/ripplo:debug`. Never weaken assertions to make a test pass — if it's an app bug, report with evidence.
