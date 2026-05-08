---
name: scope
description: "Manage Testing Scope — your working memory for what end-to-end flows this session is responsible for. Use when starting a task that could affect any flow the running app exercises, when a coverage-drift nudge fires (e.g. user-facing code edited without a matching test update), or when the user says 'in scope' / 'out of scope'."
---

# Testing Scope

Scope is the contract that defines success criteria for this session: the set of e2e flows that must pass for the work to count as done. It lives in the dev-session DB (the user sees it in Developer Mode → Testing Scope), dies with the PR; the durable artifacts are tests in `.ripplo/tests/`.

**Scope vs coverage.** Scope is _intent_ — "these flows matter this session." Coverage (`.coverage(...)` per test, enforced by `stop-enforce`) is _proof_ — "every new interaction in the diff is claimed by some test." Scope a flow → stub a test → implement with `.coverage(...ids)`.

## Prerequisite — dev session must be live

Scope lives in the dev-session DB, which only exists while `npx ripplo watch` is running. The app's dev server also needs to be up. Run `npx ripplo doctor` first — if either is missing, run `/ripplo:start` (or spawn `npx ripplo watch` directly via `Bash` with `run_in_background`) and start the app dev server the same way if it isn't up. Without watch, scope/coverage hooks don't arm and `ripplo run` refuses to dispatch.

## Your responsibility

Maintaining accurate, sufficiently broad scope is **your** job — not the user's. They describe what they're building; you translate to the e2e flows that must pass.

For any non-trivial change:

- Enumerate every flow the change could affect (new flows AND existing flows whose behavior might shift).
- Scope them all: stub missing tests, `scope add` existing ones.
- Err on the side of breadth. The Stop gate catches new _interactions_ via `.coverage()` exhaustiveness, but it won't catch a _flow_ you didn't stub.

**Upper bound: ~50 tests in scope.** Below that, include as many as needed — don't trim for convenience. Hitting the bound means split the work into phases with the user, not narrow coverage.

Under-scoping is the default failure mode. When in doubt, scope it in.

## Commands

```sh
npx ripplo scope status                            # list current scope
npx ripplo scope add <test-id> [<test-id>...]      # bind existing tests (variadic — one call, no shell loops)
npx ripplo scope link <scope-item-id> <test-id>    # link a user free-text item to a test you stubbed
npx ripplo scope remove <scope-item-id> [<id>...]  # remove (variadic)
```

**Scope drives `ripplo run`.** Bare `npx ripplo run` (no args) auto-adds dirty `.ripplo/tests/*.ts` to scope and then runs every runnable scope item — that's the default verify loop.

## Rules

- **Edited tests auto-scope after lint passes.** The `post-edit-lint` hook scopes any edit to `.ripplo/tests/<id>.ts` once the file is lint-clean (lint errors block scoping until fixed). Don't run `scope add` for tests you're actively editing — only for previously-existing tests you didn't edit, or after `scope remove` you reversed.
- **Scope additions reference existing tests only.** `scope add <test-id>` requires a test (stub or implemented) in `.ripplo/tests/`. Free-text intents come from the user — stub a matching test and `scope link` it.
- **Stop blocks on incomplete scope** (intent items with no test, stubs not yet implemented, or workflows whose tests fail). Pausing hooks from the web UI is the only escape hatch.
- **`scope remove` is not a shortcut to clear the gate.** Don't present "implement vs. trim" as a neutral A/B — it frames discarding validation as legitimate. Valid removal: wrong flow stubbed, duplicate of another test, user explicitly said "not this session," underlying feature was cut. **Size, effort, or session length are never valid reasons.**
- **The same rule applies to every gate-bypass path** — pausing hooks via the web UI, `scope remove`, `uiOnly: true`, "implement now vs. defer?". They're all the same anti-pattern: framing skipped validation as a legitimate option. See `/ripplo:create` → "Stop-enforce stubs are not a question" for the canonical wording. The fix isn't done until the test is.
- **If the stub list feels too large, parallelize — don't trim.** See `/ripplo:create` → "Parallelizing multi-stub sessions." Only escalate to splitting across PRs after parallelizing first.
- **Scope persists across CLI restarts** — quitting marks the session inactive; items return on next start.
- **Current scope auto-injects into every prompt** via `scope-reminder` — don't run `scope status` reflexively.

## When to add

- **Any task that could affect an e2e flow** (frontend, backend, schema, infra, config) → for each affected flow, `scope add` an existing test or stub a new `.notImplemented()` (auto-scoped on save).
- **Mid-task discovery** — new flow surfaces, stub it. Auto-scope handles the rest.
- **Coverage-drift nudge** — add the missing item or revert the underlying change.
- **User-added free-text item** — stub the test and `scope link`.
