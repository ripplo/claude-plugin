---
name: iterate
description: "Act on Ripplo replay feedback: reproduce the flagged frame with ripplo snapshot, change the app, re-run the test, and verify the fix visually."
---

# Iterate on Replay Feedback

Use this when the user pastes a `Ripplo replay feedback` block — produced by the replay UI's inspect mode. The payload names a run, an exact frame (`--at` epoch-ms), the flagged element, and the user's note. Your job is a closed visual loop: see the baseline, change the app, re-run, see the result.

## What the payload gives you

- **Run handle** — `npx ripplo snapshot <runId> --at <epochMs>` reproduces the exact frame. The PNG path is printed; Read it. You are looking at what the user looked at.
- **Element identity** — tag, role/name, testid, and a best-effort CSS selector. The selector is a **hint, not ground truth**: the replayed DOM may lack stable hooks. Trust the screenshot + the user's note + the source anchor over the selector.
- **Temporal context** — the offset and nearest step title ("320ms into 'goto /event-types'"). This is how you relocate the same moment in a _new_ run.
- **Source anchor** — the test's `sourcePath` @ commit sha. File-level only; find the component from the element identity + your knowledge of the app.

## The loop

1. **See the baseline.** Run the payload's snapshot command, Read the PNG. Confirm you see what the note describes. If sub-second timing matters (skeleton flashes, staggered loads, transitions), snapshot 2–3 nearby moments (±100–300ms) to bracket the behavior.
2. **Find the code.** Use the element identity (testid, role, text) and the flagged computed styles to locate the component. The test source file shows which flow renders it.
3. **Make ONE targeted change.**
4. **Re-run the test** named by the source anchor: `npx ripplo run <test-id>`.
5. **Snapshot the same phase in the new run.** Timestamps do NOT carry across runs — timings shift. Relocate by phase, not by ms: grep the new `.ripplo/debug/<newRunId>/behavior.jsonl` for the step named in the payload's temporal context, take its `"timestamp"`, add the payload's offset-within-step, and snapshot there. Adjust ±100–300ms if the moment is animation-sensitive.
6. **Read the new PNG and compare against the baseline.** State plainly whether the complaint is fixed. If not, loop with a new hypothesis — don't stack changes.

## Timing complaints ("X appears after Y", "flashes", "janky")

These need bracketing, not a single frame. Snapshot the same few offsets in baseline and fix runs (e.g. step-start +50ms, +150ms, +300ms) and compare the sequences. The fix is verified when the new sequence shows the elements appearing together / the flash gone — not when one lucky frame looks right.

## Discipline

- Never claim a visual fix without Reading the post-fix snapshot. The PNG is the proof.
- Don't weaken or retarget the test to make the frame "right" — the test defines behavior, the feedback is about presentation within it.
- If the baseline snapshot doesn't show the user's complaint, say so and ask before changing anything — you may be looking at the wrong moment or the wrong element.
