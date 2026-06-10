# Ripplo — Claude Code Plugin

Validation-loop hooks that keep your agent's tests in step with the code it ships. Part of [Ripplo](https://ripplo.ai) — typed end-to-end tests with real backend state.

## Install

The plugin shells out to the [`ripplo` CLI](https://www.npmjs.com/package/ripplo), so authenticate first:

```sh
npx ripplo auth login
```

Then in Claude Code:

```
/plugin marketplace add ripplo/claude-plugin
/plugin install ripplo
/ripplo:setup
```

`/ripplo:setup` runs `ripplo init` (scaffolds `.ripplo/`, writes `RIPPLO_*` env vars, installs `@ripplo/testing`), starts `ripplo daemon` as a background process, and mounts the engine adapter into your app server.

## What the hooks do

Four hooks wire into the agent's workflow so tests are load-bearing, not advisory.

- **UserPromptSubmit** nudges when user-facing code has drifted from `.ripplo/tests` and surfaces the flows in scope during plan mode.
- **PreToolUse / ExitPlanMode** blocks plan exit if the plan touches user-facing code but no matching `.ripplo/tests` flow is planned.
- **PostToolUse (Edit/Write)** lints the DSL on `.ripplo/**` edits and flags user-facing edits with no matching test.
- **Stop** lints, runs scoped and changed tests, and blocks on drift — user-facing changes without a matching `.ripplo/tests` update.

The plugin treats `src/**`, `app/**`, `apps/**`, `pages/**`, `routes/**`, and `components/**` as user-facing, and ignores generated and vendor output.

## Skills

| Skill             | Description                                                  |
| ----------------- | ------------------------------------------------------------ |
| `/ripplo:setup`   | Wire the engine adapter into your app server                 |
| `/ripplo:explore` | Crawl your codebase and generate test specs                  |
| `/ripplo:create`  | Create a new test spec                                       |
| `/ripplo:scope`   | Manage Testing Scope (visible to the user in Developer Mode) |
| `/ripplo:run`     | Run tests in parallel                                        |
| `/ripplo:debug`   | Debug failures using DOM snapshots and network traces        |

## Testing Scope

Scope is the agent's working memory for what user flows the current session is on the hook for. It lives in the dev-session DB (no local file) and is mutated only via `npx ripplo scope add|link|remove`. Agent scope items must reference an existing test (stub or implemented); free-text intents come from the user via the dashboard, and the agent's job is to stub a matching test and `scope link` it. The user sees live scope in Developer Mode → Testing Scope and can pause hooks entirely from there.

## Lockfile

`ripplo init` writes the initial `.ripplo/ripplo.lock`. Commit it; the Ripplo server reads it on every push webhook. Keep it fresh via `npx ripplo compile`, or rely on the pre-commit hook `/ripplo:setup` installs.
