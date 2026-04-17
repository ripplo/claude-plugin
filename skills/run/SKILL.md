---
name: run
description: "Run Ripplo e2e tests. Use when executing tests."
---

# Run Ripplo Tests

## Usage

Run all tests:

```bash
npx ripplo run
```

Run specific tests:

```bash
npx ripplo run <id1> <id2>
```

To see available tests, browse `.ripplo/tests/` (including subfolders). Each test declares its id via `.test("<id>")` in the file — grep for that if you're looking for a specific one.

## Requirements

- `ripplo` dev session must be running (`npx ripplo` in a terminal)
- Dev server must be running at the `appUrl` configured in `createRipplo()` (`.ripplo/ripplo.ts`)
- Run `npx ripplo doctor` to verify all requirements

## On failure

**Do not re-run the test to reshape output.** The CLI output already names each failed run id and prints `Debug artifacts: .ripplo/debug/<runId>/`. Everything you need is on disk. Never pipe `npx ripplo run` through `grep`/`tail`/`head`/`paste` to find which step failed, pair ids with results, or "see the output again" — Read the artifact files instead.

Only rerun when:

- You've made a code change intended to fix the failure, or
- You're checking for flakiness via `/ripplo:flake-detect`.

Read artifacts from `.ripplo/debug/<runId>/` in this order:

1. `summary.txt` — per-step pass/fail with durations; start here to locate the failed step index
2. `error.txt` — top-level error message (e.g., dev server unreachable, config issues)
3. `steps/<failedIndex>/dom.html` — DOM at failure point
4. `steps/<failedIndex>/accessibility-tree.txt` — page structure / correct ARIA locators
5. `console.log` — browser console output
6. `network.jsonl` — network requests
7. `page-errors.log` — uncaught JS exceptions
