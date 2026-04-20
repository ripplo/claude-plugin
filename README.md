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

- **UserPromptSubmit** — reminds the agent of `.notImplemented()` stubs during plan mode, and nudges mid-session when `watchPaths` code has drifted from `.ripplo/tests` updates
- **PreToolUse: ExitPlanMode** — blocks plan exit if the plan touches user-facing code but cites no `.ripplo/tests` stubs
- **PostToolUse (Edit/Write)** — lints the DSL on `.ripplo/**` edits and flags remaining stubs on edits matching `watchPaths`
- **Stop** — lints, surfaces remaining stubs, runs changed tests, and **blocks on coverage drift**: user-facing changes with no corresponding `.ripplo/tests` update

All hook logic lives in the `ripplo` CLI (`ripplo hook <name>`) — no shell scripts, no `jq`, Windows-safe.

### Configuring watch paths

By default the plugin treats common web source globs as user-facing (`src/**`, `app/**`, `apps/**`, `pages/**`, `routes/**`, `components/**`) and ignores generated/vendor output. Override in `.ripplo/ripplo.ts`:

```ts
createRipplo(
  {
    // ...existing config
    watchPaths: ["app/frontend/**", "lib/controllers/**"],
    ignorePaths: ["**/*.gen.*", "**/vendor/**"],
  },
  { preconditions, observers, tests },
);
```

### Testing Scope

Scope is the agent's working memory for what user flows the current session should cover. It lives in the dev-session DB (no local file) and is mutated only via `npx ripplo scope add|link|remove`. Agent scope items must reference an existing test (stub or implemented); free-text intents come from the user via the dashboard, and the agent's job is to stub a matching test and `scope link` it.

The user sees live scope in Developer Mode → Testing Scope and can pause hooks entirely from the UI. Agents should consult the `/ripplo:scope` skill when planning work or when a drift nudge fires.

### Coverage drift escape hatch

If a change is genuinely test-exempt (pure refactor, infra, internal tooling), write `.ripplo/.local/drift-exempt`:

```
<sha from `ripplo hook coverage-nudge` error message>
<one-line reason>
```

The exemption auto-invalidates if the diff changes.

Your agent writes deterministic, parallelizable tests that verify your app works end-to-end. No flaky tests, no shared state, no ordering dependencies.

## Skills

| Skill                  | Description                                                          |
| ---------------------- | -------------------------------------------------------------------- |
| `/ripplo:setup`        | Wire the engine adapter into your app server                         |
| `/ripplo:explore`      | Crawl your codebase and generate test specs                          |
| `/ripplo:create`       | Create a new test spec                                               |
| `/ripplo:scope`        | Manage Testing Scope (visible to the user in Developer Mode)         |
| `/ripplo:run`          | Run tests in parallel                                                |
| `/ripplo:debug`        | Debug failures using DOM snapshots and network traces                |
| `/ripplo:flake-detect` | Reproduce a suspected flaky test under parallel load (use sparingly) |

## Prerequisites

Install and set up the [Ripplo CLI](https://www.npmjs.com/package/ripplo) first:

```sh
npx ripplo
```

This authenticates, scaffolds a `.ripplo/` directory, and starts the dev dashboard. Scaffolding also writes an initial `.ripplo/ripplo.lock` — a committed, generated artifact that the Ripplo server reads on push-webhook syncs. Keep it in sync with your `.ripplo/*.ts` via `npx ripplo compile` (or the pre-commit hook the `/ripplo:setup` skill installs).

## How It Works

Your agent uses these skills to read your codebase, discover testable user flows, and generate typed test specs — no manual test writing required. Each test defines its own preconditions, starting URL, and interaction steps using the `@ripplo/testing` DSL.

Learn more at [ripplo.ai](https://ripplo.ai).
