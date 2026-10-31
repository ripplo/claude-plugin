---
name: review
description: "Start, wait for, and address a Ripplo code review. Use when the user pastes a Ripplo code review id or a pull request URL, asks to run or rerun a Ripplo review, says 'address the review', or asks what Ripplo found. Starts reviews with the CLI, checks their status until they finish, pulls the published issues, renders the failing frames, classifies each issue, fixes the app in the working tree."
---

# Address a Ripplo code review

Input: a code review id, optionally followed by `issue <number>`, or a pull request URL to review. Output: the app fixed in the working tree, one short report per issue. When an issue number is named, address that issue only.

Everything comes from the CLI. Never query Ripplo any other way.

```sh
npx ripplo review start <prUrl> [--depth fast|deep] [--app-url <url>] [--auth <name>]   # review the latest commit, prints codeReviewId (JSON)
npx ripplo review status <codeReviewId>     # stage, reviewed commit, and latest commit (JSON)
npx ripplo review <codeReviewId>            # open issues of the review and gaps of the published attempt (JSON)
npx ripplo explain <runId>                  # failures per starting state and step, with nearby evidence (JSON)
npx ripplo snapshot <runId> --offset <ms>   # PNG + rrweb-tagged HTML of that frame
```

`explain` and `snapshot` download the run's `behavior.jsonl` to `$XDG_CACHE_HOME/ripplo/runs/<runId>/` on first use, defaulting to `~/.cache`. Sign in first if any command says so: `npx ripplo login`.

## Start and wait

- A pull request URL: run `start`, then wait for the `codeReviewId` it prints. `"alreadyRunning": true` means a review of the pull request was already in progress and nothing new started, so wait for that one. When it says the pull request has no preview URL or several, ask the user for the app address and pass it with `--app-url`. A pull request that was reviewed before is reviewed again with the last run's depth, app, and auth connection, unless a flag says otherwise.
- A code review id: run `npx ripplo review status <codeReviewId>`. When `stage` is `published`, continue with the loop below. Otherwise wait for it.

`status` prints `stage`, `reviewedSha` (the commit the published review ran on), `latestSha` (the pull request's latest commit), and `failure`. While the review is in progress `stage` is `previewBuilding`, `previewFailed`, `queued`, or `running`. It ends as `published`, `failed` (with `failure` saying why), or `stopped` (canceled, or nothing running and nothing published).

A review takes up to 30 minutes, 45 with `--depth deep`, plus any wait for the preview to deploy. Wait with the Monitor tool at its longest timeout, then keep working or end your turn:

```sh
until out=$(npx ripplo review status <codeReviewId>) || exit 1; grep -qE '"stage": "(published|failed|stopped)"' <<<"$out"; do sleep 30; done
```

A monitor stops at its timeout, which is shorter than most reviews. When it expires before the loop ends, start the same monitor again. When the user asks how the review is going, run `status` once and tell them the stage in one line. Ripplo itself waits for the preview, so never check the preview yourself. The loop exits with an error when `status` fails. Run `status` once to see the message and tell the user. When the loop ends, run `status` once more. `published` with `reviewedSha` equal to the commit you expect: run `npx ripplo review <codeReviewId>` and continue with the loop below. `published` with an older `reviewedSha`: the review you waited for ran on an earlier commit, so run `start` again and wait for the new review. `failed` or `stopped`: tell the user.

## Loop, per issue

1. **Read the issue.** `title`, `body`, `number` (the Ripplo issue number), `kind` (`regression`, `new`, or `existing`, relative to the reviewed change), `appearance` (`behavior` or `visual`), `workflow` (the workflow slug, or `null` when an explorer trail found the issue), and `evidence` (`runId`, `frameMs`). The body is the reviewer's claim. Verify it, do not trust it.
2. **See what the reviewer saw.** `npx ripplo snapshot <runId> --offset <frameMs>`, then Read the PNG. The rendered frame is the evidence. A string in `behavior.jsonl` can be the test's own assertion text.
3. **See what failed.** `npx ripplo explain <runId>`. Each failure carries its `place` (the starting state or the step), its `detail` (a model failure such as a state mismatch or a missing outcome, a failed element check, or a driver error), the network, console, and span events in the 4s before, and `snapshotOffsetMs` for the frame. A state mismatch lists the expected and observed state. Grep the cached `behavior.jsonl` by `"kind"` only for detail explain did not surface.
4. **Decide.** Either the app is wrong, or the claim is. Fix the app when the frame shows the broken behavior. When the frame contradicts the claim, say so with the run id and frame, and change nothing. Never change app behavior just to make a finding disappear.
5. **Prove the frame, not the diff.** Before saying fixed, reason from the rendered frame and the failing check to the code you changed. Never conclude from a log string or a toast.

Issues are independent. Fan out to subagents when there are many, one issue or one shared file cluster per agent, each told to load `/ripplo:review` first.

## Finish

Report per issue: fixed or disputed, what changed, run id and frame you checked. When `gaps` is not empty, say how many workflows the review could not cover and that `/ripplo:cover <codeReviewId>` adds what they need. Do not act on gaps here. Tell the user to push. A review of the new commit is the proof. Once the push is on the pull request, offer to run `npx ripplo review start <prUrl>` and wait for it as described above.
