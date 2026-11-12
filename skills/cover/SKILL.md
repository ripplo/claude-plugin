---
name: cover
description: "Add what Ripplo could not cover. Use when the user pastes `/ripplo:cover`, alone, with a code review id, or with a list of workflows, or asks to make an uncovered workflow testable. Reads each gap, adds the API or route the app lacks so Ripplo can set up and observe that state, and reports per gap."
---

# Cover the workflows a Ripplo review could not

Input: nothing, a code review id, or one line per workflow pasted after the command (`- <workflow>: <what Ripplo cannot do>`). Output: the app changed in the working tree so Ripplo can create and observe the state each gap names, one short report per gap.

With nothing after the command, the gaps are every gap of the project connected to this repository. With an id, they are the gaps of that review. Both come from the CLI. Never query Ripplo any other way. With pasted lines, those are the gaps and there is nothing to fetch. When the input ends with a `Server: <url>` line, it is not a gap: prefix every `npx ripplo` command with `RIPPLO_SERVER_URL=<url>`.

```sh
npx ripplo gaps                    # every gap of the project (JSON)
npx ripplo review <codeReviewId>   # issues and gaps of the published attempt (JSON)
```

When `gaps` says several projects are connected to the repository, ask the user which one and pass it with `--project <id>`. Read the `gaps` array: `workflow` names the user journey, `blockedBy` names what the app does not give Ripplo. Sign in first if the command says so: `npx ripplo login`.

## What a gap means

Ripplo tests through the browser as a signed-in run user. Before a test it sets up the starting state and reads it back through the app's own APIs, using the run's browser session. When the app has no way to create or observe some state, Ripplo records a gap instead of inventing state. Ripplo never edits application code, so the gap stays until the app gains the capability.

Every request a run makes carries a signed `x-ripplo-run` header, also when no user is signed in. A route can accept a Ripplo run by verifying that header with `ripploRunId({ headers, secrets })` from `@ripplo/auth`, using the same secret the app's `/ripplo` handler uses. It returns the run id, or `undefined` when the header is missing, expired, or forged.

## Loop, per gap

1. **Read `blockedBy`.** It says what Ripplo cannot create or observe. It never says how to fix it.
2. **Look for an existing API.** Find the app code that creates or reads that state. If an API already does it and the run user can call it with their own session, report that and change nothing. If it exists only behind a role the run user cannot hold, allow it for a verified Ripplo run.
3. **Otherwise add the smallest API that does it.** A route that creates the row or state the gap names, or one that reads it back. Guard it with `ripploRunId` and reject when it returns `undefined`. Never mount it unguarded.
4. **Keep it application code.** Test it like the rest of the app. Do not write `.ripplo/` files, bindings, or state schemas. The next Ripplo review of the pull request writes those and the workflow for each gap.

Gaps are independent. Fan out to subagents when there are many, one gap or one shared file cluster per agent, each told to load `/ripplo:cover` first.

## Finish

Report per gap: already possible, access extended, or added, naming the route or API.

The next review reads the pull request description to learn which gaps to cover. Add this section to it, one line per gap, with the `workflow` exactly as the gap gives it. Include the gaps that were already possible, because no code change points the review at them.

```md
## Ripplo gaps

- <workflow>: added `POST /api/ripplo/invoices`, which creates an invoice for the run's organization.
- <workflow>: already possible, `GET /api/orders/:id` returns the refund state.
```

When the branch has no pull request yet, give the user the section to paste when they open one.

Tell the user to push. Once the push is on the pull request, offer to run `npx ripplo review start <prUrl> --depth deep`, with the `prUrl` from `npx ripplo review <codeReviewId>`, and wait for it as `/ripplo:review` describes. The review covers each listed workflow, or keeps its gap and says what still blocks it.
