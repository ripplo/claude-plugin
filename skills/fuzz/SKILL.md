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

1. **Pull the evidence.** `npx ripplo pull <runId>` downloads that run's `behavior.jsonl` to `.ripplo/debug/<runId>/behavior.jsonl` from the server, so it survives even when the local run folder was cleaned up. Then read it like any run: grep by `kind` (`action`/`assertion`/`rrweb`/`network`/`console`/`error`/`span`/`meta`) and snapshot moments with `npx ripplo snapshot <runId> --at <ts>` — recipes in `/ripplo:run`. The repro is the minimal action sequence that triggers the failure.
2. **Classify** — app bug vs test gap (the four-move decision tree lives in `/ripplo:run`):
   - **App bug** — the workflows are right; the app breaks when actions compose this way. Fix the app and file it with `npx ripplo report-bug` (bar and fields in `/ripplo:run`) — pass the `explore-…` repro run id as `--run` to link the bug to the finding, and cite it in `--surfaced-by`.
   - **Test gap** — the check failed because a declaration is missing or wrong: an effect the action really has but never declared, a page rule scoped too broadly, a world producing an unintended state. Fix the declaration in `.ripplo/`.
3. **Resolve.** After the fix, mark the finding resolved (or dismissed, if the evidence proves the app behavior is intended) in the Issues dashboard. The explorer dedupes by signature, so a real fix means the finding stops recurring — a dismissed finding is one you've judged not-a-bug with proof.
4. **One root cause often resolves siblings.** Findings with the same failing step usually share a cause — fix it once, then re-check the other open findings before deep-diving them.

## Add-vs-weaken guardrail

Workflow edits that **add** declarations (a missing effect, a new `when` branch, a covering workflow) are normal fixes. Edits that **delete or weaken** declarations (dropping a page rule, removing a declared effect, coarsening a vocabulary) leave that behavior permanently unchecked — only do this after proving from app source that the current behavior is intended, and cite that proof to the user. Never silence a finding by loosening the workflows when the app is wrong.
