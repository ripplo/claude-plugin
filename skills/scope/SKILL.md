---
name: scope
description: "Manage Testing Scope — your working memory for which end-to-end flows this session is responsible for. Use when starting a task that could affect any flow the running app exercises, when a drift nudge fires (user-facing code edited without a matching test), or when the user says 'in scope' / 'out of scope'."
---

# Testing Scope

Scope is the contract that defines success criteria for this session: the set of e2e flows that must pass for the work to count as done. It lives in the dev-session DB (the user sees it in Developer Mode → Testing Scope), and dies with the PR; the durable artifacts are the tests in `.ripplo/tests/`.

**Scope is intent; a passing test is proof.** Scoping a flow says "this matters this session." Discharging it means a test in `.ripplo/tests/` exercises that flow and passes. Scope a flow → write its test (`/ripplo:create`) → run it green.

## Prerequisite

Scope lives in the dev-session DB — needs `npx ripplo daemon` + the app's dev server. Run `npx ripplo doctor`; if missing, `/ripplo:start`.

## Your responsibility

Maintaining accurate, sufficiently broad scope is **your** job — not the user's. They describe what they're building; you translate to the e2e flows that must pass.

For any non-trivial change:

- Enumerate every flow the change could affect (new flows AND existing flows whose behavior might shift).
- Scope them all: write missing tests, `scope add` existing ones.
- Err on the side of breadth. Under-scoping is the default failure mode — when in doubt, scope it in.

**Upper bound: ~50 tests in scope.** Below that, include as many as needed. Hitting the bound means split the work into phases with the user, not narrow coverage.

## Commands

```sh
npx ripplo scope status                              # list current scope
npx ripplo scope add "<intent>" ["<intent>"...]      # bind existing tests (variadic — one call, no shell loops)
npx ripplo scope link <scope-item-id> "<intent>"     # link a user free-text item to a test you wrote
npx ripplo scope remove <scope-item-id> [<id>...]    # remove (variadic)
```

**Scope drives `ripplo run`.** Bare `npx ripplo run` (no args) auto-adds dirty `.ripplo/tests/*.ts` to scope and then runs every runnable scope item — that's the default verify loop.

## Rules

- **Edited tests auto-scope once lint-clean.** A lint-clean edit to `.ripplo/tests/<file>.ts` scopes itself. Don't run `scope add` for tests you're actively editing — only for previously-existing tests you didn't touch, or to reverse a `scope remove`.
- **Scope additions reference existing tests only.** `scope add "<intent>"` requires a test in `.ripplo/tests/`. Free-text intents come from the user — write a matching test and `scope link` it.
- **`scope remove` is not a shortcut to clear the gate.** Valid removal: wrong flow scoped, duplicate of another test, user explicitly said "not this session," underlying feature was cut. Size, effort, and session length are never valid reasons.
- **If the flow list feels too large, parallelize — don't trim.** See `/ripplo:create` → "Parallelizing multi-test sessions."
- **Scope persists across CLI restarts** — quitting marks the session inactive; items return on next start.
- **Current scope auto-injects into every prompt** — don't run `scope status` reflexively.

## When to add

- **Any task that could affect an e2e flow** (frontend, backend, schema, infra, config) → for each affected flow, `scope add` an existing test or write a new one (auto-scoped once lint-clean).
- **Mid-task discovery** — a new flow surfaces, write its test.
- **Drift nudge** — user-facing code changed without a matching test; add the missing flow or revert the change.
- **User-added free-text item** — write the test and `scope link` it.
