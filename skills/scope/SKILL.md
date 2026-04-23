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
- Err on the side of breadth. The Stop gate catches new _interactions_ via `.coverage()` exhaustiveness, but it won't catch a new _flow_ you didn't stub — that's still on you to scope.

**Upper bound: ~50 tests in scope at once.** Below that, include as many as needed to cover the functionality — don't trim for convenience. If a change genuinely exceeds 30, split the work into phases with the user. Hitting the bound is a signal the change is too large for one session, not a reason to narrow coverage.

Under-scoping is the default failure mode. When in doubt, scope it in.

**Edited tests auto-scope.** Any edit to `.ripplo/tests/<id>.ts` is automatically added to scope by the `post-edit-lint` hook. You don't need to run `scope add` for tests you're actively editing. Use `scope add` explicitly only when binding an already-existing test you didn't edit this session, and `scope remove` when a test is genuinely out of scope (removal remains manual — editing a test after removing it will re-scope it).

## Related skills (load these too)

- `/ripplo:explore` — discover flows and stub tests
- `/ripplo:create` — per-test authoring workflow

## What scope is

Scope is your working memory for what end-to-end flows this session is responsible for — anything the running app exercises (frontend, backend, schema, infra, config, deps) that your changes could affect. It lives in the dev-session DB; the user sees it live in Developer Mode → Testing Scope. Scope dies with the PR; the durable artifacts are tests in `.ripplo/tests/`.

**Scope vs coverage.** Scope is _intent_ — "these flows matter this session." Coverage (`.coverage(...)` on each test, enforced at `stop-enforce`) is _proof_ — "every new interaction in the diff is claimed by some test." They're complementary: scope ensures you know what to test; coverage enforcement ensures new affordances don't ship unclaimed. Scope a flow, stub a test, implement with `.coverage(...ids)` — that's the end-to-end chain.

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
- **Stubs auto-scope on creation.** The `post-edit-lint` hook scopes any edit to `.ripplo/tests/<id>.ts`, so a newly stubbed test is in scope by the time `post-edit` completes. Don't duplicate the call manually.
- **The Stop hook blocks on incomplete scope** (intent items with no test, stubs not yet implemented, or workflows whose tests fail). Pausing hooks from the dashboard is the only escape hatch.
- **Ripplo tests are how you validate what you actually built.** Without a passing test, you don't know the feature works — you're guessing. The Stop gate exists because "I wrote the code and it looked right" is not evidence. Treat every scoped test as load-bearing: it's the proof that belongs with the diff.
- **`scope remove` is not a shortcut to clear the gate, and "implement vs. trim" is not a neutral choice to present to the user.** Offering the user an A/B between "implement all stubs" and "remove stubs to unblock Stop" frames discarding validation as legitimate — it is not. Don't present it. Scope removal is only valid when an item is genuinely out of scope: wrong flow stubbed, duplicate of another test, the user explicitly said "not this session," or the underlying feature was cut. **Size, effort, or session length are never valid reasons to remove.**
- **If the stub list feels too large, parallelize — don't trim.** Stub implementation is embarrassingly parallel across files. See `/ripplo:create` → "Parallelizing multi-stub sessions" for how to fan out subagents. Only escalate to the user (to split across PRs) after you've actually tried parallelizing, not as a first move.
- **Scope persists across CLI restarts** — quitting marks the session inactive; items return on next start.
- **Current scope auto-injects into every prompt** via `scope-reminder` — don't run `scope status` reflexively.

## When to add

- **Any task that could affect an end-to-end flow** (frontend, backend, schema, infra, config) → for each affected flow, `scope add` an existing test (so Stop re-validates it) or stub a new `.notImplemented()` test (auto-scoped on save).
- **Mid-task discovery** — when a new flow surfaces, stub it. Auto-scope handles the rest.
- **Coverage-drift nudge** — add the missing item or revert the underlying change.
- **User-added free-text item** — stub the test and `scope link`.
