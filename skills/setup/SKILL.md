---
name: setup
description: "Wire @ripplo/testing into the application server. Use when initializing Ripplo in a project for the first time, or when the engine endpoint is not yet mounted (e.g. `npx ripplo doctor` reports them missing)."
---

# Ripplo Setup

Mount the engine endpoint into the app server and wire `.ripplo/ripplo.ts` to point at them.

## Procedure

1. Read `packages/testing/README.md` ("Server Setup") for adapter usage.
2. **Detect framework** from `package.json`:
   - `express` → `@ripplo/testing/express`
   - `fastify` → `@ripplo/testing/fastify`
   - `next` → `@ripplo/testing/nextjs` (App Router)
   - Anything else (Hono, Koa, Bun, Deno, Workers) → raw engine, see "Custom integration" below.
3. **Confirm with the user**: which app hosts endpoints, path prefix (default `/ripplo`), webhook secret env var (default `RIPPLO_WEBHOOK_SECRET`), and (for raw-engine) the framework before generating the handler.
4. Install `@ripplo/testing` in the chosen app using the workspace's package manager.
5. **Wire the adapter.** Always pass `enabled: process.env.ENABLE_RIPPLO_TESTING === "true"` (or equivalent) — never hardcode `true`. When false the adapter mounts a no-op so endpoints can't ship to prod.
6. **Create/update `.ripplo/ripplo.ts`** with `createRipplo({ appUrl, engineUrl, projectId, webhookSecret })`. **This is the only `createRipplo()` call in the entire app** — calling it twice throws. All other code (adapter wiring, precondition impls) imports the instance from `.ripplo/ripplo.ts`. The `engineUrl` suffix must match the prefix mounted in step 5.
7. Install the pre-commit hook (below).
8. `npx ripplo doctor` — resolve all issues.
9. Once green, invoke `/ripplo:explore` (plan coverage) or `/ripplo:create` (single test).

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

### Express

```ts
import { createExpressHandler } from "@ripplo/testing/express";
import ripplo from "<path to .ripplo/ripplo>";
app.use(
  "/ripplo",
  createExpressHandler({ enabled: process.env.ENABLE_RIPPLO_TESTING === "true", ripplo }),
);
```

### Fastify

```ts
import { registerFastifyHandler } from "@ripplo/testing/fastify";
import ripplo from "<path to .ripplo/ripplo>";
await app.register(
  registerFastifyHandler({ enabled: process.env.ENABLE_RIPPLO_TESTING === "true", ripplo }),
  { prefix: "/ripplo" },
);
```

### Next.js (App Router)

```ts
// app/ripplo/[action]/route.ts
import { createNextHandler } from "@ripplo/testing/nextjs";
import ripplo from "@/.ripplo/ripplo";
export const PUT = createNextHandler({
  enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
  ripplo,
});
```

The handler dispatches on the last URL segment (`execute-preconditions`, `execute-observer`, or `teardown-preconditions`). One dynamic route file covers them — don't split into separate route files.

## Preconditions vs. observers

The engine endpoint hosts two primitives:

- **Preconditions** — test data setup/teardown (`.ripplo/preconditions/*.ts`). Declared on the DSL side with `.contract<T>()`, implemented on the server side with `ripplo.implementPrecondition(handle, { setup, teardown })`.
- **Observers** — backend state assertions mid-test (`.ripplo/observers/*.ts`). Declared with `.observer(name).input<T>().budget("fast" | "slow" | "async").contract()`, implemented with `ripplo.implementObserver(handle, async (ctx, params) => ctx.pass() | ctx.retry(reason) | ctx.fail(reason))`. Used in tests via `assert.backend(observerHandle, params)`.

Both live alongside the same `ripplo` instance; `ripplo.implementPrecondition` and `ripplo.implementObserver` are distinct methods (do not conflate).

### Custom integration (raw engine)

For unsupported frameworks, use `createEngine` directly. Always go through the exported helpers — never reimplement webhook verification or cookie serialization.

```ts
import {
  buildSetCookieHeader,
  createEngine,
  serializeCookie,
  verifyWebhookSignature,
} from "@ripplo/testing";
import ripplo from "../.ripplo/ripplo.js";

const engine = createEngine(ripplo);
const webhookSecret = ripplo.getConfig().webhookSecret;
// PUT /execute-preconditions, PUT /execute-observer, PUT /teardown-preconditions:
// raw text body → verifyWebhookSignature → JSON.parse →
// engine.executeBatch({ appUrl }) | engine.teardown(preconditions, data) →
// forward result.cookies as Set-Cookie via buildSetCookieHeader(serializeCookie(c)).
```

See `packages/testing/README.md` "Custom integration (raw engine)" for the full handler example.

## Rules

- Never bypass webhook signature checking or hardcode the secret.
- Never hardcode `enabled: true`. Bind it to an env flag.
- Prefer a first-class adapter; only use raw engine for unsupported frameworks. Always import the helpers — never reimplement them or pull `standardwebhooks` directly.
- The path prefix in `app.use(...)` / `prefix` / route file path **must match** the `engineUrl` suffix in `.ripplo/ripplo.ts`. Mismatches silently fail.
- One `createRipplo()` per app, in `.ripplo/ripplo.ts`. Everywhere else imports it.

## Gotchas

- Run `npx ripplo` from the directory containing `.ripplo/` (typically the repo root).
- Put `ENABLE_RIPPLO_TESTING=true` and `RIPPLO_WEBHOOK_SECRET=<secret>` in the gitignored env file the host app's dev server actually loads (e.g. `.env.local` in the Next.js app dir, `.env.development.local` for Vite, `.env` in the Express/Fastify server dir if that's what your dev runner reads). Restart the dev server after changes.
