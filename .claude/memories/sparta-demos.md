---
name: sparta-demos
description: "Authoring, recording, and machine-verifying Sparta PR demo clips — the scripted-input recorder is the standard path"
metadata:
  type: feedback
---

# Sparta — demo authoring & verification

The scripted-input recorder is the **standard** demo path as of #318/#321. The
older hand-authored/recorded `replay` path (documented in the main `sparta.md`
"Authoring & verifying demo scenarios" section) still works and is fine for a
quick reuse of `demos/showcase.json`, but prefer scripted input for anything that
shows a specific player gesture.

## Standing rule: always check a demo thoroughly for unnatural behavior, not just the claimed feature

Before treating a demo/recording as verified, watch (or dump-state) the **whole
clip**, not just the tick(s) that prove the specific feature under review. A
demo that correctly shows the intended mechanic can still contain something
else unnatural — a facing whipsaw, a swirl, a stray unit drifting off-order, a
formation intermixing — that a narrow "does the claimed thing happen" check
walks right past. Several incidents below were each found this way, only
because someone looked at the full clip rather than the specific claim:
mid-march facing swings invisible to a bbox-only settle check (#774), a
melee-lock formation swirl found only by extending a 300-tick trace to 700
(#724), a reform-hold swirl exposed only once a timing fix made the hold long
enough to render it, and an inherited combat scenario that never actually
reached the moment its own caption described (#623, "A stalled approach").

**How to apply:**
- Watch/dump the full clip end to end (per-tick `facing`, position, and
  `order_mode`, not just a few widely-spaced sample ticks — see "Bbox-settling
  checks alone miss a mid-march swirl" in `sparta.md`) and ask "does anything
  here look wrong," not only "does the claimed thing happen."
- Extend the trace window if a rotation/drift looks like it might still be
  accelerating rather than settling — a 300-tick sample can look stable while
  a 700-tick one reveals a real, still-growing problem (#724).
- Treat a demo review as covering the **whole battle**, including units and
  ticks the caption doesn't mention — an unrelated transient elsewhere in the
  same clip can be mistaken for a bug in the change under review, or a real
  bug can hide in a part of the clip nobody was told to look at.
- This is a strengthening of, not a replacement for, the state-dump and
  frame-capture techniques below — use those tools, just point them at the
  entire clip rather than only the claimed moment.

## Author a scripted-input demo (the standard path)

Sparta PR demos **can** show player-gesture features (multi-unit form-up, orders,
etc.) — don't reflexively `skip` them.

1. Write `demos/inputs/<name>.json`:
   `{ "seed":"12345", "camera":[{tick,x,y,zoom}], "steps":[...] }`. Steps are
   stamped with a physics tick (60/s) and use world coords: `click [x,y]`,
   `shift_click`, `rmb_click`, `box {from,to}`, `rmb_drag {from,to,shift?}`,
   `key "Y"`.
2. Point a **per-PR** manifest `demos/demo.<issue-or-PR#>.json` at it (NOT the
   bare `demos/demo.json` — that single shared file caused constant merge
   conflicts; #416/#417 switched CI to prefer a `demos/demo.*.json` file *added*
   in the PR diff, falling back to `demo.json` then `showcase.json`). Shape:
   `{ "input":"demos/inputs/<name>.json", "caption":…, "fixed_fps":30,
   "max_frames":150, "fps":15, "width":720 }`. For a static/illegible-in-motion
   change, `{ "skip":true, "reason":… }` and rely on stills in the PR body.
3. CI's Demo video workflow detects `input` and runs
   `tools/demo/DemoInputRecorder.tscn`, which drives a LIVE battle by injecting
   the steps through the real `SelectionManager`, so the clip exercises the actual
   controls.

**Standard 5v5 (`seed "12345"`):** player uids 0-4 =
Spearmen(140)/Infantry(120)/Archers(90)/Cavalry(80)/Cavalry(80) at
x=476.75/626.75/806.75/973.25/1123.25, y=300; enemies 5-9 at y=700 (issue #677:
the x's are no longer an even 500/650/800/950/1100 -- `Battle._spawn_line` now
widens each adjacent pair's gap to fit their actual formation widths instead of a
flat 150 px, so a wide LOOSE-order regiment like Archers can't overlap its
neighbour; see `demos/README.md` for the per-unit table and the derivation).
Spawn positions are seed-independent, so clicks land regardless. For a form-up
facing the enemy (+y/down), drag **right→left** (start point on the right).
Box-select a horizontal row with e.g. `{from:[450,270], to:[850,330]}` (grabs
uids 0/1/2 -- still valid since it only needs to bracket the row, not exact x's).
Pick infantry (pointer marks) for facing-maneuver demos — they read cleanly
under rotation. Demo click coords are **world** coords (cursor override), not
screen.

## Verify locally without ffmpeg (PNG-frame capture)

Movie Maker writes a PNG sequence for a `.png` path:

```sh
SPARTA_DEMO_INPUT="res://demos/inputs/<name>.json" "$GODOT_BIN" \
  --rendering-driver opengl3 --write-movie <scratch>/f.png \
  --fixed-fps 30 --quit-after 130 res://tools/demo/DemoInputRecorder.tscn
```

then `Read` a frame PNG. (The live `_draw()` renders the form-up preview during
the drag, so the gesture shows.) Drop `--headless` on Windows — it crashes Movie
Maker. Run `--headless --import` first in a fresh worktree. See the
"Local testing" section of `sparta.md` for the binary.

**Throwaway tool-scene screenshots** — for a state a recorded battle can't easily
reach, write a one-off `tools/demo/_shot_<n>.gd` + `.tscn` (a `Node` that loads
`Battle.tscn`, drives it, then
`get_viewport().get_texture().get_image().save_png("user://…")` and
`get_tree().quit()`), run it `--rendering-driver opengl3` (NOT headless — the
dummy renderer gives a null texture), then `Read` the PNG and **delete the
throwaway files**. Forcing states: hold-Space order overlay →
`Replay.mode = Replay.Mode.PLAYBACK; Replay.show_demo_orders = true`; mark LOD →
set `cam.zoom < 1.30` (below `LOD_ZOOM_OUT`). Annotate untyped
`load(...).instantiate()` with `: Node` or it's a parse error.

**Upscale crops to verify few-pixel render detail.** Mark-LOD glyphs are ~2 px; a
full-size screenshot looked fine but *hid* a regression (a "fixed" mark was
actually striping the other way). Crop and upscale with PIL NEAREST:
`Image.open(p).crop(box).resize((w*7,h*7), Image.NEAREST).save(out)`. Render
principle this caught: a directional mark glyph must be **compact along the facing
axis** (front-reach ≤ the infantry pointer's span); elongating it just trades
horizontal stripes for vertical ones when a packed rank rotates. Distinguish unit
types by *silhouette* (dart/kite/pointer), keeping team colour pure — a per-type
colour tint muddies the block's team-colour `modulate`.

## Verify a demo by exact game-state values (state dump)

As of PR #501 (#500) a demo can be verified by **reading exact game-state
values**, not just interpreting a rendered frame. It's the machine-readable
companion to `SPARTA_DEMO_FRAMES` PNG capture (#492), on the same recorder.

**Dump command (Windows / Git Bash):**
```sh
GODOT_BIN="…/Godot_v4.7-stable_win64_console.exe" \
  tools/demo/dump-state.sh demos/inputs/rout-rally.json 8,60,140 /tmp/state
```
Then `Read` each `state_<tick>.json` and assert on the values. Unlike frame
capture, the dump reads sim state (not the drawn frame), so it runs
**`--headless`** — no `--rendering-driver opengl3`, no window, faster.

**Plumbing (mirrors the frames path):**
- Env `SPARTA_DEMO_STATE` = comma-separated tick list; `SPARTA_DEMO_STATE_DIR` =
  out dir (default temp); `SPARTA_DEMO_STATE_FULL=1` also dumps raw per-soldier
  arrays.
- An input script can carry a `"state": [ticks]` array; env + script merge via the
  same `DemoFrames.merge_ticks` used by `frames`.
- Env-gated: unset = off; normal recording and the frames path are unchanged.

**Per-unit JSON fields** (readable enum NAMES, not ints): `uid`, `name`, `team`,
`position` [x,y], `facing` [x,y], `morale`, `state`
(IDLE/MOVING/FIGHTING/ROUTING/DEAD), `formation`
(NORMAL/TIGHT/LOOSE/SQUARE/SHIELD_WALL/TESTUDO), `soldiers`, `current_speed`,
`order_mode` (from `Battle.ORDER_MODE_NAMES`), `target_enemy_uid`, `engaged`, and
a `soldier_summary` {count, centroid, bbox, prone_count}.

**Pure-vs-node split:** the enum-name maps + `soldier_summary` are pure static
funcs in `tools/demo/DemoState.gd` (a `class_name`, unit-tested in
`test/unit/test_demo_state.gd` like `DemoFrames`); the node-side dump (walking the
"units" group, JSON write) lives on `DemoInputRecorder.gd`. New `class_name` → run
`godot --headless --import` and commit the `.gd.uid`.

**Gotchas baked into the dump:**
- `_sim_soldier_pos` is WORLD-space; the summary centroid/bbox use it directly.
- "prone" is per-soldier (`_sim_prone[i] > 0` = down); "engaged" is per-UNIT
  (`is_engaged()`) — so the summary carries `prone_count` per-soldier but
  `engaged` is a unit bool.
- A unit routs only at `morale <= 0` (`UnitCombat.gd`). Don't claim a ROUTING
  state a scenario doesn't actually produce (the `rout-rally.json` staged unit is
  annihilated before morale hits 0, so it never reaches ROUTING within reachable
  ticks).
- Enum-name maps use an explicit table with an "UNKNOWN(<n>)" fallback, so a new
  enum member surfaces as a greppable token. A merge that adds enum members (e.g.
  main adding SHIELD_WALL/TESTUDO) leaves the map STALE even when conflict-free —
  update the map + its test + the README field row.

## A unified "all artifacts done" quit-check must guard on armed

When two (or more) optional per-tick artifact paths (frame capture, state dump)
share ONE "are we done?" check that gates `get_tree().quit()`, the check must
require at least one path to be armed. Otherwise the empty case
(`0 == 0 and 0 == 0`) is trivially true and the run quits after the first tick.

This bit PR #501: a state-dump path (`_state_ticks`) was added next to the
frame-capture path (`_frame_ticks`) in `tools/demo/DemoInputRecorder.gd`, unifying
the two done-checks into one `_all_artifacts_done()` called unconditionally each
physics frame. In a normal CI movie recording neither env var is set, so both tick
lists are empty and the naive check returned `true` on tick 1 — quitting every
recording after one frame.

Fix (the guard is load-bearing — keep it FIRST so it short-circuits):

```gdscript
func _all_artifacts_done() -> bool:
	return (_frame_ticks.size() + _state_ticks.size()) > 0 \
		and _captured.size() == _frame_ticks.size() \
		and _state_dumped.size() == _state_ticks.size()
```

Root cause was moving the quit call out of the old `if _frame_ticks.has(tick)`
guard into an unconditional call. When you refactor a guarded side effect into a
shared helper, the guard that was implicit in the enclosing `if` must be made
explicit inside the helper. Also update sibling checks (e.g. a timeout handler) to
use the same unified predicate.

## CI re-record trigger & shared-checkout hazard

CI re-records only when the push diff touches
`scenes/`/`scripts/`/`assets/`/`project.godot`/`demos/*.json`/`demos/scenarios/**`/`demos/inputs/**`
— a demos-only push now DOES re-trigger (fixed in #317). A `main`-merge that drags
scripts into the diff also re-triggers.

**Shared-checkout hazard:** this repo often has concurrent AI sessions on the local
checkout. Always do PR work in an isolated `git worktree` off `origin/<branch>`,
never on the shared checkout. `main` moves fast (physics slices), so expect
repeated `demos/demo.json` merge conflicts — resolve by keeping your branch's
manifest, and check for a `demos/demo.<PR#>.json` first: CI prefers a
`demos/demo.*.json` file *added in the PR diff* over the bare `demo.json`, so the
correct clip records even if the merge left `demo.json` holding another PR's
content. Still fix `demo.json` when it's stale — a `git merge origin/main`
silently takes main's `demo.json` (theirs).

## An inherited demo scenario must still resolve within its own frame budget

When a demo's `input` scenario gets reused or adapted from an earlier feature
(e.g. a hollow-square-render PR reusing the original anti-cavalry-square
combat scenario), it's not enough that the scenario runs without erroring —
verify the specific thing the caption claims actually happens on screen
*before* `max_frames` cuts the clip off. A pure-render PR (#623, the
shield-ring overlay) inherited `anti-cav-square.json`'s rear-cavalry-charge
setup, but the cavalry never reached the infantry within the manifest's
300-frame budget — still `MOVING`/unengaged with ~20 frames left, only
reaching `FIGHTING` at the exact cutoff tick. The clip showed a stalled
approach instead of anything the caption described, and the caption itself
never even claimed a charge (it only described the render change) — the
combat setup was vestigial, carried over from before the feature was split
out of its original test.

**How to catch this:** `tools/demo/dump-state.sh` at ticks spanning the whole
`max_frames` window (not just a few early ones) and check `engaged`/`state`
on every unit through to the last tick. If a "climax" moment (contact,
formation completing, a rally) lands at or after the frame cutoff, either
extend `max_frames` or — better, when the combat isn't actually relevant to
what the PR changed — replace it with a focused no-enemies scenario, e.g.
`demos/inputs/schiltron-formation-only.json`, which drives one unit through a
formation change with no enemy units present so there's no combat arc to time
against `max_frames` at all. This is the same "keep each demo simple and focused"
principle CLAUDE.md already states, extended with a concrete failure mode:
inherited scenario elements that don't actually complete are worse than no
scenario elements at all. (`Lacaedemon/sparta` PR #623, 2026-07-03.)

## Default new demo scripts to `"drill": true` unless the demo needs an enemy

A demo whose actual subject is a maneuver, formation, order-queue, or UI change has no reason
to spawn a live opponent — the default 5v5 layout's enemy AI is pure noise for it, and can
actively confuse verification. `demos/README.md`'s `drill` field docs now state this as the
default: set `"drill": true` unless the demo is specifically about combat/enemy interaction (a
clash, a rout, an engagement mechanic, morale under fire).

This is a preventive default, not a fix for a specific incident this session hit — no PR's
review rounds so far have actually traced back to enemy-proximity/engagement noise (checked:
PR #840's three review rounds were all about caption accuracy on the player's own units'
frontage/timing values, not enemy interaction). The principle stands on its own: a live
opponent adds a whole axis of state (detection range, targeting, engagement) a non-combat demo
has no use for and every reader/reviewer has to mentally rule out.

**How to apply:** when authoring a NEW `demos/inputs/*.json` (per "Author each demo scenario
fresh" below — don't retrofit this onto an existing, already-verified demo just because it
lacks `drill`), default to `"drill": true` and a `scenario` array (or the default single-unit
spawn) containing only the unit(s) the demo needs, unless showing a live opponent is the
actual point. This composes with "Construct scenarios to isolate the phenomenon in question"
below — it's the same isolation principle, applied specifically to "does this demo need an
enemy at all."

## Construct scenarios to isolate the phenomenon in question

The general form of the lesson above, generalized beyond a single frame-budget
timing bug: **when a demo or regression test is meant to prove one specific
mechanic works, stage the scenario so nothing else can interfere with it** —
don't layer the mechanic onto a combat arc whose outcome also depends on
unrelated factors (relative unit speeds, AI targeting choices, RNG).

Concrete case: `test_rout_rally_demo_scenario.gd` (two cavalry vs. one weak
infantry) used to prove a routed unit RALLIES — it relied on routing units
being untargetable, so the cavalry lost interest and the infantry reliably
broke contact. When routing units became valid combat targets (#638, PR #654:
routing units should be attackable), the *same* scenario now reliably shows
the *opposite* outcome — the faster cavalry catch and annihilate the
infantry before it can recover — because "does it rally" now depends on
whether the pursuer can keep pace, not just on the rout mechanic itself. The
combat arc was never a clean proof of "broken units can recover"; it only
happened to demonstrate that under one specific matchup's relative speeds.

Fixed by splitting into two demos/tests, each isolating one phenomenon:
- `test_rout_annihilation_demo_scenario.gd` (renamed from the original file)
  keeps the two-cavalry matchup, now asserting what it actually proves: a
  relentlessly-pursued router is run down and destroyed, not that it rallies.
- `test_morale_recovery_demo_scenario.gd` (new) proves the RECOVERABLE side of
  routing in isolation: a single unit, started already `_rout()`-ing directly
  (not via combat), with **no enemy on the field at all**. Nothing can
  interfere with its morale recovery, so it cleanly demonstrates the "broken"
  state's recovery path on its own.

**Gotcha hit building the isolated version:** a scenario with zero team-1
units (no `{"team": 1, ...}` entries at all) makes `Battle._check_victory()`
see `_team_in_play(1) == false` from tick 0 — with `p_alive == true` this
takes the `elif not e_alive: _end("Victory!")` branch *immediately*, which
sets `get_tree().paused = true`. A GUT test looping `await
get_tree().physics_frame` then hangs forever, since physics frames don't fire
while the tree is paused — `_check_victory()`'s own `drill_mode` early return
exists for exactly this "no opponent" case, so set `_battle.drill_mode =
true` on any single-team scenario, even when using a custom `scenario` array
rather than the default line spawn (`drill_mode` only changes *spawning*
behavior on the default-line path, but `_check_victory()` reads it
unconditionally regardless of how units were spawned).

Also relevant when authoring a demo this way: a routing state can currently
only be reached as a side effect of real combat casualties
(`UnitCombat.register_casualties`'s `morale <= 0` check calls `Unit._rout()`)
— a scenario/replay file alone can't declare a unit's starting state as
ROUTING the way a GUT test can by calling `_rout()` directly. That's why the
isolated recovery case above is a GUT-test-only regression guard for now, not
also a recordable website demo clip — sparta#657 tracks the follow-up to make
it recordable. (`Lacaedemon/sparta` PR #654, 2026-07-04.)

## A hotkey rebind (merge-conflict collision fix) has THREE copies to sync, not one

When resolving an `OrderMode`-enum merge collision (see `sparta.md`'s
"Battle.gd merge" section) forces a stance's default hotkey to change —
e.g. `all_out_attack` rebinding off a colliding `KEY_COMMA` to a free
`KEY_PERIOD` — the code fix (`Settings.gd`'s `DEFAULT_ORDER_BINDINGS`,
`Battle.gd`, `HUD.gd`) is only one of three places that name the key. The
other two are easy to miss because they're prose/data, not code a compiler
or test suite checks:

- **The scripted-input demo file itself** (`demos/inputs/<name>.json`):
  its `steps` array presses the OLD key literally
  (`{"key": "Comma", "ctrl": true}`), so after a rebind it silently arms the
  WRONG stance instead of erroring — the recording still runs to completion,
  it just demonstrates the wrong thing. Its own `_comment` field usually
  also spells out the key in prose ("Ctrl+,") and goes stale the same way.
- **The per-PR demo manifest's caption** (`demos/demo.<N>.json`'s
  `"caption"` field): CI copies this verbatim into the PR description, so a
  stale key symbol here (`"hotkey ,)"`) tells every reader of the PR the
  wrong key even though the code and the recording are both already fixed.

None of these three are caught by `tools/check.sh validate test` — the
Godot import and GUT suite don't read caption strings or demo JSON prose.
The only thing that catches the demo-input-file case is actually running
the recording and reading the result: `tools/demo/dump-state.sh
demos/inputs/<name>.json <ticks> <outdir>`, then confirming the armed
unit's `order_mode` field names the INTENDED stance, not some other one —
CI's own per-tick state transcript comment on the PR is the same check,
just after the fact. After any hotkey rebind, grep the whole repo for the
OLD key's string name (`grep -rn '"key": "Comma"' demos/` or whatever the
prior binding was) to find every stale copy before considering the fix
complete, and re-verify with a state dump rather than trusting that fixing
`Settings.gd` was the whole job. (`Lacaedemon/sparta` PR #704, 2026-07-10:
a merge-resolution agent correctly rebound `all_out_attack` to `KEY_PERIOD`
in every code site but missed both `demos/inputs/all-out-attack.json`'s own
key press and `demos/demo.704.json`'s caption — caught only via the live
CI state transcript showing `Sweep routers` armed instead of `All-out
attack`, then a second stale caption reference caught by a follow-up
review round.)

## A bare stance/order key only ARMS it — Ctrl+key is what issues it immediately

`SelectionManager._dispatch_key()` resolves a stance/order hotkey (`H`, `F`, `K`, etc. —
anything in `Settings.order_bindings`) to a mode, then branches on the modifier: a PLAIN
keypress calls `_set_armed_mode(mode)` ("arm a smart-order stance" — it takes effect on the
NEXT move/attack order the player issues), while `Ctrl+<key>` calls `_issue_stance(mode)`
("writes the stance in place immediately — no move/attack needed"). A demo scripting a bare
`{"key": "H"}` to put a unit on `ORDER_HOLD` right after spawn does NOT actually change
`order_mode` at all — the state dump keeps reading `order=Normal` no matter how much later
you check, since nothing ever issued the armed stance (there's no subsequent order to
trigger it). This differs from a plain FORMATION hotkey (`O`, `T`, `L` for Square/Tight/
Shield Wall) — those apply immediately on a bare keypress; only ORDER-MODE stances
(`Settings.order_bindings`' own keys) have the arm-vs-issue split.

**How to apply:** any demo/test that needs a specific `order_mode` (not formation) to be
ACTIVE, not just armed, must script `{"key": "<letter>", "ctrl": true}` — verify with
`dump-state.sh`'s `order_mode` field before trusting the scenario, the same way you'd verify
any other scripted key. (`Lacaedemon/sparta` PR #749, 2026-07-11: `{"key": "H"}` alone left
`order_mode` reading `Normal` through the whole recording, letting a `HOLD`-intended
defender auto-chase the approaching charger — fixed by adding `"ctrl": true`.)

## Movie Maker's `fixed_fps` sets the VIDEO frame rate, not the physics tick rate — don't assume 1:1

Physics runs at a fixed 60 ticks/sec regardless of a recording's `--fixed-fps` value
(`project.godot` has no `physics_ticks_per_second` override, and Movie Maker only forces
the RENDER/video step to advance in lockstep with simulated time — it doesn't slow physics
itself down to match). So `demos/demo.*.json`'s `max_frames` (a VIDEO frame count, at
`fixed_fps`) does NOT equal the number of physics ticks the clip covers unless
`fixed_fps: 60`. At `fixed_fps: 30`, each video frame spans 2 physics ticks, so
`max_frames: 210` covers roughly **420** physics ticks, not 210. The existing "Extract
frames without ffmpeg" section above states "Frame index == physics tick at `--fixed-fps
60`" — that's only true at `fixed_fps: 60` specifically; it does NOT generalize to other
`fixed_fps` values, and reading it that way silently miscounts by whatever
`60 / fixed_fps` ratio applies.

**How to verify empirically rather than assume:** re-run the exact recording command
(`--fixed-fps <N> --quit-after <max_frames>`) with `SPARTA_DEMO_STATE` armed at ticks near
your predicted cutoff (both the naive 1:1 guess and the `60/fixed_fps`-scaled one) —
`dump-state.sh`'s state-dump pass isn't bounded by `max_frames`/`--quit-after` (it runs
until every armed tick is captured or the recorder itself quits), so whichever ticks
actually get dumped before the run ends tells you the true cutoff directly, rather than
computing it by hand.

**Why this matters:** a review finding claimed a demo's `max_frames: 210` (at
`fixed_fps: 30`) cut off before a claimed "cavalry visibly decelerates" moment, reasoning
from the WRONG (1:1 tick:frame) assumption — CI's own per-tick state transcript comment
happened to include ticks up to 390, which is genuinely `dump-state.sh` running past the
movie's own cutoff (per the tool's design), not evidence the movie itself covered that far.
The empirical re-run above (ticks 209/270/330/390 all captured within the SAME
`--quit-after 210` command CI runs) settled it: the clip's actual physics-tick coverage
extends well past what a naive frame==tick reading would suggest, and the deceleration was
genuinely within frame budget. (`Lacaedemon/sparta` PR #749, 2026-07-11.)

## Author each demo scenario fresh — don't copy an existing one's scenario/steps

Copying an existing `demos/inputs/*.json`'s `scenario`/`steps` block as a starting point for
a new demo — even with modifications (a different unit type swapped in, an extra scripted
step appended, a tweaked caption) — is not acceptable. Write each new scenario from scratch:
its own unit types, its own coordinates, its own seed, its own step sequence, chosen to fit
what THIS demo needs to show, not inherited from whatever scenario happened to be handy.

This is distinct from "Construct scenarios to isolate the phenomenon in question" above —
that section is about NOT layering a new mechanic onto an inherited combat arc with
unrelated interfering factors. This rule is broader: don't reuse another demo's scenario
file as a template at all, even when the borrowed setup would isolate the phenomenon fine on
its own. A fresh scenario is also more likely to actually fit the new feature (e.g. a
different unit count/type, a different attack geometry) instead of forcing the new feature
into a shape designed for something else.

**Concrete case:** PR #758's `engaged-highlight-live-proximity.json` (the engaged-soldier
highlight debug visual) was first written by copying `anti-cav-square.json`'s two-cavalry-
rear-charge setup wholesale (same Infantry unit, same coordinates, same seed) and only adding
a `show_engaged_highlight` flag and a Hold step. The user flagged this directly: "stop
copying demo scenarios; create each one fresh." Rewritten from scratch with a different unit
type (Spearmen), different seed, different coordinates, and a materially different setup
(three cavalry attacking from three directions at once, rather than two from the rear) — a
choice that also happened to better demonstrate the omnidirectional multi-attacker pressure
the underlying fix (`UnitFormation.live_perimeter_indices`) is about, something the copied
two-attacker-rear scenario didn't showcase as clearly.

**How to apply:** when starting a new `demos/inputs/*.json`, don't `Read` an existing one and
edit a copy. Design the scenario from the feature's own requirements — what unit(s), what
formation, what attack angle(s), what timing best demonstrates the specific behavior under
review — then write it fresh. Re-verify its timing empirically via `dump-state.sh` the same
way any new scenario needs verification, per the sections above. (`Lacaedemon/sparta` PR
#758, 2026-07-11.)

## A precise-tick caption claim on a LONG battle: verify against CI's own posted transcript, not a local `dump-state.sh` run

The "verify before claiming" convention above (and the demo-state-dump entries in `sparta.md`)
assumes a local `dump-state.sh` run is an authoritative stand-in for what CI will show. That
holds for short/simple scenarios, but breaks down for a **long, chaotic** battle (many soldiers
colliding over 700+ ticks): a local Windows headless run and CI's Linux run of the **identical
seed** can diverge in their exact tick-by-tick numbers past some point, even though the AI
decision logic itself and every early tick match exactly.

**Concrete case:** PR #794's reserve-commit demo (`general-doctrine-reserves.json`, a ~900-tick
battle) needed a caption stating the exact tick a reserve unit first engages. A local
`dump-state.sh` run and CI's own posted per-tick transcript for the PR agreed byte-for-byte
through tick 720 (identical morale/soldier counts at every checked 60-tick interval), then
diverged: by tick 780 the local run already showed the unit `FIGHTING` while CI's transcript
still showed `MOVING`, with small differences elsewhere (one unit's morale 88.5 vs 89.2). A
caption written from the local run ("engaged by tick 780") was flagged by review as wrong
against CI's own transcript (still `MOVING` at 780, `FIGHTING` only by 840) — the local run's
claim was internally consistent and directly verified, just verified against the wrong source.
This is very likely floating-point drift compounding over hundreds of ticks of live soldier
collision physics between platforms/builds, not a bug in the PR's own logic (early-tick
agreement was exact, and the same-process determinism tests — replay-identical-on-same-seed —
still pass, since those compare two runs *within the same process*, not across platforms).

**How to apply:** for a demo covering a long/chaotic battle (rule of thumb: several hundred
ticks of live multi-unit combat, not a short scripted maneuver), don't trust a local
`dump-state.sh` run alone for a **precise**-tick claim in a caption — cross-check against CI's
own posted transcript comment for the actual PR/commit before finalizing the wording, or word
the claim with enough tick-range slack (a 60-tick AI-decision window, e.g. "between tick 780
and 840") to be robust to this kind of drift. A local run is still fine for a first-pass
sanity check and for short/simple scenarios where no divergence has ever been observed.
(`Lacaedemon/sparta` PR #794, 2026-07-12.)

**Recurred twice more in one session (PRs #861 and #866, 2026-07-15), both caught by review, not
by the authoring agent's own pre-push check.** #861's caption claimed the position-anchor marker
led its centroid "throughout the clash" from a local run's tick-460 numbers; CI's actual
transcript showed it trailing by 4-6 world units at the two earlier sampled ticks, only pulling
ahead near the end. #866's caption implied all three countermarch variants finish on-screen; CI's
transcript showed the Laconian unit still mid-march at the clip's last sampled tick, needing the
`state` range and `max_frames` extended before it actually settled. Both are the SAME failure
mode this entry already names, just recurring — worth treating as a standing pre-push check for
ANY demo carrying a specific numeric or completion claim (not only "long/chaotic battle" ones):
before finalizing a caption, fetch or generate the transcript for the actual commit that will
ship, not a local run from an earlier or different commit, and confirm every specific claim
against it line by line. When delegating demo authorship to a subagent, state this check
explicitly in the brief up front — both recurrences were from agents who verified locally, wrote
a confident caption from that, and never diffed it against what CI would actually record.

## Footprint-preserving maneuvers are inherently subtle on screen — stage for legibility, verify by per-region pixel-diff

A footprint-preserving maneuver — the conversio/about-face (#394), where the block reverses 180°
in place, front rank becoming rear, keeping its exact footprint — barely moves the block
silhouette; only the internal rank order flips. A naive eyeball of a few sampled frames wrongly
reads it as "static" (exactly what happened on PR #465's first CI clip). Quarter-turns (#371) and
file-doubling share the trap. This is the *perceptual* counterpart to sparta.md's "Verify
maneuvers tick by tick" entry (that's about sim correctness): the sim can be perfectly correct
while the clip still fails the "the demo must SHOW the change" bar.

**Author for legibility.** Stage a **lone unit** (recorder `scenario` field + `"drill": true`, no
opponent) rather than the default 5v5 line where the pivot is buried; use a **tight camera**
framed clear of the bottom HUD (~90 px of world); keep the **rear destination close** so both the
pivot and the ensuing (~15 px/s) march land inside the clip; frame the mid-pivot moment where the
block is rotated diagonally through its intermediate heading.

**Verify clip motion by per-region inter-frame pixel-diff, not a coarse scan.** Measure the
**unit region** separately from the **UI region** (HUD/selection ring animate independently and
can mask/fake motion). The signature of a maneuver landing is the **unit-region change ramping
up then plateauing** (turn starts → peaks mid-pivot → settles). A flat unit-region diff = not
visible; a diff confined to the UI region = only chrome moved. Cross-check with a state dump (on
#465 the dump confirmed facing `[0,1]` → through-west → `[0,-1]` with position holding through the
pivot, then advancing). Use `SPARTA_DEMO_FRAMES` (PNG, non-headless) for the framed moments and
`SPARTA_DEMO_STATE` (headless) for the values. Bump website `record-demos.sh` `max_frames` to
cover the whole sequence (e.g. 180 → 300), not just the pivot.

## A delegated implementation task needs the demo-manifest contract stated explicitly, not assumed

Briefing an agent (human or AI) to "implement issue X" does not automatically produce a
`demos/demo.<slug>.json` for the resulting PR — the demos/README.md "author contract" and its
required self-check are easy to omit from a task brief that's otherwise thorough (data model,
tests, regression coverage), because they live in a separate doc the brief never pointed at.
When no per-PR manifest lands, CI's resolution order (`demos/README.md`'s "Resolution order")
silently falls back to the legacy shared `demos/demo.json` — which usually holds **another,
unrelated PR's** input script and caption (it's a perennial stale leftover; see "Shared-checkout
hazard" above). The posted demo section then looks complete (a GIF renders, a caption reads
fluently) while describing a different change entirely, with nothing in CI flagging it — this is
a silent content-accuracy bug, not a build failure.

**Concrete case:** PR #831 (Slice 0 of the atomic order queue, #827) was delegated to an agent
whose brief covered the code/test/regression scope in detail but never mentioned
`demos/README.md` or the manifest contract. CI fell back to `demos/demo.json`, which still held
PR #523's caption ("the info panel now reads the maneuver... reporting 'Wheeling'") and pointed
at `demos/inputs/wheel.json` — entirely unrelated to the rear-move/lateral-pivot tree conversion
#831 actually made. The user caught it by eye ("I don't see the info panel in the demo for
831?"); nothing in CI's green checks surfaced the mismatch.

**How to apply:** when delegating implementation work whose PR will trigger `demo-video.yml`
(anything touching `scenes/`, `scripts/`, `assets/`, or `project.godot`), explicitly instruct the
sub-agent to add its own `demos/demo.<slug>.json` per `demos/README.md`'s contract and run the
"Required demo self-check" (render frames, confirm the change is visible) before considering the
task done — don't assume a thorough code/test brief implies the demo obligation. When reviewing a
PR's demo section, check the manifest actually lives in *this* PR's diff (`git show
<sha>:demos/demo.<slug>.json` or `git diff --stat` against the base) rather than trusting that a
GIF is present and a caption reads plausibly — a fluent caption describing the wrong PR is not
self-evidently wrong from the text alone. (`Lacaedemon/sparta` PR #831, 2026-07-13.)

## A "wait then quit" helper reachable from multiple recorder modes needs a mode-guarded await

The demo-video CI job's state-transcript step (drives `DemoInputRecorder` in state-only mode)
once hung for the full 5-minute step timeout even though every armed tick's snapshot had already
been written. Root cause (`tools/demo/DemoInputRecorder.gd`): `_quit_after_captures()`
unconditionally did `await RenderingServer.frame_post_draw` before `get_tree().quit()` — needed
so an in-flight FRAME-capture `save_png()` can finish. But a STATE-ONLY dump (`_frame_ticks`
empty) never captures a frame, and under `--headless` the dummy renderer may never emit
`frame_post_draw` at all, so the await never resolves. The wall-clock safety-net timer didn't
rescue it either: it only called `quit()` `if not _all_artifacts_done()` — but all artifacts
*were* done, so the "safety net" saw nothing to warn about and did nothing.

**Fix (both needed):** (1) `_quit_after_captures()` awaits `frame_post_draw` only `if not
_frame_ticks.is_empty()` — a state-only dump quits immediately; (2) the timeout handler calls
`get_tree().quit()` **unconditionally**, only skipping the WARNING when done. General lesson: an
`await <signal>` used as a "let pending I/O finish" pattern is safe to make unconditional only if
that signal is guaranteed to fire on every code path reaching the function — here one caller
(frame capture, real renderer) always fires it, another (state-only, `--headless` dummy
renderer) doesn't. A shared fallback timer isn't enough if its own logic assumes "done implies no
work left." (PR #519; `demo` CI job dropped from a 6-min timeout to ~1m20s.)
