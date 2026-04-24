# Ripplo — Claude Code Plugin

**Ripplo closes the loop on full-stack app development.** When an agent (or human) ships a user-facing change, Ripplo ensures there is a deterministic, backend-aware test proving it works end-to-end — UI, API, database, async jobs. Tests are how you and the user agree on what success looks like: preconditions define the starting state, observers assert backend mutations, and coverage IDs ensure no interaction on the app's surface area ships unclaimed. When you stop, you have both the feature and the proof it works.

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

Your agent writes deterministic, parallelizable tests that verify your app's full stack — UI through backend state — works end-to-end. No flaky tests, no shared state, no ordering dependencies.

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

## What your agent does

Your agent uses these skills to map the app's user-facing surface area, define success criteria as typed test specs, and keep app code and tests in lockstep. Each test defines its own preconditions, starting URL, interaction steps, and backend observers using the `@ripplo/testing` DSL — no manual test writing required.

Learn more at [ripplo.ai](https://ripplo.ai).
