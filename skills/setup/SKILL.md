---
name: setup
description: "Initialize Ripplo from zero in a project: auth login → init → start the daemon → mount the engine adapter → first passing run. Use when a project has no `.ripplo/` directory yet, or when `npx ripplo doctor` reports the engine endpoint is missing."
---

# Ripplo Setup

Flow: **user logs in once → run `npx ripplo init` → start `npx ripplo daemon` in the background → mount the engine adapter → author and run a first workflow**.

Most users have never used Ripplo. Narrate in plain language and explain why before asking for input or editing files. Avoid internal terms ("engine", "adapter", "entity", "world", "lockfile") in user-facing questions until you've defined them. Orientation up front: "Ripplo runs end-to-end browser tests against your app. Setup will log you in, scaffold a `.ripplo/` folder for workflow definitions, add a small adapter to your backend so tests can seed data and verify results, and run a first test to confirm everything works."

**Already-set-up repos:** if `.ripplo/workflows/` exists, skip step 2 (init) and step 8 (first run), but still satisfy steps 1, 3, and 5. Run `npx ripplo doctor` first and fix each failing check using the matching step — a rejected token or missing daemon still needs fixing.

## 1. Authenticate

`npx ripplo auth status`. Valid session → step 2. Missing or rejected → drive the login yourself; never ask the user to run the CLI:

```sh
npx ripplo auth login   # background Bash process
```

It opens the browser, prints a verification URL + code, and polls until approved. Monitor the stdout for the URL and code, then tell the user: "I've opened your browser to sign in — approve the code shown (`<code>`), or visit `<url>` if it didn't open. I'll wait." On exit, verify with `npx ripplo auth status`.

## 2. Collect answers, run `npx ripplo init`

Fetch projects yourself — never ask the user to paste a project id:

```sh
npx ripplo projects list   # JSON: { "projects": [{ "id", "name" }] }
```

- **0 projects** — stop; the user must create one in the dashboard first.
- **1 project** — auto-select.
- **2+** — `AskUserQuestion` with project **names**, map the choice back to its id.

Then resolve the rest (detect first, confirm via `AskUserQuestion` in plain terms — "Where does your frontend run in dev?", "Does your backend run on the same port?"):

- **Env file** — the file the dev server already loads (Next.js: `.env.local`; Vite: `.env`/`.env.local` via `loadEnv`; Express/Fastify: `.env` via `dotenv`). Path is **relative to `.ripplo/`** — repo-root `.env.local` is `../.env.local`.
- **App URL** (`RIPPLO_APP_URL`) — where the frontend loads in a browser; the base URL Playwright navigates to. In a split setup this is the **frontend** dev server. Default `http://localhost:3000`.
- **Engine URL** (`RIPPLO_ENGINE_URL`, optional) — where Ripplo reaches the backend adapter. Defaults to `<app-url>/ripplo`; override when the backend runs on a different port (Vite on `:5173`, API on `:3000` → `http://localhost:3000/ripplo`).

```sh
npx ripplo init --project <id> --env ../.env.local --app-url <url> [--engine-url <url>]
```

Init scaffolds `.ripplo/`, writes `RIPPLO_APP_URL` / `RIPPLO_ENGINE_URL` / `RIPPLO_WEBHOOK_SECRET` / `ENABLE_RIPPLO_TESTING=true` to the env file, installs `@ripplo/testing` + `@ripplo/instrument`, compiles the lockfile, and ensures the Playwright browser. **Don't hand-write any of those files** — init owns scaffolding.

## 3. Start the daemon

`npx ripplo daemon` is the long-running local test executor; it must stay alive for the dev session. Spawn via `Bash` with `run_in_background`, `cwd` = the directory containing `.ripplo/` (workspace root in monorepos). Tell the user it runs their tests locally and to leave it running. The app dev server is a separate process — make sure it's also up. Steps 7–8 depend on the daemon.

## 4. Mount the engine adapter

`ENABLE_RIPPLO_TESTING=true` (written by init) is the kill switch — the adapter refuses to run unless it's `true`, so test routes can never reach production. Before editing, tell the user: "I'm adding a small route to your backend (at `/ripplo`, behind the `ENABLE_RIPPLO_TESTING` flag). Tests use it to seed data and read back state for verification."

The **engine funnel** maps each entity in `.ripplo/entities/` to a `seed` (create a row) and `read` (return this run's rows) impl against your DB. Create `<app>/src/test/engine.ts`:

```ts
import { createEngine } from "@ripplo/testing";
import ripplo from "../../../../.ripplo/index.js";
import { impls } from "./impls.js"; // per-entity { seed, read } — see /ripplo:create "Adding an entity"

export const engine = createEngine(ripplo, { entities: impls, singletons: {} }, teardown);
```

`impls` starts empty and grows one entry per entity — TS errors until every entity has one. `teardown` deletes a run's seeded rows by run id.

Mount it (Express; other frameworks adapt the engine's `setup`/`state`/`teardown` to their router):

```ts
import { createEngineHandler } from "@ripplo/testing/express";
import { engine } from "./test/engine.js";

app.use(
  "/ripplo",
  createEngineHandler({ enabled: process.env.ENABLE_RIPPLO_TESTING === "true", engine }),
);
```

**Bind `enabled` to the env flag — never hardcode `true`.** The mount path must match the `RIPPLO_ENGINE_URL` path.

### Preload `@ripplo/instrument`

Add the preload to the backend's dev script so runs capture backend spans alongside browser actions:

```sh
node --import @ripplo/instrument server.js
tsx watch --import @ripplo/instrument src/index.ts
NODE_OPTIONS="--import @ripplo/instrument" next dev
```

Frameworks with a register hook (Next.js `instrumentation.ts`) can call `register` from `@ripplo/instrument/register` instead. The preload is dormant when no daemon is running — safe to leave permanently. Restart the dev server after adding it.

## 5. Signal when your app is ready

Ripplo waits for your app to say it's interactive before it starts checking anything on a page. Without that signal it can only guess when the app has loaded, and a slow cold boot — especially with several runs going at once — eats the check budget, so tests time out on elements that were about to appear. Your app owns this signal.

Before editing, tell the user: "I'm adding one line so the test runner waits until your app has actually finished loading before it checks the page, instead of guessing."

Call `ready()` once the first real screen has rendered — not while a loading skeleton is up:

```ts
import { ready } from "@ripplo/testing";

ready(); // at your app's genuine "interactive" point
```

Put it at the app's true ready point for your framework:

- **TanStack Router / React Router** — after the first route resolves with its data: `router.subscribe("onResolved", () => ready())`.
- **Next.js** — in a root layout effect once the initial data has rendered.
- **Plain SPA** — right after the top-level data load settles and you render real content.

Gate the call behind the same build-time testing flag your app already uses (`VITE_ENABLE_RIPPLO_TESTING`, `NEXT_PUBLIC_ENABLE_RIPPLO_TESTING`, …) so it's a no-op in production. This is **required**: if `ready()` never fires within 30s of a page load, every run fails with `appNotReady`.

## 6. Install the pre-commit hook

```sh
#!/bin/sh
if git diff --cached --name-only | grep -q '^\.ripplo/.*\.ts$'; then
  npx ripplo compile --check || {
    echo "ripplo.lock is stale — run \`npx ripplo compile\` and stage the result."
    exit 1
  }
fi
```

With husky/lefthook/simple-git-hooks, gate the same check on staged `.ripplo/**/*.ts`.

## 7. Verify

`npx ripplo doctor` — resolve every issue before moving on. Key checks: dev server reachable at `RIPPLO_APP_URL`, dev session live. Briefly tell the user what doctor confirmed.

## 8. First workflow (first-time setup only)

Skip if `.ripplo/workflows/` already has workflows. Otherwise setup isn't complete until **one run passes** — the web onboarding gates its Continue button on a run with `status=completed` and `hasFailed=false`. Tell the user up front you'll write and run a tiny first workflow to unblock it.

- Hand off to `/ripplo:create` — it owns authoring and running.
- Pick a trivial smoke workflow (load the entry route, assert a top-level element). If the entry surface is non-obvious, ask via `AskUserQuestion`.
- `npx ripplo run <test-id>`. If it fails, debug via `.ripplo/debug/<runId>/behavior.jsonl` — don't leave the user staring at a red first run.

## Rules

- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true`.
- Every app must call `ready()` from `@ripplo/testing` when it's interactive — runs fail with `appNotReady` otherwise. Signal after real content renders, not on a loading skeleton, and gate it behind the build-time testing flag.
- Adapter mount path must match the `RIPPLO_ENGINE_URL` suffix — mismatches silently fail.
- The daemon runs from the directory containing `.ripplo/` — set Bash `cwd` accordingly in monorepos.
- **Worktrees are self-contained** (own DevSession, scope, debug artifacts), but env files don't carry over and dev-server ports collide between siblings. In a fresh worktree: copy the env file from main (or symlink a shared one), pick a distinct port, and update both `RIPPLO_APP_URL` and `RIPPLO_ENGINE_URL` to it. `npx ripplo doctor` flags missing env files.
