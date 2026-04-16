---
name: flake-detect
description: "Run flake detection on a Ripplo test. Executes N parallel runs to detect non-deterministic behavior."
user-invokable: true
---

# Ripplo Flake Detection

Run a test multiple times in parallel to detect flakiness.

## Usage

```bash
npx ripplo flake-detect <slug> --runs=10
```

## Interpreting results

- **0% flake rate**: Test is deterministic. Ship it.
- **>0% flake rate**: Test has non-deterministic behavior. Common causes:
  - **Race conditions**: Actions fire before transitions complete — add assertions between actions
  - **Hardcoded data**: Multiple runs collide on unique constraints — use precondition data
  - **Timing-dependent locators**: Elements appear/disappear based on load time — use more stable locators
  - **Non-exact text matching**: Text varies slightly between runs — ensure exact `equals` matching

## When to run

- After a new test passes for the first time
- After modifying an existing test
- As part of CI to catch regressions
