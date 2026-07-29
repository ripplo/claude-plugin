---
name: setup
description: "Initialize Ripplo from zero: sign in → init → start the daemon → connect state sources and browser readiness → first passing run. Use when a project has no `.ripplo/` yet, or when `npx ripplo doctor` reports an integration is missing."
---

# Ripplo Setup

Flow: **log in → `npx ripplo init` → start `npx ripplo daemon` → connect state sources and browser readiness → author + run a first workflow**.

Most users are new. Narrate in plain language and define internal terms before using them.
Orientation: "Ripplo runs end-to-end browser tests against one typed model of application state.
Setup scaffolds that model, connects each source of truth, teaches Ripplo how to sign in when
needed, and runs a first test."

**Already set up** (`.ripplo/workflows/` exists): run `npx ripplo doctor` first. Skip initialization
and first-workflow authoring. Revisit the server or browser integration only when its check fails or
the state schema now declares that source.

## 1. Sign in to Ripplo

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

Init scaffolds `.ripplo/`, writes env vars (`RIPPLO_APP_URL`, `RIPPLO_ENGINE_URL`,
`RIPPLO_WEBHOOK_SECRET`, `ENABLE_RIPPLO_TESTING=true`), installs the version-matched Ripplo
packages and Zod, compiles the lockfile, and ensures the Playwright browser. Let init create the
scaffold and those four settings. Step 5 explains the one additional public browser alias some
frameworks need.

Init installs Zod. Import `z` from `zod/v4` in state schemas. `@ripplo/testing` uses the same Zod
version internally but does not re-export it. If the app already declares Zod 3, init preserves it,
installs Zod 4 as `zod4`, and generates `import { z } from "zod4"` instead.

## 3. Start the daemon

`npx ripplo daemon` is the long-running local executor. Spawn via `Bash` `run_in_background`, `cwd` = directory containing `.ripplo/`. Tell the user to leave it running. The app dev server is a separate process — ensure it's up too.

## 4. Connect server-owned state and sign-in

Read `.ripplo/state.ts` before adding an adapter. The root schema supports at most one
`source.http(...)` and one `source.browser(...)`:

Init's empty `app` HTTP source is only a compileable placeholder. Replace it with the app's actual
HTTP source, browser source, or both before writing an adapter. Do not implement an engine for the
empty placeholder.

| Model capability | Integration |
| --- | --- |
| HTTP-owned state | Create one HTTP source engine and mount its server adapter |
| Signed-in journeys | Create one authentication engine per supported HTTP record collection and mount one authentication adapter |
| Browser-owned state | Create one browser source engine and pass it to `connect(engine)` in step 5 |
| No browser-owned state | Call `connect()` without an engine in step 5 |
| Browser readiness | Call the returned connection's `ready()` after the page is interactive |

Do not add an HTTP source merely to hold browser state. If the schema has no HTTP source and
workflows stay signed out, skip the server adapters and continue to step 5.
For a browser-heavy app with signed-in journeys, keep the actor records in the HTTP source and the
rest of the model in the browser source. The server then implements actor setup, actor reads,
teardown, and sign-in without owning unrelated application state.

`ENABLE_RIPPLO_TESTING=true` is the server kill switch. Tell the user what you are adding:
"I'm adding a signed route at `/ripplo` so Ripplo can read and set up server-owned state." Create
the HTTP engine from the HTTP source handle. It reads the complete source fragment. Its setup shape
is derived exhaustively from the Zod schema:

```ts
import { createStateSourceEngine } from "@ripplo/testing/engine";
import { state } from "../../../../.ripplo/state.js";

export const coreEngine = createStateSourceEngine(state.core, {
  read: ({ runId }) => readCoreState(runId),
  setup: {
    records: {
      projects: ({ input, runId }) => insertProject({ input, runId }),
      users: ({ input, runId }) => insertUser({ input, runId }),
    },
    fields: ({ input, runId }) => setCoreFields({ input, runId }),
  },
  teardown: ({ runId }) => clearRunData(runId),
});
```

TypeScript requires every setup implementation implied by the schema. A read-only source provides
only `read`. A setup-capable source provides `setup` and `teardown`. `setup.fields` returns the
complete fixed state it materialized. Each `setup.records` callback returns the complete row it
created, including generated fields.

Mount the adapter for your host at a path matching `RIPPLO_ENGINE_URL`. Import from the matching
subpath under `@ripplo/testing`. Express:

```ts
import { createStateSourceHandler } from "@ripplo/testing/express";
import { coreEngine } from "./test/engine.js";

app.use(
  "/ripplo",
  createStateSourceHandler({
    enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
    engine: coreEngine,
  }),
);
```

**Bind `enabled` to the env flag — never hardcode `true`.** Mount path must match `RIPPLO_ENGINE_URL`.

Koa, Nest, Next.js, Hono, and Elysia expose the same handler names, but each framework mounts its
handler differently. Fastify exposes `registerStateSourceHandler()` and
`registerAuthenticationHandler()`. Read the chosen subpath's types instead of copying Express
mounting code.

**Ripplo calls every engine route with `PUT`**, at `<RIPPLO_ENGINE_URL>/<action>` — `PUT /ripplo/setup`,
`PUT /ripplo/state`, `PUT /ripplo/teardown`, `PUT /ripplo/sign-in`. The handler types are
method-agnostic, so a framework that routes by method needs the verb written out. Next.js App Router
names each export after its method, which means `export const POST` typechecks and then answers every
call with 405:

```ts
// app/ripplo/[action]/route.ts
import { createAuthenticationHandler, createStateSourceHandler } from "@ripplo/testing/nextjs";
import { coreEngine, userAuthenticationEngine } from "@/lib/ripplo/engine";

const enabled = process.env.ENABLE_RIPPLO_TESTING === "true";
const stateSource = createStateSourceHandler({ enabled, engine: coreEngine });
const authentication = createAuthenticationHandler({
  enabled,
  engines: [userAuthenticationEngine],
});

export const PUT = async (request: Request): Promise<Response> => {
  const stateSourceResponse = await stateSource(request);
  return stateSourceResponse.status === 404 ? authentication(request) : stateSourceResponse;
};
```

A route that 405s on every action is this mistake. Check the verb before debugging anything else.

**Vite dev server:** mount HTTP state through a plugin. Add the sign-in plugin below only when
needed:

```ts
import { ripploStateSourcePlugin } from "@ripplo/testing/vite";
import { coreEngine } from "./src/test/engine";

export default defineConfig({
  plugins: [
    react(),
    ripploStateSourcePlugin({ engine: coreEngine, path: "/ripplo" }),
  ],
});
```

The plugins load the env file, gate on `ENABLE_RIPPLO_TESTING`, and read
`RIPPLO_WEBHOOK_SECRET`. `RIPPLO_ENGINE_URL` is `<app-url>/ripplo`.

`@ripplo/instrument` is a **server-side** span preload — skip for a client-only app. Browser
connection is still required (step 5).

### Add sign-in only when workflows need it

Sign-in is separate from state setup. It can bind only to a record collection inside the HTTP
source:

```ts
import { createAuthenticationEngine } from "@ripplo/testing/engine";
import { createAuthenticationHandler } from "@ripplo/testing/express";
import { state } from "../../../../.ripplo/state.js";

export const authenticationEngine = createAuthenticationEngine(state.core.users, {
  currentActor: ({ runId, session }) => readCurrentActor({ runId, session }),
  signIn: ({ actor, runId }) => signInUser({ actor, runId }),
});

app.use(
  "/ripplo",
  createAuthenticationHandler({
    enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
    engines: [authenticationEngine],
  }),
);
```

For Vite, also import `ripploAuthenticationPlugin` from `@ripplo/testing/vite` and add
`ripploAuthenticationPlugin({ engines: [authenticationEngine], path: "/ripplo" })` beside the
state-source plugin.

- **`signIn({ actor, runId }) => session`** mints the browser session. Ripplo routes `actor.set()`
  through the authentication engine attached to that record collection.
- **`currentActor({ session, runId }) => row | null`** resolves live cookies to complete signed-in
  row. Ripplo calls it while observing the run. Read fresh.
- One authentication adapter may receive engines for several actor record collections. Exactly one
  engine may recognize the live session.

Checklist, reading the app's own auth code:

1. **Find where the app verifies a session** (`getUser`, `auth()`, session middleware). `signIn` produces what it reads.
2. **Token or session row?** JWT-cookie apps → mint a token with the app's signing secret. Session-table apps → insert a session row, set its id as the cookie.
3. **Exact cookie names + attributes.** Copy from app config (NextAuth differs with/without HTTPS) — a wrong name fails silently.
4. **Identity matching.** `currentActor` must return exact row represented by live session. Ripplo
   matches complete row against observed state and materialized setup row.
5. **Guards on a fresh session** (MFA, email verification, onboarding, feature gates) — set up state that passes every one.
6. **Verify set-up roles/permissions against the real database** — mismatches show as flaky 403s, not clear failures. Query the actual rows.

**Session in localStorage?** Return the stored entries through `Session.origins`. `currentActor`
receives the same cookies, headers, and origin storage. Do not add a parallel identity cookie.

Add the preload to the backend dev script (skip for client-only):

```sh
node --import @ripplo/instrument server.js
tsx watch --import @ripplo/instrument src/index.ts
NODE_OPTIONS="--import @ripplo/instrument" next dev
```

Frameworks with a register hook (Next.js `instrumentation.ts`) can call `register` from `@ripplo/instrument/register`. Restart the dev server after adding it.

## 5. Connect browser state and readiness

Every app calls `connect` before rendering while browser testing is enabled. With a browser source,
create its engine in the app bundle and pass it to `connect`:

```ts
import { connect } from "@ripplo/testing/browser";
import { createStateSourceEngine } from "@ripplo/testing/engine";
import { state } from "../../../.ripplo/state";

const frontendEngine = createStateSourceEngine(state.frontend, {
  read: () => Promise.resolve(persistentAppStore.getState()),
  setup: {
    fields: ({ input }) => {
      persistentAppStore.setFields(input);
      return Promise.resolve(input);
    },
    records: {
      drafts: ({ input }) => Promise.resolve(persistentAppStore.createDraft(input)),
    },
  },
  teardown: () => Promise.resolve(persistentAppStore.reset()),
});

const enabled = import.meta.env.VITE_ENABLE_RIPPLO_TESTING === "true";
const connection = enabled ? await connect(frontendEngine) : null;

if (connection != null) {
  const stopReadySignal = router.subscribe("onResolved", () => {
    connection.ready();
    stopReadySignal();
  });
}

renderApp();
```

- **TanStack/React Router** — after the first route resolves, call `connection.ready()` once for
  that page boot.
- **Next.js** — in `instrumentation-client.ts` (not a layout effect/client component — those don't fire behind a tunnel).
- **Plain SPA** — after the top-level data load settles.

Gate `connect` outside the public API with a build-time browser flag such as
`VITE_ENABLE_RIPPLO_TESTING` or `NEXT_PUBLIC_ENABLE_RIPPLO_TESTING`. `npx ripplo init` writes the
server-side `ENABLE_RIPPLO_TESTING` flag. Add its framework-specific public counterpart when the
browser bundle cannot read that variable. Do not expose `RIPPLO_WEBHOOK_SECRET` to the browser.

`await connect(engine)` and `connection.ready()` have different jobs:

- `connect(engine)` mounts the browser source. During a run it waits for browser setup to finish
  before the app renders.
- `connection.ready()` tells Ripplo that the current page has finished loading its interactive
  content. It does not set up state.

Use `await connect()` without an engine when the browser owns no modeled state. A run that does not
receive `connection.ready()` within the app startup deadline fails with `appNotReady`.

Ripplo sets up HTTP state, signs in, loads the app, and then sets up browser state. Browser setup
may depend on HTTP-created records and may read signed-in application state. Persist browser setup
in local storage, IndexedDB, or another store that survives navigation. After setup and readiness,
Ripplo resets to a blank page, starts capture, and performs the workflow's first `goto` as a hard
navigation. HTTP setup cannot depend on browser setup. `npx ripplo compile` rejects that dependency.

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

Skip if `.ripplo/workflows/` has workflows. Otherwise one run must pass — web onboarding enables Continue after a run reports `status=passed` with no failed checks.

- Hand off to `/ripplo:create`.
- Pick the smallest critical user intent available. Follow its natural multi-step path and declare
  its visible outcome plus complete state effects. Do not add a page-load smoke test only to unlock
  onboarding. Non-obvious intent or entry point → `AskUserQuestion`.
- `npx ripplo run <workflow-slug>[/<test-slug>]`. Fails → debug via `.ripplo/debug/<runId>/behavior.jsonl`.

Turn on the background explorer (third gate) with `npx ripplo explore on` — it walks composed paths and files findings as tasks. Triage via `/ripplo:tasks`.

## Rules

- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true` — bind to the env flag.
- Every app connects before render and calls `connection.ready()` after real content is interactive.
- Adapter mount path must match the `RIPPLO_ENGINE_URL` suffix.
- Daemon runs from the directory containing `.ripplo/` — set Bash `cwd` accordingly.
- **Worktrees:** env files don't carry over, ports collide. Copy the env file from main, pick a distinct port, update `RIPPLO_APP_URL` + `RIPPLO_ENGINE_URL`.
