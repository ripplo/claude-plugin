---
name: tasks
description: "Pick up Ripplo tasks — open-ended requests anchored to a replay frame/element (fix a bug, change behavior, extend/write a workflow, ask a question), plus background-explorer findings. Use when a tasks reminder fires, when the user points you at a task or finding, or before running any `npx ripplo tasks` command. Routes the request; for app changes enforces the prove-it loop: reproduce the flagged frame, change the app, re-run, attach exact run/frame/element proof."
---

# Pick up Ripplo tasks

A task is an open-ended request anchored to a moment in a run (a run, a frame, usually an element). The comment thread is the ask.

The **background explorer** files tasks too: local and cloud workers walk guided random paths over enabled actions no workflow author wrote. Every failed check becomes a **finding** — deduped by signature, opened as a task of kind `finding` anchored to its `explore-…` repro run. Findings don't wake you but block session end until triaged.

Explorer is always-on: a green `npx ripplo run` auto-enables it. `npx ripplo explore on|off` toggles, but a manual off lasts only until the next green run. Durable off is `npx ripplo hooks pause` (also silences the other gates).

## Task lifecycle

Four states. The task watcher (`/ripplo:start`) wakes you when one needs attention; the done-check blocks session end while any task is open.

- **open** — needs you. New, reopened, or user replies. `npx ripplo tasks start <id>` marks it in progress (user can no longer edit it — start when you begin, not when you notice).
- **reopened** — your resolution didn't hold. Revisit the fix, find what you missed, prove it again.
- **needs clarification** — waiting on the user. Set with `clarify` when genuinely blocked; their reply flips it back to open and wakes you.
- **resolved / dismissed** — done. If the user resolves/dismisses while you work it, **stop working it** — you find out at your next stop.

Clear every open task exactly one way: **resolve** with proof, **clarify**, or **dismiss** if not actionable. Silence never clears a task. The block is a hook — `npx ripplo hooks pause` turns it off (for unrelated work, not to skip an open task).

## Understand, then route

1. **See what they saw.** `npx ripplo tasks show <id>` prints the thread, each anchor's element, and the exact `snapshot` command for its frame. **Precomputed element details are a hint, not ground truth** — run the snapshot, Read the PNG, validate every assumption against the rendered frame and the `data-rrweb-id`-tagged DOM in `snapshot-<ms>ms.html` before acting.
2. **Route:**
   - **App change** (bug, behavior, layout, copy) → change it, then **prove with exact run + frame + element** (below).
   - **Test coverage** ("cover this flow", "add a test") → load `/ripplo:create`; deliverable is the workflow running green.
   - **Question / ambiguous** → answer in a `comment` anchored to the frame, or `clarify`.
   - **Explorer finding** (kind `finding`) → triage loop below.

## Explorer findings

Category names what broke: **crash** (app threw), **data rule** (cross-entity reference stopped holding), **fact** (a declared expectation contradicted), **frame** (visual defect). Every finding is a contradiction of something a workflow declared — the explorer never files findings from ignorance (unknown state is silent) and never guesses. Triage one at a time:

1. **Explain.** `npx ripplo explain <runId>` reads the repro run back (auto-pulls `behavior.jsonl` from the server). Groups failing checks by step, gives expected vs actual, prints the exact `snapshot --at`. Drop to raw `behavior.jsonl` / `npx ripplo snapshot` only for missing detail.
2. **Classify** (four-move tree in `/ripplo:run`):
   - **App bug** — fix the app, file with `npx ripplo report-bug --run <explore-runId>` to link the bug to the finding. (Duplicate/stacked UI like doubled toasts is usually this — e.g. a toast without a stable id.)
   - **Model gap** — a missing/wrong declaration. **Hardening the workflow declarations is always the remedy** — the model is sound and expressive enough; never conclude a finding "needs new machinery" or is "inexpressible". Match the shape:
     - Outcome depends on seeded state the given never covers → enrich `given` with `Entity.maybe(...)`/a singleton + `when(branch...)` per outcome. The branch condition must mirror the app's actual rule — read the app source.
     - Element appears/enables as an effect of an action (dirty-form Save, leave-prompt, reveal) → declare it on the acting step: the fill that reveals expects `visible(...)`, the save/discard that clears expects `not(visible(...))`, the initial clean state declares `not(visible(...))`. Dirtiness is an effect, not a state law.
     - A bare click with an invisible side effect (selection, toggle) lets the explorer skip it → declare the effect (`checked(...)`, the confirm button's `disabled(...)`→`enabled(...)` gate). If the app exposes no aria state for it, add it — that's an accessibility fix too.
     - Re-clicking a modal/menu opener → model the container as `surface(..., { overlay: true })`; toggle-style panels → pin their singleton in the given and cover open/switch/close in a dedicated toggle workflow.
     - A row/element revealed by a tab or filter switch → declare the reveal on that step.
       Fix the declaration, run `npx ripplo compile` until clean. A workflow passing alone is not grounds to dismiss.
3. **Confirm.** `npx ripplo replay <runId>` re-drives the sequence. Clean = resolved. Edited `.ripplo/`? Confirm with `npx ripplo compile` + `npx ripplo run <affected>`.
4. **Resolve.** `npx ripplo tasks resolve <id> --run <replayRunId>`. **You cannot dismiss a finding** — the server rejects it; intended behavior is still a model fix (declare it). One root cause often resolves sibling findings sharing a failing step.

**Add-vs-weaken guardrail.** Edits that **add** declarations are normal. Edits that **delete or weaken** them (dropping a fact, removing a declared effect, making a fact's values vaguer) only after proving from app source the behavior is intended — cite that proof. Never silence a finding by loosening workflows when the app is wrong.

## Proof — non-negotiable for app changes

- **Exact run + frame + element, or it didn't happen.** Attach `runId`, frame (`--at`/`--offset`), and the element on the resolving comment.
- **The proof run must reproduce the failure condition.** Hover/focus/overlap/scroll bug → the run must perform it.
- **The rendered frame is the evidence, not log text.** A string in `behavior.jsonl` can be the test's own assertion text. Render with `snapshot` and **Read the PNG**.
- **No hand-waving.** See the before, make the change, see the after. Can't see the after → not done.

### Strongest proof: red → green assertion

When the defect is a predicate, pin it with an assertion **red before the fix, green after** — prefer over a one-off screenshot.

- Extend the workflow that exercises the flow, run it red on the broken app, fix, watch it go green.
- **`unobstructed(locator)`** for one element covering another: `hover(row) → expect(unobstructed("..."))`; `not(unobstructed(...))` asserts it _is_ covered. Use `visible`/`value`/`text` and `Entity.created/updated/deleted` the same way.
- Transient element (toast, spinner, skeleton): `ephemeral(text(testId("toast-success"), "Saved"))` waits for it and passes the instant it appears, without leaking onto later steps.
- Backend/state bug → backend assertion on the mutation step. Wrong value → pin the value.

### If not provable in an existing workflow, write one

Don't resolve on a tangential run. Either:

1. Extend the flagging workflow (add the `hover`, seed state, branch), resolve on that run, or
2. Write a new workflow (`/ripplo:create`) reproducing the condition, scope it, run it red→green.

New scaffolding (predicate, entity + impl, given) is in-scope, not a follow-up.

## Visual loop (look/layout/timing bugs no predicate captures)

Also covers a transient element when the complaint is how it _looks_ (style, position, wording) — snapshot the frame where it's up. Pure existence is an `ephemeral(...)` assertion instead.

1. **Baseline.** `npx ripplo snapshot <runId> --offset <frameMs>` (`show` prints the command). Read the PNG, confirm it shows the complaint. Doesn't? Stop and ask.
2. **Find the code** from the anchored element identity + screenshot. Trust the screenshot over a CSS-selector hint.
3. **One targeted change.** Don't stack changes across loops.
4. **Re-run** the workflow (`npx ripplo run <workflow-slug>[/<test-slug>]`); findings re-drive with `npx ripplo replay <runId>` (snapshot the fresh `replay-…` id).
5. **Snapshot the same phase and compare.** Timestamps don't carry across runs — relocate by phase: grep the new `behavior.jsonl` for the anchored step's `"timestamp"`, add the within-step offset, pass via `--at`.
6. **State plainly whether fixed, with before/after PNGs.** Not fixed → new hypothesis, loop.

**Find the right frame — bisect.** No exact frame (flash, stagger, transition)? `snapshot --offset <ms>` prints each frame's offset + total duration. Bracket, snapshot the midpoint, Read, halve toward the frame that shows the visual. Timing complaints need a _sequence_ — snapshot the same offsets in baseline and fix, compare.

## CLI loop

```sh
npx ripplo tasks list                     # open tasks
npx ripplo tasks list --wait              # block until the first finding lands (don't sleep)
npx ripplo tasks show <id>                # thread + anchors
npx ripplo tasks start <id>               # mark picked up
npx ripplo tasks comment <id> <body> --run <runId> --offset <ms> --element <rrwebId> [--as <name>]
npx ripplo tasks resolve <id> --run <runId> [--note <text>] [--as <name>]
npx ripplo tasks clarify <id> <body>      # blocked on the user
npx ripplo tasks dismiss <id> [--note <text>]   # not actionable
```

- **Anchor the proof comment to an element + frame.** For `--element`: run `snapshot`, grep the `snapshot-<ms>ms.html` for your element (every node tagged `data-rrweb-id`), read the id off the tag. `--element` takes an **element** node id (not a text node — use its parent); `--offset` is ms from recording start where it's present. One `comment` per comment; multiple anchored comments annotate a multi-part fix.
- **`resolve` requires `--run`.** Resolve only after seeing green.
- **`clarify`** only when you genuinely need the user.

## Parallel

Tasks are independent — fan out. Delegate each (or a cluster sharing one workflow) to a subagent, run concurrently.

- **Tell every subagent which skills to load first** — they don't inherit context: `/ripplo:tasks` always, plus `/ripplo:create` (authoring) or `/ripplo:run` (diagnosis) as needed.
- **Don't parallelize tasks editing the same files/workflow** — serialize those.

## Before you resolve

- [ ] Read the snapshot PNG, validated element/state against the DOM.
- [ ] A run exercises the broken condition (hover/state/branch).
- [ ] Fix pinned by a **red→green assertion** or **before/after PNGs you Read**.
- [ ] Resolving comment **anchored to run, frame, element**.
- [ ] Never concluded "fixed" from a diff, toast, or log string.
- [ ] No run reaches the condition? You extended/wrote the workflow that does.
