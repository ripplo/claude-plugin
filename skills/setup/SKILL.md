---
name: setup
description: "Wire @ripplo/testing into the application server. Use when initializing Ripplo in a project for the first time, or when the precondition endpoints are not yet mounted (e.g. `npx ripplo doctor` reports them missing)."
---

# Ripplo Setup

Mount the precondition endpoints into the application server and wire `.ripplo/ripplo.ts` to point at them.

## Steps

1. **Read** `packages/testing/README.md` (the "Server Setup" section) for the adapter usage reference.
2. **Detect the framework** — look at `package.json` and the entry point of the server app:
   - `express` in dependencies → Express adapter (`@ripplo/testing/express`)
   - `fastify` in dependencies → Fastify adapter (`@ripplo/testing/fastify`)
   - `next` in dependencies → Next.js adapter (`@ripplo/testing/nextjs`, App Router)
   - Anything else (Hono, Koa, Bun, Deno, Cloudflare Workers, etc.) → use the **raw engine** path (see "Custom integration" below)
3. **Confirm with the user** before installing or wiring anything: which app should host the endpoints, what path prefix to use (default `/ripplo/preconditions`), and the env-var name for the webhook secret (default `RIPPLO_WEBHOOK_SECRET`). For raw-engine paths, also confirm the framework before generating the handler.
4. **Install `@ripplo/testing`** in the chosen app if it isn't already a dependency. Use the workspace's package manager (check `packageManager` in root `package.json` or the lockfile).
5. **Wire the adapter** following the matching pattern from the README. The adapter takes a required `enabled: boolean` flag — pass `process.env.ENABLE_RIPPLO_TESTING === "true"` (or equivalent) so it cannot be enabled in production by accident. When `enabled` is false the adapter mounts a no-op handler.
6. **Create or update `.ripplo/ripplo.ts`** with `createRipplo({ appUrl, preconditionsUrl, projectId, webhookSecret })`. The `preconditionsUrl` must match the prefix you mounted in step 5. **This is the only `createRipplo(...)` call in the entire app** — everywhere else (server adapter wiring, precondition implementations) must import the instance from `.ripplo/ripplo.ts`. Calling `createRipplo()` twice throws at runtime.
7. **Verify** by running `npx ripplo doctor`. Resolve any reported issues before handing off.

## Adapter cheatsheet

### Express

```ts
import { createExpressHandler } from "@ripplo/testing/express";
import ripplo from "<path to .ripplo/ripplo>"; // import the existing instance — do not call createRipplo() here
app.use(
  "/ripplo/preconditions",
  createExpressHandler({ enabled: process.env.ENABLE_RIPPLO_TESTING === "true", ripplo }),
);
```

### Fastify

```ts
import { registerFastifyHandler } from "@ripplo/testing/fastify";
import ripplo from "<path to .ripplo/ripplo>"; // import the existing instance — do not call createRipplo() here
await app.register(
  registerFastifyHandler({ enabled: process.env.ENABLE_RIPPLO_TESTING === "true", ripplo }),
  { prefix: "/ripplo/preconditions" },
);
```

### Next.js (App Router)

```ts
// app/ripplo/preconditions/[action]/route.ts
import { createNextHandler } from "@ripplo/testing/nextjs";
import ripplo from "@/.ripplo/ripplo";
export const PUT = createNextHandler({
  enabled: process.env.ENABLE_RIPPLO_TESTING === "true",
  ripplo,
});
```

The Next.js handler dispatches on the last URL segment (`execute-batch` / `teardown`). One dynamic route file covers both endpoints — do not create separate `execute-batch/route.ts` and `teardown/route.ts` files.

### Custom integration (raw engine)

For frameworks without a first-class adapter (Hono, Koa, Bun, Deno, Cloudflare Workers, etc.), use `createEngine` directly and wire two routes by hand. Always go through the exported helpers — never reimplement webhook verification or cookie serialization.

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
// One handler for PUT /execute-batch, one for PUT /teardown.
// Each: read raw text body → verifyWebhookSignature → JSON.parse →
// engine.executeBatch({ appUrl }) or engine.teardown(preconditions, data) →
// forward result.cookies as Set-Cookie via buildSetCookieHeader(serializeCookie(c)).
```

See the **Custom integration (raw engine)** section of `packages/testing/README.md` for the full handler example and the list of caller responsibilities.

## Rules

- **Never bypass the webhook signature check** or hardcode a secret in source. The secret comes from the environment.
- **Never hardcode `enabled: true`.** Bind it to an env flag like `process.env.ENABLE_RIPPLO_TESTING === "true"` — the adapter no-ops when `enabled` is false, which is how we keep the endpoints out of production.
- **Prefer a first-class adapter when one exists.** Only use the raw engine path for unsupported frameworks. When you do, always import `verifyWebhookSignature`, `serializeCookie`, and `buildSetCookieHeader` from `@ripplo/testing` — never reimplement them or pull `standardwebhooks` directly.
- **Never invent the path prefix.** The value passed to `app.use(...)` / `prefix` / the route file path must equal the `preconditionsUrl` suffix in `.ripplo/ripplo.ts`. Mismatches silently fail at runtime.
- **One `createRipplo()` call per app.** It lives in `.ripplo/ripplo.ts`. Server-side adapter wiring and precondition implementations must `import ripplo from` that file — never create a second instance. Calling `createRipplo()` twice in the same process throws.
