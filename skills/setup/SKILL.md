---
name: setup
description: "Initialize Ripplo from zero in a project: orchestrate `ripplo auth login` → `ripplo init` → start `ripplo watch` as a background process → mount the engine adapter → hand off to `/ripplo:create` to author and run the user's first test so onboarding can advance. Use when a project has no `.ripplo/` directory yet, or when `ripplo doctor` reports the engine endpoint is missing."
---

# Ripplo Setup

Flow: **user logs in once → Claude runs `ripplo init` → Claude starts `ripplo watch` as a background process → Claude mounts the engine adapter → Claude authors and runs a first test**.

## How to talk to the user

Most users have never used Ripplo before. As you move through these steps, narrate what's happening in plain language and explain _why_ before asking for input or making changes — don't just dump commands and jargon. A quick orientation up front helps:

> "Ripplo runs end-to-end browser tests against your app. Setup will: log you in, scaffold a `.ripplo/` folder for test definitions, add a small adapter to your backend so tests can set up data and check results, and run a first test to confirm everything works."

Avoid Ripplo-internal terms ("engine", "adapter", "executor", "preconditions", "observers", "lockfile") in user-facing questions until you've explained them. When you must use one, define it the first time.

> **First-time onboarding only:** if `.ripplo/tests/` already has tests (i.e. this is a re-run of setup, a worktree, or a re-mount after the adapter was removed), stop after step 7 — the "first passing run" requirement in step 8 only applies the first time a project is being set up. The web onboarding UI blocks its "Continue" button on a passing run, so skipping step 8 during true first-time setup leaves the user stuck.

## 1. User authenticates

```sh
npx ripplo auth login
```

Tell the user: "This opens a browser so you can log into Ripplo — only you can do this part." Then wait. Verify with `npx ripplo auth status` before continuing.

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

- **Env file**: the file the user's dev server already loads at startup — Ripplo will append three new env vars to it (the URLs above plus a webhook secret). Detect this yourself before asking: Next.js loads `.env.local` automatically; Vite uses `loadEnv` (usually `.env` or `.env.local`); Express/Fastify usually `.env` via `dotenv`. Path is **relative to `.ripplo/`** — repo-root `.env.local` is `../.env.local`; monorepo `apps/server/.env` is `../apps/server/.env`. Confirm the detected path with the user in plain terms ("Your dev server reads `.env.local` — I'll add Ripplo's vars there. OK?") rather than asking them to choose a path cold.
- **App URL** (`RIPPLO_APP_URL`): where the user's frontend loads in a browser — the base URL Playwright navigates to. In a separate-frontend/backend setup, this is the **frontend** dev server (e.g. Vite on `:5173`, Next.js on `:3000`). Default `http://localhost:3000`.
- **Engine URL** (`RIPPLO_ENGINE_URL`, optional): where Ripplo reaches the backend adapter (preconditions, observers, webhooks). Defaults to `<app-url>/ripplo` — correct when frontend and backend are the same server. **Override** when the backend runs on a different port (e.g. Vite frontend on `:5173`, API on `:3000` → engine URL is `http://localhost:3000/ripplo`) or when the adapter mounts at a different prefix.

When asking the user, explain in plain terms — they're new to Ripplo and won't know what an "adapter" or "engine" is. Phrase it like: "Where does your frontend run in dev?" and "Does your backend run on the same port, or a different one?" Use the answers to fill in the URLs yourself.

```sh
npx ripplo init --project <id> --env ../.env.local --app-url <url> [--engine-url <url>]
```

`--env` is **relative to `.ripplo/`** (so a repo-root `.env.local` is `../.env.local`).

Init scaffolds `.ripplo/{index.ts, tsconfig.json, project.json, preconditions/, observers/, tests/}`, writes `RIPPLO_APP_URL` / `RIPPLO_ENGINE_URL` / `RIPPLO_WEBHOOK_SECRET` to the chosen env file, installs `@ripplo/testing`, compiles the initial lockfile, and ensures the Playwright browser. **Don't hand-write any of those files** — init owns scaffolding.

## 3. Start `ripplo watch` as a background process

`ripplo watch` is the long-running process that actually executes tests in a local browser when you (or the dashboard) trigger a run. It must stay alive for the duration of the dev session. Spawn it via `Bash` with `run_in_background`, set `cwd` to the directory containing `.ripplo/` (workspace root in monorepos). Tell the user: "I'm starting `ripplo watch` in the background — this is what runs your tests locally. Leave it running while you work." The user's app dev server is a separate process — make sure it's also running (start it the same way if it isn't, or skip if it's already up).

Steps 7–8 (`ripplo doctor`, the first run) depend on watch being live, so do this before moving on.

## 4. Append `ENABLE_RIPPLO_TESTING=true` to the env file

This flag is the kill switch for the test integration on the user's backend — the adapter (next step) refuses to do anything unless `ENABLE_RIPPLO_TESTING=true`, so the test routes can never accidentally run in production. Init wrote the three `RIPPLO_*` vars; append this one yourself and tell the user what it does ("This flag turns on test-only routes in your backend. It should only ever be `true` in dev — never set it in prod.").

## 5. Mount the engine adapter

Before editing, explain to the user what you're about to do: "I'm adding a small route to your backend (mounted at `/ripplo` by default, behind the `ENABLE_RIPPLO_TESTING` flag from step 4). Tests use it to set up data they need before running (preconditions) and to verify backend state after running (observers) — without your test code having to touch the database directly."

Detect the framework from `package.json` and use the matching adapter from `packages/testing/README.md` ("Server adapters"): `@ripplo/testing/{express,fastify,nextjs,hono,koa,nestjs,elysia}`, or the raw engine for unsupported frameworks.

Create `<app>/src/test/engine.ts` — the implementation funnel:

```ts
import { createEngine } from "@ripplo/testing";
import ripplo from "../../../../.ripplo/index.js";

export const engine = createEngine(ripplo, { preconditions: {}, observers: {} });
```

Then mount the adapter. Express example (other frameworks in the testing README):

```ts
import { createExpressHandler } from "@ripplo/testing/express";
import { engine } from "./test/engine.js";

app.use(
  "/ripplo",
  createExpressHandler({
    enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
    engine,
  }),
);
```

**Bind `enabled` to the env flag — never hardcode `true`.** The mount path **must match** the `RIPPLO_ENGINE_URL` suffix.

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

With husky/lefthook/simple-git-hooks, gate the same `npx ripplo compile --check` on staged `.ripplo/**/*.ts`.

## 7. Verify install

Run `npx ripplo doctor` and resolve every issue before moving on. The two key checks: the app's dev server is reachable at `RIPPLO_APP_URL`, and the dev session is live (`ripplo watch` running). If something's red, fix it (or restart the relevant process) — don't continue to step 8 with warnings outstanding. Briefly tell the user what doctor confirmed ("Your dev server and the local executor are both up — Ripplo can reach them.") so they know setup is on track.

## 8. Author and run a first test (first-time setup only)

**Skip this step if `.ripplo/tests/` already contains tests** — re-runs of setup, worktrees, and adapter remounts don't need to produce a fresh passing run, and the user isn't sitting in the onboarding UI.

For a true first-time setup (no existing tests), setup isn't complete until the user has **at least one passing run**. The web onboarding flow keeps the user parked on a "Setting things up…" screen with the Continue button disabled until a run reports `status=completed` and `hasFailed=false`. Tell the user this up front: "I'll write a tiny first test and run it — that unblocks the Continue button in the dashboard."

- Hand off to the **`/ripplo:create`** skill — it owns test authoring + running and is what produces an executable test. (`/ripplo:explore` only stubs `.notImplemented()` tests, so it cannot satisfy the onboarding gate.)
- Pick a trivial smoke test as the first one (e.g. load the app's entry route and assert a top-level element renders) so it passes without deep app-specific knowledge. If the entry surface is non-obvious, ask the user via `AskUserQuestion`.
- Run it with `npx ripplo run <name>`. If it fails, debug using artifacts under `.ripplo/debug/<runId>/` before declaring setup done — do not leave the user staring at a red first run.

## Rules

- First-time setup isn't done until one test has passed — the onboarding "Continue" button waits on this signal. If `.ripplo/tests/` already has tests, step 8 doesn't apply and stopping at step 7 is correct.
- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true`.
- Adapter mount path must match `RIPPLO_ENGINE_URL` suffix — mismatches silently fail.
- Prefer a first-class adapter; raw engine only for unsupported frameworks.
- `ripplo watch` runs from the directory containing `.ripplo/` — set the Bash `cwd` accordingly in monorepos.
- **Worktrees are self-contained** (own DevSession, scope, debug artifacts), but env files don't carry over (they're typically gitignored) and dev-server ports collide between siblings. In a fresh worktree: copy the env file from main (or symlink to a shared one), pick a distinct dev-server port for this worktree, and **update both `RIPPLO_APP_URL` and `RIPPLO_ENGINE_URL` in that env file to point at the new port** (e.g. `RIPPLO_APP_URL=http://localhost:3001`, `RIPPLO_ENGINE_URL=http://localhost:3001/ripplo`). `ripplo doctor` flags missing env files.
