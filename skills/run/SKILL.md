---
name: run
description: "Run Ripplo e2e tests. Use when executing tests."
---

# Run Ripplo Tests

```sh
npx ripplo run <id1> <id2>   # specific tests
npx ripplo run               # full suite — minutes of compute, use sparingly
```

**Default to the smallest relevant set.** Bias scoped:

- Fixed one test → rerun just that test.
- Touched a feature area → rerun only the tests covering that area.
- `npx ripplo scope status` lists the tests this session is responsible for — natural target for a scoped re-run.
- Full suite only when the user asks, or as a final green-light.

## Requirements

- `npx ripplo` running in a terminal (dev session active)
- Dev server running at `appUrl` from `.ripplo/ripplo.ts`
- `.ripplo/ripplo.lock` up to date — if you edited `.ripplo/*.ts` outside the watcher, run `npx ripplo compile` first
- `npx ripplo doctor` verifies all of the above

## On failure

Don't re-run to reshape stdout. The CLI prints `Debug artifacts: .ripplo/debug/<runId>/` for each failed run — Read those files. Never pipe `npx ripplo run` through `grep`/`tail`/`head` to find which step failed.

Only rerun when you've made a fix. For diagnosis use `/ripplo:debug`.
