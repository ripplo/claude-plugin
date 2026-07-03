---
name: start
description: "Start the `ripplo daemon` background process for this project's dev session. Use when `npx ripplo doctor` reports no active dev session, when dev-mode hooks aren't firing, or when the user says `/ripplo:start`. Takes an optional executor arg — `/ripplo:start cloud` switches runs to Ripplo's cloud fleet after the daemon is up."
---

# Ripplo Start

Bring the dev environment up so Ripplo dev mode fires: two background processes — the app's dev server and `npx ripplo daemon`. Both must run before dev-mode hooks arm and `npx ripplo run` can dispatch.

## Executor: local (default) or cloud

The skill takes one optional argument that picks where runs and exploration paths execute — the browsers and runtime driving your workflows.

- **`/ripplo:start`** (no arg) or **`/ripplo:start local`** → runs execute in browsers on this machine. Default — every daemon starts local.
- **`/ripplo:start cloud`** → after the daemon is up, run `npx ripplo executor cloud`: the daemon brings up a per-session tunnel and runs execute on Ripplo's infra, not your machine. Use when you want runs off your box (heavy suites, a slow laptop, parity with CI).

The executor switches live — `npx ripplo executor <local|cloud>` (or the dev-bar toggle in the web UI) takes effect for the next run, no daemon restart. `npx ripplo executor` with no argument prints the current mode. Either way the daemon still owns the local dev session, hooks, and IPC — only where the runs execute changes.

## Procedure

1. `npx ripplo doctor`. Note which checks are red: `Dev server` (the app), `Dev session` (daemon), or both.
2. **`Dev server` red:** start the app's dev server via `Bash` with `run_in_background`. Read `package.json` `scripts.dev` for the right command; set `cwd` to what the script expects.
3. **`Dev session` red:** spawn the daemon via `Bash` with `run_in_background`, `cwd` = the directory containing `.ripplo/` (workspace root in monorepos): `npx ripplo daemon`. If the user asked for cloud (`/ripplo:start cloud`), run `npx ripplo executor cloud` once doctor is green.
4. Wait 3–5 seconds, re-run `npx ripplo doctor`. Green → confirm to the user.
5. Still red with the daemon in the process list: read its background log via `BashOutput` and surface what it printed. Common causes: auth token missing/expired, env file not found, Ripplo server unreachable, wrong cwd. Stop and report — don't loop.
6. Dev session green: run `npx ripplo tasks list` once to surface the current backlog, then pick up anything open.
7. Arm the task watcher so tasks filed later wake you without a re-prompt: call the `Monitor` tool with `command: "npx ripplo tasks watch"`, `persistent: true`, `description: "new ripplo tasks"`, `cwd` = the directory containing `.ripplo/`. Each event is a new task or a user reply — pick it up, delegating to a subagent when the work is cleanly delegable. Stop it with `TaskStop` if the user asks.

## Daemon lifecycle

`npx ripplo daemon` takes a lifecycle action: `start` (default, the long-running process), `stop`, `restart`, and `status`.

- **`npx ripplo daemon status`** — quick foreground check: running or not, version, active/queued runs, explorer state. Use it before assuming anything about the daemon.
- **`npx ripplo daemon stop`** — signals the running daemon and waits up to 10s for a clean exit. Use it when a daemon you don't own is holding the dev session (a stale one from another terminal).
- **`npx ripplo daemon restart`** — stop then start in one foreground process. This is for a human's terminal. As an agent, don't use it — the start half runs forever and your Bash call never returns. Instead: `npx ripplo daemon stop` (foreground, returns quickly), then spawn `npx ripplo daemon` with `run_in_background` as usual.

When to restart the daemon: after `npx ripplo update` or a CLI rebuild (the daemon keeps running old code until restarted), or when `daemon status` says running but runs aren't dispatching. Switching executor (local ↔ cloud) needs no restart — `npx ripplo executor <mode>`. A daemon that refuses to start because another holds the lock prints the holder's pid — stop that one first, don't fight the lock.

## Rules

- **Spawn as harness-managed background shells, never `&`.** Use `Bash` with `run_in_background` for the dev server and daemon, and the `Monitor` tool for the watcher. Never background with `&`, `nohup`, or `disown` — those detach the process from the harness, so you lose the handle and can't read its log or stop it.
- **Idempotent.** Skip any spawn whose check is already green. Never start a second daemon for the same project — the second exits because the first holds the dev session. Need the session back (stale version)? `npx ripplo daemon stop` first. Wrong executor? `npx ripplo executor <mode>` — no restart. Never restart an already-running dev server (you may interrupt the user's work). One watcher per session — don't arm a second.
- **Right cwd.** The daemon and watcher run from the directory containing `.ripplo/`; the dev server's cwd depends on its script.
- **Don't "fix" the app dev server beyond starting it.** If it errors (port in use, missing env, build failure), surface the error and stop — that's the user's environment to debug.
