---
name: setup
description: "Wire @ripplo/testing into the application server. Use when initializing Ripplo in a project for the first time, or when the engine endpoint is not yet mounted (e.g. `npx ripplo doctor` reports them missing)."
---

# Ripplo Setup

Mount the engine endpoint into the app server and wire `.ripplo/ripplo.ts` to point at it.

## Mental model: two funnels

- **Definitions funnel into `createRipplo`.** In `.ripplo/ripplo.ts` you pass three registries — `preconditions`, `observers`, `tests` — to `createRipplo(config, { preconditions, observers, tests })`. This is the single point where the DSL graph is registered; there is no global builder.
- **Implementations funnel into `createEngine`.** In the app server you call `createEngine(ripplo, { preconditions: {...}, observers: {...} })`. The impls object is exhaustiveness-checked by TypeScript — missing keys and unknown keys are compile errors. Adapters (`@ripplo/testing/express`, `/fastify`, `/nextjs`, `/hono`, `/koa`, `/nestjs`, `/elysia`) mount the resulting `engine`.

Never call `createRipplo()` or `createEngine()` outside these two places.

## Procedure

1. Read `packages/testing/README.md` ("Architecture", "Wiring it together", "Server Setup") for the full reference.
2. **Detect framework** from `package.json`:
   - `express` → `@ripplo/testing/express`
   - `fastify` → `@ripplo/testing/fastify`
   - `next` → `@ripplo/testing/nextjs` (App Router)
   - `hono` → `@ripplo/testing/hono`
   - `koa` → `@ripplo/testing/koa`
   - `@nestjs/core` → `@ripplo/testing/nestjs`
   - `elysia` → `@ripplo/testing/elysia`
   - Anything else → raw engine, see "Custom integration" below.
3. **Confirm with the user**: which app hosts the endpoint, path prefix (default `/ripplo`), webhook secret env var (default `RIPPLO_WEBHOOK_SECRET`), and (for raw-engine) the framework before generating the handler.
4. Install `@ripplo/testing` in the chosen app using the workspace's package manager.
5. **Create/update `.ripplo/ripplo.ts`** with the new signature. The `engineUrl` suffix must match the prefix used when mounting the adapter in step 8.

   ```ts
   // .ripplo/ripplo.ts
   import { createRipplo } from "@ripplo/testing";
   import { preconditions } from "./preconditions/index.js";
   import { observers } from "./observers/index.js";
   import { tests } from "./tests/index.js";

   export default createRipplo(
     {
       appUrl: "https://localhost:3001",
       engineUrl: "https://localhost:3001/ripplo",
       projectId: "<project-id>",
     },
     { preconditions, observers, tests },
   );
   ```

   `webhookSecret` defaults to `process.env.RIPPLO_WEBHOOK_SECRET` and `createRipplo` throws if it's missing. The CLI auto-loads `.ripplo/.env` before each compile, so live edits to `.ripplo/ripplo.ts` and `.ripplo/.env` are picked up in dev mode without restarting.

6. **Scaffold the registry files.**

   ```ts
   // .ripplo/preconditions/index.ts
   import { precondition } from "@ripplo/testing";

   export const authLoggedIn = precondition("auth:logged-in")
     .description("Authenticated test user")
     .contract<{ userId: string }>();

   export const preconditions = { authLoggedIn /* , ... */ };
   ```

   ```ts
   // .ripplo/observers/index.ts
   import { observer } from "@ripplo/testing";
   export const observers = {
     /* ...handles... */
   };
   ```

   ```ts
   // .ripplo/tests/index.ts
   // Each test file exports a TestDefinition; compose them here.
   // import { fooTest } from "./foo-test.js";
   // export const tests = [fooTest];
   export const tests = [] as const;
   ```

7. **Create `<app>/src/test/engine.ts`** — the single implementation funnel. The object keys must exactly match the registries in `.ripplo/ripplo.ts`.

   ```ts
   // <app>/src/test/engine.ts
   import { createEngine } from "@ripplo/testing";
   import ripplo from "../../../../.ripplo/index.js"; // adjust path
   import { prisma } from "../lib/prisma.js";

   export const engine = createEngine(ripplo, {
     preconditions: {
       authLoggedIn: {
         setup: async (ctx) => {
           // create user, set cookies via ctx.setCookie()
           return { userId: ctx.uniqueId("user") };
         },
         teardown: async (ctx) => {
           /* clean up using ctx.data.userId */
         },
       },
     },
     observers: {
       /* ...impls... */
     },
   });
   ```

8. **Wire the adapter.** Always pass `enabled: process.env.ENABLE_RIPPLO_TESTING === "true"` (or equivalent) — never hardcode `true`. When false the adapter mounts a no-op so endpoints can't ship to prod. Pass the `engine` from step 7 — not the bare `ripplo` instance.
9. Install the pre-commit hook (below).
10. `npx ripplo doctor` — resolve all issues.
11. Once green, invoke `/ripplo:explore` (plan coverage) or `/ripplo:create` (single test).

## Lockfile

`ripplo compile`/`lint` (and the dashboard watcher) write `.ripplo/ripplo.lock` — the compiled DSL serialized as JSON. **Committed.** The Ripplo server reads it on GitHub push webhooks instead of executing user TypeScript. `.gitattributes` marks it `linguist-generated=true` so GitHub collapses the diff.

If stale or missing, the webhook returns 422 and the branch doesn't sync. The pre-commit hook below prevents stale state from being committed.

## Pre-commit hook

```sh
#!/bin/sh
if git diff --cached --name-only | grep -q '^\.ripplo/.*\.ts$'; then
  npx ripplo compile --check || {
    echo "ripplo.lock is stale — run \`npx ripplo compile\` and stage the result."
    exit 1
  }
fi
```

If a `pre-commit` hook already exists, append the `if` block. With husky/lefthook/simple-git-hooks, add the same `npx ripplo compile --check` invocation gated on staged `.ripplo/**/*.ts` to that tool's config.

## Adapter cheatsheet

All adapters take the `engine` produced by `createEngine(ripplo, impls)` — not the bare `ripplo` instance.

### Express

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

### Fastify

```ts
import { registerFastifyHandler } from "@ripplo/testing/fastify";
import { engine } from "./test/engine.js";

await app.register(
  registerFastifyHandler({
    enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
    engine,
  }),
  { prefix: "/ripplo" },
);
```

### Next.js (App Router)

```ts
// app/ripplo/[action]/route.ts
import { createNextHandler } from "@ripplo/testing/nextjs";
import { engine } from "@/server/test/engine";

export const PUT = createNextHandler({
  enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
  engine,
});
```

The handler dispatches on the last URL segment (`execute-preconditions`, `execute-observer`, or `teardown-preconditions`). One dynamic route file covers them — don't split into separate route files.

### Hono

```ts
import { Hono } from "hono";
import { createHonoHandler } from "@ripplo/testing/hono";
import { engine } from "./test/engine.js";

const app = new Hono();
app.route(
  "/ripplo",
  createHonoHandler({
    enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
    engine,
  }),
);
```

`createHonoHandler` returns a `Hono` sub-app; mount it via `app.route(prefix, ...)`. Runs on Node, Bun, Deno, and Workers.

### Koa

```ts
import mount from "koa-mount";
import { createKoaHandler } from "@ripplo/testing/koa";
import { engine } from "./test/engine.js";

app.use(
  mount(
    "/ripplo",
    createKoaHandler({
      enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
      engine,
    }),
  ),
);
```

The Koa handler reads the raw body itself — do not place a body-parser before it.

### NestJS

```ts
import { RipploTestingModule } from "@ripplo/testing/nestjs";
import { engine } from "./test/engine.js";

@Module({
  imports: [
    RipploTestingModule.forRoot({
      enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
      engine,
      path: "ripplo",
    }),
  ],
})
export class AppModule {}
```

Requires `@nestjs/platform-express` and `reflect-metadata`. `path` is the controller prefix (default `"ripplo"`).

### Elysia

```ts
import { Elysia } from "elysia";
import { createElysiaHandler } from "@ripplo/testing/elysia";
import { engine } from "./test/engine.js";

const app = new Elysia().group("/ripplo", (app) =>
  app.use(
    createElysiaHandler({
      enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
      engine,
    }),
  ),
);
```

### Custom integration (raw engine)

For unsupported frameworks, mount the `engine` directly over the three routes. Always go through the exported helpers — never reimplement webhook verification or cookie serialization.

```ts
import { buildSetCookieHeader, serializeCookie, verifyWebhookSignature } from "@ripplo/testing";
import { engine } from "./test/engine.js";

const webhookSecret = engine.getConfig().webhookSecret;
// PUT /execute-preconditions, PUT /execute-observer, PUT /teardown-preconditions:
// raw text body → verifyWebhookSignature → JSON.parse →
// engine.executePreconditions({ appUrl }) | engine.executeObserver(name, params) | engine.teardown(preconditions, data) →
// forward result.cookies as Set-Cookie via buildSetCookieHeader(serializeCookie(c)).
```

See `packages/testing/README.md` "Custom integration (raw engine)" for the full handler example.

## Preconditions vs. observers

- **Preconditions** — test data setup/teardown (`.ripplo/preconditions/index.ts`). Declared with `precondition(name).description(...).requires({...}).contract<TData>()`; implemented as a `{ setup, teardown }` pair in the `preconditions` slot of the `createEngine` impls object.
- **Observers** — backend state assertions mid-test (`.ripplo/observers/index.ts`). Declared with `observer(name).description(...).input<TInput>().budget(tier).contract()`; implemented as an async function in the `observers` slot of the `createEngine` impls object. Used in tests via `assert.backend(observerHandle, params)`. **Required on every test that exercises a mutation flow** — see `/ripplo:create` → "What makes a good test".

Both live in the same `engine.ts`; TypeScript enforces that every handle in the registries has a matching impl key.

## Rules

- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true`. Bind it to an env flag.
- Prefer a first-class adapter; only use raw engine for unsupported frameworks. Always import the helpers — never reimplement them or pull `standardwebhooks` directly.
- The path prefix in `app.use(...)` / `prefix` / route file path **must match** the `engineUrl` suffix in `.ripplo/ripplo.ts`. Mismatches silently fail.
- `createRipplo()` is called once — in `.ripplo/ripplo.ts`. `createEngine()` is called once — in the app's `engine.ts`. Everywhere else imports those values.
- Never duplicate a `precondition()` or `observer()` call across files. Declare once in `.ripplo/` and import the handle. Since `createEngine`'s impls object is exhaustiveness-checked against the `.ripplo/` registries, adding a stray definition in app code can't contribute — it would never be called.

## Gotchas

- Run `npx ripplo` from the directory containing `.ripplo/` (typically the repo root).
- Put `ENABLE_RIPPLO_TESTING=true` and `RIPPLO_WEBHOOK_SECRET=<secret>` in the gitignored env file the host app's dev server actually loads (e.g. `.env.local` in the Next.js app dir, `.env.development.local` for Vite, `.env` in the Express/Fastify server dir if that's what your dev runner reads). Restart the dev server after changes.
