---
name: flake-detect
description: "Reproduce a suspected flaky test by running it N times in parallel. Use only when you have evidence of intermittent failure — not as a default post-create check."
---

# Ripplo Flake Detection

Use **only** when you suspect non-determinism and need to reproduce it. **Not** part of the normal create/run loop — it's expensive.

Triggers:

- A test that passed once but failed on a later run with no spec change.
- User reports intermittent CI failures on a specific test.
- You're debugging a precondition you suspect isn't isolating per-run.

## Prerequisite

Needs the app dev server + `npx ripplo watch`. Run `npx ripplo doctor`; if missing, `/ripplo:start`.

```sh
npx ripplo flake-detect <id> --runs=10
```

## Interpreting

- **0% flake rate** — couldn't reproduce. Failure is elsewhere (env, infra) or rarer than 10 runs surfaces.
- **>0%** — reproduced. Common causes:
  - **Race condition** — actions fire before transitions complete; add an assertion between actions.
  - **Hardcoded precondition data** — runs collide on unique constraints. See `/ripplo:create` → "Parallel safety" (`ctx.uniqueId`, `ctx.uniqueEmail`).
  - **Destructive precondition** — a `setup()` calls `update` or `delete`, which can match rows from another in-flight run. Preconditions must be create-only; refactor the row to be created with the desired state instead of mutated downstream.
  - **Timing-dependent locators** — element appears/disappears based on load time; use a stable locator.
  - **Non-exact text** — exact `equals` only, no `contains`/regex.

To diagnose a specific failing run, pick a `runId` from the output and invoke `/ripplo:debug`.
