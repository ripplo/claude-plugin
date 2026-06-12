---
name: run
description: "Run Ripplo e2e tests and manage Testing Scope — the set of flows this session must prove before work counts as done. Use when executing tests, when a drift nudge fires, or when the user says 'in scope' / 'out of scope'. Not for diagnosis (use /ripplo:debug)."
---

# Run Ripplo Tests

```sh
npx ripplo run                          # auto-scopes dirty workflows + runs scope (default)
npx ripplo run <workflow-slug> ...      # one workflow — runs all its enumerated tests
npx ripplo run <workflow-slug>/<test-slug>  # one test path (one when branch; "main" when no branches)
npx ripplo run --all                    # full suite — minutes of compute, use sparingly
```

**Scope is the unit of iteration.** Bare `npx ripplo run` auto-adds dirty `.ripplo/workflows/*.ts` files to scope, then runs every runnable scope item — the right default while iterating. Explicit ids only for a one-off rerun (workflow slug = all its tests, workflow/test = one branch); `--all` only when the user explicitly asks.

## Requirements

Needs the app dev server + `npx ripplo daemon` (run refuses to dispatch otherwise). `npx ripplo doctor` checks both; if red, `/ripplo:start`. Run compiles + syncs `.ripplo/` on demand. If it reports `"<slug>" was synced but the server didn't return it`, run `npx ripplo sync`.

## On failure

The CLI prints the failed step, the findings, and `Debug artifacts: .ripplo/debug/<runId>/`. Read the output and `behavior.jsonl` — don't pipe `npx ripplo run` through `grep`/`tail`/`head`, and don't re-run to reshape stdout. Only rerun after a fix. For diagnosis: `/ripplo:debug`.

## Testing Scope

Scope is the session's success contract: the e2e flows that must pass for the work to count as done. It lives in the dev-session DB (visible in Developer Mode → Testing Scope) and dies with the PR; the durable artifacts are the workflows in `.ripplo/workflows/`. **Scope is intent; a passing test is proof.** Scope a flow → write its workflow (`/ripplo:create`) → run it green.

Accurate, sufficiently broad scope is **your** job, not the user's. They describe what they're building; you translate to the flows that must pass. For any non-trivial change:

- Enumerate every flow it could affect — new flows and existing flows whose behavior might shift.
- Scope them all: write missing workflows, `scope add` existing ones.
- Err toward breadth. Under-scoping is the default failure mode.

Upper bound: ~50 workflows in scope. Hitting it means split the work into phases with the user, not narrow coverage.

### Commands

```sh
npx ripplo scope status                              # list current scope
npx ripplo scope add "<intent>" ["<intent>"...]      # bind existing workflows (variadic — one call, no shell loops)
npx ripplo scope link <scope-item-id> "<intent>"     # link a user free-text item to a workflow you wrote
npx ripplo scope remove <scope-item-id> [<id>...]    # remove (variadic)
```

### Rules

- **Edited workflows auto-scope once lint-clean.** Don't `scope add` workflows you're actively editing — only previously-existing workflows you didn't touch, or to reverse a remove.
- **`scope add` references existing workflows only.** Free-text intents come from the user — write a matching workflow and `scope link` it.
- **`scope remove` is not a shortcut to clear the gate.** Valid: wrong flow, duplicate, user said "not this session," feature cut. Size, effort, and session length are never valid reasons.
- **Flow list too large? Parallelize, don't trim.** See `/ripplo:create` → "Parallelizing multi-workflow sessions."
- **Scope persists across CLI restarts** — items return on next start.
- **Current scope auto-injects into every prompt** — don't run `scope status` reflexively.

### When to add

- Any task that could affect an e2e flow (frontend, backend, schema, infra, config) → `scope add` an existing workflow or write a new one per affected flow.
- Mid-task discovery — a new flow surfaces, write its workflow.
- Drift nudge — user-facing code changed without a matching workflow; add the missing flow or revert the change.
- User-added free-text item — write the workflow and `scope link` it.
