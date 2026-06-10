---
name: start
description: "Start the `ripplo daemon` background process for this project's dev session. Use when `npx ripplo doctor` reports no active dev session, when dev-mode hooks aren't firing, or when the user explicitly says `/ripplo:start`."
---

# Ripplo Start

Bring this project's dev environment up to a state where Ripplo dev mode actually fires. That's two background processes: the app's dev server, and `npx ripplo daemon`. Both need to be running before dev-mode hooks arm and `ripplo run` can dispatch.

## Procedure

1. Run `npx ripplo doctor`. Note which checks are red: `Dev server` (the app), `Dev session` (daemon), or both.
2. **If `Dev server` is red:** start the app's dev server via `Bash` with `run_in_background`. Look at `package.json` `scripts.dev` to know the right command for this project. Set `cwd` to the directory the script expects (usually the repo root, sometimes `apps/<app>/`).
3. **If `Dev session` is red:** spawn `npx ripplo daemon` via `Bash` with `run_in_background`. Set `cwd` to the directory containing `.ripplo/` (workspace root in monorepos).
4. Wait briefly (3–5 seconds) for both to come up, then re-run `npx ripplo doctor`. If green, confirm to the user.
5. If `Dev session` is still red after the grace window even though `ripplo daemon` is in the process list, read the background bash log via `BashOutput` and surface what the daemon printed. Common causes: auth token missing/expired, env file not found, Ripplo server unreachable, wrong cwd. Stop and report — don't loop.

## Rules

- **Idempotent.** If a check is already green, skip the corresponding spawn. Never start a second `ripplo daemon` for the same project — they'll fight over the dev session. Never restart the app dev server if it's already up — you may interrupt the user's work.
- **Run from the right cwd.** Watch must be invoked from the directory containing `.ripplo/`. The app dev server's cwd depends on its script — match what the user's `package.json` expects.
- **Don't try to "fix" the app dev server beyond starting it.** If it errors out (port in use, missing env, build failure), surface the error to the user and stop. That's their environment to debug, not yours.
