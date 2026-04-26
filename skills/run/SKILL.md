---
name: run
description: "Run Ripplo e2e tests via `npx ripplo run`. Use when executing tests after a fix or to verify a new test passes — not for diagnosis (use /ripplo:debug)."
---

# Run Ripplo Tests

```sh
npx ripplo run <id1> <id2>   # specific tests
npx ripplo run               # full suite — minutes of compute, use sparingly
```

**Default to the smallest relevant set:**

- Fixed one test → rerun just that test.
- Touched a feature area → rerun only the tests covering that area.
- `npx ripplo scope status` lists the tests this session is responsible for — natural target for a scoped re-run.
- Full suite only when the user asks, or as a final green-light.

## Requirements

- `npx ripplo doctor` is the canonical preflight — it reports both `dev-server` (app at `RIPPLO_APP_URL` reachable) and `dev-session` (`ripplo watch` live for this cwd) as independent checks. If either fails, `ripplo run` will refuse to dispatch.
- If `dev-session` is red, run `/ripplo:start` (or spawn `npx ripplo watch` directly via `Bash` with `run_in_background`). If `dev-server` is red, start the app's dev server the same way.
- `npx ripplo run` already compiles + syncs `.ripplo/` resources on demand before each invocation. If the server appears out of sync independently of a run (e.g. the diagnostic says `"<slug>" was synced but the server didn't return it`), use `npx ripplo sync` to re-push.

## On failure

The CLI prints `Debug artifacts: .ripplo/debug/<runId>/` for each failed run — Read those files. **Never pipe `npx ripplo run` through `grep`/`tail`/`head`.** Don't re-run to reshape stdout.

Only rerun when you've made a fix. For diagnosis: `/ripplo:debug`.
