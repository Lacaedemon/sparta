---
name: verify-via-state-dump
description: Verify a claimed gameplay behavior (a maneuver, formation, speed/physics rule, or combat/morale rule) against the machine-readable per-tick state transcript instead of trusting a video/GIF. Use before merging a PR, whenever a claim is visually ambiguous or seems to contradict a demo clip, or as a standard defect check (blobbing, pulsing, flank/rank-swapping, facing whipsaw) on any newly authored demo.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Verify via state dump

Prove a gameplay claim numerically, from the sim's own per-tick JSON state,
rather than by eyeballing a rendered frame or a GIF. This is the method that
ran across today's maneuver, formation, speed/physics, and combat/morale
verification sweeps (#474, #469, #466, #463, #485, #487, #452, #471, #442,
#449, #454, #497, #439, #431, #460, #495, #465/#517, #541) — it caught five
real bugs that a video-eyeballing pass missed.

## When to use this

- Verifying a PR's or issue's claimed gameplay behavior before merging.
- A demo clip looks plausible but the claim is subtle (mid-maneuver geometry,
  per-soldier identity, an exact speed/timing threshold, a morale/rout
  trigger tick).
- A claim in a PR description or review comment seems to contradict what a
  linked video/GIF shows, or the claim can't be confirmed by eye at all.
- Any newly authored demo, as a standard check against the "Standard demo
  defect checklist" below — run it before considering the demo verified,
  regardless of whether the rendered clip looks fine.

## Why not just watch the video

Aggregate/whole-clip visual checks — and even automated bbox/centroid
footprint checks — can miss real bugs, because they only prove the *summary*
stayed put, not that every individual soldier moved the way the claim says:

- **#517 (about-face centre-pivot).** The unit's final facing and position
  looked correct at the end of the turn. The bug was in the *middle* of the
  turn — the pivot briefly recentered on the unit's centroid instead of
  holding its anchor file — and only showed up sampling frames mid-maneuver,
  not at the clip's start/end.
- **#541 (soldier identity-swap).** The aggregate footprint — centroid,
  bounding box, soldier count — was **identical** before and after, because
  the formation's layout was symmetric: soldiers had swapped which body
  occupied which slot, but the slots themselves didn't move. A bbox/centroid
  check, or a human glancing at the clip, saw "nothing changed" and passed
  it. Only tracking **each soldier by index** (not by slot) caught the swap.

The lesson: aggregate metrics prove less than they seem to. Whenever a claim
is about *identity* or *mid-action* geometry, check per-soldier, per-tick —
not just the start/end aggregate.

## The method

1. **Stage a minimal scenario.** Write (or copy and edit) a scratch
   `demos/inputs/*.json` script — it doesn't need to be committed unless it's
   also going into the PR's demo manifest. Use:
   - `"seed"` — battle seed; `"12345"` is the documented standard layout
     (see `demos/README.md`, "Hand-authoring a scenario", for unit
     uid/position/speed tables).
   - `"drill": true` — solo rehearsal: only team 0 deploys, the sim never
     auto-ends, so a maneuver can be exercised with no combat. Good for
     wheeling/nudge/formation claims.
   - `"scenario": [...]` — stage a custom matchup instead of the default 5v5
     when the claim needs a specific pairing (a rout, a flank charge, a
     morale threshold). Each entry: `team` (0 player / 1 enemy), `type`
     (`Spearmen`/`Infantry`/`Archers`/`Cavalry`), `x`, `y`, optional `facing`
     `[x,y]`, `count`, `morale`, `formation` (0 Normal, 1 Tight, 2 Loose,
     3 Square, 4 Shield Wall, 5 Testudo).
   - `"camera"` — optional keyframes `{tick,x,y,zoom}`; irrelevant to the
     state dump itself (state is read from sim data, not the drawn frame),
     but keep it if you'll also render frames for a sanity look.

   Example (`demos/inputs/wheel.json`, real file in this repo):
   ```json
   {
     "seed": "12345",
     "drill": true,
     "camera": [{"tick": 0, "x": 650.0, "y": 300.0, "zoom": 1.1}],
     "steps": [
       {"tick": 10, "click": [650, 300]},
       {"tick": 30, "key": "C"},
       {"tick": 150, "key": "Z"}
     ]
   }
   ```

2. **Script the exact action the claim is about**, via `"steps"` — each
   stamped with a physics `tick` (60/s):
   - `{"tick": t, "click": [x, y]}` / `"shift_click"` / `"rmb_click"` — a
     press+release at a world-space point (select, or issue an order).
   - `{"tick": t, "box": {"from": [x,y], "to": [x,y]}}` — a drag box-select.
   - `{"tick": t, "rmb_drag": {"from": [x,y], "to": [x,y], "shift": false}}`
     — a right-drag move/form-up order.
   - `{"tick": t, "key": "Y"}` — a gameplay hotkey (formation cycle, stance,
     etc.).

3. **Dump per-tick state.** Either add a `"state": [t1, t2, ...]` array to
   the input script, or set the `SPARTA_DEMO_STATE` env var (the two merge).
   Use the wrapper:
   ```sh
   GODOT_BIN="C:\path\to\Godot_v4.7-stable_win64_console.exe" \
     tools/demo/dump-state.sh demos/inputs/<script>.json 8,60,140 /tmp/state
   ```
   This runs `--headless` (fast, no window) and writes one
   `state_<tick>.json` per tick to the output dir. Pick ticks the run
   actually reaches — a battle freezes its tick when it ends (rout resolves,
   one side wiped), so a tick armed past that never fires; for a `drill`
   scenario the sim never auto-ends, so any tick up to the script's length
   works.

   Set `SPARTA_DEMO_STATE_FULL=1` when the claim is about **individual
   soldiers** — identity, per-body position/facing — not just the unit as a
   whole. This adds `soldiers_full` per unit: index-aligned `pos`, `facing`,
   `hp`, `prone`, `stamina` arrays (world-space `[x,y]` pairs for pos/facing).
   Without it you only get `soldier_summary` (`count`, `centroid`, `bbox`,
   `prone_count`) — a compact digest that, per #541 above, cannot distinguish
   "nothing moved" from "everyone moved and swapped identities."

   Per-unit fields always present: `uid`, `name`, `team`, `position`,
   `facing`, `morale`, `state` (`IDLE`/`MOVING`/`FIGHTING`/`ROUTING`/`DEAD`),
   `formation` (`NORMAL`/`TIGHT`/`LOOSE`/`SQUARE`/`SHIELD_WALL`/`TESTUDO`),
   `soldiers` (living count), `current_speed`, `order_mode`, `rank_relief`
   (intra-unit rank-rotation mode), `target_enemy_uid`, `engaged`, `tier`
   (`CLOSE`/`FAR`), `current_order`, `order_phase`.

   **A `tier: "FAR"` unit carries no per-soldier payload at all** — no
   `soldier_summary` and no `soldiers_full`, even with the full flag set: a
   far-tier formation is an aggregate record with no individual bodies
   (docs/large-scale-simulation-design.md). Check `tier` before concluding a
   missing `soldier_summary` means a malformed dump; the aggregate scalars
   (`position`, `facing`, `morale`, `soldiers`) are still present and are the
   right fields to assert on. A per-soldier claim about a far-tier unit is
   unverifiable by construction — the scenario must keep the unit close-tier
   (inside DEMOTE_RANGE of an enemy) for the ticks under test.

4. **Compute the right metric for the claim** — don't default to the
   aggregate:
   - **Footprint/spacing claims** ("the block stays in formation", "the unit
     doesn't spread out") — `soldier_summary.centroid` / `.bbox` / `.count`
     across ticks is enough.
   - **Identity/individual-body claims** ("soldier stays in its own file",
     "no soldier teleports/swaps") — use `soldiers_full`. Track **by array
     index**, not by nearest-neighbor position: soldier `i` at tick A should
     (or per the claim, should NOT) be near soldier `i`'s own tick-B slot.
     Compare index-to-index across ticks, not just "is some soldier near
     this spot."
   - **Timing claims** (first casualty, rally tick, rout-trigger tick,
     speed-cap-reached tick) — scan the per-tick `state`/`morale`/`soldiers`/
     `current_speed` sequence for the tick where the value crosses the
     claimed threshold; report that tick number.

5. **Compare against the claim numerically.** State the exact numbers (tick,
   position, morale, index) that confirm or refute the claim. Don't describe
   a frame — quote the JSON values.

6. **If the claim doesn't hold**, search for an existing issue first
   (`gh issue list --search ...`), then file one with the concrete
   before/after numbers as proof — a tick table (tick, field, expected,
   actual), not a prose description.

## Standard demo defect checklist

Run this checklist against **every newly authored demo**, not just when a
rendered clip looks visibly wrong — that's the whole point of checking
numerically instead of by eye (see "Why not just watch the video" above). Each
item below is a specific, previously-documented failure mode; compute the
listed metric from a `dump-state.sh` transcript (`SPARTA_DEMO_STATE_FULL=1`
for the identity-tracking checks) across a **dense** tick sequence spanning
the whole clip, not just the start/end.

1. **Blobbing** — soldiers clump together, losing their commanded rank/file
   spacing. *Check:* compute the mean nearest-neighbor distance between every
   pair of `soldiers_full.pos` entries for the unit, per tick. Flag it if the
   mean drops well below `FORMATION_SPACING` (9.0 world units / 0.45m)
   *without* an explicit tighter-order (`TIGHT`/`SHIELD_WALL`/`TESTUDO`) active
   in that tick's `formation` field — those orders intentionally compress
   spacing, so check `formation` before calling a tight mean a defect.

2. **Pulsing** — a formation's footprint expands and contracts repeatedly
   instead of holding steady or changing smoothly and monotonically. *Check:*
   compute `soldier_summary.bbox` area (or width × depth) per tick across the
   dense sequence and count local minima/maxima. More than one full
   expand-contract cycle, absent an intentional formation-shape change (a
   frontage resize, a Square deploy), is pulsing.

3. **Flank-swapping** — the unit's left and right flanks trade places.
   *Check:* using `soldiers_full`, project each soldier's position onto the
   axis perpendicular to `facing` (its lateral offset from the unit centroid),
   tracked **by array index** across ticks. Flag any soldier whose lateral
   offset flips sign relative to centroid while its immediate index neighbors
   don't. This is the LEFT/RIGHT-restricted case of the general per-soldier
   identity-swap class described in #541 above — same technique (index, not
   nearest-position), scoped to one axis.

4. **Rank-swapping** — front and rear ranks trade places. *Check:* the same
   by-index projection as flank-swapping, but onto the axis *parallel* to
   `facing` (depth from centroid) instead of perpendicular. Flag a soldier
   whose depth sign flips relative to its rank-neighbors. This is the
   FRONT/BACK-restricted case of the same #541 identity-swap class.

5. **Facing whipsaw / continuous rotation / reshape surge** — the broader
   "swirl" family: rapid back-and-forth reorientation, a steady unwanted
   rotation, or a position jump during what should be an in-place reshape.
   *Check:* dump `facing` at dense intervals across the whole clip and watch
   for large or non-monotonic swings even when the unit arrives at the
   correct final state (see "Bbox-settling checks alone miss a mid-march
   swirl" in `.claude/memories/sparta.md`). For an in-place reshape or turn,
   also check that `position` (the regiment centroid) holds still or moves
   smoothly rather than surging mid-transition.

**Escalate to torque instrumentation once the checklist finds something.**
These five checks tell you a defect is present; they don't tell you which
subsystem produces it. When the pulsing or rotation checks above trip,
reach for the heavier cumulative-torque-instrumentation technique in "Two
DISTINCT root causes behind 'formation visibly spins'" in
`.claude/memories/sparta.md` — temporary `print()`s in
`Battle._on_soldier_tick()` accumulating a net-torque proxy per soldier-layer
stage, printed every N ticks, always reverted before committing. It's too
heavyweight to run by default on every demo, but it's the tool that
root-caused #724 and #774, and a fresh run (not an assumption that a prior
fix still applies) is the right next step whenever this checklist flags a
rotation or pulse.

## Known pitfalls

- **GIF frame extraction needs PIL's `ImageSequence`, not ffmpeg**, when
  ffmpeg isn't available locally. Sample frames across the **whole** clip,
  not just the start/end — a footprint-preserving maneuver bug (#517) can
  live entirely in the middle of the motion and never show at the
  endpoints.
- **Verify a cited commit SHA actually matches the PR's current HEAD**
  before trusting a linked demo as representative of the code under review.
  A demo comment can go stale after a later push. Issue #542 tracks a CI
  freshness gate for this; until it lands, check manually
  (`gh pr view <N> --json headRefName,commits` or compare the SHA in the
  demo-media link against `git rev-parse HEAD` on the PR branch).
- **Aggregate metrics can't distinguish "nothing moved" from "everything
  moved and swapped identity-preservingly."** Any claim of position- or
  identity-invariance (a formation change that's supposed to preserve who
  stands where, a maneuver that's supposed to keep files intact) needs a
  per-soldier-index check, not just a bbox/centroid comparison — see #541.

## Reference

- `demos/README.md`, "Verifying a demo by state (AI verification)" — the
  full field reference and CI's automatic per-PR transcript.
- `tools/demo/DemoState.gd` — pure serialization (`soldier_summary`,
  enum-name tables).
- `tools/demo/DemoInputRecorder.gd` — the recorder; builds `soldiers_full`
  (`_soldier_arrays`) and the per-unit record.
- `tools/demo/dump-state.sh` — the CLI wrapper used above.
- `demos/inputs/*.json` — existing scripted-input scenarios to copy from
  (e.g. `wheel.json`, `rout-rally.json`, `about-face.json`,
  `file-doubling.json`).
