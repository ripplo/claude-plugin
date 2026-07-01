---
name: fuzz
description: "Triage findings from Ripplo's background explorer — the generative fuzzer that composes action sequences no workflow author wrote and reports the failures it catches as findings on the server. Use when the user asks to triage/fix explorer findings, when run output reports findings, or before resolving any finding."
---

# Triage Explorer Findings

The background explorer fuzzes the app: local and cloud workers walk guided random paths over enabled actions, and every failed check becomes a **finding** reported to the server and deduped by signature. Your job is the refine step: confirm each finding, classify it, fix, and verify.

Exploration is toggled from the dev mode bar (the explore popover). If there are no open findings, say so.

## List findings

`npx ripplo findings` lists open findings — each with its category (crash, data rule, page rule, frame), occurrence count, signature, and repro `runId` (the `explore-…` id you pull evidence with). `--json` for machine output. Findings also surface in the web Issues dashboard, where a user resolves or dismisses them.

## Per finding, one at a time

1. **Explain.** `npx ripplo explain <runId>` reads the run back to you — auto-pulling its `behavior.jsonl` from the server first (runs aren't kept on local disk, so the stream is always fetched on demand). Each failing check grouped by step, where a page rule was learned from (the workflow, its `holds only when` state, and a nudge when it fired in a different flow than it was learned in), the expected vs actual values for a state mismatch, the network/console/span events around the failure, and the exact `snapshot --at` for the failing frame. Start here — it replaces hand-grepping the stream. Drop to the raw `behavior.jsonl` (grep by `kind`) and `npx ripplo snapshot <runId> --at <ts>` only when you need detail `explain` didn't surface. The repro is the minimal action sequence that triggers the failure.
2. **Classify** — app bug vs test gap (the four-move decision tree lives in `/ripplo:run`):
   - **App bug** — the workflows are right; the app breaks when actions compose this way. Fix the app and file it with `npx ripplo report-bug` (bar and fields in `/ripplo:run`) — pass the `explore-…` repro run id as `--run` to link the bug to the finding, and cite it in `--surfaced-by`.
   - **Test gap** — the check failed because a declaration is missing or wrong: an effect the action really has but never declared, a page rule scoped too broadly, a world producing an unintended state. Fix the declaration in `.ripplo/`.
3. **Confirm.** `npx ripplo replay <runId>` re-drives this exact trail (same base state, same actions, same params) against the app. A clean run means resolved. If you fixed a **test gap** (edited `.ripplo/`), replay may report the model changed — that's expected, confirm with `npx ripplo lint` and `npx ripplo run <affected>` instead. The background explorer also re-confirms by signature dedup, so a real fix stops recurring.
4. **Resolve.** Once confirmed, mark the finding resolved (or dismissed, if the evidence proves the app behavior is intended) in the Issues dashboard.
5. **One root cause often resolves siblings.** Findings with the same failing step usually share a cause — fix it once, then re-check the other open findings before deep-diving them.

## Add-vs-weaken guardrail

Workflow edits that **add** declarations (a missing effect, a new `when` branch, a covering workflow) are normal fixes. Edits that **delete or weaken** declarations (dropping a page rule, removing a declared effect, coarsening a vocabulary) leave that behavior permanently unchecked — only do this after proving from app source that the current behavior is intended, and cite that proof to the user. Never silence a finding by loosening the workflows when the app is wrong.
