---
name: setup
description: "Initialize Ripplo from zero in a project: orchestrate `ripplo auth login` → `ripplo init` → start `ripplo daemon` as a background process → mount the engine adapter → hand off to `/ripplo:create` to author and run the user's first test so onboarding can advance. Use when a project has no `.ripplo/` directory yet, or when `ripplo doctor` reports the engine endpoint is missing."
---

# Ripplo Setup

Flow: **user logs in once → Claude runs `ripplo init` → Claude starts `ripplo daemon` as a background process → Claude mounts the engine adapter → Claude authors and runs a first test**.

## How to talk to the user

Most users have never used Ripplo before. As you move through these steps, narrate what's happening in plain language and explain _why_ before asking for input or making changes — don't just dump commands and jargon. A quick orientation up front helps:

> "Ripplo runs end-to-end browser tests against your app. Setup will: log you in, scaffold a `.ripplo/` folder for test definitions, add a small adapter to your backend so tests can set up data and check results, and run a first test to confirm everything works."

Avoid Ripplo-internal terms ("engine", "adapter", "executor", "entity", "world", "lockfile") in user-facing questions until you've explained them. When you must use one, define it the first time.

> **Already-set-up repos:** if `.ripplo/tests/` already exists, the project doesn't need scaffolding — but **still run step 1** (auth) and step 3 (start `ripplo daemon`) if they aren't satisfied. Skip step 2 (init) and step 7 (first passing run); the "first passing run" requirement only applies to genuine first-time setup, where the onboarding UI gates its "Continue" button on it.
>
> Run `npx ripplo doctor` first to see what's actually missing, and address each failing check using the matching step below. Don't bail out just because the repo looks "already set up" — a rejected token or missing daemon process still needs fixing.

## 1. Authenticate

Run `npx ripplo auth status`. If it reports a valid session, skip to step 2. If it reports **missing** or **rejected** (token expired/invalidated), drive a fresh login yourself — don't ask the user to run the CLI.

Start the device-code login as a background `Bash` process:

```sh
npx ripplo auth login
```

It opens the user's browser, prints a verification URL + code to stdout, then polls until approved. Use `Monitor` to read the verification URL and code from the process stdout, then tell the user in plain language: "I've opened your browser to sign in to Ripplo — approve the code shown there (`<code>`), or visit `<url>` if it didn't open. I'll wait." Don't ask the user to run any command themselves.

When the background process exits successfully, verify with `npx ripplo auth status` and continue.

## 2. Collect answers, run `ripplo init`

First, fetch the user's projects so you can resolve the project yourself — never ask the user to paste a project id:

```sh
npx ripplo projects list
```

Output is JSON: `{ "projects": [{ "id": "...", "name": "..." }] }`. Then:

- **0 projects** — stop and tell the user to create one in the Ripplo dashboard before re-running setup.
- **1 project** — auto-select; omit `--project` (init also auto-selects, but passing the id is fine).
- **2+ projects** — `AskUserQuestion` with the project **names** as options, then map the chosen name back to its id.

Then ask the user via `AskUserQuestion` for the remaining answers (never the project id):

- **Env file**: the file the user's dev server already loads at startup — Ripplo appends its env vars there. Detect this yourself before asking: Next.js loads `.env.local` automatically; Vite uses `loadEnv` (usually `.env` or `.env.local`); Express/Fastify usually `.env` via `dotenv`. Path is **relative to `.ripplo/`** — repo-root `.env.local` is `../.env.local`; monorepo `apps/server/.env` is `../apps/server/.env`. Confirm the detected path in plain terms rather than asking the user to choose a path cold.
- **App URL** (`RIPPLO_APP_URL`): where the user's frontend loads in a browser — the base URL Playwright navigates to. In a separate-frontend/backend setup, this is the **frontend** dev server (e.g. Vite on `:5173`, Next.js on `:3000`). Default `http://localhost:3000`.
- **Engine URL** (`RIPPLO_ENGINE_URL`, optional): where Ripplo reaches the backend adapter. Defaults to `<app-url>/ripplo` — correct when frontend and backend are the same server. **Override** when the backend runs on a different port (e.g. Vite frontend on `:5173`, API on `:3000` → engine URL is `http://localhost:3000/ripplo`).

When asking, explain in plain terms: "Where does your frontend run in dev?" and "Does your backend run on the same port, or a different one?" Use the answers to fill in the URLs yourself.

```sh
npx ripplo init --project <id> --env ../.env.local --app-url <url> [--engine-url <url>]
```

`--env` is **relative to `.ripplo/`** (so a repo-root `.env.local` is `../.env.local`).

Init scaffolds `.ripplo/{index.ts, tsconfig.json, project.json, entities/, singletons/, worlds/, tests/}`, writes `RIPPLO_APP_URL` / `RIPPLO_ENGINE_URL` / `RIPPLO_WEBHOOK_SECRET` / `ENABLE_RIPPLO_TESTING=true` to the chosen env file, installs `@ripplo/testing` + `@ripplo/instrument`, compiles the initial lockfile, and ensures the Playwright browser. **Don't hand-write any of those files** — init owns scaffolding.

## 3. Start `ripplo daemon` as a background process

`ripplo daemon` is the long-running process that executes tests in a local browser when you (or the dashboard) trigger a run. It must stay alive for the dev session. Spawn it via `Bash` with `run_in_background`, set `cwd` to the directory containing `.ripplo/` (workspace root in monorepos). Tell the user: "I'm starting `ripplo daemon` in the background — this runs your tests locally. Leave it running while you work." The user's app dev server is a separate process — make sure it's also running.

Steps 6–7 (`ripplo doctor`, the first run) depend on the daemon being live, so do this before moving on.

## 4. Mount the engine adapter

Init wrote `ENABLE_RIPPLO_TESTING=true` to the env file alongside the `RIPPLO_*` vars. This flag is the kill switch for the test integration on the user's backend — the adapter refuses to do anything unless it's `true`, so the test routes can never accidentally run in production. Tell the user: "Init added `ENABLE_RIPPLO_TESTING=true` to your env file — this turns on the test-only routes I'm about to add. It should only ever be `true` in dev."

Before editing, explain what you're about to do: "I'm adding a small route to your backend (mounted at `/ripplo` by default, behind the `ENABLE_RIPPLO_TESTING` flag). Tests use it to set up the data they need before running and to read back database state for verification — without your test code touching the database directly."

The **engine funnel** maps each entity in `.ripplo/entities/` to a `seed` (create a row) and `read` (return this run's rows) implementation against your DB. Create `<app>/src/test/engine.ts`:

```ts
import { createEngine } from "@ripplo/testing";
import ripplo from "../../../../.ripplo/index.js";
import { impls } from "./impls.js"; // per-entity { seed, read } — see /ripplo:create "Adding an entity"

export const engine = createEngine(ripplo, { entities: impls, singletons: {} }, teardown);
```

`impls` starts empty and grows one entry per entity as tests are written — TS errors until every entity has an impl. `teardown` deletes a run's seeded rows by run id.

Then mount the adapter. Express:

```ts
import { createEngineHandler } from "@ripplo/testing/express";
import { engine } from "./test/engine.js";

app.use(
  "/ripplo",
  createEngineHandler({ enabled: process.env.ENABLE_RIPPLO_TESTING === "true", engine }),
);
```

**Bind `enabled` to the env flag — never hardcode `true`.** The mount path is the `RIPPLO_ENGINE_URL` path — when `RIPPLO_ENGINE_URL` ends in `/ripplo`, mount at `/ripplo`. For non-Express frameworks, adapt the engine's `setup`/`state`/`teardown` to your router (the Express adapter is the reference).

### Preload `@ripplo/instrument` in the dev server

Add the `@ripplo/instrument` preload (installed by init) to the backend's dev script so test runs capture backend spans alongside browser actions:

```sh
node --import @ripplo/instrument server.js
tsx watch --import @ripplo/instrument src/index.ts
NODE_OPTIONS="--import @ripplo/instrument" next dev
```

Frameworks with a register hook (Next.js `instrumentation.ts`) can `import { register } from "@ripplo/instrument/register"` and call it instead. The preload is dormant when no daemon is running — safe to leave in the dev script permanently. Tell the user: "I'm adding a one-flag preload to your dev script — it streams your backend's spans into Ripplo's test traces so failures show what the server did, not just what the browser saw." Restart the dev server after adding it.

## 5. Install the pre-commit hook

```sh
#!/bin/sh
if git diff --cached --name-only | grep -q '^\.ripplo/.*\.ts$'; then
  npx ripplo compile --check || {
    echo "ripplo.lock is stale — run \`npx ripplo compile\` and stage the result."
    exit 1
  }
fi
```

With husky/lefthook/simple-git-hooks, gate the same `npx ripplo compile --check` on staged `.ripplo/**/*.ts`.

## 6. Verify install

Run `npx ripplo doctor` and resolve every issue before moving on. The two key checks: the app's dev server is reachable at `RIPPLO_APP_URL`, and the dev session is live (`ripplo daemon` running). If something's red, fix it — don't continue to step 7 with warnings outstanding. Briefly tell the user what doctor confirmed.

## 7. Author and run a first test (first-time setup only)

**Skip this step if `.ripplo/tests/` already contains tests.**

For a true first-time setup (no existing tests), setup isn't complete until the user has **at least one passing run**. The web onboarding flow keeps the user on a "Setting things up…" screen with the Continue button disabled until a run reports `status=completed` and `hasFailed=false`. Tell the user up front: "I'll write a tiny first test and run it — that unblocks the Continue button in the dashboard."

- Hand off to **`/ripplo:create`** — it owns test authoring + running.
- Pick a trivial smoke test as the first one (e.g. load the app's entry route and assert a top-level element renders) so it passes without deep app-specific knowledge. If the entry surface is non-obvious, ask the user via `AskUserQuestion`.
- Run it with `npx ripplo run <test-id>` (the slug from `ripplo compile` output; the quoted intent string also works). If it fails, debug using `.ripplo/debug/<runId>/behavior.jsonl` before declaring setup done — don't leave the user staring at a red first run.

## Rules

- First-time setup isn't done until one test has passed — the onboarding "Continue" button waits on this signal. If `.ripplo/tests/` already has tests, step 7 doesn't apply.
- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true`.
- Adapter mount path must match the `RIPPLO_ENGINE_URL` suffix — mismatches silently fail.
- `ripplo daemon` runs from the directory containing `.ripplo/` — set the Bash `cwd` accordingly in monorepos.
- **Worktrees are self-contained** (own DevSession, scope, debug artifacts), but env files don't carry over (typically gitignored) and dev-server ports collide between siblings. In a fresh worktree: copy the env file from main (or symlink a shared one), pick a distinct dev-server port, and **update both `RIPPLO_APP_URL` and `RIPPLO_ENGINE_URL` in that env file to point at the new port**. `ripplo doctor` flags missing env files.
