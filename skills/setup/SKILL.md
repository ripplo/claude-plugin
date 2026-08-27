---
name: setup
description: "Connect an app to Ripplo. Use when the user says 'set up Ripplo', 'install ripplo', 'add the ripplo handler', or has a Ripplo project with a failing authentication check. Installs @ripplo/auth, writes the sign-in handler for the app's auth library, mounts it behind a flag, wires the secret, and verifies the endpoint."
---

# Set up Ripplo in an app

Input: the app's repository in the working tree. Output: `@ripplo/auth` installed, a sign-in handler the app owns, the endpoint verified, and the user pointed at their first review. Ask for nothing you can read from the code.

Ripplo reviews pull requests by driving the app in a browser. It needs one signed endpoint, `POST /ripplo`, that creates a signed-in session for a run and cleans up after it. Nothing else lands in the repository — no test files, no config directory, no CLI.

## 1. Read the app

Find, in this order, and say what you found in one line each:

- Server framework: express, fastify, hono, koa, nestjs, nextjs, elysia, or another fetch-standard runtime.
- Auth library: better-auth, next-auth / auth.js, Clerk, Lucia, Supabase, or a hand-rolled session table.
- The privileged database client. Teardown deletes a user, so it needs a client that bypasses row policies (a `system` client, a service role, a raw ORM instance).
- Where env vars live for the deployed test environment: Railway, Vercel, Fly, a `.env` on a host.
- The public base URL of the deployed test environment. Reviews run against a deployed build, never localhost.

## 2. Install

```sh
npm install @ripplo/auth     # or pnpm add / yarn add / bun add, matching the lockfile
```

If the user hands you a tarball instead, vendor it under `vendor/` with a content hash in the filename and reference it as `file:../../vendor/<name>.tgz`. Make sure the deploy image copies `vendor/` before install.

## 3. Write the handler

One file, `src/ripplo/authentication.ts` (or the app's equivalent), exporting one object:

```ts
import type { AuthenticationHandlerOptions } from "@ripplo/auth";

export const authentication: AuthenticationHandlerOptions = {
  createSession: ({ runId }) => createRunSession(runId),
  teardown: ({ runId }) => teardownRun(runId),
};
```

Laws the handler obeys. Check each before moving on:

- One user per run, named from `runId` (`ripplo-<runId>@ripplo.test`). `createSession` creates the user when it is missing and signs in when it exists. Never reuse a real account.
- The session comes from the auth library's own sign-in, never from writing a session row by hand. Return its cookies as Playwright `storageState.cookies`. `extraHTTPHeaders` is `{}` unless the app authorizes by header.
- `teardown` deletes the run user through the privileged client. Confirm the schema cascades sessions, accounts, and memberships from the user row. If it does not, delete those first.
- No hardcoded password. Derive the run credential from `runId`.
- No secrets in the file. The signing secret is read by `@ripplo/auth` from `RIPPLO_WEBHOOK_SECRET`.

Recipes, adapt to what step 1 found:

- better-auth: [references/better-auth.ts](references/better-auth.ts). Proven on a production app. `signUpEmail` then `signInEmail({ asResponse: true })`, cookies parsed from `Set-Cookie`.
- next-auth / auth.js: no server-side sign-in API. Create the user, then mint a session through the adapter (`adapter.createSession`) and return the session cookie the app's `cookies.sessionToken.name` expects.
- Clerk: create the user with the backend SDK, mint a sign-in token, exchange it for a session, return `__session`.
- Hand-rolled sessions: create the user and a session row with the app's own helpers, return the cookie the middleware reads.

The `Set-Cookie` parser in the better-auth recipe is library-agnostic. Reuse it.

## 4. Mount it

Behind an env flag the deployed test environment sets and production never does:

```ts
import { createAuthenticationHandler } from "@ripplo/auth/express";

if (env.ENABLE_RIPPLO_TESTING) {
  app.use(createAuthenticationHandler(authentication));
}
```

Adapters: `@ripplo/auth/express`, `/fastify`, `/hono`, `/koa`, `/nestjs`, `/nextjs`, `/elysia`. The root export is a fetch-standard `(Request) => Promise<Response>` for anything else. Mount before body parsers that would consume the raw body, and add the flag to the app's env schema so a typo fails at boot.

Run the app's typecheck and lint. Fix everything before continuing.

## 5. Route run traffic (when the app talks to third parties)

Every request a run makes carries a signed `x-ripplo-run` header. Where the app calls Stripe, sends email, hits a rate limiter, or records analytics, gate on it:

```ts
import { ripploRunId } from "@ripplo/auth";

const runId = ripploRunId(req.headers);
```

`runId` is set only for requests Ripplo made. Use a fake client, skip the limiter, or tag the row with the run id. Skip this step when the app has no such side effects.

## 6. Wire the environment

On the deployed test environment only:

- `ENABLE_RIPPLO_TESTING=true`
- `RIPPLO_WEBHOOK_SECRET=<from the Ripplo project's Security settings>`

Ask the user for the secret, or for access to set it. Never paste it into the repository. Deploy.

## 7. Verify

```sh
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://<app>/ripplo -H "content-type: application/json" -d '{}'
```

`401` means the handler is mounted and rejecting unsigned calls — correct. `404` means the flag is off or the deploy has not landed. Then in the Ripplo project's Environment settings set the app URL and the authentication URL (`https://<app>/ripplo`) and press Check authentication. Green is done.

## 8. Hand off

Tell the user to press Start mapping on the project, or comment on any pull request:

```
@ripplo review https://<preview-url>
```

Report what you wrote, the flag name, where the secret lives, and the verification result.
