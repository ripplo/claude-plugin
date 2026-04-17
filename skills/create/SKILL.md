---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

## Steps

1. Read `packages/testing/README.md` for the DSL reference and determinism rules.
2. **Stub first.** Add the test as `.notImplemented()` so it shows up in `npx ripplo status --format summary` and the plugin can track the stub → implementation transition. Fill in steps in a follow-up edit that removes `.notImplemented()`.
3. **Register the file.** `.ripplo/index.ts` imports every test and precondition file explicitly — after creating a new test at `.ripplo/tests/<id>.ts`, add `import "./tests/<id>.js";` to `.ripplo/index.ts`. The CLI only sees what's imported from there.
4. Browse `.ripplo/preconditions/` (including subfolders) to understand available preconditions and their data contracts. If the folder is empty or a required precondition doesn't exist, add one — add a matching `import "./preconditions/<file>.js";` to `.ripplo/index.ts`.
5. Read the relevant source files (routes, components, forms) to find real ARIA roles, button text, and form fields. **Never fabricate locators** — trace them to source code. If the app lacks sufficient ARIA roles or accessible names to target elements reliably, **add them to the app first** (semantic HTML, `role=`, labeled form fields) rather than falling back to `testId()`. Good accessibility is a prerequisite for deterministic tests.
6. Write the test under `.ripplo/tests/` using the DSL. Organize however makes sense — one test per file, multiple tests per file, or nested subfolders by feature are all fine. The id comes from `.test("<id>")`, not the filename.
   - Use `role()` locators exclusively (testId only when no ARIA role exists)
   - Destructure precondition data and use it for dynamic values
   - Every step gets `.as("description")`
   - End with assertions that verify the `expectedOutcome`
7. Run `npx ripplo lint` — fix all errors before proceeding.
8. Run `npx ripplo run <id>` — if it fails, read `.ripplo/debug/<runId>/` artifacts and iterate.
9. Once passing, run `npx ripplo flake-detect <id>` to verify determinism (10 parallel runs).

## What makes a good test

Don't just assert the URL changed or that the button you clicked is still visible. Assert:

- Correct **new** elements appear after each action (dialog opened, form rendered, success message shown, page heading changed)
- Text content matches expectations (headings, labels, feedback messages, error messages) — use `assert.text` / `assert.value` / `assert.url` / `assert.count`, not just `assert.visible`
- The UI reflects the mutation result (new item appears in list, counter updates, status changes)
- Elements that should NOT be visible are gone (`assert.not.visible` for closed dialogs, cleared spinners, dismissed errors)

A test that clicks a button and then asserts the same button is still visible is not a test — it verifies nothing about what the click _did_. The `tautological-post-click-assert` lint rule catches this; don't try to satisfy it by adding another `assert.visible` of the same element — verify the actual effect.

When the run passes, re-read the test against its `expectedOutcome`. A test that passes but doesn't assert the outcome is not done. Run `npx ripplo lint` and fix every diagnostic before declaring done.

## Determinism Rules (non-negotiable)

- Use `role()` locators exclusively. Only use `testId()` when no ARIA role exists.
- All text assertions use exact matching. No `contains`, `startsWith`, or regex.
- Destructure precondition data in `steps()` — never hardcode values from preconditions.
- Every step must have `.as("description")`.

## Iteration

If a run fails, invoke `/ripplo:debug` — it has the full diagnosis checklist, artifact order, and evidence discipline. Do not weaken assertions to make a test pass; if it's an app bug, report with evidence.
