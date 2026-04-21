---
name: scope
description: "Manage Testing Scope — your working memory for what end-to-end flows this session is responsible for. Use when starting a task that could affect any flow the running app exercises, when the drift nudge fires, or when the user says 'in scope' / 'out of scope'."
---

# Testing Scope

## Your responsibility

Maintaining an accurate, sufficiently broad scope is **your** job — not the user's. The user describes what they're building; you translate that into the set of e2e flows that must pass to prove the feature actually works.

For any non-trivial change:

- Enumerate every user flow the change could affect — new flows AND existing flows whose behavior might shift.
- Scope them all: stub missing tests, `scope add` existing ones.
- Err on the side of breadth. A missed flow is a silent regression the Stop gate won't catch.

**Upper bound: ~50 tests in scope at once.** Below that, include as many as needed to cover the functionality — don't trim for convenience. If a change genuinely exceeds 30, split the work into phases with the user. Hitting the bound is a signal the change is too large for one session, not a reason to narrow coverage.

Under-scoping is the default failure mode. When in doubt, scope it in.

**Rule: any test you add, stub, or change must be in scope immediately.** Do not wait until the end of the session or batch a scope-add "later" — the instant you create or modify `.ripplo/tests/<id>.ts`, run `npx ripplo scope add <id>` (bulk: `scope add <id1> <id2>...`). Tests not in scope are invisible to the Stop gate, so an out-of-scope stub is the same as no stub at all.

## Related skills (load these too)

- `/ripplo:explore` — discover flows and stub tests
- `/ripplo:create` — per-test authoring workflow

## What scope is

Scope is your working memory for what end-to-end flows this session is responsible for — anything the running app exercises (frontend, backend, schema, infra, config, deps) that your changes could affect. It lives in the dev-session DB; the user sees it live in Developer Mode → Testing Scope. Scope dies with the PR; the durable artifacts are tests in `.ripplo/tests/`.

**"Done" for a scope item means two things together: the app code delivers the user-facing behavior, AND a passing test proves it.** Authoring a test against broken UI/API isn't done. Shipping the feature without a test isn't done either. Scope is the contract that keeps both halves honest.

## Commands

```sh
npx ripplo scope status                                # list current scope
npx ripplo scope add <test-id> [<test-id>...]          # bind one or more existing tests to scope (variadic)
npx ripplo scope link <scope-item-id> <test-id>        # link a user free-text item to a test you stubbed
npx ripplo scope remove <scope-item-id> [<id>...]      # remove one or more (variadic)
```

`add` and `remove` are bulk: pass space-separated ids in a single invocation rather than looping in shell.

## Rules

- **Scope additions only reference existing tests.** `scope add` requires a test id; the workflow (stub or implemented) must already exist in `.ripplo/tests/`. Free-text intents come from the user only — stub a matching test and `scope link` it.
- **Every stub must be scope-added the same turn you create it.** Stubs not in scope are invisible to the user and don't block Stop.
- **The Stop hook blocks on incomplete scope** (intent items with no test, stubs not yet implemented, or workflows whose tests fail). Pausing hooks from the dashboard is the only escape hatch.
- **`scope remove` is not a shortcut to clear the gate.** Only remove items that are genuinely out of scope or no longer needed. If implementing the remaining items feels too large, raise it with the user — don't quietly trim scope to make Stop pass.
- **Scope persists across CLI restarts** — quitting marks the session inactive; items return on next start.
- **Current scope auto-injects into every prompt** via `scope-reminder` — don't run `scope status` reflexively.

## When to add

- **Any task that could affect an end-to-end flow** (frontend, backend, schema, infra, config) → for each affected flow, either `scope add` an existing test (so Stop re-validates it) or stub a new `.notImplemented()` test and scope add that.
- **Mid-task discovery** — when a new flow surfaces, stub + scope add immediately.
- **Coverage-drift nudge** — add the missing item or revert the underlying change.
- **User-added free-text item** — stub the test and `scope link`.
