import type { AuthenticationHandlerOptions, Session } from "@ripplo/auth";

import { auth } from "../auth.js";
import { authEnv } from "../auth-env.js";
import { sys } from "../domain/system.js";

export const authentication: AuthenticationHandlerOptions = {
  createSession: ({ runId }) => createRunSession(runId),
  teardown: ({ runId }) => teardownRun(runId),
};

async function createRunSession(runId: string): Promise<Session> {
  const email = runEmail(runId);
  await ensureRunUser({ email, runId });
  const response = await auth.api.signInEmail({
    asResponse: true,
    body: { email, password: runSecret(runId) },
  });
  const cookies = response.headers.getSetCookie().map((header) => parseSetCookie(header));
  return { extraHTTPHeaders: {}, storageState: { cookies, origins: [] } };
}

async function teardownRun(runId: string): Promise<void> {
  await sys.user.deleteMany({ where: { email: runEmail(runId) } });
}

function runEmail(runId: string): string {
  return `ripplo-${runId}@ripplo.test`;
}

interface EnsureRunUserParams {
  readonly email: string;
  readonly runId: string;
}

async function ensureRunUser({ email, runId }: EnsureRunUserParams): Promise<void> {
  const existing = await sys.user.findFirst({ select: { id: true }, where: { email } });
  if (existing != null) {
    return;
  }
  await auth.api.signUpEmail({
    body: { email, name: `Ripplo ${runId.slice(0, 8)}`, password: runSecret(runId) },
  });
}

function runSecret(runId: string): string {
  return `${runId}-${runId.length.toString(36)}-run`;
}

type StorageCookie = Session["storageState"]["cookies"][number];

function parseSetCookie(header: string): StorageCookie {
  const [pair = "", ...rest] = header.split(";").map((part) => part.trim());
  const separator = pair.indexOf("=");
  if (separator === -1) {
    throw new TypeError(`Ripplo could not read a session cookie: ${header}`);
  }
  const attributes = cookieAttributes(rest);
  const expires = attributes.get("expires");
  return {
    domain: attributes.get("domain") ?? new URL(authEnv.BETTER_AUTH_URL).hostname,
    expires: expires == null ? -1 : Math.floor(new Date(expires).getTime() / 1000),
    httpOnly: attributes.has("httponly"),
    name: pair.slice(0, separator),
    path: attributes.get("path") ?? "/",
    sameSite: sameSiteOf(attributes.get("samesite")),
    secure: attributes.has("secure"),
    value: pair.slice(separator + 1),
  };
}

function cookieAttributes(parts: ReadonlyArray<string>): ReadonlyMap<string, string> {
  const entries = parts.map((part): readonly [string, string] => {
    const eq = part.indexOf("=");
    return eq === -1
      ? [part.toLowerCase(), ""]
      : [part.slice(0, eq).toLowerCase(), part.slice(eq + 1)];
  });
  return new Map(entries);
}

function sameSiteOf(value: string | undefined): StorageCookie["sameSite"] {
  const lowered = value?.toLowerCase();
  if (lowered === "strict") {
    return "Strict";
  }
  if (lowered === "none") {
    return "None";
  }
  return "Lax";
}
