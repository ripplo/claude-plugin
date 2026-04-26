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

## Prerequisite — dev session must be live

This skill needs two background processes running: the app's dev server, and `npx ripplo watch`. Run `npx ripplo doctor` first — if either is missing, run `/ripplo:start` (or spawn `npx ripplo watch` directly via `Bash` with `run_in_background`) and start the app dev server the same way if it isn't up. Without watch, `ripplo run` refuses to dispatch.

```sh
npx ripplo flake-detect <id> --runs=10
```

## Interpreting

- **0% flake rate** — couldn't reproduce. Failure is elsewhere (env, infra) or rarer than 10 runs surfaces.
- **>0%** — reproduced. Common causes:
  - **Race condition** — actions fire before transitions complete; add an assertion between actions.
  - **Hardcoded precondition data** — runs collide on unique constraints. See `/ripplo:create` → "Parallel safety" (`ctx.uniqueId`, `ctx.uniqueEmail`).
  - **Timing-dependent locators** — element appears/disappears based on load time; use a stable locator.
  - **Non-exact text** — exact `equals` only, no `contains`/regex.

To diagnose a specific failing run, pick a `runId` from the output and invoke `/ripplo:debug`.
