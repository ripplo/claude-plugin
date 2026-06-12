---
name: report
description: "Report a critical application bug that Ripplo caught, so it lands on the project's Caught Bugs dashboard. Use the moment you confirm a real app bug — while debugging, after a test catches broken behavior, or when new coverage exposes a defect."
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

`--run` and `--test` are optional but include them when you have them — they link the bug to its replay on the dashboard. Exception: never pass an exploration run id (`explore-...`) as `--run` — exploration runs have no server Run row and the server rejects the report; cite it in `--surfaced-by` instead.

## The bar for filing

Only **functionality bugs in the app under test** — behavior a user would hit and call broken. Every dashboard entry should be something the team is glad the tests caught.

Do not file:

- Test gaps, wrong locators, races, under-specified assertions, world/seed problems — those are model fixes.
- Flaky infrastructure, daemon/sync issues, stale lockfiles.
- Style, copy, or cosmetic issues with no functional impact.
- Anything unconfirmed against evidence (failing assertion, network/span trace, page error).

## Picking the kind

- Broken behavior was built **this session** → `new_feature_bug`.
- It **worked before** a recent change broke it → `regression`.
- It was **already broken** and new coverage exposed it → `latent_bug`.

## When to fire

- In `/ripplo:debug`, the moment the decision lands on app bug — file before reporting back to the user.
- In `/ripplo:create`, when a new test fails against an existing flow and the app is confirmed wrong → `latent_bug`.
- After any run that caught broken behavior you then fixed — file with the run id of the catching (red) run.

One report per distinct root cause. A bug breaking five tests is one report; cite the most direct test/run.

## Writing the fields

- `--title` — name the broken behavior, not the test: "Checkout total ignores applied coupon", not "checkout test failed".
- `--root-cause` — the actual defect: function, file, missing branch, dropped call.
- `--surfaced-by` — one or two sentences of evidence: which assertion failed, what behavior.jsonl showed.

Filing doesn't replace telling the user — still surface it in your response with the evidence.
