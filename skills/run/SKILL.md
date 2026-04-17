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

Read debug artifacts from `.ripplo/debug/<runId>/`:

- `steps/<failedIndex>/dom.html` — DOM at failure point
- `steps/<failedIndex>/accessibility-tree.txt` — page structure
- `console.log` — browser console output
- `network.jsonl` — network requests
- `page-errors.log` — uncaught JS exceptions
