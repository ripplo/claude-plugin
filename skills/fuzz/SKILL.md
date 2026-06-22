---
name: fuzz
description: "Triage findings from Ripplo's background explorer — the deterministic fuzzer that composes action sequences no workflow author wrote and records the failures it catches in a local findings log. Use when the user asks to triage/fix explorer findings, when run output reports pending findings, or before resolving any finding via replay."
---

# Triage Explorer Findings

The daemon's background explorer fuzzes the app: it composes action sequences no author wrote and records every failed check as a **finding** in a local findings log (`.ripplo/.local/explore-ledger.jsonl`). Your job is the refine step: confirm each finding, classify it, fix, and verify by replay.

If the findings log is empty or exploration is off, say so — exploration runs via `npx ripplo daemon --explore` (or foreground `npx ripplo explore`).

## Commands

- **List:** `npx ripplo explore findings` — pending findings in triage order (layer ascending: crash → data rule → page rule → frame; occurrences descending within a layer), plus recurrent flaky-candidates (same failure 3+ times, never deterministically reproduced — triage last; usually a race). `--json` for machine output. Default scope is all pending; a count or specific id from the user narrows it.
- **Detail:** `npx ripplo explore findings <id>` — full evidence: mismatch lines (expected vs actual), trail, occurrence window, captured run + behavior.jsonl path. Read this before opening the stream.
- **Replay:** `npx ripplo explore replay <id>` — re-executes the finding's minimal trail; the only way a fix gets re-validated. A clean replay resolves the finding.
- **Dismiss:** `npx ripplo explore dismiss <id>` — mark a finding not-a-bug / won't-fix without a replay. Use when the evidence proves the app behavior is intended and no fix is coming — not as a shortcut past a real finding.

Resolve (clean replay) and dismiss both sync to the server, so the project's Issues dashboard reflects your triage — resolved and dismissed findings drop off the default open list. Findings with the same `mismatch:` step usually share one root cause — fix it once, then replay the siblings.

## Per finding, one at a time

1. **Evidence.** The finding's captured run reads like any test run: grep `.ripplo/debug/<runId>/behavior.jsonl` by `kind`, snapshot moments with `npx ripplo snapshot` — recipes in `/ripplo:run`. The trail line shows the minimal action sequence (`test#step` labels) that triggers it.
2. **Classify** — app bug vs test gap (the four-move decision tree lives in `/ripplo:run`):
   - **App bug** — the workflows are right; the app breaks when actions compose this way. Fix the app and file it with `npx ripplo report-bug` (bar and fields in `/ripplo:run`) — pass the `explore-…` finding id as `--run` (it won't link a replay, but the server records it) and omit `--test`. Also cite the exploration run id in `--surfaced-by`. Kind is usually `latent_bug`.
   - **Test gap** — the check failed because a declaration is missing or wrong: an effect the action really has but never declared, a page rule scoped too broadly, a world producing an unintended state. Fix the declaration in `.ripplo/`.
3. **Verify + resolve:** `npx ripplo explore replay <id>`. Clean replay resolves the finding and marks its targets covered. A narrowed `given` that makes the trail unplannable reports **unreachable** and resolves it — make sure a workflow covers the state you excluded. Still-reproduces = the fix didn't land. Diverged = behavior changed but is still wrong — re-read the evidence.
4. **After any fix, replay the other pending findings before deep-diving them** — one root cause often resolves siblings with different signatures.

## Add-vs-weaken guardrail

Workflow edits that **add** declarations (a missing effect, a new `when` branch, a covering workflow) are normal fixes. Edits that **delete or weaken** declarations (dropping a page rule, removing a declared effect, coarsening a vocabulary) leave that behavior permanently unchecked — only do this after proving from app source that the current behavior is intended, and cite that proof to the user. Never silence a finding by loosening the workflows when the app is wrong.
