---
name: run
description: "Run Ripplo e2e tests and manage Testing Scope — the set of flows this session must prove before work counts as done. Use when executing tests, when a drift nudge fires, or when the user says 'in scope' / 'out of scope'. Not for diagnosis (use /ripplo:debug)."
---

# Run Ripplo Tests

```sh
npx ripplo run                     # auto-scopes dirty tests + runs scope (default)
npx ripplo run <test-id> ...       # specific tests (the slug from run output; quoted intent also works)
npx ripplo run --all               # full suite — minutes of compute, use sparingly
```

**Scope is the unit of iteration.** Bare `npx ripplo run` auto-adds dirty `.ripplo/tests/*.ts` files to scope, then runs every runnable scope item — the right default while iterating. Explicit test ids only for a one-off rerun; `--all` only when the user explicitly asks.

## Requirements

Needs the app dev server + `npx ripplo daemon` (run refuses to dispatch otherwise). `npx ripplo doctor` checks both; if red, `/ripplo:start`. Run compiles + syncs `.ripplo/` on demand. If it reports `"<slug>" was synced but the server didn't return it`, run `npx ripplo sync`.

## On failure

The CLI prints the failed step, the oracle's findings, and `Debug artifacts: .ripplo/debug/<runId>/`. Read the output and `behavior.jsonl` — don't pipe `npx ripplo run` through `grep`/`tail`/`head`, and don't re-run to reshape stdout. Only rerun after a fix. For diagnosis: `/ripplo:debug`.

## Testing Scope

Scope is the session's success contract: the e2e flows that must pass for the work to count as done. It lives in the dev-session DB (visible in Developer Mode → Testing Scope) and dies with the PR; the durable artifacts are the tests in `.ripplo/tests/`. **Scope is intent; a passing test is proof.** Scope a flow → write its test (`/ripplo:create`) → run it green.

Accurate, sufficiently broad scope is **your** job, not the user's. They describe what they're building; you translate to the flows that must pass. For any non-trivial change:

- Enumerate every flow it could affect — new flows and existing flows whose behavior might shift.
- Scope them all: write missing tests, `scope add` existing ones.
- Err toward breadth. Under-scoping is the default failure mode.

Upper bound: ~50 tests in scope. Hitting it means split the work into phases with the user, not narrow coverage.

### Commands

```sh
npx ripplo scope status                              # list current scope
npx ripplo scope add "<intent>" ["<intent>"...]      # bind existing tests (variadic — one call, no shell loops)
npx ripplo scope link <scope-item-id> "<intent>"     # link a user free-text item to a test you wrote
npx ripplo scope remove <scope-item-id> [<id>...]    # remove (variadic)
```

### Rules

- **Edited tests auto-scope once lint-clean.** Don't `scope add` tests you're actively editing — only previously-existing tests you didn't touch, or to reverse a remove.
- **`scope add` references existing tests only.** Free-text intents come from the user — write a matching test and `scope link` it.
- **`scope remove` is not a shortcut to clear the gate.** Valid: wrong flow, duplicate, user said "not this session," feature cut. Size, effort, and session length are never valid reasons.
- **Flow list too large? Parallelize, don't trim.** See `/ripplo:create` → "Parallelizing multi-test sessions."
- **Scope persists across CLI restarts** — items return on next start.
- **Current scope auto-injects into every prompt** — don't run `scope status` reflexively.

### When to add

- Any task that could affect an e2e flow (frontend, backend, schema, infra, config) → `scope add` an existing test or write a new one per affected flow.
- Mid-task discovery — a new flow surfaces, write its test.
- Drift nudge — user-facing code changed without a matching test; add the missing flow or revert the change.
- User-added free-text item — write the test and `scope link` it.
