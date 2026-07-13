---
name: setup
description: "Initialize Ripplo from zero: auth login → init → start the daemon → mount the engine adapter → first passing run. Use when a project has no `.ripplo/` yet, or when `npx ripplo doctor` reports the engine endpoint is missing."
---

# Ripplo Setup

Flow: **log in → `npx ripplo init` → start `npx ripplo daemon` → mount the engine adapter → author + run a first workflow**.

Most users are new. Narrate in plain language; define internal terms before using them. Orientation: "Ripplo runs end-to-end browser tests. Setup logs you in, scaffolds `.ripplo/`, adds a small backend adapter so tests can seed data and verify results, and runs a first test."

**Already set up** (`.ripplo/workflows/` exists): skip steps 2 and 8, still do 1, 3, 5. Run `npx ripplo doctor` first; fix each failing check via its step.

## 1. Authenticate

`npx ripplo auth status`. Valid → step 2. Missing/rejected → drive login yourself (never ask the user to run the CLI):

```sh
npx ripplo auth login   # background Bash process
```

Monitor stdout for the URL + code, then tell the user: "I've opened your browser — approve the code (`<code>`), or visit `<url>`. I'll wait." Verify with `npx ripplo auth status`.

## 2. Collect answers, run `npx ripplo init`

Fetch projects yourself — never ask for a project id:

```sh
npx ripplo projects list   # { "projects": [{ "id", "name" }] }
```

- **0 projects** — `AskUserQuestion` for a name (suggest the repo folder name), `npx ripplo projects create <name>`, use the returned id. Multiple orgs → re-run with `--org <id>`.
- **1+ projects** — `AskUserQuestion` with project **names** + "create new", map choice to id. Never auto-select.

Resolve the rest (detect, then confirm via `AskUserQuestion`):

- **Env file** — the file the dev server loads (Next.js `.env.local`; Vite `.env`/`.env.local`; Express `.env`). Path is **relative to `.ripplo/`** — repo-root `.env.local` is `../.env.local`.
- **App URL** (`RIPPLO_APP_URL`) — where the frontend loads in a browser. In a split setup, the frontend dev server. Default `http://localhost:3000`.
- **Engine URL** (`RIPPLO_ENGINE_URL`, optional) — where Ripplo reaches the backend adapter. Defaults to `<app-url>/ripplo`; override when the backend runs on a different port.

```sh
npx ripplo init --project <id> --env ../.env.local --app-url <url> [--engine-url <url>]
```

Init scaffolds `.ripplo/`, writes env vars (`RIPPLO_APP_URL`, `RIPPLO_ENGINE_URL`, `RIPPLO_WEBHOOK_SECRET`, `ENABLE_RIPPLO_TESTING=true`), installs `@ripplo/testing` + `@ripplo/instrument`, compiles the lockfile, ensures the Playwright browser. **Don't hand-write any of those files.**

## 3. Start the daemon

`npx ripplo daemon` is the long-running local executor. Spawn via `Bash` `run_in_background`, `cwd` = directory containing `.ripplo/`. Tell the user to leave it running. The app dev server is a separate process — ensure it's up too.

## 4. Mount the engine adapter

`ENABLE_RIPPLO_TESTING=true` is the kill switch — the adapter refuses to run unless it's `true`. Tell the user: "I'm adding a route at `/ripplo`, behind `ENABLE_RIPPLO_TESTING`, for tests to seed data and read back state."

The **engine funnel** maps each entity to `seed`/`read` impls. Create `<app>/src/test/engine.ts`:

```ts
import { createEngine } from "@ripplo/testing";
import ripplo from "../../../../.ripplo/index.js";
import { impls } from "./impls.js";
import { signIn, currentActor } from "./auth.js";

export const engine = createEngine(
  ripplo,
  { entities: impls, signIn, currentActor, singletons: {} },
  teardown,
);
```

`impls` grows one entry per entity (TS errors until complete). `signIn` needs one impl per `principal: true` entity; `currentActor` is one global impl; `teardown` deletes a run's seeded rows by run id.

Mount the adapter for your host at a path matching `RIPPLO_ENGINE_URL`. Same contract behind each subpath: `@ripplo/testing/{express,fastify,koa,nestjs,nextjs,hono,elysia,vite}`. Import the named export from your framework's subpath (check its `.d.ts`). Express (Fastify/Koa/Nest/Hono/Elysia same shape):

```ts
import { createEngineHandler } from "@ripplo/testing/express";
import { engine } from "./test/engine.js";

app.use(
  "/ripplo",
  createEngineHandler({ enabled: process.env.ENABLE_RIPPLO_TESTING === "true", engine }),
);
```

**Bind `enabled` to the env flag — never hardcode `true`.** Mount path must match `RIPPLO_ENGINE_URL`.

**Client-only Vite SPA (no backend)?** Mount on the Vite dev server; impls run server-side in the Vite process:

```ts
// vite.config.ts
import { ripploPlugin } from "@ripplo/testing/vite";
import { engine } from "./src/test/engine";

export default defineConfig({
  plugins: [react(), ripploPlugin({ engine, path: "/ripplo" })],
});
```

The plugin loads your env file, gates on `ENABLE_RIPPLO_TESTING`, reads `RIPPLO_WEBHOOK_SECRET` — pass only `engine` (+ optional `path`). `RIPPLO_ENGINE_URL` is `<app-url>/ripplo`.

`@ripplo/instrument` is a **server-side** span preload — skip for a client-only app. Browser-side `ready()` is still required (step 5).

### Seeding a signed-in session

Auth is its own contract — `seed` creates the row, never a session. Two impls on a `principal: true` entity (usually `user`):

- **`signIn(row) => Session`** — one per principal. Mints a browser session (`{ cookies, origins }`, Playwright storage-state shape). Called when a `given` or mid-run `actor.set` targets that principal.
- **`currentActor(session) => id | null`** — one global. Resolves live cookies to the signed-in id (or `null`). Ripplo calls it every frame — read fresh, never cache.

Checklist, reading the app's own auth code:

1. **Find where the app verifies a session** (`getUser`, `auth()`, session middleware). `signIn` produces what it reads.
2. **Token or session row?** JWT-cookie apps → mint a token with the app's signing secret. Session-table apps → insert a session row, set its id as the cookie.
3. **Exact cookie names + attributes.** Copy from app config (NextAuth differs with/without HTTPS) — a wrong name fails silently.
4. **Identity matching.** The verifier's claim (`token.sub`, `session.userId`) must equal the seeded user's id; `currentActor` returns that same id.
5. **Guards on a fresh session** (MFA, email verification, onboarding, feature gates) — seed a state that passes every one.
6. **Verify seeded roles/permissions against the real database** — mismatches show as flaky 403s, not clear failures. Query the actual rows.

**Auth in localStorage, not cookies?** Ripplo captures cookies every frame; a localStorage-only token gives an empty session and every run fails with `signed-in actor showed ∅ but the test expected "<id>"`. Mirror the id into a cookie, gated by the flag:

```ts
// where your app learns who is signed in, gated by the flag
if (import.meta.env.VITE_ENABLE_RIPPLO_TESTING === "true") {
  document.cookie = userId
    ? `ripplo-actor=${userId}; path=/; SameSite=Lax`
    : "ripplo-actor=; path=/; Max-Age=0";
}
```

Then `signIn` sets the same cookie; `currentActor` reads `ripplo-actor` back. Only the id travels — real auth stays in localStorage.

Add the preload to the backend dev script (skip for client-only):

```sh
node --import @ripplo/instrument server.js
tsx watch --import @ripplo/instrument src/index.ts
NODE_OPTIONS="--import @ripplo/instrument" next dev
```

Frameworks with a register hook (Next.js `instrumentation.ts`) can call `register` from `@ripplo/instrument/register`. Restart the dev server after adding it.

## 5. Signal when your app is ready

Ripplo waits for your app to say it's interactive. Call `ready()` once the first real screen has rendered — not on a loading skeleton:

```ts
import { ready } from "@ripplo/testing";

ready();
```

- **TanStack/React Router** — after the first route resolves: `router.subscribe("onResolved", () => ready())`.
- **Next.js** — in `instrumentation-client.ts` (not a layout effect/client component — those don't fire behind a tunnel).
- **Plain SPA** — after the top-level data load settles.

Gate behind the build-time testing flag (`VITE_ENABLE_RIPPLO_TESTING`, `NEXT_PUBLIC_ENABLE_RIPPLO_TESTING`, …). **Required**: no `ready()` within 30s → every run fails with `appNotReady`.

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

`npx ripplo doctor` — resolve every issue. Key checks: dev server reachable at `RIPPLO_APP_URL`, dev session live.

## 8. First workflow (first-time only)

Skip if `.ripplo/workflows/` has workflows. Otherwise one run must pass — web onboarding gates Continue on a run with `status=completed`, `hasFailed=false`.

- Hand off to `/ripplo:create`.
- Pick a trivial smoke workflow (load the entry route, assert a top-level element). Non-obvious entry → `AskUserQuestion`.
- `npx ripplo run <workflow-slug>[/<test-slug>]`. Fails → debug via `.ripplo/debug/<runId>/behavior.jsonl`.

A green run auto-enables the background explorer (third gate) — it walks composed paths and files findings as tasks. Triage via `/ripplo:tasks`.

## Rules

- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true` — bind to the env flag.
- Every app must call `ready()` when interactive (else `appNotReady`); after real content, gated by the build-time flag.
- Adapter mount path must match the `RIPPLO_ENGINE_URL` suffix.
- Daemon runs from the directory containing `.ripplo/` — set Bash `cwd` accordingly.
- **Worktrees:** env files don't carry over, ports collide. Copy the env file from main, pick a distinct port, update `RIPPLO_APP_URL` + `RIPPLO_ENGINE_URL`.
