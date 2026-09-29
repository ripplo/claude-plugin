---
name: review
description: "Address the findings of a Ripplo code review. Use when the user pastes a Ripplo code review id, says 'address the review', or asks what Ripplo found. Pulls the published issues with the CLI, renders the failing frames, classifies each issue, fixes the app in the working tree."
---

# Address a Ripplo code review

Input: a code review id, optionally followed by `issue <number>`. Output: the app fixed in the working tree, one short report per issue. When an issue number is named, address that issue only.

Everything comes from the CLI. Never query Ripplo any other way.

```sh
npx ripplo review <codeReviewId>            # open issues of the review and gaps of the published attempt (JSON)
npx ripplo explain <runId>                  # failures per starting state and step, with nearby evidence (JSON)
npx ripplo snapshot <runId> --offset <ms>   # PNG + rrweb-tagged HTML of that frame
```

`explain` and `snapshot` download the run's `behavior.jsonl` to `$XDG_CACHE_HOME/ripplo/runs/<runId>/` on first use, defaulting to `~/.cache`. Sign in first if any command says so: `npx ripplo login`.

## Loop, per issue

1. **Read the issue.** `title`, `body`, `number` (the Ripplo issue number), `kind` (`regression`, `new`, or `existing`, relative to the reviewed change), `appearance` (`behavior` or `visual`), `workflow` (the workflow slug, or `null` when an explorer trail found the issue), and `evidence` (`runId`, `frameMs`). The body is the reviewer's claim. Verify it, do not trust it.
2. **See what the reviewer saw.** `npx ripplo snapshot <runId> --offset <frameMs>`, then Read the PNG. The rendered frame is the evidence. A string in `behavior.jsonl` can be the test's own assertion text.
3. **See what failed.** `npx ripplo explain <runId>`. Each failure carries its `place` (the starting state or the step), its `detail` (a model failure such as a state mismatch or a missing outcome, a failed element check, or a driver error), the network, console, and span events in the 4s before, and `snapshotOffsetMs` for the frame. A state mismatch lists the expected and observed state. Grep the cached `behavior.jsonl` by `"kind"` only for detail explain did not surface.
4. **Decide.** Either the app is wrong, or the claim is. Fix the app when the frame shows the broken behavior. When the frame contradicts the claim, say so with the run id and frame, and change nothing. Never change app behavior just to make a finding disappear.
5. **Prove the frame, not the diff.** Before saying fixed, reason from the rendered frame and the failing check to the code you changed. Never conclude from a log string or a toast.

Issues are independent. Fan out to subagents when there are many, one issue or one shared file cluster per agent, each told to load `/ripplo:review` first.

## Finish

Report per issue: fixed or disputed, what changed, run id and frame you checked. When `gaps` is not empty, say how many workflows the review could not cover and that `/ripplo:cover <codeReviewId>` adds what they need. Do not act on gaps here. Tell the user to push. Ripplo reviews the new commit, that review is the proof.
