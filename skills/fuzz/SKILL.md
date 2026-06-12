---
name: fuzz
description: "Triage findings from Ripplo's background explorer — the deterministic fuzzer that composes action sequences no test author wrote and records oracle violations in a local ledger. Use when the user asks to triage/fix explorer findings, when run output reports pending findings, or before resolving any finding via replay."
---

# Triage Explorer Findings

The daemon's background explorer fuzzes the app: it composes action sequences no author wrote and records every oracle violation as a **finding** in a local ledger (`.ripplo/.local/explore-ledger.jsonl`). Your job is the refine step: confirm each finding, classify it, fix, and verify by replay.

If the ledger is empty or exploration is off, say so — exploration runs via `npx ripplo daemon --explore` (or foreground `npx ripplo explore`).

## Commands

- **List:** `npx ripplo explore findings` — pending findings in triage order (oracle layer ascending: crash → invariant → law → frame; occurrences descending within a layer), plus recurrent flaky-candidates (same divergence 3+ times, never deterministically reproduced — triage last; usually a race). `--json` for machine output. Default scope is all pending; a count or specific id from the user narrows it.
- **Detail:** `npx ripplo explore findings <id>` — full evidence: divergence lines (expected vs observed), trail, occurrence window, captured run + behavior.jsonl path. Read this before opening the stream.
- **Replay:** `npx ripplo explore replay <id>` — re-executes the finding's minimal trail; the only way a fix gets re-validated.

Findings with the same `diverged:` step usually share one root cause — fix it once, then replay the siblings.

## Per finding, one at a time

1. **Evidence.** The finding's captured run reads like any test run: grep `.ripplo/debug/<runId>/behavior.jsonl` by `kind`, snapshot moments with `npx ripplo snapshot` — recipes in `/ripplo:debug`. The trail line shows the minimal action sequence (`test#step` labels) that triggers it.
2. **Classify** — app bug vs model gap (the four-move decision tree lives in `/ripplo:debug`):
   - **App bug** — the model is right; the app breaks when actions compose this way. Fix the app and file it with `npx ripplo report-bug` (bar and fields in `/ripplo:report`) — but omit both `--run` and `--test`: exploration runs have no server Run row and the server rejects the report. Cite the exploration run id in `--surfaced-by`. Kind is usually `latent_bug`.
   - **Model gap** — the oracle fired because a declaration is missing or wrong: an effect the transition really has but never declared, a view-law scoped too broadly, a world producing an unintended state. Fix the declaration in `.ripplo/`.
3. **Verify + resolve:** `npx ripplo explore replay <id>`. Clean replay resolves the finding and marks its targets covered. A narrowed `given` that makes the trail unplannable reports **unreachable** and resolves it — make sure a test covers the state you excluded. Still-reproduces = the fix didn't land. Diverged = behavior changed but is still wrong — re-read the evidence.
4. **After any fix, replay the other pending findings before deep-diving them** — one root cause often resolves siblings with different signatures.

## Add-vs-weaken guardrail

Model edits that **add** declarations (a missing effect, a narrowing `when`, a covering test) are normal fixes. Edits that **delete or weaken** declarations (dropping a law, removing a declared effect, coarsening a vocabulary) make the oracle permanently blind there — only do this after proving from app source that the current behavior is intended, and cite that proof to the user. Never silence a finding by loosening the model when the app is wrong.
