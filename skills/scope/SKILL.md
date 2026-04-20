---
name: scope
description: "Manage Testing Scope — your working memory for what end-to-end flows this session is responsible for. Use when starting a task that could affect any flow the running app exercises, when the drift nudge fires, or when the user says 'in scope' / 'out of scope'."
---

# Testing Scope

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
