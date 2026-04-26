---
name: setup
description: "Initialize Ripplo from zero in a project: orchestrate `ripplo auth login` → `ripplo init` → start `ripplo watch` as a background process → mount the engine adapter → hand off to `/ripplo:create` to author and run the user's first test so onboarding can advance. Use when a project has no `.ripplo/` directory yet, or when `ripplo doctor` reports the engine endpoint is missing."
---

# Ripplo Setup

Flow: **user logs in once → Claude runs `ripplo init` → Claude starts `ripplo watch` as a background process → Claude mounts the engine adapter → Claude authors and runs a first test**.

> **First-time onboarding only:** if `.ripplo/tests/` already has tests (i.e. this is a re-run of setup, a worktree, or a re-mount after the adapter was removed), stop after step 7 — the "first passing run" requirement in step 8 only applies the first time a project is being set up. The web onboarding UI blocks its "Continue" button on a passing run, so skipping step 8 during true first-time setup leaves the user stuck.

## 1. User authenticates

```sh
npx ripplo auth login
```

Device-code flow opens a browser; the human has to do this. Verify with `npx ripplo auth status` before continuing.

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

- **Env file**: which file the host app's dev server loads. Path is **relative to `.ripplo/`** — repo-root `.env.local` is `../.env.local`; monorepo `apps/server/.env` is `../apps/server/.env`. Next.js loads `.env.local` automatically; Vite needs `loadEnv`; Express usually `.env` via `dotenv`. Default `../.env.local`.
- **App URL**: dev server URL. Default `http://localhost:3000`.
- **Engine URL** (optional): defaults to `<app-url>/ripplo`. Override when the adapter mounts at a different prefix, or when the backend runs on a different port than the frontend (e.g. Vite frontend on `:5173`, API on `:3000` → `RIPPLO_ENGINE_URL=http://localhost:3000/ripplo`).

```sh
npx ripplo init --project <id> --env-file ../.env.local --app-url <url> [--engine-url <url>]
```

`--env-file` is **relative to `.ripplo/`** (so a repo-root `.env.local` is `../.env.local`).

Init scaffolds `.ripplo/{index.ts, tsconfig.json, project.json, preconditions/, observers/, tests/}`, writes `RIPPLO_APP_URL` / `RIPPLO_ENGINE_URL` / `RIPPLO_WEBHOOK_SECRET` to the chosen env file, installs `@ripplo/testing`, compiles the initial lockfile, and ensures the Playwright browser. **Don't hand-write any of those files** — init owns scaffolding.

## 3. Start `ripplo watch` as a background process

`ripplo watch` is the local executor and must be running for the dev session to be live. Spawn it via `Bash` with `run_in_background`, set `cwd` to the directory containing `.ripplo/` (use the workspace root in monorepos). The user's app dev server is a separate process — make sure it's also running (start it the same way if it isn't, or skip if the user already has it up).

Steps 7–8 (`ripplo doctor`, the first run) depend on watch being live, so do this before moving on.

## 4. Append `ENABLE_RIPPLO_TESTING=true` to the env file

The adapter is gated on this flag so it can't ship to prod. Init wrote the three `RIPPLO_*` vars; append the gate.

## 5. Mount the engine adapter

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

`npx ripplo doctor` — resolve every issue. Confirm both checks are green: the app's dev server is reachable, and the dev session is live (`ripplo watch` running).

## 8. Author and run a first test (first-time setup only)

**Skip this step if `.ripplo/tests/` already contains tests** — re-runs of setup, worktrees, and adapter remounts don't need to produce a fresh passing run, and the user isn't sitting in the onboarding UI.

For a true first-time setup (no existing tests), setup isn't complete until the user has **at least one passing run**. The web onboarding flow keeps the user parked on a "Setting things up…" screen with the Continue button disabled until a run reports `status=completed` and `hasFailed=false`.

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
