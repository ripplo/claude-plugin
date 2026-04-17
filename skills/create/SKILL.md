---
name: create
description: "Create a new Ripplo test spec. Use when adding a new e2e test for a user flow."
---

# Create Ripplo Test

## Steps

1. Read `packages/testing/README.md` for the DSL reference and determinism rules.
2. Read `.ripplo/preconditions.ts` to understand available preconditions and their data contracts.
3. Read the relevant source files (routes, components, forms) to find real ARIA roles, button text, and form fields. **Never fabricate locators** — trace them to source code. If the app lacks sufficient ARIA roles or accessible names to target elements reliably, **add them to the app first** (semantic HTML, `role=`, labeled form fields) rather than falling back to `testId()`. Good accessibility is a prerequisite for deterministic tests.
4. Write the test to `.ripplo/tests/<slug>.ts` using the DSL:
   - Use `role()` locators exclusively (testId only when no ARIA role exists)
   - Destructure precondition data and use it for dynamic values
   - Every step gets `.as("description")`
   - End with assertions that verify the `expectedOutcome`
5. Run `npx ripplo lint` — fix all errors before proceeding.
6. Run `npx ripplo run <slug>` — if it fails, read `.ripplo/debug/<runId>/` artifacts and iterate.
7. Once passing, run `npx ripplo flake-detect <slug>` to verify determinism (10 parallel runs).

## Determinism Rules (non-negotiable)

- Use `role()` locators exclusively. Only use `testId()` when no ARIA role exists.
- All text assertions use exact matching. No `contains`, `startsWith`, or regex.
- Destructure precondition data in `steps()` — never hardcode values from preconditions.
- Every step must have `.as("description")`.

## Iteration

If a run fails:

- Read `.ripplo/debug/<runId>/steps/<failedIndex>/dom.html` and `accessibility-tree.txt` for correct locators
- Check `console.log` and `network.jsonl` for errors
- Fix the root cause, not the symptom — don't weaken assertions
- If the failure is an app bug (not the test), report it to the user
