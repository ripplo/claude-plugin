---
name: iterate
description: "Act on Ripplo replay feedback: reproduce the flagged frame with ripplo snapshot, change the app, re-drive the run (ripplo run for authored tests, ripplo replay for explore findings), and verify the fix visually."
---

# Iterate on Replay Feedback

Use when the user pastes a `Ripplo replay feedback` block (from the replay UI's inspect mode). The payload names a run, an exact frame (`--at` epoch-ms), the flagged element, and the user's note. Your job is a closed visual loop: see the baseline, change the app, re-run, see the result.

## The payload

- **Run handle** — `npx ripplo snapshot <runId> --at <epochMs>` reproduces the exact frame; Read the printed PNG. For later snapshots prefer `--offset <ms>` (ms from recording start) — the output prints each frame's offset and the duration, so bracketing is `--offset 50`, `--offset 150`, `--offset 300`.
- **Element identity** — tag, role/name, testid, best-effort CSS selector. The selector is a hint, not ground truth — trust the screenshot, the user's note, and the source anchor over it.
- **Temporal context** — offset and nearest step title ("320ms into 'goto /event-types'"). This is how you relocate the same moment in a new run.
- **Source anchor** — the test's `sourcePath` @ commit sha, file-level only. Present means authored test, absent means explore finding (see below); either way, find the component from the element identity.

## Authored test vs explore finding

Source anchor present → **authored test**: has a test id, re-drive with `npx ripplo run <test-id>`.

Source anchor absent → **explore finding** (`explore-…` run handle): re-drive the stored walk with `npx ripplo replay <runId>`. `run` and `teleport` do not work on explore runs. `replay` records a fresh run and prints its id (`replay-…`); snapshot that id to see the result, not the original.

## The loop

1. **See the baseline.** Run the payload's snapshot command, Read the PNG, confirm it shows what the note describes. If snapshot reports the run isn't on disk (a cloud run), pull it first: `npx ripplo pull <runId>`. If sub-second timing matters (skeleton flashes, staggered loads), bracket 2–3 nearby moments (±100–300ms).
2. **Find the code** from the element identity and flagged styles.
3. **Make one targeted change.**
4. **Re-run** per run kind (see above): `npx ripplo run <test-id>` or `npx ripplo replay <runId>`.
5. **Snapshot the same phase in the new run** — the `replay-…` id for explore, the fresh authored run otherwise. Timestamps don't carry across runs — relocate by phase, not absolute ms. Start with `--offset` at the baseline frame's printed offset and bracket. For precision, grep the new behavior.jsonl for the step named in the temporal context, take its `"timestamp"`, add the payload's within-step offset, pass via `--at`. If the file isn't on disk (cloud run), pull it first: `npx ripplo pull <runId>`.
6. **Compare PNGs and state plainly whether the complaint is fixed.** If not, loop with a new hypothesis — don't stack changes.

## Timing complaints ("X appears after Y", "flashes", "janky")

Bracket, don't single-frame: snapshot the same few offsets in baseline and fix runs and compare the sequences. Verified when the new sequence shows the behavior gone — not when one lucky frame looks right.

## Discipline

- Never claim a visual fix without Reading the post-fix snapshot. The PNG is the proof.
- Don't weaken or retarget the workflow to make the frame "right" — the workflow defines behavior; the feedback is about presentation within it.
- If the baseline doesn't show the user's complaint, say so and ask before changing anything — you may have the wrong moment or element.
