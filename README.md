# Ripplo — Claude Code Plugin

AI-powered end-to-end testing skills for [Claude Code](https://claude.ai/code).

## Install

In Claude Code, run:

```
/plugin marketplace add ripplo/claude-plugin
/plugin install ripplo
```

## How It Works

The plugin hooks into your agent's workflow to create a tight validation loop around `.notImplemented()` stubs — the test lifecycle goes **stub in plan → implement with code → validate at stop**:

- **UserPromptSubmit (plan mode)** — reminds the agent of existing `.notImplemented()` stubs so the plan references them
- **PreToolUse: ExitPlanMode** — blocks plan exit if the plan touches user-facing code but cites no `.ripplo/tests` stubs
- **PostToolUse (Edit/Write)** — lints the DSL on `.ripplo/**` edits and flags remaining stubs on `apps/**` edits
- **Stop** — runs `ripplo lint --require-implemented`, surfaces remaining stubs via `ripplo status --format summary`, and runs only the tests changed this session

Your agent writes deterministic, parallelizable tests that verify your app works end-to-end. No flaky tests, no shared state, no ordering dependencies.

## Skills

| Skill                  | Description                                           |
| ---------------------- | ----------------------------------------------------- |
| `/ripplo:setup`        | Wire the precondition adapter into your app server    |
| `/ripplo:explore`      | Crawl your codebase and generate test specs           |
| `/ripplo:create`       | Create a new test spec                                |
| `/ripplo:run`          | Run tests in parallel                                 |
| `/ripplo:debug`        | Debug failures using DOM snapshots and network traces |
| `/ripplo:flake-detect` | Run N parallel executions to detect flaky tests       |

## Prerequisites

Install and set up the [Ripplo CLI](https://www.npmjs.com/package/ripplo) first:

```sh
npx ripplo
```

This authenticates, scaffolds a `.ripplo/` directory, and starts the dev dashboard. Scaffolding also writes an initial `.ripplo/ripplo.lock` — a committed, generated artifact that the Ripplo server reads on push-webhook syncs. Keep it in sync with your `.ripplo/*.ts` via `npx ripplo compile` (or the pre-commit hook the `/ripplo:setup` skill installs).

## How It Works

Your agent uses these skills to read your codebase, discover testable user flows, and generate typed test specs — no manual test writing required. Each test defines its own preconditions, starting URL, and interaction steps using the `@ripplo/testing` DSL.

Learn more at [ripplo.ai](https://ripplo.ai).
