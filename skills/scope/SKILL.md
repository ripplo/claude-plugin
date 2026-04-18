---
name: scope
description: "Manage Testing Scope — your working memory for what end-to-end flows this session is responsible for. Use when starting a task that could affect any flow the running app exercises, when the drift nudge fires, or when the user says 'in scope' / 'out of scope'."
---

# Testing Scope

Scope is your working memory for what end-to-end flows this session is responsible for — anything the running app exercises (frontend, backend, schema, infra, config, deps) that your changes could affect. It lives in the dev-session DB; the user sees it live in Developer Mode → Testing Scope. Scope dies with the PR; the durable artifacts are tests in `.ripplo/tests/`.

## Commands

```sh
npx ripplo scope status                          # list current scope
npx ripplo scope add <test-id>                   # bind an existing test to scope
npx ripplo scope link <scope-item-id> <test-id>  # link a user free-text item to a test you stubbed
npx ripplo scope remove <scope-item-id>          # remove
```

## Rules

- **Scope additions only reference existing tests.** `scope add` requires a test id; the workflow (stub or implemented) must already exist in `.ripplo/tests/`. Free-text intents come from the user only — stub a matching test and `scope link` it.
- **Every stub must be scope-added the same turn you create it.** Stubs not in scope are invisible to the user and don't block Stop.
- **The Stop hook blocks on incomplete scope** (intent items with no test, stubs not yet implemented). Pausing hooks from the dashboard is the only escape hatch.
- **Scope persists across CLI restarts** — quitting marks the session inactive; items return on next start.
- **Current scope auto-injects into every prompt** via `scope-reminder` — don't run `scope status` reflexively.

## When to add

- **Any task that could affect an end-to-end flow** (frontend, backend, schema, infra, config) → for each affected flow, either `scope add` an existing test (so Stop re-validates it) or stub a new `.notImplemented()` test and scope add that.
- **Mid-task discovery** — when a new flow surfaces, stub + scope add immediately.
- **Coverage-drift nudge** — add the missing item or revert the underlying change.
- **User-added free-text item** — stub the test and `scope link`.
