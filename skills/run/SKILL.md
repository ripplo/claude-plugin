---
name: run
description: "Run Ripplo e2e tests. Use when executing tests."
user-invokable: true
---

# Run Ripplo Tests

## Usage

Run all tests:

```bash
npx ripplo run
```

Run specific tests:

```bash
npx ripplo run <slug1> <slug2>
```

List available tests:

```bash
npx ripplo list
```

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
