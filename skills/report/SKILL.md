---
name: report
description: "Report a critical application bug that Ripplo caught, so it lands on the project's Caught Bugs dashboard. Use the moment you confirm a real app bug — while debugging a failed run, after a test catches broken behavior, or when authoring coverage exposes a defect in an existing flow."
---

# Report a Caught Bug

When a Ripplo test surfaces a **real application bug**, file it:

```sh
npx ripplo report-bug \
  --kind <new_feature_bug|regression|latent_bug> \
  --title "Short bug name" \
  --root-cause "What was actually wrong in the app code" \
  --surfaced-by "How the test/run exposed it — cite the failing assertion or behavior.jsonl evidence" \
  --run <runId> \
  --test "<test id>"
```

`--run` and `--test` are optional but include them whenever you have them — they link the bug to its replay on the dashboard. `--test` takes the test's intent string (same id you pass to `npx ripplo run`).

## The bar for filing

File only **functionality bugs in the app under test** — behavior a user would hit and call broken. This feeds the project's Caught Bugs dashboard; every entry should be something the team is glad the tests caught.

Do NOT file:

- Test gaps, wrong locators, race conditions, under-specified assertions, world/seed problems — those are model fixes, not app bugs.
- Flaky infrastructure, daemon/sync issues, stale lockfiles.
- Style, copy, or cosmetic issues with no functional impact.
- Anything you haven't confirmed against evidence (failing assertion, network/span trace, page error).

## Picking the kind

- `new_feature_bug` — the bug is in the thing being built **this session**. The agent (or user) wrote a new feature and the test caught it broken before it shipped.
- `regression` — the bug broke behavior that **previously worked**. A change this session (or a recent commit) broke an existing flow; the test was green before and red now for an app reason.
- `latent_bug` — the bug **already existed** and was exposed while creating test coverage for a previously untested flow. Nothing this session broke it; the new test found it.

Decision tree: Was the broken behavior created this session? → `new_feature_bug`. Did it work before this session's (or a recent) change? → `regression`. Neither — it was already broken when coverage arrived? → `latent_bug`.

## When to fire

- Inside `/ripplo:debug`, the moment the decision lands on **app bug** (move 1) — file it before reporting back to the user.
- Inside `/ripplo:create`, when a brand-new test fails against an existing flow and investigation confirms the app is wrong → `latent_bug`.
- After any run where a test caught broken behavior you then fixed — file it with the run id of the catching (red) run.

One report per distinct root cause. A bug breaking five tests is one report; cite the most direct test/run.

## Writing the fields

- `--title` — name the broken behavior, not the test: "Checkout total ignores applied coupon", not "checkout test failed".
- `--root-cause` — the actual defect in app code, as specifically as you know it: function, file, missing branch, dropped call.
- `--surfaced-by` — one or two sentences of evidence: which assertion failed, what behavior.jsonl showed (failed network call, wrong DB value via the oracle, page error).

Reporting the bug does not replace telling the user — still surface it in your response with the evidence.
