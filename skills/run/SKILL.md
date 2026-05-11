---
name: run
description: "Run Ripplo e2e tests via `npx ripplo run`. Use when executing tests after a fix or to verify a new test passes — not for diagnosis (use /ripplo:debug)."
---

# Run Ripplo Tests

```sh
npx ripplo run               # auto-scopes dirty tests + runs scope (default)
npx ripplo run <id1> <id2>   # specific tests
npx ripplo run --all         # full suite — minutes of compute, use sparingly
```

**Scope is the unit of iteration.** Bare `ripplo run` runs every runnable test in the current dev-session scope after auto-adding any dirty `.ripplo/tests/*.ts` files. That's the right default while iterating.

- Use `npx ripplo scope status` to see what's in scope; `ripplo scope add <id>` to add.
- Pass explicit ids only to override scope for a one-off rerun.
- `--all` only when the user explicitly asks. Scope is the green-light surface — if a test isn't in scope, it isn't this session's responsibility.

## Requirements

- Needs the app dev server + `npx ripplo watch`. Run `npx ripplo doctor`; if either is red, `/ripplo:start`. Run refuses to dispatch otherwise.
- `npx ripplo run` compiles + syncs `.ripplo/` resources on demand. If the diagnostic says `"<slug>" was synced but the server didn't return it`, run `npx ripplo sync` to re-push.

## On failure

The CLI prints `Debug artifacts: .ripplo/debug/<runId>/` for each failed run — Read those files. **Never pipe `npx ripplo run` through `grep`/`tail`/`head`.** Don't re-run to reshape stdout.

Only rerun when you've made a fix. For diagnosis: `/ripplo:debug`.
