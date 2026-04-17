---
name: run
description: "Run Ripplo e2e tests. Use when executing tests."
---

# Run Ripplo Tests

## Usage

**Default to running the smallest relevant set of tests, not the full suite.** `npx ripplo run` with no ids runs every test — that is minutes of compute and should be rare. Bias toward scoped runs:

- Fixed a single test? Rerun just that test: `npx ripplo run <id>`.
- Made a code change touching a feature area? Rerun only the tests covering that area (browse `.ripplo/tests/` and pass their ids).
- Only run the full suite when the user explicitly asks for it, or as a final green-light check after scoped runs already pass.

Run specific tests:

```bash
npx ripplo run <id1> <id2>
```

Run all tests (use sparingly — see above):

```bash
npx ripplo run
```

To see available tests, browse `.ripplo/tests/` (including subfolders). Each test declares its id via `.test("<id>")` in the file — grep for that if you're looking for a specific one.

## Requirements

- `ripplo` dev session must be running (`npx ripplo` in a terminal)
- Dev server must be running at the `appUrl` configured in `createRipplo()` (`.ripplo/ripplo.ts`)
- Run `npx ripplo doctor` to verify all requirements
- `.ripplo/ripplo.lock` must be up to date. If you've edited anything in `.ripplo/*.ts` without running the watcher, run `npx ripplo compile` (or `npx ripplo lint`, which also writes the lockfile) before running tests remotely — the Ripplo server reads the committed lockfile.

## On failure

**Do not re-run the test to reshape output.** The CLI output already names each failed run id and prints `Debug artifacts: .ripplo/debug/<runId>/`. Everything you need is on disk. Never pipe `npx ripplo run` through `grep`/`tail`/`head`/`paste` to find which step failed, pair ids with results, or "see the output again" — Read the artifact files instead.

Only rerun when:

- You've made a code change intended to fix the failure, or
- You're checking for flakiness via `/ripplo:flake-detect`.

For deeper diagnosis (categorized root causes, evidence discipline) invoke `/ripplo:debug`. Read artifacts from `.ripplo/debug/<runId>/` in this order:

1. `summary.txt` — per-step pass/fail with durations; start here to locate the failed step index
2. `error.txt` — top-level error (dev server unreachable, config issues, etc.)
3. `steps/<failedIndex>/dom.html` — DOM at failure point
4. `steps/<failedIndex>/accessibility-tree.txt` — page structure / correct ARIA locators
5. `steps/<failedIndex>/storage.json` — auth/session state
6. Compare with `steps/<failedIndex - 1>/` to see what changed between steps
7. `console.log` — browser console output
8. `network.jsonl` — network requests
9. `page-errors.log` — uncaught JS exceptions
10. `steps/<failedIndex>/screenshot.png` — last resort after the text artifacts
