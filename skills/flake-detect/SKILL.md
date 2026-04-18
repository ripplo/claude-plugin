---
name: flake-detect
description: "Reproduce a suspected flaky test by running it N times in parallel. Use only when you have evidence of intermittent failure — not as a default post-create check."
---

# Ripplo Flake Detection

Use this **only** when you suspect a test is flaky and want to reproduce the non-deterministic behavior for debugging. Do **not** run it after every new test or every passing run — it's expensive and not part of the normal create/run loop.

Triggers that warrant it:

- A test that passed once but failed on a later run with no spec change.
- The user reports intermittent CI failures on a specific test.
- You're debugging a precondition you suspect isn't isolating per-run.

```sh
npx ripplo flake-detect <id> --runs=10
```

## Interpreting

- **0% flake rate** — couldn't reproduce. The intermittent failure is elsewhere (env, infra) or rarer than 10 runs surfaces.
- **>0%** — reproduced. Common causes:
  - **Race condition** — actions fire before transitions complete; add assertions between actions.
  - **Hardcoded precondition data** — runs collide on unique constraints. See "Parallel safety for preconditions" in `/ripplo:explore` (`ctx.uniqueId`, `ctx.uniqueEmail`).
  - **Timing-dependent locators** — element appears/disappears based on load time; use a stable locator.
  - **Non-exact text** — exact `equals` only, no `contains`/regex.

To diagnose a specific failing run in a flaky batch, pick a `runId` from the output and invoke `/ripplo:debug`.
