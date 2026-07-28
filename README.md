# Ripplo — Claude Code Plugin

Validation-loop hooks that keep your agent's tests in step with the code it ships. Part of
[Ripplo](https://ripplo.ai) — typed end-to-end tests over the application’s observable state.

## Install

One command installs the plugin and opens a guided setup session in Claude Code:

```sh
npx ripplo setup
```

The session signs you in, creates your project, runs `npx ripplo init` (scaffolds `.ripplo/`, writes
`RIPPLO_*` env vars, and installs the version-matched Ripplo packages plus Zod), starts
`npx ripplo daemon` as a background process, and connects the state sources your app uses.

Installing by hand instead: `/plugin marketplace add ripplo/claude-plugin`, `/plugin install ripplo`, then `/ripplo:setup`.

## What the hooks do

Four hooks wire into the agent's workflow so tests are load-bearing, not advisory.

- **UserPromptSubmit** nudges when user-facing code has drifted from `.ripplo/workflows` and surfaces the flows in scope during plan mode.
- **PreToolUse / ExitPlanMode** blocks plan exit if the plan touches user-facing code but no matching `.ripplo/workflows` flow is planned.
- **PostToolUse (Edit/Write)** lints the DSL on `.ripplo/**` edits and flags user-facing edits with no matching workflow.
- **Stop** lints, runs scoped and changed tests, and blocks on drift — user-facing changes without a matching `.ripplo/workflows` update.

The plugin treats `src/**`, `app/**`, `apps/**`, `pages/**`, `routes/**`, and `components/**` as user-facing, and ignores generated and vendor output.

## What the agent authors

Ripplo workflows are models of critical user journeys, not scripts for fixed fixtures.

- One root Zod schema defines observable application state.
- Each workflow starts from the widest state constraints compatible with its full user journey.
- The solver synthesizes concrete starting state for each reachable named branch.
- Generated values flow through state handles into URLs, locators, inputs, and effects.
- Exact strings and numbers are reserved for values that genuinely drive behavior.
- Every application-state change is declared. Changes outside those effects are frame violations.
- Every declared effect must be provably changing from the state known at that step.

`/ripplo:discover` identifies journeys and their broad state space. `/ripplo:create` enforces the
authoring model and ends with a generality audit.

## Application integration

The root state schema may contain one HTTP source, one browser source, or both.

- HTTP state uses a server-side source engine mounted through the app framework adapter.
- Signed-in journeys use a separate authentication engine attached to an HTTP record collection.
- Browser state uses the same source-engine contract and is passed to `connect(engine)` before the
  app renders.
- Apps without modeled browser state still call `connect()` before render.
- The returned connection's `ready()` method is called only after the current page is interactive.
  It reports readiness and does not set up state.

Ripplo sets up HTTP state, signs in, and then sets up browser state. Browser setup may depend on
server-created records. The reverse dependency fails compilation. `/ripplo:setup` contains the
framework-specific wiring and lifecycle details.

## Skills

| Skill              | Description                                                    |
| ------------------ | -------------------------------------------------------------- |
| `/ripplo:setup`    | One-time onboarding: sign in, scaffold, connect sources, first run |
| `/ripplo:start`    | Bring up the dev server + daemon for the dev session           |
| `/ripplo:discover` | Map critical journeys and the state each journey depends on     |
| `/ripplo:create`   | Author a wide, complete model of one critical user journey      |
| `/ripplo:run`      | Run tests, diagnose failures, manage Testing Scope, file bugs  |
| `/ripplo:tasks`    | Pick up tasks and explorer findings, prove the fix with a run  |

## Testing Scope

Scope is the agent's working memory for what user flows the current session is on the hook for. It lives in the dev-session DB (no local file) and is mutated only via `npx ripplo scope add|link|remove`. Agent scope items must reference an existing workflow (stub or implemented); free-text intents come from the user via the dashboard, and the agent's job is to stub a matching workflow and `scope link` it. The user sees live scope in Developer Mode → Testing Scope and can pause hooks entirely from there.

## Lockfile

`npx ripplo init` writes the initial `.ripplo/ripplo.lock`. Commit it. The Ripplo server reads it on
every push webhook. Keep it fresh with `npx ripplo compile`, or rely on the pre-commit hook
`/ripplo:setup` installs.
