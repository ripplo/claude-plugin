<div align="center">

<img src="assets/logo.svg" width="88" alt="Ripplo" />

# Ripplo for Claude Code

**Make your coding agent prove its work.**

End-to-end validation for agent-built apps, enforced inside the agent loop.

[![Version](https://img.shields.io/badge/version-0.14.0-green.svg)](.claude-plugin/plugin.json)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757.svg)](https://docs.claude.com/en/docs/claude-code/plugins)

[**Website**](https://ripplo.ai) · [**Docs**](https://ripplo.ai/docs)

<a href="https://www.youtube.com/watch?v=hrjQg55Bc5w"><img src="https://img.youtube.com/vi/hrjQg55Bc5w/maxresdefault.jpg" width="720" alt="Watch the Ripplo demo" /></a>

*▶ Watch the demo*

</div>

---

Ripplo discovers the critical end-to-end **workflows** in your application and handles QA for you, so you don't need to write tests or manually click through the entire UI before every release. Our guiding principles:

**Ripplo is strict.** It enforces a programmatic quality and correctness bar on the workflows themselves at compilation time. Best practices around testing, linting, and hooks are built in, so you don't end up testing your AI slop with more AI slop.

**Ripplo is legible.** Developers can scrub through the frontend interactions, backend state, and validations for each workflow, all updating in real time using interactive replays.

Ripplo workflows form a feedback loop that pushes your AI to build better software in the first place — fewer bugs reach users, and developers can prove and understand each new feature in the context of the larger user journey.

## This plugin

This repository contains the Claude Code plugin that guides the agent to automatically generate and maintain workflows as you develop. It lets the agent author and run workflows, and wires in hooks so validation is mechanical: the agent can't call work done until every workflow in scope passes.

## Install

One command — Ripplo creates your initial workflows for you:

```sh
npx ripplo setup
```

The session signs you in, creates your project, runs `ripplo init` (scaffolds `.ripplo/`, writes `RIPPLO_*` env vars, installs `@ripplo/testing`), starts `ripplo daemon` in the background, and mounts the engine adapter into your app server.

By hand instead:

```
/plugin marketplace add ripplo/claude-plugin
/plugin install ripplo
/ripplo:setup
```

**Requirements** — Claude Code, Node 20+, and a Node backend you can mount the engine adapter into (Express, Fastify, Next.js).

## Skills

Six slash commands, each owning one job. Your agent loads the right one by trigger — or invoke any of them directly.

| Skill              | What it does                                                        |
| ------------------ | ------------------------------------------------------------------- |
| `/ripplo:setup`    | One-time onboarding: auth, scaffold, engine adapter, first run      |
| `/ripplo:start`    | Bring up the daemon for the dev session                             |
| `/ripplo:discover` | Crawl the codebase to map click paths and plan coverage             |
| `/ripplo:create`   | Model the state a workflow touches, write the steps, run it         |
| `/ripplo:run`      | Run workflows, diagnose failures, manage Testing Scope, file bugs   |
| `/ripplo:tasks`    | Pick up tasks and explorer findings, prove the fix with a run       |

## Testing Scope

Scope is the agent's working memory for which workflows this session is on the hook for. It lives in the dev-session DB — no local file — and changes only through `npx ripplo scope add|link|remove`.

Agent scope items must reference an existing workflow, stub or implemented. Free-text intents come from you via the dashboard; the agent's job is to stub a matching workflow and `scope link` it. You see live scope in Developer Mode → Testing Scope, and can pause the hooks entirely from there.

## Lockfile

`ripplo init` writes the initial `.ripplo/ripplo.lock`. Commit it — the Ripplo server reads it verbatim on every push webhook, and never executes your DSL. Keep it fresh with `npx ripplo compile`, or rely on the pre-commit hook `/ripplo:setup` installs.

## Docs

[**ripplo.ai/docs**](https://ripplo.ai/docs) covers setup (by hand or one command), day-to-day use, and the agentic reviewers.

## Support

Bugs and feature requests: [open an issue](https://github.com/ripplo/claude-plugin/issues). For anything else, [reach the team](https://ripplo.ai).

<div align="center">
<sub>Built by <a href="https://ripplo.ai">Ripplo</a>.</sub>
</div>
