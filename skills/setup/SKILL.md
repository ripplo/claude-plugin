---
name: setup
description: "Wire @ripplo/testing into the application server. Use when initializing Ripplo in a project for the first time, or when the precondition endpoints are not yet mounted (e.g. `npx ripplo doctor` reports them missing)."
user-invokable: true
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
3. **Confirm with the user** before installing or wiring anything: which app should host the endpoints, what path prefix to use (default `/api/test/preconditions`), and the env-var name for the webhook secret (default `RIPPLO_WEBHOOK_SECRET`). For raw-engine paths, also confirm the framework before generating the handler.
4. **Install `@ripplo/testing`** in the chosen app if it isn't already a dependency. Use the workspace's package manager (check `packageManager` in root `package.json` or the lockfile).
5. **Wire the adapter** following the matching pattern from the README. Always wrap the mount behind an env guard like `process.env.ENABLE_RIPPLO_TESTING === "true"` so it cannot be enabled in production by accident.
6. **Create or update `.ripplo/ripplo.ts`** with `createRipplo({ appUrl, preconditionsUrl, projectId, webhookSecret })`. The `preconditionsUrl` must match the prefix you mounted in step 5.
7. **Verify** by running `npx ripplo doctor`. Resolve any reported issues before handing off.

## Adapter cheatsheet

### Express

```ts
import { createExpressHandler } from "@ripplo/testing/express";
app.use("/api/test/preconditions", createExpressHandler({ ripplo }));
```

### Fastify

```ts
import { registerFastifyHandler } from "@ripplo/testing/fastify";
await app.register(registerFastifyHandler({ ripplo }), { prefix: "/api/test/preconditions" });
```

### Next.js (App Router)

```ts
// app/api/test/preconditions/[action]/route.ts
import { createNextHandler } from "@ripplo/testing/nextjs";
import ripplo from "@/.ripplo/ripplo";
export const PUT = createNextHandler({ ripplo });
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
- **Never expose the endpoints in production.** Always gate the mount on an env flag.
- **Prefer a first-class adapter when one exists.** Only use the raw engine path for unsupported frameworks. When you do, always import `verifyWebhookSignature`, `serializeCookie`, and `buildSetCookieHeader` from `@ripplo/testing` — never reimplement them or pull `standardwebhooks` directly.
- **Never invent the path prefix.** The value passed to `app.use(...)` / `prefix` / the route file path must equal the `preconditionsUrl` suffix in `.ripplo/ripplo.ts`. Mismatches silently fail at runtime.
