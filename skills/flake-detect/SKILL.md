---
name: flake-detect
description: "Run flake detection on a Ripplo test. Executes N parallel runs to detect non-deterministic behavior."
---

# Ripplo Flake Detection

Run a test multiple times in parallel to detect flakiness.

## Usage

```bash
npx ripplo flake-detect <id> --runs=10
```

## Interpreting results

- **0% flake rate**: Test is deterministic. Ship it.
- **>0% flake rate**: Test has non-deterministic behavior. Common causes:
  - **Race conditions**: Actions fire before transitions complete — add assertions between actions
  - **Hardcoded precondition data**: Multiple runs collide on unique constraints — see the "Parallel safety for preconditions" section in `/ripplo:explore` for the `ctx.uniqueId` / `ctx.uniqueEmail` helpers
  - **Timing-dependent locators**: Elements appear/disappear based on load time — use more stable locators
  - **Non-exact text matching**: Text varies slightly between runs — ensure exact `equals` matching

To diagnose a specific failing run inside a flaky batch, pick one `runId` from the output and invoke `/ripplo:debug` — the full diagnosis checklist applies.

## When to run

- After a new test passes for the first time
- After modifying an existing test
- As part of CI to catch regressions
