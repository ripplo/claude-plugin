---
name: start
description: "Start the `ripplo daemon` background process for this project's dev session. Use when `npx ripplo doctor` reports no active dev session, when dev-mode hooks aren't firing, or when the user says `/ripplo:start`."
---

# Ripplo Start

Bring the dev environment up so Ripplo dev mode fires: two background processes — the app's dev server and `npx ripplo daemon`. Both must run before dev-mode hooks arm and `npx ripplo run` can dispatch.

## Procedure

1. `npx ripplo doctor`. Note which checks are red: `Dev server` (the app), `Dev session` (daemon), or both.
2. **`Dev server` red:** start the app's dev server via `Bash` with `run_in_background`. Read `package.json` `scripts.dev` for the right command; set `cwd` to what the script expects.
3. **`Dev session` red:** spawn `npx ripplo daemon` via `Bash` with `run_in_background`, `cwd` = the directory containing `.ripplo/` (workspace root in monorepos).
4. Wait 3–5 seconds, re-run `npx ripplo doctor`. Green → confirm to the user.
5. Still red with the daemon in the process list: read its background log via `BashOutput` and surface what it printed. Common causes: auth token missing/expired, env file not found, Ripplo server unreachable, wrong cwd. Stop and report — don't loop.

## Rules

- **Idempotent.** Skip any spawn whose check is already green. Never start a second daemon for the same project (they fight over the dev session); never restart an already-running dev server (you may interrupt the user's work).
- **Right cwd.** The daemon runs from the directory containing `.ripplo/`; the dev server's cwd depends on its script.
- **Don't "fix" the app dev server beyond starting it.** If it errors (port in use, missing env, build failure), surface the error and stop — that's the user's environment to debug.
