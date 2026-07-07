---
name: tasks
description: "Pick up Ripplo tasks — open-ended requests users anchor to a replay frame and element while exploring their app (fix a bug, change behavior, extend or write a workflow, ask a question). Use when a tasks reminder fires, when the user points you at a task, or before running any `npx ripplo tasks` command. Routes the request, and for app changes enforces the prove-it loop: reproduce the flagged frame, change the app, re-run, attach exact run/frame/element proof."
---

# Pick up Ripplo tasks

A task is an open-ended request anchored to a moment in a run. Users explore their app across space and time — the replay makes every frame, element, and workflow inspectable — and file a request on any facet of what they see: fix a visual bug, change a behavior, extend a workflow, write a new one, or ask how something works. The anchor (a run, a frame, usually an element) is the shared context; the comment thread is the conversation.

## The task lifecycle — what needs your attention, and when you can stop

A task moves through four states. Know which state means "act" and which means "hands off," because two mechanisms enforce this for you: the task watcher (armed by `/ripplo:start`) wakes you the moment a task needs attention, and the done-check blocks you from ending the session while any task is still open.

- **open** — needs you. New tasks, reopened tasks, and user replies on an open task all land here. The watcher surfaces each one live, even while you sit idle. Pick it up, and mark the pickup with `npx ripplo tasks start <id>` — that flags it in progress in the panel so the user sees it's being worked. Resolving, dismissing, or clarifying clears the flag; until then the task stays yours. The user can no longer edit a task once you've started it, so start when you actually begin, not when you merely notice it.
- **reopened** — a task you resolved that the user sent back. This is not a fresh unrelated request — your earlier resolution didn't hold. Revisit that fix, find what you missed, and prove it again. The watcher flags reopens distinctly for exactly this reason.
- **needs clarification** — waiting on the user, not on you. You set this with `clarify` when you're genuinely blocked. It leaves your queue until the user replies, and their reply flips it back to **open** and wakes you. Don't sit on a needs-clarification task.
- **resolved / dismissed** — done. Out of the queue, out of the done-check. If the user resolves or dismisses a task while you're working it, it is no longer relevant — **stop working it.** You won't get a wake for this (that would be noise) — you find out at your next stop, where the done-check no longer lists it. Don't keep grinding a task that's left the open set.

While hooks are active, you cannot end the session with a task still open — the done-check blocks and lists each one. Clear every open task exactly one way: **resolve** it with proof, **clarify** it if you need the user, or **dismiss** it if it's not actionable. Silence is never how a task leaves the queue. (The block is a hook, so it only fires while hooks are on. `npx ripplo hooks pause` turns them off — that's for when the user is working on something unrelated and the Ripplo gates are just noise, not a way to slip past an open task you should be handling.)

## Understand the request, then route it

1. **See what they saw.** `npx ripplo tasks show <id>` prints the full thread, each anchor's element (tag, role, testid, text, best-effort CSS selector), and the exact `snapshot` command for its frame. The anchor tells you the moment; the thread tells you the ask. **The precomputed element details are a starting hint, not ground truth** — run the snapshot, Read the PNG, and validate every assumption (which element, what state, what's on top of it) against the rendered frame and the `data-rrweb-id`-tagged DOM in the `snapshot-<ms>ms.html` it writes before you act. Eliminate the ambiguity; don't act on the label alone.
2. **Route by what's actually being asked:**
   - **A change to the app** (bug, behavior, layout, copy) → make the change, then **prove it with an exact run, frame, and element** (next section). This is the common case and the bar is strict.
   - **Extend or write test coverage** ("cover this flow", "this workflow should also check…", "add a test for…") → load `/ripplo:create`; the deliverable is the workflow running green over the requested flow.
   - **A question, or anything ambiguous** → answer in a `comment` anchored to the frame, or `clarify` if you need the user before you can act.

Match the response to the request — don't force every task into the fix-and-prove loop. But the moment a task means changing the app, the proof bar below is non-negotiable.

## The non-negotiable for app changes: proof

The single most common failure here is the **false proof** — claiming something is fixed without a run that actually exercises the broken condition. Every resolve of an app change must clear this bar:

- **Exact run + frame + element, or it didn't happen.** "I fixed the layout" is not proof. A `runId`, a frame (`--at`/`--offset`), and the element it shows is proof. Attach them on the resolving comment.
- **The proof run must reproduce the failure condition.** If the bug only appears on hover/focus/overlap/scroll, the proof run must perform that interaction. A run that never hovered cannot prove a hover bug — resolving on it is a false proof.
- **The rendered frame is the evidence — not log text.** `grep`ping behavior.jsonl for a string can match the _test's own assertion text_, not the DOM — a string in the stream is not proof the UI rendered it. Proof of what the user saw is the rrweb frame: render it with `snapshot` and **Read the PNG**.
- **No hand-waving, ever.** Do not assume a change worked, do not infer it from the diff, do not say "this should fix it." See the before, make the change, see the after. If you can't see the after, you are not done.

## The strongest proof: a deterministic assertion (red → green)

When the bug is verifiable, the durable proof is an assertion in a workflow that was **red before the fix and green after** — not a one-off screenshot. Prefer this over a snapshot whenever you can express the defect as a predicate.

- Extend the workflow that exercises the flow with the assertion that pins the correct behavior, run it, watch it go **red on the broken app**, fix the app, watch it go **green**. That red→green transition is the proof.
- Ripplo provides **`unobstructed(locator)`** for interaction-triggered visual bugs (one element covering another). It hit-tests the locator's box against what's actually painted on top. Use `expect(unobstructed("..."))` after the interaction that should reveal the element (e.g. `hover(row) → expect(unobstructed("..."))`); use `not(unobstructed(...))` to assert something _is_ covered. Reach for `visible`/`value`/`text` and the backend `Entity.created/updated/deleted` assertions the same way — encode the fix as a check, don't eyeball it.
- A task anchored on a **transient element** — a toast, spinner, or skeleton that appears then vanishes — is provable as an assertion, not just a snapshot. Wrap it: `ephemeral(text(testId("toast-success"), "Saved"))` waits for it to appear and passes the instant it does, without leaking onto later steps. When the complaint is that a momentary element did or didn't show, this red→green assertion is the durable proof — prefer it over the visual loop.
- A backend or state bug → a backend assertion on the mutation step. A wrong value → pin the value. The rule is the same: make the run go red first, or you haven't proven the bug existed.

## If it isn't provable in an existing workflow, write one

A bug that no current clickpath reaches is **unprovable as a test — and an unprovable bug is the root of every false proof.** Don't resolve on a tangential run. Either:

1. Extend the flagging workflow so its run faithfully exercises the bug (add the `hover`, the seed state, the branch), then resolve on that run — this makes the proof and the flag point at the same moment. Or
2. Write a new workflow (`/ripplo:create`) whose run reproduces the condition, scope it, run it red→green.

New scaffolding (a predicate, an entity + engine impl, a given) is in-scope work, not a follow-up.

## The visual loop (presentation / iteration tasks)

This loop is for look, layout, and timing bugs no predicate captures — spacing, color, alignment, jank. It covers transient elements too when the complaint is how one looks: a toast's style, position, or wording is iterated here, snapshotting the frame where it's up. Only pure existence — did the toast or spinner appear at all — is an `ephemeral(...)` assertion instead. For "this looks wrong at this frame" tasks, run a closed loop and Read every PNG:

1. **See the baseline.** `npx ripplo snapshot <runId> --offset <frameMs>` (the frame offset the task is anchored to — `show` prints the exact command) reproduces the flagged frame; Read the PNG and confirm it shows the complaint. `snapshot` auto-pulls the run's behavior stream on demand — runs aren't kept on local disk, so this fetch happens for local and cloud runs alike. Baseline doesn't show the complaint? Stop and ask — you may have the wrong frame or element.
2. **Find the code** from the anchored element identity (tag, role/name, testid) and the screenshot. Trust the screenshot over a CSS-selector hint.
3. **Make one targeted change.** Don't stack changes across loops.
4. **Re-run** the workflow that produced the frame (`npx ripplo run <workflow-slug>[/<test-slug>]`); explore findings re-drive with `npx ripplo replay <runId>` (prints a fresh `replay-…` id — snapshot _that_).
5. **Snapshot the same phase in the new run and compare.** Timestamps don't carry across runs — relocate by phase. Start at the baseline frame's printed offset and bracket; for precision grep the new behavior.jsonl for the step named in the anchor, take its `"timestamp"`, add the within-step offset, pass via `--at`.
6. **State plainly whether it's fixed, with the before/after PNGs.** Not fixed → new hypothesis, loop.

### Finding the right frame: visually bisect

When you don't have the exact frame — a flash, a stagger, a transition — binary-search the recording instead of guessing. `snapshot --offset <ms>` (ms from recording start) prints each frame's offset and the total duration. Bracket the window, snapshot the midpoint, Read it, and halve toward the frame that shows the visual: `--offset 0`, then `--offset <half>`, narrowing each step. A handful of snapshots pins a sub-second moment that single-frame guessing would miss. Timing complaints ("appears after", "janky") need a _sequence_ — snapshot the same few offsets in baseline and fix and compare the sequences; verified means the new sequence shows the behavior gone, not one lucky frame.

## The CLI loop

```sh
npx ripplo tasks list                     # open tasks for this dev session
npx ripplo tasks show <id>                # full message thread, with each message's run + frame anchor
npx ripplo tasks start <id>               # mark picked up — shows in progress until resolved, dismissed, or clarified
npx ripplo tasks comment <id> <body> --run <runId> --offset <ms> --element <rrwebId> [--as <name>]
npx ripplo tasks resolve <id> --run <runId> [--note <text>] [--as <name>]
npx ripplo tasks clarify <id> <body>      # blocked on the user — ask what you need
npx ripplo tasks dismiss <id> [--note <text>]   # not actionable
```

- **Anchor your proof comment to an element and frame.** To get `--element`: run `snapshot` for the frame, then grep the `snapshot-<ms>ms.html` it writes — every element is tagged `data-rrweb-id`, so grep your element's class or text and read the id off the matching tag. (Don't dig `behavior.jsonl` for it — that's the raw mutation stream, not a queryable DOM.) `--element` takes the rrweb id of an **element** node (a text node has no box to highlight — use its parent element); `--offset` takes the frame offset in ms from recording start (same units as `snapshot --offset`) where that element is present. This is what the user sees pinned on the replay — element-and-frame-specific proof is the point, especially for visual feedback. One `comment` call per comment; multiple anchored comments on one task is the right way to annotate a multi-part visual fix (point at the icon, point at the title, each with its note).
- **`resolve` carries the proof run** (`--run` is required). Resolve only after you've seen the green — the red→green assertion, or the before/after snapshots, or both.
- **`clarify`** when you genuinely need the user — it flags "Needs you" in the panel. Don't clarify to avoid work.

## Work many tasks in parallel

The queue fills up — tasks are independent units, so fan out. Delegate each task (or a cluster sharing one workflow) to a subagent and run them concurrently. Two rules:

- **Explicitly tell every subagent which skills to load first.** Subagents don't inherit your skill context — their prompt must instruct them to load `/ripplo:tasks` (the proof bar and the command gate apply to them too), plus any other skill the task needs: `/ripplo:create` if it authors or extends a workflow, `/ripplo:run` if it runs and diagnoses tests. A subagent without the right skills loaded will wield Ripplo wrong and fake proofs.
- **Don't parallelize tasks that edit the same files or workflow** — serialize those to avoid clobbering. Independent tasks across different areas are the ones to fan out.

Keep the run/snapshot/proof loop on each subagent; the daemon shards the actual runs across workers, so concurrent runs are fine.

## Discipline checklist before you resolve

- [ ] You Read the snapshot PNG and validated the element/state against the DOM — you did not act on the precomputed hint alone.
- [ ] A run exists whose recording **exercises the broken condition** (hover/state/branch included).
- [ ] The fix is pinned by a **red→green assertion**, or by **before/after PNGs you Read**, or both.
- [ ] The resolving comment is **anchored to the run, frame, and element**.
- [ ] You never concluded "fixed" from the diff, a toast, or a log string.
- [ ] No run reaches the broken condition yet? You extended or wrote the workflow that does — you did not resolve without proof.
