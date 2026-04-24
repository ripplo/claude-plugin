---
name: setup
description: "Wire @ripplo/testing into the application server. Use when initializing Ripplo in a project for the first time, or when the engine endpoint is not yet mounted (e.g. `npx ripplo doctor` reports them missing)."
---

# Ripplo Setup

Setup wires Ripplo into the app so tests can drive the real backend. This is what lets Ripplo close the loop on full-stack development — tests aren't mocked sketches, they exercise the full stack against real preconditions and observe real backend state.

Mount the engine endpoint into the app server and wire `.ripplo/ripplo.ts` to point at it.

## Procedure

1. **Read `packages/testing/README.md`** — the "Server Setup" section is the source of truth for every adapter (Express, Fastify, Next.js App Router, Hono, Koa, NestJS, Elysia, and raw-engine for unsupported frameworks). This skill is the checklist; the README is the code.
2. **Detect framework** from the host app's `package.json` and pick the matching subpath import (`@ripplo/testing/express`, `/fastify`, `/nextjs`, `/hono`, `/koa`, `/nestjs`, `/elysia`, or raw engine).
3. **Confirm with the user**: which app hosts the endpoint, path prefix (default `/ripplo`), webhook secret env var (default `RIPPLO_WEBHOOK_SECRET`).
4. Install `@ripplo/testing` in the chosen app.
5. **Create/update `.ripplo/ripplo.ts`** — `engineUrl` suffix must match the mount prefix in step 8.

   ```ts
   import { createRipplo } from "@ripplo/testing";
   import { preconditions } from "./preconditions/index.js";
   import { observers } from "./observers/index.js";
   import { tests } from "./tests/index.js";

   export default createRipplo(
     {
       appUrl: "https://localhost:3001",
       engineUrl: "https://localhost:3001/ripplo",
       projectId: "<id>",
     },
     { preconditions, observers, tests },
   );
   ```

   `webhookSecret` defaults to `process.env.RIPPLO_WEBHOOK_SECRET` and `createRipplo` throws if missing. The CLI auto-loads `.ripplo/.env` before each compile.

6. **Scaffold the three registry files** with empty registries:

   ```ts
   // .ripplo/preconditions/index.ts
   export const preconditions = {};
   // .ripplo/observers/index.ts
   export const observers = {};
   // .ripplo/tests/index.ts
   export const tests = [] as const;
   ```

7. **Create `<app>/src/test/engine.ts`** — the single implementation funnel. Keys match the registries; TypeScript exhaustiveness-checks.

   ```ts
   import { createEngine } from "@ripplo/testing";
   import ripplo from "../../../../.ripplo/index.js";

   export const engine = createEngine(ripplo, { preconditions: {}, observers: {} });
   ```

8. **Wire the adapter** — follow the README block for your framework. Reference example (Express):

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

   Pass the `engine` from step 7, not the bare `ripplo`. Always bind `enabled` to an env flag — never hardcode `true`.

9. Install the pre-commit hook (below).
10. `npx ripplo doctor` — resolve all issues.
11. Once green, invoke `/ripplo:explore` or `/ripplo:create`.

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

With husky/lefthook/simple-git-hooks, gate the same `npx ripplo compile --check` on staged `.ripplo/**/*.ts` via that tool's config.

## Rules

- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true` — bind to an env flag so endpoints can't ship to prod.
- Path prefix in the adapter mount **must match** the `engineUrl` suffix in `.ripplo/ripplo.ts`. Mismatches silently fail.
- Prefer a first-class adapter; only use raw engine for unsupported frameworks. Always import the exported helpers — never reimplement webhook verification or cookie serialization.
- `ENABLE_RIPPLO_TESTING=true` and `RIPPLO_WEBHOOK_SECRET=<secret>` go in the gitignored env file the host app's dev server actually loads. Restart the dev server after changes.
- Run `npx ripplo` from the directory containing `.ripplo/`.
