---
name: start
description: "Start the `ripplo daemon` background process for this dev session. Use when `npx ripplo doctor` reports no active dev session, when dev-mode hooks aren't firing, or on `/ripplo:start`. Optional executor arg — `/ripplo:start cloud` switches runs to Ripplo's cloud fleet after the daemon is up."
---

# Ripplo Start

Two background processes must run before dev-mode hooks arm and `npx ripplo run` dispatches: the app's dev server and `npx ripplo daemon`.

## Executor: local (default) or cloud

Optional arg picks where runs execute:

- **`/ripplo:start`** / **`local`** → runs on this machine (default).
- **`/ripplo:start cloud`** → after the daemon is up, `npx ripplo executor cloud`: the daemon brings up a per-session tunnel, runs execute on Ripplo's infra.

Switches live — `npx ripplo executor <local|cloud>` takes effect next run, no restart. No arg prints the current mode. The daemon always owns the local dev session, hooks, and IPC — only where runs execute changes.

## Procedure

1. `npx ripplo doctor`. Note red checks: `Dev server`, `Dev session`, or both.
2. **`Dev server` red:** start the app dev server via `Bash` `run_in_background`. Read `package.json` `scripts.dev`; set `cwd` to what it expects.
3. **`Dev session` red:** spawn `npx ripplo daemon` via `Bash` `run_in_background`, `cwd` = directory containing `.ripplo/`. Cloud requested → `npx ripplo executor cloud` once doctor is green.
4. Wait 3–5s, re-run `npx ripplo doctor`. Green → confirm to the user.
5. Still red with the daemon running: read its log via `BashOutput`, surface it. Common causes: auth token, env file, server unreachable, wrong cwd. Stop and report — don't loop.
6. Dev session green: `npx ripplo tasks list`, pick up anything open, mark each with `npx ripplo tasks start <id>`.
7. Arm the task watcher: `Monitor` tool with `command: "npx ripplo tasks watch"`, `persistent: true`, `description: "new ripplo tasks"`, `cwd` = directory containing `.ripplo/`. Each event is a new task, reopen, or user reply (not a finding — those triage via `/ripplo:tasks`). Delegate to a subagent when cleanly delegable. `TaskStop` if the user asks.

## Daemon lifecycle

`npx ripplo daemon` takes: `start` (default), `stop`, `restart`, `status`.

- **`status`** — running or not, version, active/queued runs, explorer state.
- **`npx ripplo explore` / `on` / `off`** — show/toggle the background explorer (needs a live daemon). Runs on either executor.
- **`stop`** — signals the daemon, waits up to 10s. Use when a stale daemon holds the dev session.
- **`restart`** — foreground, for a human's terminal. **As an agent, don't use it** — the start half runs forever. Instead: `npx ripplo daemon stop`, then spawn `npx ripplo daemon` with `run_in_background`.

Restart after `npx ripplo update` or a CLI rebuild, or when `status` says running but runs aren't dispatching. Executor switch needs no restart. A daemon that can't get the lock prints the holder's pid — stop that one first.

## Rules

- **Spawn as harness-managed background shells, never `&`/`nohup`/`disown`** — those detach the process so you lose its log and handle. Use `Bash` `run_in_background` (dev server, daemon) and `Monitor` (watcher).
- **Skip any spawn whose check is already green.** Never start a second daemon (it exits — the first holds the session); need the session back → `stop` first. Wrong executor → `npx ripplo executor <mode>`, no restart. Never restart a running dev server. One watcher per session.
- **Right cwd.** Daemon + watcher run from the directory containing `.ripplo/`; dev server cwd depends on its script.
- **Don't "fix" the app dev server beyond starting it.** Errors → surface and stop; that's the user's environment.
