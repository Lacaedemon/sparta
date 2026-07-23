---
name: sparta-gotchas
description: "Operational gotchas and reviewer conventions for Lacaedemon/sparta (Godot tactical battle game)"
metadata:
  type: feedback
---

# Sparta — working notes

## Standing design philosophy: bottom-up physics, no top-down gimmicks

Sparta's combat/movement sim is built **bottom-up from individual-level physics**
(mass, momentum, acceleration/friction, real collision), not top-down shortcuts. A
mechanic should **emerge from the underlying physics**, not be bolted on as a flat
modifier or an instant state switch that ignores it. Concretely:

- **No snaps.** A continuously-rendered or continuously-simulated quantity (speed,
  facing, translucency, position) should ease toward its target via a rate
  (acceleration/friction), never jump there in one frame. #738/#739 fixed
  `Unit._current_speed` bleeding off via friction instead of snapping to 0 (merged).
  #740/#741 applies the same fix to routing translucency, fading it instead of
  switching instantly (merged) — scoped to the regimental flag only, per design
  feedback: the per-soldier marks and other chrome stay fully opaque.
- **No inert numbers.** A quantity that represents real motion must actually cause
  motion — a decaying speed that doesn't move the unit is a display artifact, not
  physics. #742/#743 (merged) made residual `_current_speed` coast the unit
  forward as it decelerates, instead of counting down while `position` sits
  frozen; the fix consolidates onto `_approach_velocity` (the unit's actual travel
  velocity, already read by the soldier-body feed-forward and combat charge bonus —
  never truly combat-only, just under-documented as one) rather than adding a
  parallel velocity field. #747 (merged) fixed a gap #743's own tests never
  exercised: `UnitCombat`'s "spend the charge" strike reset zeroed
  `_approach_velocity` on the exact tick a unit's last opponent died, leaving the
  idle-coast guard with no travel direction — see "A prior PR's own claimed
  verification can be wrong even after merge" below. #749 (merged, closes #745's
  first slice) went further: added real soldier-to-soldier enemy-contact collision
  physics (`SoldierCollision.enemy_contact_impulse` /
  `SoldierEnemyContact.accumulate`), and made the regiment's own `position` a pure
  function of its soldier bodies' actual positions (`SoldierBodies.couple`) rather
  than an independently-controlled point the bodies must return to — see "Regiment
  position is a pure function of body positions" below. #752 tracks the remaining
  gap in that slice (Square/Schiltron's engaged-soldier selection is still
  index-based, not live-proximity-based, under multi-attacker chaos).
- **No top-down combat-multiplier gimmicks where a physical mechanism already exists.**
  Prefer deriving an outcome (a spear stopping a charge, a knockback felling a soldier)
  from mass/momentum/impulse over a flat "type X beats type Y" bonus. This is the
  standing rationale behind #164/#296 (move collision to the individual soldier level)
  and the long-horizon #550 (individual-level LOD simulation at Cannae scale).
- **No synthetic force duplicating a physical mechanism that already produces the same
  outcome.** A DIFFERENT failure mode than a flat type-bonus above: PR #981 (#240,
  sustained melee standoff) first shipped a longer-reach soldier ACTIVELY BACKING AWAY
  once a shorter-reach enemy closed in, to hold its reach distance. Caught in review: the
  push-back this was meant to deliver already exists — every landed strike already
  applies real, physically-motivated knockback (`SoldierMelee`/`SoldierCombat`), so a
  longer-reach side's opening-strike advantage (it lands hits before the enemy is even in
  range) already carries through the sustained case via that existing mechanism. Adding a
  second, synthetic backing-away force on top was exactly the kind of top-down gimmick
  this philosophy exists to avoid, just aimed at MOTION instead of a damage/defense
  multiplier. Corrected to: the longer-reach side holds its ground and gets NO bias at
  all (equal-or-longer reach is unconditionally zero); only the OUTREACHED side still
  actively presses in, since closing the gap to negate a real disadvantage isn't
  redundant with anything else already in the sim. A genuine "fighting retreat" as a
  deliberate PLAYER-COMMANDED tactic (not the passive default) is still a legitimate
  mechanic — tracked separately as its own order/stance (#983) rather than folded into
  the default per-soldier physics. Before adding a new per-soldier bias/force, check
  whether an existing mechanism (knockback, reach-based hit resolution, contact impulses)
  already produces the intended outcome as a side effect — if so, the new mechanic should
  do LESS, not add a parallel force alongside it.

When implementing or reviewing a new mechanic, ask: does this emerge from the
individual-level physics already in place, or is it a shortcut layered on top? Prefer
the former; flag the latter as a candidate for this list.

## Issue-selection priority: core mechanics over polish

When picking which open issue to grab next (`gi`/`gii`/`gia`/`gip`), prefer **core
mechanics** work over **polish**, all else equal. Core mechanics is anything that
changes the actual simulation a battle runs on: combat/collision physics, movement
and maneuvers, formations, morale/routing, AI decision-making, or the campaign
layer's own rules — the kind of work the "bottom-up physics" philosophy above
governs. Polish is everything that makes the existing simulation more presentable or
more convenient without changing what it computes: rendering/art/asset quality,
camera behavior, HUD/UI layout, new platforms (3D mode, mobile), demo/tooling
convenience, or documentation-only issues with no mechanic attached.

This mirrors ai-config's own infra-over-feature tie-breaker (`pr-prioritization.md`)
— a priority nudge, not an override: an explicit `P0`-`P3` label, a blocking
relationship, or a direct instruction from the user still ranks above it. Apply it
only when candidates are otherwise close in priority, the same scope the
infra-over-feature tie-breaker uses.

Concretely, from the backlog as surveyed 2026-07-11: #164/#296 (individual-level
collision), #240 (weapon-reach standoff), #453/#458/#480/#718 (maneuvers,
formations, move-order types, disciplined-vs-undisciplined march behavior), #724
(engage-turn swirl bug), and #750 (crowding-pressure evaluation) are core mechanics.
#69 (3D mode), #131 (smartphone version), #386 (terrain art), #414 (fog of war —
mostly a rendering/visibility-of-information feature once the underlying detection
already exists), #467 (demo options), #496 (comb wikipedia for ideas), and #756-style
CI/tooling issues are polish or infrastructure, not core mechanics specifically
(infrastructure still gets its own tie-breaker per `pr-prioritization.md`, applied
before this one when the candidates are CI/tooling rather than gameplay UI/art).

## Pending: migrate to gha quarto-publish `@v2` (branch deploy)

Sparta is the registered `quarto-publish` consumer in gha's `REVDEPS.md`, and
gha cut a **breaking v2** (gha#118): `quarto-publish` moved from the Pages
`actions/deploy-pages` artifact to a `gh-pages` **branch** deploy. `@v1` was
rolled back to the last compatible commit, so sparta is safe on `@v1` for now.
To move to `@v2`: (1) Settings → Pages → Source = "Deploy from a branch",
`gh-pages` / `(root)`; (2) change the `quarto-publish.yml` caller's job
permissions from `pages: write` + `id-token: write` to `contents: write`;
(3) bump the pin to `@v2`. Migration steps live in the gha CHANGELOG.

## Website docs scope in stacked PRs

Sparta requires user-facing PRs to update the `website/` docs (the website-update
policy in the repo's `CLAUDE.md`). That requirement makes it easy to over-document:
on a stacked PR, write docs only for features whose code is on the *current branch's*
ancestry, not for a sibling branch's feature.

This is the sparta instance of the general rule in `preferences.md` ("only document
features present on the current branch's ancestry — grep first").

**Concrete case:** in the terrain-speed PR (#185), website docs were written for the
order-response delay feature (from `feat/order-response-delay`, a separate branch also
targeting `main`). That code was never in `feat/terrain-speed`'s ancestry, so the
reviewer correctly flagged it as a "hallucinated feature." Before documenting a feature,
`grep` for its symbol/constant (e.g. `order_response_delay`) on the current branch; if
it's absent, move the docs to the branch where the code lives.

## Demo scenario design — team 0 is stationary by default

Only team 1 (enemy AI, `_run_enemy_ai()`) auto-advances. Team 0 (player units) stays
**stationary** until given an explicit order, so any hand-authored
`demos/scenarios/*.json` replay that needs team 0 engaged must issue a move (or attack)
order early — at tick 0 or close to it. This bit the line-relief scenario (PR #200): the
relief order fired before any engagement because the player unit never advanced.

After writing a scenario, work out the engagement timing on paper before relying on the
CI clip to confirm it — a mistimed scenario wastes a CI run and may silently record an
unrelated moment.

The reference tables a scenario author needs — spawn positions and UIDs, effective unit
speeds, and the order `target`-field semantics — live with the code in sparta's
`demos/README.md` and `REPLAY.md`, not here. A memory copy of constants like
`SPEED_SCALE` and the spawn layout would rot silently when the game changes them.

## Demo camera path — record it like a human operator

When recording the camera presentation track for a demo (the track played back by
`tools/demo/DemoRunner.gd`), move the camera the way a person would, not a robot.
Repeated reviewer feedback on PR #232:

- **Don't chase the unit centroid recomputed every frame** — it drifts both ways as
  units shuffle and die, so the pan constantly *reverses direction* and reads as
  jerky even when smoothed. Sample a fixed focus point **once**, or don't anchor to
  the centroid at all.
- **Hold, then move once in one direction, then hold** — script holds plus single
  eased (smoothstep) moves; aim for ~1 direction-reversal per axis over the whole
  clip.
- **End on a multi-second stable hold** — finish all camera motion well before the
  recording ends (set `max_frames` to cover the motion *plus* the hold) so the clip
  doesn't cut off mid-move.
- **Raise the framerate for a moving camera** — `fixed_fps` 30 / GIF `fps` 12 suit a
  static-camera battle, but a panning/zooming camera looks choppy at 12 fps. Use
  `"fixed_fps": 60, "fps": 30` and bump `max_frames` to keep the duration.

Playback also low-passes the track (`Battle.camera_smoothing`, default `CAMERA_SMOOTHING`), but that smooths
magnitude, not direction — fix the *path*, not just the filter. Verify by logging
the played-back camera and counting velocity sign-changes and per-tick jerk, not by
eyeballing one frame. The committed `demos/camera-showcase.json` is baked keyframes
(no centroid logic); author the recorder as a throwaway off-screen scene.

## Demo media in PRs — inline play-once GIF + link to the MP4

The demo workflow posts the PR clip as an **inline GIF that plays once** (ffmpeg
`-loop -1`, freezes on the final frame) plus a **link to the MP4 with sound**
(#236). The MP4 rides the `demo-media` branch and is linked, not embedded.

**Why a GIF and not a poster→MP4 player (the road not taken):** a committed `.mp4`
does render a pausable/scrubbable player at its `/blob/<branch>/x.mp4` page (the
`/raw/` form serves `application/octet-stream` and just downloads), so a
poster-image-linked-to-blob *looks* like a CI-automatable click-to-play. It shipped
briefly (#237) but **GitHub's blob-view video player doesn't work on the mobile site
or app**, so the poster led nowhere on mobile. Reverted to the inline GIF, which
renders everywhere including mobile. An inline `<video>` player only renders for
files on GitHub's browser-only attachment CDN, which CI can't reach. Full contract
lives in `demos/README.md`. See also [[reference-github-media-embedding]].

## Authoring & verifying demo scenarios (hard-won gotchas)

When hand-authoring a `demos/scenarios/*.json` replay (a `seed` + `orders` +
optional `camera` track) and verifying it locally:

- **The replay loader requires `version: 1` and `physics_tps: 60`.** Without both,
  `Replay.start_playback` returns false *silently* and `DemoRunner` falls back to a
  fresh random battle — so the clip records the wrong thing (units at spawn, no
  orders, default camera) with no error. Always include them (see `showcase.json`).
- **A HOLD order does NOT keep an enemy unit stationary.** The enemy AI
  (`Battle._run_enemy_ai`) sets `target_enemy` directly every `AI_PERIOD`, and
  `Unit._think`'s chase branch (`elif target_enemy != null`) fires regardless of
  `order_mode == HOLD` (HOLD only suppresses chasing a *detected* foe, not an
  explicitly-set target). So you can't stage a "held line" the player charges into;
  units meet in the middle. Design demos around the natural clash instead.
- **Camera playback steps between keyframes, then EMA-smooths** (`Battle.camera_smoothing`, default `CAMERA_SMOOTHING`).
  For a smooth pan/zoom, emit *dense* eased keyframes (e.g. every ~3 ticks with a
  smoothstep), not sparse ones.
- **Record locally on macOS** with `GODOT_BIN` (`/Applications/Godot.app/Contents/MacOS/Godot`):
  `SPARTA_DEMO_REPLAY="res://demos/scenarios/X.json" $GODOT_BIN --rendering-driver opengl3
  --write-movie /tmp/d.avi --fixed-fps 60 --quit-after N res://tools/demo/DemoRunner.tscn`.
  Movie Maker works headless (no Xvfb needed on macOS).
- **Extract frames without ffmpeg:** the AVI is MJPEG in `00db` chunks. Walk the
  `movi` LIST sequentially (tag `00db` = JPEG frame, `01wb` = audio), reading each
  chunk's little-endian size; decode the JPEGs with PIL. A naive `FFD8..FFD9` scan
  over-counts (internal markers), so parse the chunks. Frame index == physics tick
  at `--fixed-fps 60`. This lets you verify a demo frame-by-frame before pushing.

Verify timing on paper first (unit speeds in `demos/README.md`), then confirm by
recording + extracting a few frames — don't trust a CI run to catch a mistimed
scenario.

## Release workflow — tag-gated publish, and the NSIS installer path

The `Release builds` workflow (`.github/workflows/release.yml`) builds on
`push: tags: v*` **and** on manual `workflow_dispatch`. A dispatch run builds
every artifact — including the NSIS installer step — and only the final
*publish to the GitHub Release* is tag-gated. So you can validate the installer
build without cutting a release; just don't expect a dispatch run to publish one.
A bug in the tag-only publish path, though, only surfaces when you actually tag.

- **The relative `OutFile` in `tools/installer/sparta.nsi` landed in the `.nsi`'s
  own directory (`tools/installer/`), not the workflow's working dir.** makensis
  ran from the repo root with the script path, yet the built installer wasn't in
  the repo root — a `mv "sparta-…setup.exe" build/` from there failed with
  *cannot stat*. (NSIS docs are muddy on whether a relative `OutFile` is cwd- or
  script-relative, and it varies — don't rely on either.) This was the first tag
  to run the installer step (added after v0.1.0). Fix pattern: make the path an
  overridable define (`!ifndef OUTFILE` / `!define OUTFILE …` / `!endif`) and pass
  an absolute `-DOUTFILE="$(pwd)/build/…"` from the workflow, matching how
  `EXE_PATH` is already absolute — then makensis writes straight into `build/`
  regardless.
- **The release workflow runs from the *tagged* tree.** Fixing `main` is not
  enough: re-point the tag at the fixed commit (`git tag -f -a v0.2.0 <sha>` +
  `git push origin v0.2.0 --force`) to re-trigger. Reusing a tag is fine when no
  release ever published under it.
- **A backgrounded `gh run watch … ; echo EXIT $?` exits 0 even when the run
  failed** — the wrapper's exit code is the `echo`'s, not the run's. Read the run
  `conclusion` explicitly afterward; don't trust the task's exit code.

## Local testing — repo targets Godot 4.7 (no more 4.6 dance)

As of PR #420 ("Upgrade engine target from Godot 4.6.x to Godot 4.7", merged
2026-06-30), Sparta **targets Godot 4.7** — `project.godot`'s `config/features`
is committed as `"4.7"` on `main`. Local machines run 4.7 too, so target and
binary match.

- **No more 4.6↔4.7 bump/restore.** The old workflow (bump `config/features`
  4.6→4.7 before a local run, then `git checkout project.godot` to restore 4.6)
  is **obsolete and now actively wrong** — restoring to 4.6 regresses the
  committed target. Run the suite directly; leave `project.godot` alone.
- **Getting the binary:** point `GODOT_BIN` at a 4.7 binary (the `_console`
  variant gives terminal output on Windows), e.g.
  `GODOT_BIN=<path> bash tools/check.sh validate test chars`, or run GUT
  straight: `<binary> --headless -s addons/gut/gut_cmdln.gd -gdir=res://test
  -ginclude_subdirs -gexit`.
- **The `test_settings.gd` doubler quirk** is the same GUT-on-4.7 issue
  described just below — if a lone `test_settings.gd` doubler parse error
  appears it's that known quirk, not a regression. Since the #420 upgrade the
  full suite has been observed passing every test, so don't assume that failure
  is still present, and don't pin an exact test total; the suite grows.

## GUT's doubler breaks on void-returning methods under Godot 4.7

`partial_double()`/`double()` can fail to parse under Godot 4.7 + GUT v9.7.0:
some generated wrapper methods still emit an invalid `return` for void-returning
or default-parameter methods, which 4.7's stricter return-type checking now
rejects ("A void function cannot return a value"). This is bitwes/Gut#816 — GUT
9.7.0's fix for the underlying Godot change doesn't cover every method shape.
Hit while migrating to 4.7 (#420): `test_settings.gd`'s one `partial_double()`
use on `Settings.gd` (which has several void methods and default-valued params)
failed this way. Fix: skip the doubler for the affected script — write a small
hand-rolled subclass that overrides just the method you need to spy on (GDScript
dispatches it virtually from the base class's own calls), e.g. a counter in an
overridden `_save()` instead of `assert_not_called`. Check before reaching for
GUT's doubler on any script with void or default-valued-param methods.

## Verify maneuvers/soldier bodies tick by tick, not by eyeballing GIFs

For maneuver/soldier-body work, **verify by stepping the simulation tick by tick
— in the real Battle scene — and asserting on actual body positions**, not by
watching demo GIFs/frames.

**Why:** during the quarter-turn (#371) work, demo GIFs at 50px blocks were
ambiguous and misleading. A headless GUT test that instantiates
`scenes/Battle.tscn` (set `Replay.forced_seed`), awaits `get_tree().physics_frame`
one tick at a time, and logs/asserts each unit's `_sim_soldier_pos` bbox +
per-tick max body step caught what frames couldn't: it proved the sim correct
(bbox constant, step ≤0.02px) and isolated the real problems to the **render**
(figure-LOD didn't show facing #399; spear/archer marks striped under rotation
#400) and a deferred **engage** behavior (#402). An isolated single-unit test
misses bugs that only appear under the full per-tick orchestration (steering +
couple + combat).

**How to apply:**
- Write a live-battle tick-by-tick test (see
  `test/unit/test_quarter_turn_battle.gd`) asserting no per-tick surge / no
  footprint drift / no reposition. Make it permanent — it's the regression guard.
- Treat demo GIFs as a *presentation* check only, never the correctness signal.
  A clean tick-by-tick test + a bad-looking GIF means the bug is in rendering,
  not the sim.

## Settings.gd setters persist to the REAL user://settings.cfg in tests

`Settings.gd`'s setter methods (`set_order_binding`, and the property setters
like `edge_scroll =`, `show_unit_speed =`, `form_up_dist_default =`) all call
`_save()` internally, which writes the **real** `user://settings.cfg` on whatever
machine runs the test — GUT tests are not sandboxed. A test that calls a setter
to trigger `Settings.changed` (e.g. to verify a UI element repaints on a live
rebind) persists that change to the developer's actual config, contaminating real
gameplay and every later test run until manually fixed.

**Why this matters:** caught on `test_shortcuts_overlay.gd` — a test called
`Settings.set_order_binding("skirmish", KEY_J)` to verify the overlay repaints;
this silently rewrote the `skirmish=` binding from the default (KEY_K) to KEY_J.
The editor and later playtests then loaded skirmish bound to J. Required manually
editing `settings.cfg` to restore.

**How to apply:**
- To trigger `Settings.changed` **without** the disk write, mutate the backing
  dict/property directly and emit by hand:
  `Settings.order_bindings["slug"] = KEY_X; Settings.changed.emit()` — NOT
  `Settings.set_order_binding(...)`. Mirrors the safe pattern in
  `test_selection_manager.gd` (`Settings.order_bindings["hold"] = KEY_Z`).
- After writing/reviewing a GUT test that touches `Settings`, grep the diff for
  any setter-method call (`Settings.set_*(`, or a property assignment like
  `Settings.show_unit_speed = ...`) and replace with direct mutation + manual
  `changed.emit()` when the test only needs the signal, not persistence.
- If contamination is suspected, check
  `C:\Users\<user>\AppData\Roaming\Godot\app_userdata\Sparta\settings.cfg`
  (Windows) for stale values and restore.

**This same file is shared ACROSS worktrees, not just across test runs in
one.** Godot's `user://` path keys off the project **name** ("Sparta"), not
the checkout path, so `godot --headless --import`, `tools/check.sh test`, and
`tools/demo/dump-state.sh` all read/write the identical
`~/.local/share/godot/app_userdata/Sparta/settings.cfg` (Linux) regardless of
which `.claude/worktrees/pr-<N>/` they're invoked from. Running a merge
resolution's test suite in one worktree while verifying a demo's keybinding
via `dump-state.sh` in a different worktree at the same time can silently
clobber the second run's keybindings mid-verification — the state dump then
shows the WRONG stance armed (or none at all), looking exactly like a code
bug in the just-resolved merge, when the actual cause is the other worktree's
concurrent GUT run persisting its own (possibly test-scrambled) keybinding
overrides to the same shared file. If a state-dump result looks wrong right
after a merge-conflict resolution, `rm -f
~/.local/share/godot/app_userdata/Sparta/settings.cfg` and re-run the dump
before concluding the fix itself is broken — don't trust a single dump when
another worktree's Godot process could have been running concurrently.
(Session running parallel background agents across `pr-704`/`pr-707`/`pr-713`
worktrees, 2026-07-10: a `sweep-routers.json` sanity dump showed
`order_mode: "All-out attack"` — a completely unrelated PR's stance — at the
exact tick its own `Ctrl+,` should have armed `Sweep routers`, traced to a
`settings.cfg` on disk holding scrambled keybinding values from a concurrent
test run in a sibling worktree.)

**The same collision fires WITHIN one worktree too: never launch a second
Godot suite (test/coverage) anywhere while one is still running.** Two
background `tools/check.sh` runs in the SAME worktree share not just
`settings.cfg` but the `.godot` import cache and the single
`coverage/lcov.info` output path — the second run's results are garbage
without erroring (a coverage report that silently reflects a stale test set,
a spurious single-test failure elsewhere in the suite). The contamination
tell in `settings.cfg` is keybinding overrides holding scrambled values
(e.g. `chase=65`/'A', `sweep_routers=87`/'W'); delete the file and rerun
alone before believing any failure. One Godot process at a time, machine-wide
— treat a running background check task as a lock. (GII batch endgame,
2026-07-15: launched a patch_coverage rerun while the prior one was still
going in the same worktree; the "rerun" reported the pre-edit coverage
number, and a later full-suite run failed one unrelated test until the
scrambled `settings.cfg` was deleted.)

**A branch SWITCH counts as a second writer too: never `git checkout` in a
worktree while a Godot job is still running there.** The suite (and the
coverage/patch_coverage runs especially) reloads scripts from disk as it
goes, so checking out a different branch mid-run swaps the source out from
under the running process — the results are silently a mix of two trees and
must be discarded, even though nothing errors. Treat a running background
check as locking the CHECKOUT, not just the Godot binary: no branch
switches, no file edits in that tree, until the task completes or is
killed. When multi-PR work makes this bite (a long coverage run on PR A
while PR B needs implementing), rely on CI's own Coverage/codecov-patch for
PR A instead of a local run, or kill and rerun the local job after the
switch. (GII session, 2026-07-16: switched the worktree to the next issue's
branch while patch_coverage for the prior PR was still running; the run had
to be killed and CI's checks used as the authority instead.)

## An axis computed by folding `_formation_angle` must re-pick the facing-aligned frame after a conversio

`_wheel_pivot_point` folds `_formation_angle` into the slot-grid axes so a
wheel hinges against the grid as physically laid out — required for chained
quarter turns (±PI/2 folds). But a completed conversio folds
`_formation_angle` to ±PI, which spins BOTH axes 180°: "front" points at the
physical rear and the `signf(dir)` flank flips, so the hinge lands at the
rear corner of the WRONG flank and the whole block wheels BACKWARD around it
(every soldier backpedaling, cos(facing) = -0.99 across the swing). The
rectangular lattice is identical under a 180° spin, so the fix is to re-pick
the other representative when the folded front axis opposes facing — and the
threshold must be `dot < -0.5`, NOT `< 0.0`: a quarter-turn fold's dot is
zero only mathematically, and in 32-bit float the sign is noise, so a bare
sign check mirrors the tested chained-quarter-turn hinge at random (the full
suite caught exactly that on the first attempt; the file's own 16 wheel tests
all passed over the backward wheel because none asserted hinge POSITION).
Watching the recorded demo caught what the tests missed — the user asked why
soldier 8 was backpedaling. Any new consumer that folds `_formation_angle`
into a direction calculation needs the same ±PI re-pick, a hinge/anchor
POSITION assertion in its tests, and edge-case runs at both fold values.
(`Lacaedemon/sparta` PR #871, 2026-07-15.)

## MultiMesh instance transforms don't read back in headless tests

`MultiMesh.set_instance_transform_2d(i, t)` followed immediately by
`get_instance_transform_2d(i)` in a headless GUT test returns identity, not the
value just set — even for `Unit._mm_body`, whose write path is proven correct in
production. `instance_count` reads back fine; only the per-instance transform
buffer doesn't sync back to the CPU-side getter without a render/RenderingServer
sync point headless tests never reach.

**Why:** hit while adding a per-soldier facing-pip MultiMesh layer (#399). A
sanity check against the already-shipped `_mm_body` also read back identity,
confirming a general Godot/headless limitation, not a new-code bug. No existing
test asserts on `get_instance_transform_2d()`; they check `instance_count` and
`mesh` identity only.

**How to apply:** don't test by setting a MultiMesh instance transform and
reading it back. Extract the transform computation into a small pure `static
func` (plain values in, `Transform2D` out) and unit-test *that* — e.g.
`Unit._facing_pip_transform(prone, sf, pos) -> Transform2D`. This is also
better-factored code, so the fix pays for itself.

## Battle.gd merge: order-sentinel and same-name-local collisions

Two feature PRs that each extend `Battle.gd`'s order pipeline often introduce
**colliding additions** git merges without a textual conflict, but that are
semantically or syntactically broken. Watch for two specific collisions when
resolving a `Battle.gd` merge:

- **Order-sentinel constant collision.** Order types are encoded as negative
  sentinels in the `target` field (`ORDER_APPEND_WAYPOINT -2`,
  `ORDER_FORMATION_ONLY -3`, `ORDER_FRONTAGE_ONLY -4`, …). Two branches each grab
  the *next* free value independently — e.g. #469 added `ORDER_NUDGE := -5` and
  main's #474 added `ORDER_WHEEL := -5`. If both keep `-5`, the two
  `if target_uid == …` dispatch arms alias each other and one order silently runs
  the other's handler. **Fix:** keep main's value, renumber the incoming PR's
  sentinel to the next free slot (`ORDER_NUDGE := -6`), leave a matching comment.
  Run `grep -n "ORDER_" scripts/Battle.gd` after resolving to confirm every
  sentinel is unique.
- **Same-named local in one function.** Both dispatch arms landed in
  `_apply_order_cmd` and both declared `var dir`. GDScript scopes a `var` to the
  whole **function**, not the `if` block, so two `var dir` in one function is a
  redeclaration parse error even in separate `if`s. The textual merge stacks them
  with no conflict; validate catches it only at import. **Fix:** rename one
  (e.g. main's wheel arm to `var wheel_dir`).

**Verify the resolve with `tools/check.sh validate`** (Godot import) before
trusting the merge — a redeclaration or shadow surfaces only at parse time.
Learned resyncing #469 (arrow-key nudge) after main merged #474 (wheel).

**At cascade scale: resolving once doesn't mean the sentinel collision is
over — merging ANY sibling into `main` re-conflicts every OTHER sibling a
second time.** When several `OrderMode`-adding PRs are open at once (five,
2026-07-10: `ALL_OUT_ATTACK` #704, `PIN_DOWN` #707, `ROLL_THE_LINE` #708,
`SWEEP_ROUTERS` #711, `CHASE` #713), each one independently claims the next
free enum value/hotkey against whatever `main` looked like when it was last
resynced — so resolving PR A against PR B's already-merged value doesn't
settle anything permanently. The moment PR B (or C, or D) itself merges to
`main`, every other still-open sibling's `mergeable_state` flips back to
`dirty`, because `main` just moved again and picked up yet another occupied
enum/hotkey slot. This isn't a one-time fan-out to absorb; it's a recurring
tax that hits once per merge in the cascade — expect to re-run this same
renumbering exercise on every remaining sibling after each individual
sibling lands, not just once at the start. Re-check every open PR's
`mergeable_state` right after any one of them merges (the `post-merge`
skill's cascade-conflict-scan step) rather than assuming a clean resolve
earlier in the day still holds.

**The hotkey half of the collision can be preemptively deconflicted between
two still-open sibling PRs; the enum VALUE half cannot.** When two siblings
each independently rebind onto the same free key after a shared ancestor
merge (e.g. both #704's `ALL_OUT_ATTACK` and #713's `CHASE` picked
`KEY_APOSTROPHE` after #707's `PIN_DOWN` merge forced both off
`KEY_PERIOD`), it's safe to edit one sibling's still-open branch directly and
rebind it to a different free key — a hotkey is just an integer with no
cross-branch invariant, so this permanently removes that specific collision
regardless of merge order. **Don't try the same trick on the enum value**
(e.g. reserving `CHASE = 11` on one branch so it won't collide with
`ALL_OUT_ATTACK = 10` on the other): `test_hud_stance.gd`'s
`test_stance_entry_ids_are_sequential_and_unique` asserts each branch's own
`HUD._STANCE_ENTRIES` ids run `0..N-1` with no gaps, so a branch can only
place its newest stance at exactly `(highest existing value) + 1` — it can't
reserve a future slot for a sibling it can't see. That half of the collision
stays real and can only resolve at actual merge time, via the normal cascade
process above. (`Lacaedemon/sparta` PR #713, 2026-07-10: attempted
`CHASE = 11` to preemptively dodge #704, immediately failed
`test_stance_entry_ids_are_sequential_and_unique` with
`[0..9, 11] != [0..9, 10]`; reverted the enum change, kept the hotkey
rebind to `KEY_BACKSLASH`.)

## Routing units early-return in `_physics_process` — merge-isolated

In `scripts/Unit.gd`, `_physics_process` takes an **early return** for a routing
unit:

```gdscript
if state == State.ROUTING:
    _process_rout(delta)
    if state != State.DEAD:   # timer expired: rallied (IDLE) or shattered
        _separate()           # routers still shoulder past anyone in their path
    return
```

Routers run only `_process_rout` + `_separate` and skip the entire normal path:
`_think`, `_tick_intermixing`, morale/fatigue/cohesion ticks, and all the
movement/re-facing/formation logic below the return.

**Merge implication.** When resyncing the routing/rally branch (#460, #434)
against a `main` that landed new movement features — engage/attack re-facing
(#402/#476), file doubling (#373), anti-cav square (#487), shielded close order
(#485) — git auto-merged `Unit.gd`/`Battle.gd` cleanly, and the auto-merge was
**also semantically correct**: those features all live in the `_think`/movement
path routers never reach, so they can't interact with rout/rally state.

General rule: a state that early-returns from `_physics_process` (ROUTING, DEAD)
is isolated from any feature added to the normal think/movement path, so a clean
git auto-merge of the two branches is usually clean semantically too. Still run
the full suite (`tools/check.sh test`) to confirm — that's the real signal.

## `_check_victory` counts routers in play (last-unit rally)

`scripts/Battle.gd`'s victory check no longer counts only fightable units.
PR #495 (closes #493) replaced the `_team_units(0).size()` /
`_team_units(1).size()` counts in `_check_victory()` with a boolean helper:

```gdscript
func _team_in_play(team: int) -> bool:
    for group in ["units", "routers"]:
        for node in get_tree().get_nodes_in_group(group):
            var u = node as UnitRef
            if u != null and u.team == team:
                return true
    return false
```

`_check_victory()` ends the battle only when `not _team_in_play(0)` /
`not _team_in_play(1)`. A **routing** unit has left the `"units"` group for
`"routers"` (`Unit._rout()` → `add_to_group("routers")`) but is still on the
field and may rally, so it keeps its team **in play**. Before #495, losing the
last fightable unit ended the battle instantly and froze the router mid-rout.

- **The rally window is bounded**, so waiting on routers can't stall the outcome:
  each rout resolves (rally→IDLE or shatter→removed) within `ROUT_TIME`.
- **No AI change was needed.** The enemy AI advances on `_team_units(0)` (the
  `"units"` group only), so it already halts when the last player unit routs —
  don't add a separate "halt" hook.
- **Known gap, tracked in #504:** `_report_campaign_result()` still counts
  survivors with `_team_units(0).size()`, which EXCLUDES still-routing units.
  Pre-existing. If you touch campaign accuracy, reuse `_team_in_play` /
  union `"units"`+`"routers"` there too.

## Render-only cosmetic overlay pattern

**Superseded for the shield-wall/testudo/square case by #753:** the owner
decided the schematic overlay this pattern originally shipped
(`scripts/UnitShields.gd`, added by #486/#487/#623) was the wrong call for
those stances specifically — since #534 already restructures the real
soldier-block geometry per formation (a tight edge-to-edge grid for shield
wall/testudo, a real outward-facing square for orbis/schiltron), drawing a
second schematic on top duplicated what the physical soldier positions
already show, in tension with the "no top-down gimmicks" philosophy at the
top of this file. #753 removed `UnitShields.gd` and its call site entirely;
these formations are now read purely from the soldiers' own positions. The
pattern below is kept as a still-valid recipe for a genuinely different
future case (an effect the soldier positions truly can't convey on their
own), not as a template to reach for reflexively — check whether the real
per-soldier geometry already tells the story before adding a schematic
overlay on top of it.

When a PR is purely **"show an existing sim state on screen"** that the
soldiers' own positions can't already convey, build it as a **render-only
overlay** so it never touches sim/combat/formation code and stays
conflict-free with the many in-flight PRs that DO touch that code.

**The pattern (mirrors `UnitSprites` / the emblem/flag chrome):**

1. **Pure geometry helper** in its own `class_name` script (e.g. the former
   `scripts/UnitShields.gd`, removed by #753 -- see the pattern in
   `scripts/UnitSprites.gd` instead for a still-live example). Static funcs taking plain shape inputs
   (frontage/ranks/spacing/mark_r) returning local-frame polygons — a function of
   block shape ONLY, nothing reads or writes the sim. Directly unit-testable and
   replay-safe. Keep block geometry consistent with the formation grid:
   half-width `= (files-1)/2 * spacing`, half-depth `= (ranks-1)/2 * spacing`,
   front rank toward **-Y** (local forward), files span X — same frame
   `UnitFormation.slots` / the emblem use.
2. **A `draw(u, body, dark, lite)` dispatcher** that switches on the state
   (`u.formation_mode`) and is a **no-op** for every other value.
3. **`Unit._draw` calls it** inside a `draw_set_transform(Vector2.ZERO,
   facing.angle() + PI*0.5, Vector2.ONE)` … reset sandwich, so the overlay
   **rotates with facing and scales with the block** for free. Size off the live
   formation shape (`UnitFormation.frontage` / `ranks_for`), not the bare
   `RADIUS`. Use the team-tinted `body_c/dark_c/lite_c` already computed in
   `_draw`.

**LOD decision — differs from the emblem.** The centre emblem hides at figure LOD
(`if not _detailed_lod`) because the per-soldier silhouettes carry the type. A
shield overlay does the OPPOSITE: draw it at BOTH mark and figure LOD, because
the raised/overhead shields are exactly what the individual figures don't show.
Put the overlay OUTSIDE the `if not _detailed_lod` guard and note why.

**Coverage gotcha.** The pure geometry helpers get covered by GUT tests, but the
draw-only `draw()` / `_draw_*` funcs don't — `codecov/patch` fails on them.
Calling `unit._draw()` directly from a test errors ("Drawing is only allowed
inside this node's `_draw()`"). Instead drive it the way the engine does: add the
unit to the tree, set the stance, `queue_redraw()`, and
`await get_tree().process_frame` twice — that runs `_draw` under the real draw
notification and covers the dispatch.

## `record-demos.sh` DEMOS conflicts are ADDITIVE — keep both rows

`website/tools/record-demos.sh` holds a `DEMOS=( ... )` bash array, one row per
demo clip. Every feature PR that adds a website demo appends a new row at the end.
When two such PRs land, git conflicts on the adjacent lines:

```
<<<<<<< HEAD
  "rout_rally|demos/inputs/rout-rally-recover.json|30|300|640|input"
=======
  "testudo_under_fire|demos/inputs/testudo-under-fire.json|30|300|640|input"
>>>>>>> origin/main
```

This is an **additive** conflict, not a genuine either/or. Resolve by keeping
**both** rows — each PR's demo should survive. Don't pick a side.

Distinct from the `demos/demo.json` conflict (below / CLAUDE.md), where you keep
only YOUR PR's version because that file names the single clip CI posts for the
PR in hand. `record-demos.sh` is the persistent website catalog, so both entries
stay.

## `website/tactics.qmd` same-mechanic conflicts are a DEDUP, not additive

`website/tactics.qmd` (and `how-to-play.qmd`) conflicts differ from the
`record-demos.sh` additive case above. When two PRs document the **same mechanic**
from different angles, git shows a big block conflict, but the right resolution is
a **semantic dedup**, not "keep both sides".

Concrete case (PR #495 last-unit-rally vs main's #460 rout-rally): both rewrote
the "Morale & routing" section and each added rally prose + a demo video.
Resolution that worked:

- **Intro paragraph** — keep the richer of the two, drop the thinner one.
- **Bullets** — keep the general-mechanic bullets ("A routing unit can rally" /
  "shatters instead"), DROP your own now-redundant duplicate of that same
  explanation, and KEEP only your PR's *unique* angle (the last-unit case: "the
  battle isn't over while a side is only routing").
- **Demo videos** — this IS additive: keep BOTH `<figure>` blocks (general
  mechanic first, then the specific case), each in its own ` ```{=html} ` fence.

Rule of thumb: two docs describing the same feature → merge into one coherent
narrative (general mechanic once, then each PR's distinct implication); two *media
embeds* → keep both. Read the merged section end-to-end afterward to confirm it
doesn't say the same thing twice. `&mdash;` in figcaptions is an HTML entity, so
it passes `tools/check.sh chars` (only literal curly quotes / en-em dashes fail).

## This repo runs sessions in `.claude/worktrees/` — edit the worktree path

A Sparta session's working dir is often a git **worktree**
(`…\sparta\.claude\worktrees\<name>`), separate from the main checkout
(`…\sparta`). A feature branch created in the worktree is checked out **there**,
while the main checkout stays on `main`.

**Hazard (easy to hit twice):** Read/Edit/Write using the *main-checkout*
absolute path (`…\sparta\scripts\…`) edits files on the `main` branch, NOT the
worktree's feature branch. Then tests run from the worktree silently see none of
the changes (a new test file isn't discovered; `git status` in the worktree is
clean while the main checkout shows the edits).

**How to apply:**
- Do **all** file operations on the **worktree path**
  (`…\.claude\worktrees\<name>\…`), matching where the branch is checked out.
  Bash cwd already resets to the worktree — keep tool paths consistent with it.
- If edits don't seem to take effect, run `git status --short` in **both** the
  worktree and the main checkout to find where they landed.
- To move stray edits from the main checkout onto the worktree branch:
  `git stash push -u` in the main checkout, then `git stash pop` in the worktree
  (the stash is shared via the common `.git`). `-u` includes untracked files.
- **`gh` commands are cwd-sensitive the same way.** Running `gh pr create` from
  the main checkout (on `main`) fails with `must be on a branch named differently
  than "main"`, even though the feature branch is pushed — `gh` reads the current
  directory's checked-out branch. Run `gh pr create` (and branch-scoped
  `git push`) from the **worktree** dir.

**A second, distinct hazard: reusing a PR branch name for a NEW worktree when a
`wave5-*`-style dispatch worktree already has it checked out.** This repo's
wave-based backlog sweeps leave many named worktrees behind
(`.claude/worktrees/wave5-<slug>`), each tracking one PR's branch — they don't
get cleaned up until the PR merges and someone runs a sweep. If a later task
(e.g. resolving a fresh merge conflict on that same PR) creates a *second*
worktree for the same branch instead of reusing the existing one, git can
silently repoint the shared branch ref out from under the first worktree
rather than refusing outright — the first worktree then shows a wall of
spurious modified/deleted files (not real data loss, just its checked-out
files diffing against the ref's new tip). Always `git worktree list | grep
<branch>` before adding a new worktree for a PR branch; if one already exists,
reuse it (`git fetch` + `git reset --hard origin/<branch>`) rather than adding
a second on the same name.

**Recovery if it already happened:** the first worktree's checked-out files are
not lost — they're just diffing against the branch ref's new tip. Don't try to
merge or reconcile the two worktrees' contents. Pick the worktree that actually
has the commit you want to keep, confirm it with `git log --oneline -1` in
each, then `git worktree remove` the stale one and `git fetch` + `git reset
--hard origin/<branch>` in the survivor so both git's ref and the working tree
agree again. (Hit on PR #626, 2026-07-03.)

**A third, distinct hazard: the assigned `.claude/worktrees/<name>` directory
can look like a worktree without actually being one.** The section above
assumes the session's working directory is a genuine `git worktree` — but a
harness-assigned path under `.claude/worktrees/` isn't guaranteed to have had
`git worktree add` actually run for it. Symptom: the directory has **no
`.git`** file/folder of its own, and it's **absent from `git worktree list`**
run from the main checkout — every `git` command issued from inside it just
walks up the directory tree and finds the main checkout's `.git`, so it's
silently operating on the SAME shared repository as the main checkout and
every *other* branch checked out there, not an isolated copy.

**Why this is dangerous, concretely:** checking out a second branch from
inside this fake "worktree" (`git checkout -b other-branch origin/main`)
switches the ONE shared checkout's active branch — it does not create an
independent working tree. Any other work in flight on the branch that was
previously checked out (your own later commands, or a delegated subagent
mid-task) silently has its working-directory files yanked out from under it.
The subagent doesn't error — it just ends up running against whatever branch
is now checked out, which can be a completely different (even pre-refactor)
version of the code, and the resulting output can look plausible without
being about the branch it was asked to investigate.

**How to apply:**
- Before checking out a second branch or delegating a subagent to do file/git
  work, verify the working directory is real: check for a `.git` entry
  (`ls -la .git`) and cross-check `git worktree list` from the main checkout
  path — the assigned directory should appear in that list. If it's absent
  and has no `.git`, treat it as a plain subdirectory of the main checkout,
  not an isolated worktree.
- If it's fake and you need to work on more than one branch concurrently
  (e.g. driving several PRs at once, or delegating parallel implementation
  agents), create genuine isolated worktrees yourself:
  `git worktree add .claude/worktrees/<slug> -b <branch> origin/main` (or
  point at an existing remote branch instead of `-b` + `origin/main` to
  continue one). Do this from whichever path IS the real main checkout.
- Only ever have ONE branch checked out at a time in a fake/shared path. If
  you must switch, finish and push (or stash) whatever's in flight there
  first — don't assume "it's just a directory switch" is harmless.
- A subagent given a directory to work in has no way to know it's fake unless
  told to check — if you suspect this hazard might be live (concurrent
  branch work in the same session), tell the subagent explicitly to verify
  its own working directory is a real worktree before trusting its output, or
  give it a directory you've already confirmed with `git worktree add`
  yourself. (Hit on PR #831, 2026-07-13: `.claude/worktrees/gii-ffdb93` — the
  session's assigned directory — had no `.git` and didn't appear in `git
  worktree list`; checking out a second branch there for a concurrent PR
  silently switched the one shared checkout away from PR #831's branch mid-
  investigation by a delegated subagent, which only caught the problem
  itself by noticing `scripts/Order.gd` was missing the tree fields it
  expected and re-pinning its own investigation to an explicit `git worktree
  add ... 443972a`.)

## GII / multi-session scope — unclaimed issues, own worktree only

GII (grab issues iteratively) means picking up **unclaimed** open issues — no
existing PR, no in-progress branch. Do NOT continue another session's in-progress
PRs as part of the GII loop; those belong to their own sessions.

- Before grabbing an issue, verify no open PR covers it (`gh pr list` and check
  `headRefName` / body for "Closes #N").
- If all remaining unclaimed issues are blocked or too large, surface that to the
  user rather than hijacking in-progress PRs.
- **Never use another session's worktree** (one you did not create in this
  session). Each session owns its worktrees. If a branch is already checked out in
  a different worktree, create a fresh worktree from the remote branch in a new
  location or ask the user. Editing files in another session's worktree or its
  main-repo checkout is off-limits.

(The concrete rules here are Sparta-multi-session-specific; the general
"check for a prior claim before starting" rule lives in ai-config.)

**Post-merge tidy: never `git checkout main` (or `checkout -B main origin/main`)
inside a session worktree — the `-B` form silently bypasses git's
already-checked-out-elsewhere guard and double-checks-out `main` against the
primary checkout.** The plain `git checkout main` correctly refuses when the
primary checkout holds `main`, but a scripted fallback like
`git checkout -q main || git checkout -qB main origin/main` (with stderr
swallowed) lands on the `-B` path, which re-points the shared `main` ref and
checks it out here anyway. Both worktrees then claim `[main]` in
`git worktree list`, and the next `git pull` in the session worktree moves the
shared ref out from under the primary's working tree — the primary then shows a
wall of phantom staged diffs (the just-merged PR's changes, reversed), exactly
the stale-files symptom of the branch-repoint hazard above, with no error
anywhere. Recovery: move the session worktree onto a new branch
(`git switch -c <next-branch>`), then in the primary restore ONLY the
phantom-diff files (`git restore --staged --worktree <files>` — not a blanket
`reset --hard`, which would clobber unrelated local state like a `.ai-config`
submodule pointer). Prevention: after a merge, don't "return to main" in a
session worktree at all — fetch and branch the next task's branch directly off
`origin/main` (`git switch -c <branch> origin/main`), leaving `main` itself to
the primary checkout. (Session `gii-ffdb93`, 2026-07-16: post-#919 tidy ran the
fallback form, double-checked-out `main`, and the primary showed nine phantom
staged reversals of #919's own files until restored.)

**Post-merge tidy: `git worktree remove` on your OWN currently-active worktree
can partially succeed and leave an empty, orphaned directory — this is
harmless, not data loss.** After a PR merges, running `git worktree remove
.claude/worktrees/<name>` from the main checkout while THIS session is still
running inside that worktree (its Bash tool cwd pinned there) can fail with
`Permission denied` at the final `rmdir` step, but only *after* it already
deleted every file inside — Windows won't let git remove the directory itself
while some process (the harness's own shell for this session) still holds a
handle to it. Symptoms: `git worktree list` no longer shows the entry (git's
`.git/worktrees/<name>` admin metadata IS removed), but
`Test-Path <dir>`/`ls` on the physical path still returns true because the
now-empty directory shell lingers. Confirm nothing was lost by checking
`git branch --list <branch>` (the branch itself is untouched by `worktree
remove` — delete it separately with `git branch -d` once it no longer shows
in `git worktree list`) and `git log`/`gh pr view` to confirm the merge
actually landed on `main` before treating this as anything other than cleanup
succeeding by 99%. Don't attempt a forced re-remove or `rm -rf` on the
directory from within the same session — it can't remove its own lock, and
the leftover empty directory is inert; it'll clean up naturally once the
session ends. Also: once this happens, do not try to Read/Edit/Write any file
inside that worktree path again this session — the files are actually gone,
not just inaccessible; switch every subsequent file operation to the main
checkout's absolute path instead. (Session `gii-ffdb93`, 2026-07-13: `git
worktree remove ".claude/worktrees/gii-ffdb93"` for the just-merged PR #824
emptied the directory but left it registered as `Test-Path`-true; branch
`design/atomic-order-queue` was still present and cleanly `git branch -d`-able
afterward.)

When the next AI session reviewing a PR cites a "CLAUDE.md rule" to justify a
requested change, check that the rule's exact wording actually appears in
*this repo's* `CLAUDE.md` — not just in the harness's own baseline style
defaults, which read similarly but aren't written into this file. PR #420's
reviewer cited "one short line max — never write multi-line comment blocks" as
a CLAUDE.md rule; it isn't in sparta's `CLAUDE.md`, and the codebase's own
convention (e.g. `Settings.gd`) wraps explanatory comments across 2-3 lines.
Rebutting with that distinction is fine — verify the citation, don't just comply.

## A stub-review retry's recovered verdict posts under `github-actions`, not `claude`

When auditing a PR's true review status, don't filter comments by
`author.login == "claude"` alone — a comment matching that filter can be a
stale earlier verdict, while the actual final verdict was posted under a
**different** identity and gets silently missed.

**Why:** the repo's `claude-code-review` workflow has a stub-review retry path
(gha#185/#218 — the first attempt runs to completion but posts no `### Verdict`
line). When the retry recovers, it posts its result via a plain `gh pr comment`
step running under the workflow's default token, which attributes the comment
to **`github-actions[bot]`**, not `claude[bot]`. The original (stubbed or
successfully-verdicted) attempt posts natively as `claude[bot]`. So a PR's
comment history can contain an OLD `claude[bot]` "Needs more work" alongside a
NEWER `github-actions[bot]` "Ready for merge" — and a check that only looks for
the `claude` login finds the stale one and misses the real, current verdict.

**How to catch it:** don't filter by a specific bot login at all. Pull every
comment (`gh api repos/<owner>/<repo>/issues/<N>/comments`), sort by
`created_at`, and read the actual last one — or grep the full comment list for
`### Verdict` and take the latest match, regardless of author. Also check
`gh pr checks <N>` timing against the comment timestamps: a `review /
claude-review` / `review / require-review` run that completed **after** the
`claude[bot]` comment's timestamp is a strong signal a newer verdict exists
somewhere, even if the obvious author filter doesn't surface it.
(`Lacaedemon/sparta` PR #647, 2026-07-04 — the agent's own "fully clean, Ready
for merge" report was correct; a first-pass verification that filtered by
`author.login == "claude"` found only the stale "Needs more work" comment and
nearly contradicted a true report.)

## Verify an issue's own stated root cause empirically before implementing its proposed fix

A well-written bug issue with specific code references (line numbers, a named mechanism,
a plausible-sounding causal chain) is still a hypothesis, not a verified fact — even when
it was clearly written after real investigation. Before implementing the issue's own
"fix direction," reproduce the bug live and confirm the ACTUAL code path taken matches the
diagnosis, rather than trusting the write-up and jumping straight to the proposed fix.

**Why this matters:** issue #724 diagnosed a swirling-formation bug as `_face_for_action`'s
"already turning" branch never settling (its re-target-every-tick logic defeating
`_advance_turn`'s tight arrival epsilon). The fix direction (a positional deadband before
re-targeting) was specific, well-reasoned, and referenced real line numbers. Implementing
it and running the exact reproduction (`demos/inputs/all-out-attack.json` via
`tools/demo/dump-state.sh`) showed **zero change** in output vs. unpatched `main` — a
temporary debug print in `_face_for_action` revealed `_engage_turn_target` was NEVER
non-zero across the whole 300-tick window the bug manifests in. The offset stayed under 1°
the entire time, so every tick took the *small*-offset instant-snap branch (`_face_dir`),
never the branch the issue diagnosed and the fix targeted. The real mechanism turned out to
involve the raw **position** itself arcing (not just facing), with soldier counts and
frontage essentially frozen throughout — ruling out the issue's own "third instance of the
same hazard family" framing and pointing at `_press_into()`/`_separate()` instead.

**How to apply:** before implementing a fix a reviewer or issue author proposed (yours or
someone else's), run the issue's own reproduction command (or write an equivalent
`dump-state.sh`/live-battle trace) against the UNMODIFIED code first, and instrument the
specific branch/variable the diagnosis claims is at fault. Confirm that variable's state
actually matches the story before spending effort on the proposed fix — a `git stash` +
re-run diff (patched vs. unpatched output, byte for byte) is a fast, decisive way to catch
a fix that silently does nothing. This is the same "never assume; always verify" principle
`preferences.md` states generally, applied specifically to a bug's root-cause narrative,
not just its resolution status.

## A freshly-constructed test Unit defaults to morale 100 — routing tests can auto-rally instantly

`Unit.gd`'s `morale` field defaults to `100.0`. A GUT test that constructs a bare `Unit`
via `Unit.new()` and immediately calls `_process_rout()` to test rout/flee behavior can hit
`_process_rout`'s own auto-rally check (`morale >= RALLY_MORALE_THRESHOLD and _can_rally()`)
on the very first call — `_can_rally()` trivially returns true in an isolated unit test
(full soldier strength, and `UnitTargeting.nearest_enemy_to` finds nothing since no enemy
Unit exists in the scene), so the unit rallies immediately regardless of what the test
meant to observe. Either set `u.morale = 0.0` (or another value below
`RALLY_MORALE_THRESHOLD`) before the first `_process_rout()` call, or set `u._shattered =
true` if the test wants a flee-forever unit that never rallies at all. Also call the real
`u._rout()` first if the test depends on `_rout_timer` being armed (`ROUT_TIME`) — a unit
that never went through `_rout()` has `_rout_timer == 0.0`, so `_process_rout`'s own
"timer ran out" branch fires on the very first call, which look like a rally/shatter
outcome from the fix under test rather than from the unarmed timer.
(`Lacaedemon/sparta` PR #730, 2026-07-10.)

## `PathField.active` is a global static — reset it around any isolated-unit test touching movement/routing

`PathField.active` (a `static var`) persists across GUT tests within the same run, not just
within one test function. A test that constructs a bare `Unit` and calls `_process_rout()`
or `_move_to()` directly (bypassing a live Battle scene) gets different behavior depending
on whether some EARLIER test in the same run left a real `PathField` instance active — if
so, the pathfinding branch runs instead of the simpler straight-line-flee/move branch,
which can silently change which code path the test is actually exercising. Save and restore
it around the test, the pattern already used in `test_routing_terrain_pathfinding.gd`:
```gdscript
var old_pf: PathField = PathField.active
PathField.active = null   # (or a specific PathField, if the test needs terrain)
...
PathField.active = old_pf
```
Do this in any new isolated-unit test that calls a `Unit` method sensitive to
`PathField.active`, not just tests that are themselves about pathfinding.

## A new stance's derived cap can invert the baseline it's supposed to exceed — check the full input range, not just a weak test case

When a new order-mode/stance introduces its own derived cap or multiplier computed from
geometry or other per-unit inputs (not a flat constant), verify across the REALISTIC RANGE
of those inputs that the derived value can't fall below an existing baseline constant it's
meant to exceed. A test that only exercises a narrow/weak scenario can pass while the
general claim in its own assertion message is false for stronger inputs elsewhere in the
range.

**Concrete case:** PR #736 (knockback focus) added `SoldierCombat.clear_line_speed_cap()`
— the default "just clear the line" push-distance cap, `sqrt(2 * body_accel *
clear_distance)` — intending "trade damage for a much bigger push-back." But for realistic
front-depth pairings (`Unit._front_depth()`'s own `attack_range * 0.5` cap bounds
`clear_distance` to roughly 26-48 wu), the geometric formula tops out around 39.5-53.67
wu/s, BELOW the ordinary attack's `KNOCKBACK_SPEED_MAX = 60.0` — so a strong/charging
landed hit got shoved LESS far by the stance's own default variant than a plain attack
already pushes it, the opposite of the stated design. The included test
(`test_knockback_focus_pushes_the_defender_back_harder_than_a_normal_attacker`) asserted
this generally ("even at the default 'clear the line' setting") but only exercised a weak,
no-charge 12-soldier scenario where the normal-attack impulse never approached the cap, so
it passed despite the inversion. Caught by a `claude[bot]` review pass, not by the original
implementation or its own test.

**Fix pattern:** floor the derived cap at the baseline it's meant to exceed
(`maxf(KNOCKBACK_SPEED_MAX, clear_line_speed_cap(...))`, extracted as its own pure function
`knockback_focus_clear_line_cap()` so the floor is directly unit-testable) rather than using
the raw geometric formula alone. Add tests at BOTH ends of the input range: one proving the
floor binds where the raw formula would undercut the baseline, one proving it doesn't clip
a case where the raw formula already exceeds the baseline.

**How to apply:** when reviewing (or writing) any new per-unit derived cap/multiplier that's
framed as "at least as strong as / bigger than" an existing baseline, don't trust a single
weak-case test to prove that framing — compute (or test) the derived value at the edges of
the realistic input range and confirm it never crosses below the baseline it's supposed to
dominate. (`Lacaedemon/sparta` PR #736, 2026-07-11.)

## A prior PR's own claimed verification can be wrong even after merge

The existing "verify an issue's own stated root cause empirically" memory above covers a
not-yet-merged issue's hypothesis. It extends to a **merged, review-clean PR's own claims**
too: don't cite one as describing the current codebase state just because it merged with a
passing review — spot-check the actual reproduction before trusting it.

**Concrete case:** #743 (merged) claimed, with specific before/after position values, that
it fixed the coast-to-stop bug (residual `_current_speed` decaying while `position` sits
frozen), and its own review rounds confirmed it. The claim didn't reproduce against the
actually-merged commit: `dump-state.sh` on `main` still showed `position` pixel-frozen while
`current_speed` ramped down. Root cause: `UnitCombat`'s "spend the charge" strike-resolution
reset zeroed `_approach_velocity` on the exact tick a unit's last enemy died — the SAME tick
the idle-coast guard started reading it for a travel direction — a case #743's own tests
never exercised (they set up `_approach_velocity`/`facing` directly, never went through a
real combat kill). Fixed in #747 by falling back to `facing` in that specific
zero-velocity/nonzero-speed anomalous state.

**How to apply:** before citing a merged PR's demo/description as proof of current behavior
(e.g. when deciding whether a design-philosophy note still needs a "check whether X has
merged" hedge, or when building on top of a mechanism a recent PR claims to have fixed),
re-run its own reproduction against the current `main` rather than trusting the PR body.
This is cheap (`dump-state.sh` against the PR's own demo input) and catches exactly this
class of gap: a fix that works in the narrow scenario its own tests constructed, but not in
the real path the bug actually occurs on.

## Regiment position is a pure function of body positions

As of #749, `Unit.position` (the regiment's own kinematic point) is not an independently-
controlled value the soldier bodies chase — it's continuously re-derived FROM the bodies.
`SoldierBodies.couple()` runs every tick, computes the drift between the soldier bodies'
actual centroid and their formation-slot centroid, and slides `position` a bounded fraction
of that drift (`FOLLOW_RATE`, capped at `MAX_FOLLOW_SPEED`) toward the bodies. This runs
**unconditionally** — for every unit, every tick, regardless of order state.

**Consequence:** a unit with NO move order (including one under `ORDER_HOLD`, or simply
idle) can still visibly move if its soldier bodies get physically displaced by something
else — enemy-contact impulses, knockback, a failed brace. This isn't a bug or a "unit
trying to move" — it's the intended emergent behavior of the "no top-down gimmicks"
philosophy above: a real line hit hard enough to yield ground would physically cede that
ground, not teleport back to a fixed spot. Before #749, `MAX_FOLLOW_SPEED` was 80 (a mild
drift, largely invisible); #749 raised it to 300 specifically so this coupling could win
against genuine contact resistance, which also makes any body displacement (including from
unrelated causes) far more visible than before.

**How to apply:** when a "stationary" or `HOLD`-ordered unit appears to drift in a demo or
state dump, don't assume its order/state logic is misfiring — check whether its soldier
BODIES are being displaced (contact physics, knockback, a facing/grid change dragging slot
targets) and whether `couple()` is just honestly reporting that drift back up to `position`.
(`Lacaedemon/sparta` PR #749, 2026-07-11.)

## Multi-pair force accumulation needs a write-back clamp, not just a per-pair cap

When a per-tick force resolves in **pairs** (soldier-vs-soldier contact, not a single
discrete strike) and the same body can appear in more than one pair simultaneously, a cap
applied ONLY inside the per-pair resolution function is not enough — the pair-wise caps
compose additively across pairs unless the SUMMED result is also clamped before it's
written back to the body's velocity.

**Concrete case:** `SoldierCollision.enemy_contact_impulse()` caps its own
`effective_closing_speed` at `KNOCKBACK_SPEED_MAX`, with a docstring explicitly scoped to
"one enemy-contact pair." `SoldierEnemyContact.accumulate()` sums that impulse into each
body's `delta_v` across every simultaneously-overlapping enemy, but originally applied the
sum with a raw `+=` — a soldier touching 2-3 enemies at once (e.g. a Square-perimeter
defender pressed by several attackers from one side — MORE likely after #749's own fix
making `engaged_soldier_indices()` return the whole perimeter for Square/Schiltron, not
just a front wedge) could receive 2-3x the stated per-tick cap. No downstream clamp rescues
this for an actively-fighting body (`SoldierBodies._cap_body_speed()` only runs when idle
or reforming). Caught by `claude[bot]` review, not the original implementation or its test
(which only budgeted one `KNOCKBACK_SPEED_MAX` term per tick in
`test_collision_knockback_battle.gd`'s displacement bound).

**Fix pattern:** apply the write-back through `SoldierCombat.capped_knockback_velocity`
(which clamps the RESULTING velocity — `max(current speed, cap)` — after adding the
impulse) instead of a raw add, mirroring the pile-on clamp `SoldierMelee.resolve` already
uses for accumulated strike knockback on one body ("impulses from every attacker shoving
this body this cadence accumulate in its velocity, and each application clamps the summed
result"). Test the worst case directly: two (or more) pairs whose contact normals point in
the SAME direction (impulses stack instead of partially canceling), asserting the total
stays capped. (`Lacaedemon/sparta` PR #749, 2026-07-11.)

## `target_enemy` persistence must respect `ORDER_HOLD`'s existing contract

`UnitTargeting.current_target()`'s doc/comment states its purpose as "keep an already-live
target rather than re-scanning for the nearest," but the auto-acquire fallback path
(`nearest_enemy()`, used when `target_enemy` is null) never actually wrote its pick back
into `target_enemy` — so a unit with no explicit attack order re-ran a full nearest-enemy
scan from scratch EVERY tick. Under a multi-attacker press, tiny jostles in relative
distance flip which enemy is "nearest" tick to tick, and each flip re-arms
`_face_for_action`'s engage-turn toward a new direction — the whole grid sweeps back and
forth at the turn rate instead of settling on one foe (visible as soldiers "flying" once
body coupling is fast enough to track it — see #749 above).

**The gotcha:** persisting the auto-acquired pick (`target_enemy = enemy`, in `_think()`'s
gated combat-engagement branches) fixes that whipsaw, but `Unit.gd`'s chase branch
(`elif target_enemy != null or (chasing and not in_contact): ... _move_to(goal, delta)`)
has **no `ORDER_HOLD` guard** — because until this change, `target_enemy` only ever went
non-null via an EXPLICIT order, which `ORDER_HOLD` is specifically meant to still obey
("HOLD only suppresses chasing a DETECTED foe, not an explicitly-set target"). Committing
an auto-acquired pick unconditionally reclassifies it as that kind of explicit target: the
instant the fought enemy leaves contact (retreats, gets knocked back, routs —
`current_target()` still returns a routing unit, only `state != DEAD` is checked), the
melee/ranged branch stops firing but `target_enemy` is still set, so the HELD unit marches
off after it. Caught by `claude[bot]` review, not by the original fix or its own tests
(which only called `_think()` once, never reaching the tick where the enemy has left
contact).

**Fix:** skip the `target_enemy = enemy` commit specifically when `order_mode == ORDER_HOLD`
— this preserves the pre-existing contract at the cost of not fixing the facing-whipsaw for
an un-squared HELD unit under a multi-attacker press specifically (not a regression, since
that combination was never fixed by the persistence change in the first place — Square is
exempted from engage-turning entirely regardless of order_mode, so the common case is
covered anyway). **How to apply:** any time a field's "only ever set by an explicit order"
invariant is broken by a new auto-commit path, grep every consumer of that field for logic
that assumes the old invariant (here: an unguarded chase branch) before shipping — a single
unconditional write can silently reclassify state elsewhere in the same file relies on
staying scoped. (`Lacaedemon/sparta` PR #749, 2026-07-11.)

## An early return added to `_face_for_action` must settle any in-progress engage turn

`_face_for_action()` tracks an in-progress turn via `_engage_turn_target` (nonzero while
turning), cleared only by `_settle_engage_turn()` at completion or interruption. Adding a
NEW unconditional early return to this function (e.g. `if in_square(): return true`, added
in #749 so an omnidirectional formation never needs to reface) can strand that state: if a
unit is mid-turn when it gets switched to the new early-return condition (here,
`ORDER_FORMATION_ONLY` calling `Unit.set_formation()` mid-turn, which doesn't touch
`_engage_turn_target`), every SUBSEQUENT call takes the new early return before ever
reaching the `_advance_turn`/`_settle_engage_turn` logic that would normally finish and
clear it. `_engage_turn_target` then stays stuck non-zero forever, which — per
`is_maneuver_turning()`'s own docstring — permanently freezes `SoldierBodies.step`'s
slot-approach term: the squared body never eases onto its new slots. Caught by `claude[bot]`
review (reachable via the exact anti-cav-square flow #749 is built around: a unit turning
to face an approaching charger, then squared reactively before the turn finishes), not by
the original implementation.

**Fix:** settle any in-progress turn before taking the early return:
`if _engage_turn_target != Vector2.ZERO: _settle_engage_turn()` before `return true`.
**How to apply:** any new early return added to a stateful turn/maneuver function in this
file (anything tracking `_engage_turn_target`, `is_wheeling()`, `is_order_turning()`, or
similar) needs to settle or explicitly account for whatever in-progress state it might be
short-circuiting past — grep the function for every OTHER path that clears the same state
before assuming a new early return is safe. (`Lacaedemon/sparta` PR #749, 2026-07-11.)

## A bare `Unit.new()` test fixture defaults to `uid -1` — soldier-id collisions across fixtures

`Unit.soldier_id(index)` computes `uid * SOLDIER_ID_STRIDE + index`, and `Unit.gd`'s `uid`
field defaults to `-1` (only ever assigned a real, unique value by `Battle`'s spawn path).
A GUT test that constructs TWO bare `Unit.new()` fixtures (never spawned through Battle) and
exercises any logic keyed on `soldier_id()` — e.g. `SoldierEnemyContact.accumulate()`'s pair
canonicalization, `if sgids[b] <= sgids[a]: continue` — will see BOTH fixtures' soldier 0
resolve to the identical id (`-1 * STRIDE + 0`), so the pair gets silently treated as
already-resolved/duplicate and skipped, regardless of what the test actually intended to
exercise. This doesn't fail loudly — a test asserting "nothing changed" can pass for the
WRONG reason (id collision) instead of the reason its docstring claims (e.g. a same-team
skip, or a dead-unit skip).

**How to apply:** any GUT test constructing more than one bare `Unit.new()` fixture and
exercising soldier-id-keyed logic must assign each a distinct `uid` explicitly (e.g.
`u.uid = 1`, `u.uid = 2`), matching what a real `Battle`-spawned unit always gets. Verify a
new cross-unit test isn't accidentally passing via this collision by checking the actual
resolved values (not just the top-level assertion) the first time it's written — a debug
probe test (construct the fixtures, print `engaged_soldier_indices()`/`soldier_id()`/the
resulting velocities) is the fast way to catch it, faster than reasoning through the pair
loop by hand. (`Lacaedemon/sparta` PR #749, 2026-07-11.)

## Square/Schiltron's engaged-set staleness root cause: array compaction after casualties, not just "multi-attacker chaos"

#752 reported `Unit.engaged_soldier_indices()`'s SQUARE/SCHILTRON branch (slot-index
perimeter, `UnitFormation.square_is_perimeter`) as wrong under "multi-attacker chaos" but
didn't pin down the mechanism. Empirical check (`demos/inputs/anti-cav-square.json`,
`SPARTA_DEMO_STATE_FULL=1`, comparing each attacker soldier's true nearest-defender index
against the returned engaged set, gated to pairs actually within contact range) found a much
sharper signal: the mismatch rate is **0% at every tick before the first casualty**, then
jumps to 32%+ the instant `SoldierMelee.reap()` compacts the array. Root cause:
`square_is_perimeter(i, n, files)` is a function of SLOT INDEX in the ORIGINAL grid, but
`reap()` removes dead soldiers by splicing the per-soldier arrays — every index after a
removed soldier shifts down, so index `i` no longer sits where `block_slots` originally laid
it out. This is a **same-unit geometry bug**, not fundamentally about needing enemy-position
data (the issue's own proposed direction) — the array is stale relative to itself.

**Fix, partial:** `UnitFormation.live_perimeter_indices(positions, target_count)` replaces
the slot-index selection with the `target_count` LIVING soldiers currently farthest from the
block's own LIVE centroid (`_sim_soldier_pos`, read directly — same OUTPUT SIZE/target count
as the old ring, not the same runtime cost: selection itself is a bounded min-heap,
O(n log target_count), vs. the old O(n) index scan — more work per call, though bounded and
small relative to a tick's other per-soldier costs at this game's regiment sizes). This
measurably improves the gated mismatch rate at every post-casualty tick checked (32%→22%,
78%→70%, 67%→60%, 67%→47%, 62%→45%) with no regression on the pristine (no-casualty) case.
**It does not fully
close #752** — "farthest from live centroid" is still an approximation of "true outer ring,"
and under heavy multi-directional pressure (the block reflowing unevenly as different sides
take casualties at different rates) it can still misclassify a soldier pushed inward on one
side as "engaged" over a genuinely exposed soldier on a less-pressed side. The issue's
originally-proposed direction (each candidate's nearest ENEMY soldier within a contact
radius, via `SoldierSpatialHash`) is the fuller fix and remains open follow-up work
(#752 stays open).

**How to apply:** before implementing a "make this live/position-based instead of
index-based" fix, verify empirically whether the bug is (a) same-unit index/position
staleness (fixable by reading live positions, no cross-unit data needed) or (b) genuinely
needs cross-unit proximity data — they look identical from the bug report alone
("this-N-vs-that-N mismatch under chaos") but have very different fix complexity. Gate any
such reproduction to pairs actually within contact/reach range — an ungated "nearest globally"
metric picks up noise from units still approaching each other, which can make an otherwise-
sound fix look like it regressed the pristine case. (`Lacaedemon/sparta` PR #758, partial
fix for #752, 2026-07-11.)

**Caught by review, not the original implementation:** the first version of this fix used a
full `Array.sort_custom` over every soldier to pick the `target_count` farthest, then claimed
"the per-tick cost bound is unchanged" because the OUTPUT size matched the old algorithm's --
conflating output-size parity with runtime-cost parity. `claude[bot]` correctly called this
out: the old SQUARE branch was a single O(n) index scan; the new one added an O(n) centroid
pass plus an O(n log n) sort, strictly more work, and the claim was baked into three separate
comments/docs (`Unit.gd`, `test/unit/test_unit.gd`, this file) that all needed fixing, not just
one. Replaced the full sort with a bounded min-heap of the `target_count` best candidates
(O(n log target_count) — see `UnitFormation._worse`/`_heap_sift_up`/`_heap_sift_down`), which
is strictly less work than a full sort whenever `target_count < n` (always true here), and
added a differential test against a brute-force full-sort reference on an irregular point
cloud to catch a heap sift-up/sift-down bug the smaller/symmetric tests wouldn't. **How to
apply:** "the output is the same shape/count as before" is not the same claim as "the cost is
unchanged" -- don't let a same-size-output observation imply a same-cost one without checking
what actually changed inside the call.

## A merged "partial fix" PR can auto-close its tracking issue even without a `Closes` keyword

Merging a PR whose title/body bare-mentions a tracking issue by number (`(partial #752)`,
`Progress on #752`) can auto-close that issue on merge, even when the PR explicitly states
"does **not** close it" and a PR/issue comment says "leaving this issue open." Neither PR
#758's title nor body used a `Closes`/`Fixes`/`Resolves` keyword, so it isn't the standard
keyword-based auto-close. **The exact mechanism is unconfirmed** — the reopening comment
posted at the time guessed "repo automation matching the `#752` reference in the squash
commit title," but that's a guess, not a verified cause; a later review round flagged that
GitHub's PR "Development" sidebar auto-link (an alternative theory this entry originally
asserted) normally requires a *manually applied* link and doesn't auto-attach just because
an issue number appears in a PR title, so that theory is probably wrong too. `godot-ci.yml`'s
`resolve-main-failure` job ("Close tracking issue on green") IS ruled out, though — it only
ever touches a separate marker-tagged `ci-failure` issue, confirmed by reading the workflow.

**How to apply:** after merging any "partial fix, issue stays open" PR that mentions the
issue number anywhere in its title or body, check the issue's state immediately —
`state_reason: "completed"` right around the merge timestamp is the tell. Reopen with an
explanatory comment if it auto-closed; don't assume stating "leaving this open" in the PR
body is sufficient to prevent it. (`Lacaedemon/sparta` PR #758 / issue #752, 2026-07-11:
#752 was closed at the exact merge timestamp despite both the PR body and an issue comment
stating it should stay open; reopened with an explanation.)

**A second, independent occurrence narrows the mechanism further.** Issue #296 was
auto-closed by PR #782's merge (2026-07-12, a real commit-message keyword match, since
#782's first commit read "...closes #296") and reopened with an explanation. It was
auto-closed a SECOND time by PR #981's merge (2026-07-18, 23:43:15Z — 2 seconds after the
merge landed), even though NO commit in #981's entire squash-merge history contains a
`closes`/`fixes`/`resolves` keyword anywhere near "#296" (checked the full squash commit
body). `gh api repos/.../issues/296/events` shows this second close event's `commit_id` is
`null` — unlike the first (keyword-matched) close, which had a real commit SHA attached.
A null `commit_id` rules out the standard commit-message-keyword auto-close for this
occurrence specifically, and points instead at something that fires off the PR's own
DESCRIPTION text: #981's body mentioned "#296" prominently in an "Also found and fixed in
passing" section — not a closing-keyword sentence, but strong textual proximity to the word
"fixed". Still not a confirmed mechanism, but strengthens the case that merely naming an
issue number anywhere in a PR body (not just a commit message, and not just a literal
closing keyword) can trigger an auto-close on merge. Treat ANY issue-number mention
anywhere in a PR's commits OR its description as a close risk, not just literal
`closes #N` phrasing — check the mentioned issue's state immediately after every merge.

## A new physics-frame-keyed static cache needs an explicit `reset()` in any test that constructs its own fixture data

This generalizes the existing `PathField.active is a global static` entry above beyond
pathfinding: ANY new static, frame-keyed cache added to the soldier layer (mirroring
`SoldierSpatialHash`'s `_frame`/`is_current(frame)` pattern) is a fresh test-isolation
hazard the moment it's keyed by `Engine.get_physics_frames()` rather than a caller-supplied,
test-controlled frame number.

**Why this bites GUT tests specifically:** `Engine.get_physics_frames()` only advances on a
real physics tick. Two different, synchronous test functions that never `await
get_tree().physics_frame` run at the EXACT SAME frame number, even though they construct
completely different units. If a cache's `is_current(frame)` gate sees the same frame number
across both, the SECOND test's call reuses the FIRST test's cached grid -- built from the
first test's now-freed (or simply different) units -- instead of rebuilding from its own
fixtures. This is silent: no error, just a wrong (often EMPTY or stale) query result, which
in turn changes control flow (a fallback branch fires when it shouldn't, or vice versa).

**Concrete case:** `SoldierEnemyProximity` (added for #752's cross-unit-proximity fix, PR
#760) keys its rebuild by `Engine.get_physics_frames()` internally (unlike
`SoldierEnemyContact.accumulate(units, frame)`, whose callers -- including its own test
fixtures -- pass an explicit, test-chosen frame number precisely to avoid this). A new test
proving the proximity selection excludes a far-side ring soldier passed when run alone, but
FAILED when the full suite ran: the immediately-preceding test
(`test_engaged_soldier_indices_is_the_whole_perimeter_when_squared`, a no-enemy Square
fixture) ran at the same physics frame, rebuilt the grid with only ITS OWN unit, and the new
test's call then saw `is_current()` true and silently reused that stale, enemy-free grid --
falling back to the whole-ring selection instead of the proximity-filtered one, so the
"excluded" assertion failed.

**Fix:** call the cache's `reset()` at the start of any test that builds its own fixture
data and exercises a code path depending on it -- both the new test AND the pre-existing
neighboring test needed the guard, since either one could run first and poison the other
depending on suite ordering. This doesn't fix a production hazard (a real game tick always
advances `Engine.get_physics_frames()` between ticks, so the real per-tick rebuild is sound)
-- it's purely a test-isolation gap this kind of cache introduces. When adding a new
frame-keyed static cache: either accept an explicit frame argument from every caller (like
`SoldierEnemyContact.accumulate`) so tests can pick collision-free values, or -- if the
production call site can't reasonably do that (as here, `engaged_soldier_indices()` is called
from many places with no natural place to thread a frame argument through) -- document the
`reset()` requirement on the class itself and add it to every test that constructs its own
units for that code path. (`Lacaedemon/sparta` PR #760, 2026-07-11.)

## A symmetric "is X near Y" contact check needs BOTH sides' own range, not just one side's

When computing whether two entities are within striking/contact distance of each other, and
each side has its OWN independently-valued range (reach, radius, whatever), a check using only
ONE side's range silently breaks the case where the OTHER side is the one with the longer
range. This is the same spear-vs-sword standoff the `SoldierEnemyProximity.has_enemy_within`
and `Unit.engaged_soldier_indices` code comments themselves call out ("a longer reach lets a
soldier strike foes who cannot strike back") — but it's easy to re-introduce the same class of
bug in a NEW proximity check that doesn't reuse that exact code path.

**Concrete case:** PR #760's `SoldierEnemyProximity.has_enemy_within(pos, team, self_radius)`
computed `contact = self_radius + candidate_radius + candidate_reach` — using only the
CANDIDATE enemy's reach, never the QUERYING soldier's own. A long-reach querier (a Schiltron
spear, reach 48) could be wrongly dropped from the engaged set when facing a shorter-reach
enemy (a sword, reach 26) at a distance the QUERIER could actually close (e.g. 40 units --
beyond the sword's own 35-unit contact radius, but within the spear's 62-unit one). Caught by
`claude[bot]` review, not the original implementation or its own tests (which only tested the
candidate-has-a-longer-reach direction, never the reverse).

**Fix:** `contact = self_radius + candidate_radius + maxf(self_reach, candidate_reach)` --
thread the QUERYING side's own reach into the call (a new `self_reach` parameter), not just
the candidate's. **How to apply:** whenever a new pairwise contact/proximity check is added
for two entities with independently-valued per-side ranges, test BOTH directions explicitly
(querier-is-longer-range and candidate-is-longer-range) rather than assuming symmetry --
a same-magnitude test case can pass by coincidence even when the formula silently favors one
side. (`Lacaedemon/sparta` PR #760, 2026-07-11.)

## Claiming a demo change "can't be shown visually" needs a check for existing debug-visual precedent first

Before writing `skip: true` with a "the difference isn't visually distinguishable" rationale,
grep for an existing debug-visual overlay that already renders the exact internal state the
change affects -- a sibling PR may have already built and used one for the very same function.

**Concrete case:** PR #760 (closing #752) initially skipped its demo, reasoning that changing
WHICH soldier index gets selected as an engaged/melee candidate wasn't something a viewer could
see in a recorded clip. But PR #758 (the immediately-preceding partial fix to the SAME
function, `engaged_soldier_indices()`) had already built and used
`Settings.show_engaged_highlight` -- a dev/debug visual that tints exactly the returned
soldiers amber -- for exactly this purpose. `claude[bot]` review caught the precedent; fixed by
authoring a fresh scenario (`schiltron-asymmetric-pressure.json`, per the standing "author each
demo scenario fresh" rule) using that existing highlight: a Schiltron pressed from only ONE
side, so the highlight visibly concentrates on the pressed front instead of ringing the whole
perimeter the way the prior PR's centroid-distance selection would regardless of attacker
position -- a real, visible proof of the improvement.

**How to apply:** before skipping a demo for an "internal selection logic, not visually
distinguishable" reason, check whether ANY existing `Settings.show_*` debug toggle, highlight
overlay, or similar dev visual already renders the specific internal state your change affects
-- especially on a function a recent sibling PR also touched, since that PR may have built the
exact visual tool you need. Only skip once you've confirmed no such visual exists. (Also
verify locally with `dump-state.sh` before claiming the scenario demonstrates the fix, per this
file's other verification-before-claiming entries -- don't just trust that the render will show
what you intend.) (`Lacaedemon/sparta` PR #760, 2026-07-11.)

## Bbox-settling checks alone miss a mid-march swirl -- check FACING across the whole clip, not just position at a few sample ticks

`dump-state.sh` verification (per the entries above) checks whether a unit reaches its
target STATE/position by the end of a clip. That's not enough on its own: a unit can
legitimately arrive `IDLE` at the right final position while its `facing` swung through
100+ degrees getting there, which reads as a spinning/broken formation on screen even
though the position-only check reports "settled fine."

**Concrete case:** #458's `demos/demo.458.json` (PR #772, merged) was verified this way --
position/state at the final sampled ticks looked settled, so the PR shipped. A closer look
(prompted by a user report that #772's own demo shows swirling with zero combat) found
`facing` swinging 90 deg -> 53 deg -> ... -> -144 deg for two of the three units mid-march,
and rendered frames confirmed a REAL visible rotation (the soldier block visibly diagonal,
two units' blocks visually intermixed) -- not just a `facing`-field bookkeeping artifact.
Filed as #774 (distinct from #724's melee-lock swirl -- see below).

**How to apply:** when verifying any demo/test involving a MARCH (not just combat), dump
`facing` at dense intervals across the WHOLE clip, not just a few widely-spaced ticks, and
watch for large or non-monotonic swings even if the unit still arrives correctly. A live
frame-capture spot-check (`SPARTA_DEMO_INPUT=... xvfb-run -a godot --rendering-driver
opengl3 --write-movie <path>.png --fixed-fps 30 --quit-after N ...`, then `Read` a mid-clip
frame) is the fastest way to confirm whether a facing swing is a real visible rotation or
inert bookkeeping.

## THREE distinct root causes behind "formation visibly spins" -- don't assume it's one bug

There are at least three separate mechanisms that each independently make a regiment's
soldier block visibly rotate or smear: two swirls discovered investigating #724 and #774 in
the same session (both unresolved as of this writing), and a third -- the pre-contact
approach-march blob -- found and fixed later (#921). All show up as `facing` and the soldier
block's world orientation drifting, but they're driven by different subsystems and resist
the same fixes:

- **#724 (melee-lock swirl):** two units in PROLONGED, roughly matched melee slowly and
  continuously rotate around their clash point, accelerating over hundreds of ticks (a
  300-tick trace looks like it's settling; extending to 700 ticks shows it's actually a
  continuous, still-accelerating rotation that eventually sweeps 200+ degrees). Instrumented
  `Battle._on_soldier_tick()`'s three soldier-layer stages with a net-torque-proxy (sum of
  `cross(r_i, delta_v_i)` relative to each unit's own centroid, accumulated cumulatively
  across ticks): `SoldierEnemyContact.accumulate` is the dominant, persistently-biased
  (one-signed, ~+18750 cumulative by tick 700) source; `step_all_sim_soldiers` partially but
  not fully cancels it. Two plausible fixes were tried and BOTH had zero measurable effect:
  (a) a frame-start position snapshot for `_face_for_action`/`_press_into`/`_separate`'s
  cross-unit position reads (to rule out Gauss-Seidel processing-order bias -- ruled out: a
  "swap which team spawns first" test that seemed to confirm order-dependence was
  MISINTERPRETED, the direction actually correlates with TEAM identity, not processing
  order); (b) reverting the #749 coupling gain (`MAX_FOLLOW_SPEED` 300->80, to test a
  feedback-resonance hypothesis -- also no effect). Root cause not yet found; likely lives
  inside `SoldierEnemyContact`'s per-soldier contact-pair geometry itself (WHICH soldiers
  end up in contact, not the impulse formula, which IS Newton's-third-law symmetric per pair).
  A THIRD hypothesis, tried in a later session: `Unit.engaged_soldier_indices()`'s
  NORMAL-formation branch selected soldiers by raw array index (`for i in range(cutoff):
  out.push_back(i)`), which `SoldierMelee.reap()`'s casualty-driven array compaction makes
  stale -- the same staleness class #752/PR #758 already fixed for the SQUARE branch (see
  that section below). Instrumentation confirmed a real, growing, LOCAL-FRAME-CONSISTENT
  skew in both units' naive selections as casualties mount (which, since the two units face
  180° apart, resolves to OPPOSITE world-frame sides -- a structural, not random, asymmetry).
  Fixed as `UnitFormation.live_front_indices` (#779/PR #780) -- but this only
  MEASURABLY SLOWS the swirl's onset (the early-window ticks 100-300 rotation rate drops from
  ~170°+ to ~18° in the `all-out-attack.json` reproduction) rather than eliminating it: the
  rotation re-accelerates later once casualties exhaust the genuinely-forward candidates too,
  reaching a comparable ~222° by tick 700. Real partial mitigation, not the root cause. Next
  angle to try: instrument the actual soldier-to-soldier PAIRING `SoldierEnemyContact`
  resolves each tick (via `SoldierSpatialHash.query`'s 3x3 neighborhood) for a systematic
  left/right asymmetry independent of which soldiers get gathered -- two now-correctly-selected
  front lines could still pair asymmetrically if each side's actual footprint has reshaped
  differently under casualties.
- **#774 (march swirl, no combat):** a unit's facing swings wildly while MARCHING near other
  units, with zero enemies and zero contact -- reproduces in #458's plain drag-to-form-up
  scenario. The SAME torque-proxy instrumentation, applied to this scenario, found BOTH
  `SoldierEnemyContact` (no enemies, so 0 as expected) AND `SoldierSteering` (friendly
  avoidance -- also 0, ruling out steering as the source despite the units spawning close
  together) contribute NOTHING; the entire signal comes from `step_all_sim_soldiers` (bodies
  chasing their formation-slot targets), oscillating hugely (-147k to +103k over the march).
  Since slot targets are a pure function of `facing`/`_formation_angle`, this points
  upstream, to whatever computes the march's target HEADING each tick, not to a soldier-body
  contact/steering force at all. Not yet root-caused. Curiously, only 2 of 3 units in the
  #458 reproduction swirl -- the third (shortest lateral repositioning) stays perfectly
  stable, and all three are `disciplined: true` (ruled out as a disciplined/undisciplined
  difference).

- **A THIRD, now-fixed mechanism (#921, PR #924 -- pre-contact BLOBBING on a detouring
  approach march, distinct from both swirls above):** two stacked causes. (a)
  `PathField.next_step` steered by the ADJACENT A* cell centre, whose bearing jumps in
  coarse per-cell quanta (a shallow one-cell detour read as a hard ~68 deg turn then a hard
  counter-turn) -- fixed by string-pulling (return the farthest path point in direct line of
  sight). (b) A combat chase snapped `facing` to that bearing via `_face_dir`, and any snap
  UNDER `FACING_SNAP_ABSORB_THRESHOLD` (75 deg) rotates the whole slot grid in one tick with
  NO `_formation_angle` fold -- flank slots sweep ~10x faster than any body can run, and the
  soldiers scramble across the block (nnd collapsed 9.0 -> 0.29 wu). Fixed by `_move_to`'s
  `formed_turn` flag: disciplined approach marches (attack chase, auto-advance, support)
  centre-pivot gradually, rate paced by the corner man (`UnitManeuver.wheel_gait_rate` on
  the footprint half-diagonal via `_pivot_radius()`); at/past 75 deg the snap+fold path
  stays (the fold already holds the grid still, and a turn that large wants an about-face
  decomposition -- #922's territory). The debugging technique that cracked it: a per-tick
  trace of `facing`, `_formation_angle`, and the derived grid angle (`facing.angle() + PI/2
  + _formation_angle`), plus prints on every `_formation_angle` mutation site -- the tell
  was the grid angle jumping with NO fold print, isolating the sub-threshold `_face_dir`
  path. That per-tick grid-angle trace is cheaper and more direct than the torque proxy
  when the symptom is "block rotates/smears while marching" rather than a persistent melee
  swirl.

**How to apply:** don't assume a "formation spins" report is the same bug as a previously
diagnosed one just because the symptom looks similar. Reproduce fresh with the SAME
cumulative-torque-instrumentation technique (temporary `print()`s in
`Battle._on_soldier_tick()`, one running total per stage, printed every N ticks -- always
revert before committing) to find which specific subsystem is the source for THIS
reproduction before assuming a fix that didn't work for one case will work for the other.

## A live-battle GUT test reading `current_order` needs the tick-count wait loop, not a single bare `await physics_frame`

`Battle._physics_process` increments `_tick` AFTER running that tick's `_run_enemy_ai()` (so
`current_tick()` reads `N` *during* tick `N`'s own processing, then becomes `N+1` right after).
The established live-battle AI test pattern (`test_battle_ai_leaders.gd`, `_subcommanders.gd`)
accounts for this with `while battle.current_tick() <= SOME_TICK: await get_tree().physics_frame`
-- looping until the counter has genuinely advanced past the tick whose AI decision the test
wants to read. A test that instead does a single bare `await get_tree().physics_frame`
immediately after `add_child_autofree(battle)` and then reads live `current_order` state is
racing an off-by-one: whether that one signal lands after the newly-added Battle node's FIRST
`_physics_process` call isn't guaranteed by Godot's node-lifecycle timing, and the race is far
more likely to be lost under heavier scheduling load (a full ~100-plus-script suite run) than
when the single file runs alone.

**Concrete case:** PR #794's `test_two_doctrines_produce_visibly_different_army_behavior_from_the_same_seed`
used a single bare await, unlike every sibling test in the same file (which either call the
pure `General.decide_army()` directly -- immune to the race, since it doesn't depend on the
live tick having fired -- or already use the tick-count loop for their own live-order check).
It passed reliably in isolation (`-gselect=test_battle_ai_general.gd`, 5/5) but failed
consistently under the full suite (1571/1572, always the same test) -- the tell that it's a
timing race tied to system load, not a logic bug in the code under test. Root-caused by first
ruling out `DoctrineRegistry`'s static `_cache` (no in-place mutation anywhere, confirmed by
grep) and `General.gd`'s own RNG usage (there is none), then checking `_physics_process`'s
actual tick-increment ordering directly. Fixed by switching to
`while aggressive.current_tick() < 1: await get_tree().physics_frame`, matching the sibling
pattern.

**How to apply:** any new live-battle GUT test that spawns a `Battle` and reads
`current_order`/other live per-tick state (not just calling a pure decision function directly)
must wait via a `current_tick()` loop, never a bare single `await physics_frame` -- and a test
that passes alone but fails only under the full suite is a strong first hint to check for
exactly this pattern before suspecting the actual feature code. (`Lacaedemon/sparta` PR #794,
2026-07-12.)

## Batch-dispatched agents: verify diffs and test runs independently, don't trust completion reports

During a large parallel GIA batch (2026-07-09), several agent-reported "implemented and
tested" PRs turned out to have real, independently-confirmed problems that the reports never
mentioned:

- **Empty-claim PRs mistaken for done.** #690 (chase attack, PR #701), #676 (issue-citation
  lint, PR #706), and #687 (pin-down attack, PR #707) each had a draft PR opened per the
  `pr-on-claim` convention (an empty commit pushed up front, before implementation) where the
  actual implementation was never pushed. A draft PR existing and referencing "Closes #N" reads
  as "someone's on it" -- nothing in the PR list, checks, or title distinguishes
  mid-implementation from abandoned-before-implementation-ever-started. #706 turned out moot
  (issue #676 was already independently resolved via merged PR #684 before #706's claim even
  happened) -- always `gh issue view <N> --json state,closedAt` before re-implementing.
- **Cross-branch contamination.** Two unrelated features' commits ended up mixed onto the wrong
  branch: Newton's-laws-collision code (issue #678) landed on `feat/sweep-routers-attack`
  (issue #693) instead of its own `feat/newtons-laws-collision`, and PIN_DOWN combat logic
  (issue #687) landed on `feat/roll-the-line` (issue #691) instead of `feat/pin-down-attack` --
  leaving roll-the-line's own actual mechanic never implemented despite its enum entry existing.
  Root cause: parallel agents apparently shared a checkout/working-tree at some point, so one
  agent's commits bled into a sibling's branch. Tell: `gh pr view <N> --json commits` showing
  commit messages that don't match the PR's own stated feature, or `git diff origin/main
  origin/<other-branch> -- <file>` turning up a sibling PR's feature. Fix is mechanical once
  found (the two features were cleanly separable file-by-file in every case observed): checkout
  the misplaced files from the wrong branch onto the right one, `git rm` them from the wrong one,
  commit both sides separately.
- **Real bugs behind a "tests pass" claim**, caught only by an independent re-run on a fresh
  worktree checkout of the pushed branch (never the agent's own worktree, which can have
  uncommitted fixes never actually pushed): a GDScript syntax error (`var [a, b] = ...` array
  destructuring -- GDScript has no such syntax -- in `SoldierMelee.gd`), an undeclared
  `BattleRef.Gait` preload alias in `Unit.gd` that would fail project import entirely (found
  by a *different* agent, dispatched only to build a demo, that happened to run
  `tools/check.sh validate` as a prerequisite step), and a targeting bug where `target_enemy`
  stayed `null` in all 3 of a feature's own tests (root cause: the test spawned enemies outside
  `Unit.DETECTION_RANGE`, plus a separate instant-rally bug from calling `_rout()` directly on
  an undamaged unit with full morale).

**How to apply:** never trust "tests pass" / "ready for review" from a report alone --
re-run `tools/check.sh validate` and `tools/check.sh test` yourself from a fresh worktree of the
actual pushed remote branch before treating a batch-dispatched PR as sound. When a file that
should belong to one feature shows up on a different feature's branch (or a feature's own
expected symbol is entirely absent from its own branch's diff), suspect cross-branch
contamination before assuming the feature just wasn't written -- `git diff origin/main
origin/<branch> | grep -i "<feature-name>"` returning nothing is a fast smoke test. Give each
dispatched agent its own explicit, freshly-created worktree path in the prompt, and tell it not
to reuse/assume any pre-existing worktree unless explicitly named -- this is the likely root
cause of the cross-branch contamination cases. (`Lacaedemon/sparta`, GIA batch cleanup,
2026-07-09 -- affected PRs #695, #698, #701/#713, #702, #706/#707, #708, #709, #711.)

## A fresh worktree's first `tools/check.sh test` run needs a second `--headless --import` pass

`tools/check.sh test` vendors GUT on demand (clones into `addons/gut`) when a fresh worktree
doesn't have it yet, but Godot's `class_name` registration only happens during project import
-- which already ran (or never ran) before GUT's files existed on disk. So the very first
`tools/check.sh test` call in a brand-new worktree always fails with:

```
ERROR: Some GUT class_names have not been imported.  Please restart the Editor or run godot --headless --import
Missing class_names:  ["GutErrorTracker", ... "GutTest", ...]
```

`== summary == PASS test` / `All checks passed.` still prints -- the script doesn't treat this
as a failure, so it's easy to miss that no tests actually ran.

**How to apply:** in a fresh worktree, run `<godot> --headless --import` once, then
`tools/check.sh test` (vendors GUT), then `<godot> --headless --import` a SECOND time (registers
GUT's newly-vendored `class_name`s), then re-run `tools/check.sh test` for the real result. A
worktree that already has `addons/gut/` from a prior run only needs the one usual import pass.
Hit repeatedly across many fresh worktrees during the 2026-07-09/2026-07-13 GIA batch-cleanup
and independent-verification passes.

## The Coverage CI job shifts sim timing — read spawn values PRE-tick and budget arcs in real sim ticks

Sparta's non-gating **Coverage** job (`test-coverage.yml`) runs the GUT suite through
`addons/coverage`, which reloads counter-injected copies of the game scripts. That
instrumentation slows and shifts sim stepping, so timing-bounded scenario assertions read
drifted values and flake there while the gating "Validate & test" job passes them. This
flaked on `main` itself (#508, fixed in PR #511), not tied to any one PR. Two patterns and
their fixes (both in `test/unit/test_battle_scenario.gd` and `test_rout_rally_demo_scenario.gd`):

- **Spawn/override-value asserts must read PRE-tick.** Reading a unit's `morale`/`facing`
  after `await get_tree().physics_frame` lets one recovery/rotation tick drift it off the
  exact spawn value (morale 30.0 read as 30.033; facing -1.0 read as -0.928). `Battle._ready()`
  runs **synchronously** during `add_child_autofree(battle)` — it calls `_spawn_scenario()`,
  which registers each unit in the `"units"` group and sets `facing`/`morale` before returning.
  So delete the `await` and assert spawn values immediately; no tick can fire between
  `add_child` returning and the group query.
- **Budget scenario arcs in REAL sim ticks, not await-iterations.** Under instrumentation an
  `await physics_frame` no longer maps 1:1 onto a sim tick, so a `for i in range(N)` loop's
  index diverges from the sim's real tick. Bound the loop by `Battle.current_tick()` (incremented
  once per `_physics_process`) and derive the budget from sim constants with headroom, e.g.
  `ROUT_ONSET_BUDGET + ceil(Unit.ROUT_TIME * Replay.PHYSICS_TPS) + RALLY_MARGIN`. Prefer the
  canonical `Replay.PHYSICS_TPS` autoload over a duplicated `:= 60` local. Prefer read-pre-tick
  / real-tick budgets over loosening tolerances — a wider tolerance still races the clock.

When widening such a budget, also account for OTHER in-flight PRs that shift the same sim
dynamics (a physics retune moves *when* the block breaks) so the later PR won't re-break the
test on resync — widen via the named headroom constant, never by weakening an assertion.
(`Lacaedemon/sparta` #508/PR #511, coordinated with #497.)

## Soldier bodies ARRIVE at their slots under bounded force — not a damped spring

`scripts/SoldierBodies.gd`'s `step()` used to be a near-critically-damped **spring** toward
each formation slot (`SPRING_STIFFNESS`/`SPRING_DAMPING`), which read as visibly springy/wobbly.
PR #497 (closes #448) replaced it with **bounded "arrive" steering** tied to each unit's real
per-type stats (`accel`, `jog_speed`, from #445/#454):

```
body_accel   = max(unit.accel, BODY_ACCEL_FLOOR=30)                 # wu/s^2
arrive_speed = min(unit.jog_speed, sqrt(2*body_accel*dist), dist/delta)  # decelerates to 0 AT the slot
desired_vel  = feed_forward + dir_to_slot * arrive_speed
vel = vel.move_toward(desired_vel, body_accel*delta)                # bounded accel
# post-step inbound clamp: bound (vel - feed_forward) to dist/delta so a body carrying
# residual inbound speed lands EXACTLY on the slot instead of overshooting
pos += vel*delta                                                    # never teleports
```

The **anti-spring invariant** is *no overshoot / no oscillation*, pinned by
`test/unit/test_soldier_persistence.gd`: `test_shoved_body_arrives_without_overshoot` (distance
to slot decreases monotonically, body never crosses to the far side, checked only while
`dist > ARRIVE_EPS`) and `test_knockback_recovers_over_a_second_or_two`. Two subtleties that bit
the port: (1) the `sqrt(2·a·d)` profile steepens near the slot faster than bounded decel can
follow, so the **post-step inbound clamp** — not the desired-velocity cap — is the real overshoot
guard; (2) tests asserting the old spring's single-step velocity magnitudes had to be re-derived
to the multi-tick ramp (a body ramps to top speed over many ticks, not in one step — loop 120–360
ticks and assert the invariant throughout). Knockback impulses are untouched: a body holds the
push, then decelerates and returns under bounded force. This is the concrete mechanism behind the
"no snaps / bottom-up physics" philosophy at the top of this file; later PRs (#742/#743 coasting,
#749 body→position coupling) build on top of it rather than replacing it. (Physics constants and
exact function shapes will have moved further by the time you read this — verify against current
`scripts/SoldierBodies.gd` before relying on specifics; the anti-spring invariant itself is durable.)

## Any live-Battle test that runs a fight must seed `Replay.forced_seed`

A scenario/integration test that instantiates `scenes/Battle.tscn` and lets it run a fight draws
all combat randomness through `Replay.rng` (SoldierMelee land/wound rolls). If the test does not
seed the RNG, those rolls draw from whatever `Replay.rng` state the *previously-run tests* left —
so the outcome varies with suite ordering and the test flakes. This is a latent non-determinism
bug independent of any one PR; a physics change just **exposes** it by shifting an arc onto a
decision boundary.

**Concrete case (#497/#465):** `test/unit/test_rout_rally_demo_scenario.gd` began flaking ~50% of
full-suite runs (passed 100% in isolation) after the spring→arrival physics merged: the routing
unit **shattered** instead of rallying, tripping `assert_not_null`. A seeded trace
(`forced_seed=12345`) showed the arc routs ~tick 413 and rallies ~tick 774 — well within budget —
so the physics was fine; an unlucky casualty streak was grinding the router below
`SHATTER_STRENGTH_FRAC` or keeping an enemy inside `RALLY_CONTACT_RADIUS` at timer expiry.

**Fix:** seed deterministically in the spawn helper, exactly as the demo it guards does
(`Replay.forced_seed = 12345` **before** `add_child`; `Battle._ready()` folds it into `rng.seed`
via `Replay.start_recording()` and resets `forced_seed = -1`, one-shot per spawn). This is a
distinct failure mode from the coverage-timing budget flake above — that's about *when* an arc
completes, this is about *whether* it completes the same way each run. When a physics/balance
change surfaces a scenario-test failure, first ask "is this test deterministic?" — fix the
determinism, don't widen a budget to mask a boundary-brush. (`Lacaedemon/sparta` #497/#465.)

## Per-soldier sim cost scales SUPER-linearly — the reference battle already sits at the 60fps budget

Measured via #549 (PR #551): `tools/benchmark/run-benchmark.sh` against
`benchmarks/scenarios/large-battle.json`, scaled by `SPARTA_BENCHMARK_SCALE`
(`BenchmarkStats.scale_scenario`). Headless, physics-step time only (no render):

| soldiers | mean tick | p95 tick | implied fps |
| --- | --- | --- | --- |
| 1,720 (1×, reference) | 16.97 ms | 21.28 ms | 58.9 |
| 3,440 (2×) | 52.92 ms | 63.79 ms | 18.9 |
| 6,880 (4×) | 207.82 ms | 235.29 ms | 4.8 |

Cost is **super-linear**: 2× soldiers → ~3.1× tick cost, 4× → ~12× — consistent with PLAN.md's
O(n²) neighbor-scan note; the per-soldier layer (`_sim_soldier_pos`/`SoldierSpatialHash`) hasn't
fully escaped that shape. **The reference battle (1,720 soldiers) already sits at the 60fps budget
(16.67 ms/tick) on mean tick cost, and over budget on p95, before render cost.** So the current
architecture can't comfortably support a battle much larger than this at 60fps without a further
algorithmic win beyond the spatial hash. Treat this as a real, measured headroom constraint for
#550 (Cannae-scale) and any per-entity-granularity decision (per-soldier speed, weapon/shield
objects, individual orders): before adding another per-soldier array pass, re-run the benchmark and
check whether it pushes the curve further from linear — that's the signal an O(n) win is needed
before growing headcount. The exact multipliers drift as the sim evolves; the super-linear *shape*
is structural. (One-machine local sweep, not the PLAN.md reference-hardware numbers; re-measure
before citing exact figures.)

**Concrete regression + fix, PR #981 (#240 melee standoff):** `SoldierMeleeStandoff.accumulate`
originally called `SoldierEnemyProximity.rebuild(units, frame)` unconditionally every tick — a full
O(every living soldier in the battle) scan, run for EVERY engaged soldier's nearest-enemy lookup,
not just the rare SQUARE-mode case that whole-battle grid actually exists for. Reported by CI's
benchmark comment as +130.2% mean tick time (25.017ms -> 57.6ms on CI hardware); reproduced locally
at +62.8% (24.36ms -> 39.66ms, same reference scenario). Two independent fixes stacked to fully
resolve it, ending BELOW the pre-PR baseline (local: 24.36ms -> ~22.5-23.3ms across two runs):
1. **Scope the candidate/query population to the ENGAGED tier, not the whole battle.** A dedicated
   `SoldierEngagedEnemyProximity` grid (own file, own frame-keyed cache -- deliberately NOT shared
   with `SoldierEnemyProximity` or `SoldierSpatialHash`, since a shared frame-keyed cache can only
   ever serve ONE caller's population per tick) is rebuilt fresh each tick from exactly the units'
   own `engaged_soldier_indices()` gather, mirroring `SoldierEnemyContact.accumulate`'s existing
   gather-then-resolve pattern. This alone cut the local regression from +62.8% to roughly +31%.
2. **Prune the QUERY side using a cheap per-team (not per-unit, not per-soldier) reach comparison.**
   Once a same-or-longer-reach pairing is unconditionally zero (see the design-correction entry
   above), a soldier only needs a nearest-enemy lookup at all if its own unit's reach is LESS than
   the max reach among any OPPOSING team's currently-engaged units -- a single O(units) pre-pass
   (not O(soldiers)) that, in a battle where every current engagement happens to be same-type-vs-
   same-type (the common case for a symmetric two-army scenario), skips the ENTIRE per-soldier
   gather/rebuild/query for that tick. The candidate pool itself still has to include every engaged
   soldier regardless (a querying soldier's true nearest enemy could turn out to be equal-or-lower
   reach, resolving to zero per-pair, but it's still the geometrically correct answer to evaluate)
   -- only which soldiers get to ISSUE a query is pruned, not what's indexed.
**Lesson for any future per-soldier lookup in this codebase:** before reaching for a shared/whole-
battle spatial structure, check (a) whether the population can be scoped to just the engaged tier
(almost always yes, per the existing engaged/unengaged LOD split this whole layer is built on), and
(b) whether a cheap unit- or team-level pre-filter (not requiring a soldier-level pass at all) can
rule out entire populations from ever needing the expensive lookup, the way "my own reach already
dominates the max opposing reach" does here. Measure before adding machinery, per (a) alone often
being enough — verified here by benchmarking after each stacked fix rather than assuming.

## CI workflows render AUTHOR-controlled data — keep it as data, never let it reach a shell as code

`demo-video.yml` and its siblings run against author-controlled input: a PR author writes the demo
manifest (`demos/demo.<slug>.json`), input scripts (`demos/inputs/*.json`), captions, tick lists.
On a same-repo PR this runs on a **write-privileged** runner (pushes `demo-media`, comments on the
PR), so shell injection is a real supply-chain hole. Conventions (follow them in any workflow that
renders author data — established #506/PR #507, widened #549/PR #551):

1. **Author values reach steps via `env:`, never `${{ }}` interpolation** — `${{ }}` expands into
   the script text *before* the shell parses it, so `"; rm -rf … #` becomes code. Pass as
   `env: CAPTION: ${{ … }}` and use `"$CAPTION"`.
2. **jq programs are fixed string literals; data goes in as `--arg`/file operands** — never build a
   filter by interpolation (e.g. `jq -r '(.state // .frames // []) | map(tostring) | join(",")' "$SOURCE"`).
3. **Emit free text via `printf '%s'` with the value as an ARGUMENT**, not `echo`/`eval`; the
   `GITHUB_OUTPUT` heredoc uses a **random delimiter** (`caption_eof_$(openssl rand -hex 8)`) so
   author text can't smuggle extra outputs.
4. **A dynamic `export "${ENVVAR}=…"`** is safe only because `ENVVAR` is from a fixed set
   (`SPARTA_DEMO_REPLAY`/`SPARTA_DEMO_INPUT`), not author free-text.

**This isn't only about malicious input — it silently breaks your OWN generated values too.** In
`benchmark.yml` a step built a markdown code span (`` `tools/benchmark/baseline.json` ``) from
trusted script output, stored it via `GITHUB_OUTPUT`, and a later step spliced it with `${{ }}`
inside a quoted bash string — the backticks re-entered as live command substitution and the entire
span silently vanished from the posted comment (nothing errored). Route ANY `steps.*.outputs.*`
containing shell metacharacters through `env:`, not `${{ }}`-splicing. Also note `$()` strips
*trailing* newlines, so `BODY="$BODY"$(printf '\n\n')` is a no-op — fold separators into the same
`printf` format string. Verify comment-body assembly by simulating it in bash and `cat -A`-ing the
result; a green job doesn't prove the posted message is correct.

## Gating a CI check on "does this posted artifact still match HEAD" needs a live re-read at job completion

A workflow job that posts something derived from `github.event.pull_request.head.sha` (a demo
comment, a state transcript) uses a SHA fixed at *trigger* time — a push landing after trigger but
before the job finishes leaves a green job whose artifact cites a stale SHA.
`concurrency: cancel-in-progress` is the first defense but its propagation isn't instantaneous.

**Pattern (added to `demo-video.yml`, #542/PR #544):** as a final step in the *same* posting job,
re-read the PR's **live** head SHA from the API (`gh api repos/OWNER/REPO/pulls/$PR --jq .head.sha`)
— not the event payload — compare to the SHA the job posted against, and `exit 1` on mismatch. This
makes success self-verifying: green means the artifact was fresh as of the job's own completion.
Fold it into the posting job itself; a separate cross-check job just reintroduces the race one level
out. **Retry the lookup separately from the staleness verdict** — under `set -euo pipefail` a
transient `gh api` failure aborts with a raw error that reads like "stale," so wrap the lookup in a
small retry loop and emit two distinct messages ("could not read PR head — transient API failure,
not a staleness verdict" vs. "HEAD moved to X, evidence is for Y, failing as stale"). A bot reviewer
caught the missing-retry gap in round 1. (General CI pattern, but instantiated here in
`demo-video.yml`.)

## Battle.gd order dispatch applies every live order exactly once (immediate-apply + tagged tick-drain)

`Battle.gd`'s live order paths (`enqueue_*()`) apply every order TWICE by default — once
immediately at enqueue time (for zero-latency feedback + paused preview) and again when the
physics tick drains `_pending_orders`. Harmless for an absolute/idempotent order (formation,
frontage-resize), but corrupts any order whose effect is RELATIVE to state the first apply
already set (root cause of #517/#518: a rear-move about-face re-read the conversio the first
apply armed and fell into the wrong branch).

**Dedup pattern still in force** (`_apply_order_live`/`applied_live`, PR #519):
- `_apply_order_live(cmd)` applies the order via `_apply_order_cmd(cmd)` AND tags the in-memory
  dict: `cmd["applied_live"] = true`. Every live enqueue path routes through it instead of
  calling `_apply_order_cmd` directly.
- The tick drain still **records** every pending order for replay (unconditionally — the replay
  stream must be complete) but only **applies** it `if not o.get("applied_live", false)`. An
  order NOT applied live (e.g. a waypoint append — non-idempotent by nature, tick-authoritative)
  stays untagged and still drains-applies once, exactly as before.
- `Replay.record_order` copies EXPLICIT named fields (not the whole dict), so the `applied_live`
  tag never reaches the recorded stream — a `PLAYBACK` order read via `orders_for_tick` is
  therefore always untagged and applies once, so the PLAYBACK path is untouched by this pattern
  and replay determinism carries over automatically.

**Test pattern for a Dictionary-tag dedup:** GDScript Dictionaries are reference types, so tagging
the SAME object that sits in `_pending_orders` is visible to a drain-mimicking test helper without
re-fetching — but cross-reference the helper's gate condition to the production drain in a
comment, or the two silently diverge if the key/logic changes in only one place. Any NEW order
type added to `Battle.gd` (or an existing one you refactor) that goes through a live-enqueue path
must route through `_apply_order_live`, not call `_apply_order_cmd` directly, or it reintroduces
the double-apply bug this pattern exists to prevent. (`Lacaedemon/sparta` #517/#518, PR #519.)

## Form-up orders never use the smooth maneuvers — a big reposition needs its own facing/reform handling

`Battle._apply_order_cmd`'s move dispatch explicitly excludes side-step, back-step, rear-move
(about-face), and lateral-pivot (file-march) from ANY command that carries `cmd.has("face")` --
and a form-up (`Battle.enqueue_form_up`) always sets `face`, since it commands its own facing
from the drag line rather than reusing the unit's current one. This is deliberate ("a form-up
commands its own facing, so it never side-steps"), but it means a form-up ALWAYS falls through
to the generic move path, no matter how large or oblique the reposition -- unlike a plain move,
which gets a purpose-built maneuver (file-march, about-face, etc.) for exactly this situation.
For a short single-line drag this is invisible; for a large, oblique reposition (the checkerboard
form-up's rear row, #805/PR #818) it surfaced three real bugs, only visible by actually watching
rendered frames -- numeric position dumps (`dump-state.sh`) looked fine at every tick checked and
completely missed all three:

1. **Reform and march overlapped.** `set_frontage()` applies the new file count IMMEDIATELY at
   cmd-apply time, then the unit holds for a FIXED `REFORM_DURATION` (0.8s) before marching --
   regardless of whether the reshape had actually settled. A big frontage change (front vs. rear
   row can differ a lot) needs far longer than 0.8s for 80+ soldiers to walk into new ranks, so
   the march started while the reform was still visibly in progress.
   **Fix:** gate the hold on `Unit._reform_bodies_settled()` (the same mechanism a
   post-about-face reform already used, `_reform_until_settled`) instead of the flat timer, with
   a reshape-scaled safety cap (`Unit._reshape_timeout`, summing the OLD and NEW shape's own
   diagonals -- a full reshape's worst-case travel isn't bounded by either shape alone) as a
   backstop rather than the flat duration. The existing `REFORM_SETTLE_EPS` (1.0 world units) was
   too tight to ever actually trigger for a full reshape -- empirically, the last body or two
   hovers ~1.2 units outside it indefinitely (a wholesale reshape's own settling dynamics, via
   `SoldierBodies.couple()`, don't converge as cleanly as a same-shape angle-fold does) -- added a
   looser `REFORM_SETTLE_EPS_RESHAPE` (4.0) for this case specifically, still far tighter than a
   rank gap (`FORMATION_SPACING` is 9).
2. **The block centre-pivoted toward its own TRAVEL DIRECTION while marching, then snapped to
   its commanded facing on arrival.** `_move_to`'s ordinary "orderly move" behavior re-aims a
   marching block toward wherever it's currently walking -- correct for a plain move (final
   facing should match travel direction), wrong for a form-up (final facing is the drag line,
   not the march heading). For a diagonal reposition this rotated the whole slot grid to point
   along the travel path for the entire march, then abruptly re-oriented to the commanded facing
   the instant it arrived -- read as the formation collapsing into a diagonal column mid-march,
   then expanding back into a line on arrival.
   **Fix:** hold the form-up's `deploy_facing` fixed for the WHOLE march via `ordered_facing` (the
   same "maneuvering" mechanism a side-step already uses to hold a fixed facing) instead of
   letting the march's own centre-pivot take over.
3. **A swirl during the reform hold itself, exposed BY fix 1** (the flat 0.8s hold used to end
   before this could develop -- extending it to actually wait for settlement made it fully
   visible). The hold pivots `facing` toward `deploy_facing` -- but doing that GRADUALLY
   (`_rotate_facing_toward`) while the frontage is ALREADY fixed at its new shape from tick 1
   means the soldier slot grid is simultaneously ROTATING (facing still catching up) and FIXED
   at a new size (reshaping) every tick -- bodies chasing a target that's both moving and
   already a different shape swirl instead of converging cleanly.
   **Fix:** snap `facing` to `deploy_facing` immediately via `_face_dir` (its `_formation_angle`
   absorption keeps the snap itself invisible -- no body jump, only bookkeeping changes) instead
   of a gradual pivot, so the grid is orientation-stable from the very first hold tick and only
   the reshape itself needs to converge.

**How to apply:** when a movement/formation fix "looks right" from `dump-state.sh` position
values alone, that only proves the REGIMENT-level anchor (`Unit.position`) is correct -- it says
nothing about whether the individual SOLDIER BODIES are cleanly rank-and-file or a smear/swirl
during the transition. For any fix touching facing, frontage, or the reform hold, also capture
actual frames (`SPARTA_DEMO_FRAMES`) at several points across the WHOLE transition (not just
the final settled tick) and look at the rendered soldier blocks directly -- this is the opposite
lesson from the quarter-turn case below ("verify tick by tick, not by eyeballing GIFs"), because
that case was about proving the SIM was already correct despite an ambiguous render; this case is
about a RENDER-level defect (a concurrent-transform swirl) that a correct-looking `position` value
doesn't reveal at all. Both are real failure modes; use whichever check actually exercises the
thing you changed. (`Lacaedemon/sparta` #805, PR #818, 2026-07-13.)

## Adding a form-up distribution mode: two parallel lists serve different purposes

`SelectionManager.FormUpDist` is extended by adding a new enum value plus a `FORM_UP_DIST_NAMES`
entry -- but there are TWO separate list constants that look like the same thing and aren't:

- `SelectionManager.FORM_UP_DIST_CYCLE` -- the CANONICAL list of every mode that exists. Used as
  the fallback when a player's cycle is empty, as `_cycle_from_settings()`'s iteration order, and
  critically as what `HUD._sync_setting_toggles`'s "keep the current default reachable"
  self-correction filters against. A mode NOT in this list can never be reachable via that
  self-correction, no matter what a player's own `Settings.form_up_dist_cycle` contains.
- `Settings.form_up_dist_cycle` (and its class-level default array) -- the PERSISTED, player-
  configurable subset actually enabled by default. A new mode can (and, to avoid silently
  changing existing players' Y-key cycle, usually should) be left OUT of this one's own literal
  default array while still being IN the canonical `FORM_UP_DIST_CYCLE` above.

Getting this backwards (leaving the new mode out of BOTH) breaks the "picking the new mode as
your default keeps it in the cycle" invariant silently -- caught only by a test that sets the
new mode as the default and asserts it lands back in `Settings.form_up_dist_cycle` afterward, not
by anything that just checks the menu renders or the mode itself works. (`Lacaedemon/sparta` PR
#818: `SelectionManager.FORM_UP_DIST_CYCLE` initially omitted `CHECKERBOARD`, silently breaking
that self-correction for it specifically; `Settings.form_up_dist_cycle`'s own default array
correctly omitted it the whole time.)

## Demo authoring: a form-up's drag direction must match the intended march direction

`SelectionManager._form_up_facing(a, b)` derives the commanded facing purely from the drag's
geometry (perpendicular to `a`->`b`, with `a` as the left flank) -- it has no idea which way the
units are actually about to march. Since a form-up now HOLDS that commanded facing for the whole
march (see the entry above), a demo/scenario whose drag direction produces a facing pointing
AWAY from the actual destination (e.g. spawning above the drag line but dragging in the direction
that computes a facing pointing further away, not toward the line) makes every unit march
BACKWARD relative to its own facing for the entire clip -- previously invisible, because the old
(buggy) behavior pivoted toward the travel direction while marching and only snapped to the
commanded facing on arrival, silently hiding a wrong drag direction. Check this BEFORE finalizing
a new form-up demo: dump `facing` at an early marching tick and confirm it points toward
increasing progress along the actual march vector, not away from it. (`Lacaedemon/sparta` PR
#818: `demos/inputs/checkerboard-form-up.json`'s original left-to-right drag computed a
north-pointing facing while the units needed to march south; fixed by reversing the drag.)

## Front-rank position anchoring destabilizes in-place reshapes -- fixed on the second attempt

**Update:** fixed in PR #861 (closes #821, 2026-07-15), using ONE of the two "likely real
fixes" below -- freezing the anchor during a transition -- not both. `_position_anchor_unstable()`
(`is_maneuver_turning() or _reform_holding()`) falls back to the wider `engaged_soldier_indices()`
selection during exactly the transitions that broke the first attempt; the shipped
`near_front_soldier_indices()` still reads LIVE body positions (`UnitFormation.live_front_indices`),
same as the reverted attempt -- the canonical-target-slots-midpoint alternative was never
implemented. A second fix ingredient the first attempt didn't try: narrowing to a single live
rank was too small a sample to damp `SoldierEnemyContact`'s per-tick contact-torque noise and
measurably re-aggravated the `test_residual_melee_swirl_battle.gd` regression (~38° pivot vs.
its <28° gate); **`ANCHOR_RANKS = 2`** keeps that test's margin while still narrowing the
anchor. All 6 originally-broken tests pass unmodified (they're all unengaged scenarios the
change never touches), plus a new test (`test_couple_position_anchor_reaches_less_deep_than_the_old_selection_after_front_rank_casualties`)
proving that once the true front rank is wiped out, the narrower anchor reaches less deep into
the survivors than the old, wider selection would -- it doesn't get dragged as far back by a
casualty-thinned block. Kept the section below as-is -- the failure mode and root-cause
diagnosis it documents are exactly what the successful fix had to satisfy.

### First attempt -- tried and reverted

Discussed as a possible improvement to `Unit.position`'s semantics (currently: `SoldierBodies.
couple()` anchors on a body centroid -- the engaged front-N-ranks' centroid when engaged, the
full-block centroid otherwise) -- anchor on the LIVE front rank's own midpoint instead (one rank,
via `UnitFormation.live_front_indices`), unconditionally. Implemented and reverted: it broke 6
tests, not superficially -- `test_explicatio_widens_the_line_without_teleporting_bodies` /
`test_duplicatio_deepens_the_line` both assert an in-place reshape does NOT move the regiment
centre, and it now moved by 13-50 world units; `test_quarter_turn_in_live_battle_has_no_surge`
(same invariant, an in-place turn) surged 2.94 world units against a <1.0 requirement -- smaller
in absolute terms, but still a clear violation of the same "stays put" guarantee; one
AI-determinism test (`test_subcommander_directives_replay_identically_on_the_same_seed`) also
changed which enemy a unit's distance-based targeting picked.

**Root cause:** the full centroid averages over every body, so it stays smooth even mid-reshape
(individual bodies moving to new slots partially cancel out in the average). A LIVE "nearest-front
N bodies" selection has no such smoothing -- during a transition (a quarter-turn, a file-count
change) there is no stable "front" yet, so the anchor itself jumps around before bodies settle,
exactly where the centroid held still. Anchoring on the CANONICAL target slots' midpoint instead
of live bodies (or freezing the anchor while a reshape/turn is actively running) are the likely
real fixes, not yet tried. **How to apply:** before anchoring any per-tick coupling calculation on
a LIVE, filtered subset of bodies instead of a full-block aggregate, check its behavior specifically
during an in-place reshape/turn (not just a march) -- a live subset selection can be unstable
exactly when a full aggregate is most needed to stay smooth. (`Lacaedemon/sparta` PR #818,
reverted; tracked in issue #821.)

## Pinpointing exact lines for a `codecov/patch` gap: intersect lcov's zero-hit `DA:` lines with the diff

`codecov/patch`'s PR comment names the file and a percentage but not which specific lines are
uncovered. Rather than guessing from the function list, regenerate coverage locally
(`tools/check.sh coverage`, ~15-20 min for the full suite) and intersect two things directly:

```bash
# 1. Every zero-hit line in the target file's lcov block
awk '/^SF:.*SelectionManager\.gd/{f=1} f{print} f&&/end_of_record/{exit}' coverage/lcov.info \
  | grep "^DA:" | awk -F'[:,]' '{print $2, $3}' | awk '$2==0{print $1}'

# 2. The diff's actual added line numbers (against the merge-base, not main's current tip)
git diff --no-color -U0 "$(git merge-base HEAD origin/main)" HEAD -- scripts/SelectionManager.gd

# 3. Cross-reference: for each candidate added line, grep its exact DA: entry
grep "^DA:458," coverage/lcov.info   # DA:458,0 = uncovered; DA:458,2 = covered (2 hits)
```

The intersection is the exact uncovered line set Codecov is counting -- confirm the count matches
(Codecov said "5 lines missing"; this technique found exactly 5). Add targeted tests hitting each
line, re-run `tools/check.sh coverage`, and re-check the same `DA:` lines show a nonzero hit count
before pushing -- don't just trust that "tests were added" closed the gap; verify the specific
lines Codecov flagged. (`Lacaedemon/sparta` PR #853: 5 lines in `SelectionManager.gd`'s own-team
gating -- the box-select loop, `_select_same_type`, the conversio/quarter-turn dispatchers, and
the `_enemy_team()` empty-selection fallback -- were each genuinely untested by any existing test,
not just newly added by the diff; found and closed this way in one pass.)

## A `blob/main` doc link to a file this same PR adds 404s the link checker until merge

Docs that reference source files by absolute GitHub URL --
``[`scripts/Foo.gd`](https://github.com/Lacaedemon/sparta/blob/main/scripts/Foo.gd)``, the pattern
`website/replays.qmd`'s "Where it lives" table uses for every row (`REPLAY.md`'s equivalent table
lists every file as plain unlinked code, so this doesn't apply there) -- resolve against `main`,
not the PR branch. If the PR both adds a new script *and* documents it in `replays.qmd`'s table in
the same commit, the link 404s (`check / link-checker` fails) because the file genuinely doesn't
exist on `main` yet -- it only will once the PR merges. This isn't a flaky/external-link false
positive like the entries already excluded in `lychee.toml`; it's a real, if self-resolving,
ordering problem specific to referencing your own PR's new files.

Fix: don't hyperlink that one row until the file is actually on `main` -- keep it as plain
inline code (`` `scripts/Foo.gd` ``) in the PR that adds the file, and turn it into a real
`blob/main` link in a small follow-up once merged, or just leave it unlinked (every other row's
link still works fine). Don't add a `lychee.toml` exclusion for this -- the link is only broken
during the PR's lifetime, and a real exclusion would hide a genuinely broken `blob/main` link in a
row that *should* always resolve after merge. (`Lacaedemon/sparta` PR #858: `website/replays.qmd`'s
new `scripts/BuildInfo.gd` row 404'd the link checker on first push; caught in CI, not review.)

## A continuous per-tick impulse formula can compound ACROSS TICKS, not just across simultaneous pairs

The existing "multi-pair force accumulation needs a write-back clamp" lesson above covers a
force compounding across several simultaneous CONTACT PAIRS in one tick. PR #860 (closes #817)
found the same failure shape on a different axis: compounding across successive TICKS of the
same pair.

`SoldierCollision.enemy_contact_impulse()`'s overlap-correction term
(`overlap_frac * ENEMY_CONTACT_OVERLAP_RATE`) re-injected a FULL fresh separating impulse every
tick a pair stayed deeply overlapping, with no memory of how much separating velocity earlier
ticks had already imparted. Since position only integrates via `velocity * delta`,
`overlap_frac` lags several ticks behind a velocity change -- so a rank arriving at melee range
still at full march speed kept receiving fresh impulses well past "arrested," compounding into a
hard recoil pinned near `KNOCKBACK_SPEED_MAX` (observed peak -58.4 u/s, above Infantry's 50 u/s
jog-speed arrival cap) instead of a single bounded correction. Once knocked that far, the rank
fell out of `engaged_soldier_indices()` and had nothing but ordinary jog-paced arrival steering
to bring it back -- stranding it 50-75 world units behind the line for ~5 real seconds.

Fix: target a STEADY separating speed instead of re-injecting the full target every tick -- only
make up the shortfall between the target and whatever separating speed the pair already
carries (`overlap_needed = max(0, overlap_target - separating_speed)`).

**How to apply:** any per-tick formula that reads a lagging/derived quantity (an overlap
fraction, a penetration depth, an error term computed from position rather than velocity) to
decide how much correction to apply THIS tick needs to account for correction already applied
on PRIOR ticks, or it re-applies past what's needed every tick the lagging quantity stays
stale. This is the same accumulation-without-a-cap shape as the multi-pair case, just walked
across time instead of across simultaneous pairs -- when reviewing or writing a new continuous
(not single-strike) impulse/force calculation, check both axes: does it compound across
SIMULTANEOUS sources in one tick, and does it compound across SUCCESSIVE ticks of the same
source. (`Lacaedemon/sparta` PR #860, 2026-07-15.)

## A new maneuver can reuse an existing composite instead of building new per-soldier choreography -- but check for facing side-effects from the reused legs

PR #866 (closes #375) needed the countermarch (exelismos): reverse which end of a unit faces
the enemy by marching files through each other, with three historical variants (Macedonian
advances onto new ground, Laconian withdraws, Choral/Persian stays put). Rather than building a
new per-soldier file-interleaving physics system, it composed three ALREADY-TESTED primitives
this repo already had: `begin_about_face()` (reverse facing in place), `reform_ranks()` (already
documented, in its own doc comment, as "a real countermarch" -- it re-slots the grid via a
depth-only mirror so a full-strength rank leads instead of whichever partial rank the about-face
happened to flip forward), then an ordinary `MOVE` order whose destination encodes the
variant (advance/withdraw/stay). Soldiers still walk to their new slots under the existing
bounded-arrival body steering (`SoldierBodies`) -- nothing new was added to the movement system
itself, only which slots get assigned and how far the march leg carries the whole regiment.

**The gotcha this surfaced:** the ordinary march's centre-pivot (or the reform hold's own
"face the parked destination" fallback) re-aims a marching block toward its TRAVEL direction --
correct for a rear-move (which only ever marches toward its new facing), but for LACONIAN the
march destination is BEHIND the new facing, so the reused march leg was silently rotating the
just-completed about-face back open mid-maneuver. Fixed by holding `ordered_facing` at the
post-about-face heading through the reform + march (the same mechanism a side-step already uses
to hold a fixed facing), cleared automatically on arrival -- the maneuver-specific piece wasn't
new geometry, it was suppressing an existing leg's own facing side-effect that happened to be
wrong for this one variant.

**How to apply:** when composing a new maneuver/order out of existing tested primitives (the
right default per this repo's own preference for reuse over new machinery), don't just check
that each leg's OWN documented behavior is individually correct -- check whether any leg carries
an implicit side effect (a centre-pivot, a fallback facing, a reform-hold assumption) that was
only ever exercised by the callers it was originally built for, and could point the wrong way
for a new caller whose geometry differs (here: marching AWAY from the new facing, not toward
it). (`Lacaedemon/sparta` PR #866, 2026-07-15.)

## Frame-capture catches the render-only const miss no state test sees

When migrating a const to instance data (the caller-configurable-parameters
convention in CLAUDE.md), the DRAW layer is where a missed substitution hides:
state dumps, GUT tests, and the transcript diff all read sim state and pass
while `_draw` still renders from the old const. The per-battle-maps migration
hit this twice -- terrain textures drawn at the default map's rects (caught by
the standing mid-clip frame capture), and the no-texture ground fallback
drawing the default field rect (caught by review in the one branch a frame
capture never renders, since it only fires when textures failed to build).
After any const-to-instance migration, grep the file for remaining reads of
the old const AND frame-capture the feature actually exercising a non-default
value; the sim-equality proof on defaults says nothing about the render layer.

## Sim-equality proof for a dump-SCHEMA change: strip the additive fields, then demand byte-equality

The plain state-dump byte-diff (branch vs main, same scenario/ticks) is the standard
zero-sim-change proof -- but it breaks down when the PR itself adds fields to the dump
JSON (a new mirror field, a new diagnostic), because the dumps then differ by
construction. The fix: strip exactly the added fields from the branch dumps with jq,
normalize both sides (`jq -S`), and demand byte-equality of everything that remains --

```bash
jq -S 'walk(if type == "object" then del(.position_m, .current_speed_mps, .soldier_summary_m) else . end)' branch_dump.json
```

-- which proves the additions are purely additive (the sim and every pre-existing
field unchanged) rather than falling back to a weaker eyeball comparison. Delete ONLY
the fields the diff itself added (list them explicitly from the PR diff; don't pattern-
match), or the proof silently weakens. Used for the metric dump mirrors (PR #896,
phase E of the metric-definition migration); the same shape applies to any future
dump/transcript schema extension.

## Probe EVERY new external citation URL with lychee's exact UA before pushing

`check / link-checker` runs lychee with the UA pinned in `lychee.toml`; several
otherwise-fine sites bot-block that UA (403/415/502), and each already-known offender
has a documented exclusion there. Before pushing a diff that adds citation URLs, probe
every new URL locally with lychee's exact settings --

```bash
curl -s -o /dev/null -w "%{http_code}" -L --max-time 20 \
  -A "Mozilla/5.0 (compatible; Lychee/0.15; +https://github.com/lycheeverse/lychee)" "$url"
```

-- and check the code against `lychee.toml`'s `accept` list (403 is NOT accepted). A
bot-blocked-but-fine-in-a-browser site gets a new `lychee.toml` exclusion following the
existing commented pattern; a genuinely dead link gets fixed or dropped. Probe ALL new
URLs, GitHub ones included: a repo URL sourced from a search result, a directory
listing, or another site's link can 404 because the repo was deleted -- the Godot asset
library's "RTS Camera 3D" page still links `alfredbaudisch/GodotRTSCamera3D`, whose
GitHub repo is gone. Both failure modes (moddb.com bot-403, the deleted camera repo)
cost a red link-checker run on PR #929 after a probe pass that skipped GitHub URLs.

## Direction reversals are where the marker/body split bites: scalar speed re-aims instantly, bodies carry real momentum

`_current_speed` is a scalar with no direction: any flow that flips a unit's travel
direction (`_move_to`'s `dir`, a peel goal swapping sides, a reversal re-order) re-aims
the FULL speed instantly while the soldier bodies still carry their real momentum the old
way, and `SoldierBodies.couple()` then drags the regiment after the bodies for seconds.
Two shipped mitigations name the pattern: the cycle-charge peel BRAKES onto its standoff
(`brake_arrival`, PR #968), and a reversing re-order bleeds speed during its
response/reform hold (`REORDER_MOMENTUM_DOT_MIN`, PR #970) with the hold's centre-pivot
paced to the corner man (it was raw TURN_RATE -- the same unpaced-grid-rotation blob class
the marching pivot already fixed). When adding any new flow that turns a moving unit
sharply, give it a brake leg (or verify existing braking covers it) rather than letting
the scalar speed carry through the flip -- and expect a RESIDUAL mid-turn pinch
regardless: the wide cavalry grid's flank bodies track their sweeping slots with zero
gait margin, so nnd transiently bottoms at ~1.3-3.2 wu depending on the exact order
phase. That depth is PHASE-SENSITIVE -- do not write a test floor between those numbers
(pre/post-fix ranges overlap); anchor regression tests on the brake, the pivot pacing,
and the overshoot bound instead, which separate cleanly. The residual is the formed-turn
/ chase deformation family tracked as an open sim investigation.

## A simulated multi-leg walk test catches bugs a single-query test can't

When a pathfinding/steering function is meant to be queried repeatedly as a mover
closes in (`PathField.next_step`, or any "what's my next waypoint" API), write a GUT
test that actually **walks** it: loop `next_step` -> `move_toward` -> re-query for
hundreds of legs, asserting invariants (arrival, margin never eroding, a specific lane)
at every step -- not just a handful of single-shot queries at fixed points. A single
query only proves the waypoint is correct FOR THAT ONE STATE; a walk proves the
sequence of waypoints is stable as state evolves, which is where feedback-loop bugs
live.

**Concrete case (#944, funnel string-pulling in `PathField.gd`):** seven single-query
tests (exact corner selection, per-clearance lane scaling, corridor-side following,
determinism) all passed on the first implementation. A simulated 300-leg walk test
(`test_funnel_walk_hugs_the_boundary_without_ratcheting_inward`) caught two real bugs
the single-query tests structurally couldn't see:

- **A corner-arrive stall.** `CORNER_ARRIVE_EPS` (the radius at which a waypoint counts
  as "reached," so the funnel doesn't steer a unit at its own feet) was tuned to 4.0 wu
  against a single-body query. A FORMED REGIMENT's own anchor position wobbles by tens
  of wu while cornering (`SoldierBodies.couple()` follows the soldier bodies, not a
  fixed point), and at 4.0 wu that wobble flipped the near corner in and out of
  "reached" every few ticks -- the walk test's trace showed the walker frozen in place,
  its steering target flip-flopping every tick between the near corner and the FAR one
  on the opposite side of the obstacle (excluding the near one as "reached" left only
  the far corner as a candidate), with zero net progress for hundreds of ticks. Fixed
  by widening the epsilon to half a routing cell, large enough to dominate the
  anchor's own positional noise.
- **A graze-case side flip.** The funnel initially picked which side of an obstacle to
  round by comparing the A* route's deviation from the straight from->to chord. That
  reads correctly for a route that visibly bows around an obstacle, but misreads a
  GRAZE -- both endpoints already past the obstacle, route and chord essentially
  coincident -- as "no preferred side," which let the funnel snap to the FAR corner and
  walk the unit backward into the obstacle it was already past. Fixed by reading the
  side off the route's closest approach to the obstacle RECT's own centre instead of
  its deviation from the chord -- a measurement that stays well-defined exactly where
  the chord-based one degenerates.

**How to apply:** for any steering/pathing function, always pair single-query
correctness tests with at least one multi-leg walk test that re-queries the function
every step against realistic MOVING state (not fixed geometry) -- especially before
trusting a "looks right in isolation" implementation for a formed multi-body mover,
where feedback between the steering output and the mover's own position noise is
exactly the failure mode a static query can't exercise.

## Routing a unit tighter around terrain can crowd a neighboring friendly unit's lane

A locally-correct routing/steering improvement (a unit hugging an obstacle's boundary
more tightly, or taking a faster/more direct detour) can have a real, physically-
mediated side effect on a DIFFERENT unit that never itself interacts with the
obstacle: if the improved unit's new lane drifts closer to a neighboring friendly
unit's own march, real soldier-body contact physics (crowd-pressure, `_separate()`/
press-into) transfers transient formation deformation from the first unit onto the
second -- not a bug in the routing math, an emergent interaction between two
independently-correct behaviors.

**Concrete case (#944's funnel fix, found via the website-demo-diff CI comment on PR
#977):** the default 5v5 battle's two enemy Cavalry regiments (uid8, uid9) march
together; uid9 spawns essentially inside the default hill's x-range, so its march
routes around the hill from tick 1. The funnel fix genuinely improves uid9's own
routing (peak formation bbox measurably shrinks). But uid9's tighter lane drifts
closer to uid8's own march, and cross-unit crowd-pressure transferred a comparable
amount of the SAME transient deformation (the chase/reversal-deformation family
documented above) onto uid8 instead of eliminating it -- flagged by the demo-diff tool
as 10 "candidate regression" clips, all showing the identical uid8<->uid9 pattern.
Confirmed by a direct merge-base-vs-branch full-state dump comparison (not just
eyeballing the CI table): uid9's bbox improved (417x384 -> 389x297 at a matched tick)
while uid8's grew in compensation (240x371 -> 316x404, previously stable) -- the total
system deformation didn't get categorically worse, it moved. Filed as its own tracked
issue (#979) rather than either blocking the routing fix on it or silently absorbing
it into that PR.

**How to apply:** when a website-demo-diff (or any transcript-diff) report flags a
WIDE, systematic pattern of "regressions" that all share the same two units and the
same defect kind, don't stop at "the analyzer flagged it, revert/block" OR "it's
probably fine, merge" -- get the actual merge-base-vs-branch numbers for the
mechanism (bbox/position deltas of the specific units involved) and check whether the
SAME transient-deformation family just moved to a different unit versus a genuinely
new failure mode appeared. A same-family transfer with comparable or improved total
magnitude is a real, worth-tracking finding, not automatically a merge blocker for the
change that surfaced it.

## `tools/demo/analyze_transcript.gd` runs as a bare `SceneTree` with no autoloads -- give it dependency-free helper classes

`analyze_transcript.gd` is invoked as `godot --headless -s tools/demo/analyze_transcript.gd`
-- a bare `extends SceneTree` script with no project autoloads and no scene tree beyond
itself. A `class_name` helper it references transitively through ANY reference chain
into a real gameplay script (even one line deep -- e.g. a class that calls into `Unit`,
which itself references the `Settings` autoload) fails to compile under this context
with `Identifier not found: Settings` and cascading `Failed to compile depended scripts`
errors on every script in the reference chain, even though the same class compiles and
runs fine everywhere else (a GUT test, the live game).

**How to apply:** any new helper class meant to be consumed BOTH from live gameplay
code (a recorder/sink running inside a real Battle) AND from `analyze_transcript.gd`
directly must have its `analyze_transcript`-facing half kept dependency-free of the
game's script tree -- split it into two classes if needed: one that reads live Unit/
Battle state (fine to depend on gameplay scripts, only ever called from inside a real
scene), and one holding the pure data format / comparison logic `analyze_transcript`
actually needs (must not reference any gameplay script, even transitively). `DemoDefects.gd`
already does this (reads snapshots as plain Dictionaries, never a live `Unit`);
`DemoStateHash.gd` (per-tick hashing, reads live `Unit`/`SceneTree` state) and
`DemoHashStream.gd` (the `hash_stream.jsonl` format + offline stream comparison, referenced
by both the live recorder and `analyze_transcript.gd`) are the same split, added for
#954's sim-state-hash slice after the first cut (one combined class) broke
`analyze_transcript.gd --compare-hashes` with exactly this compile-error cascade.

## Arming a stance is sticky global session state, not scoped to whichever unit was selected when you armed it -- it applies to EVERY subsequent order, not just one

A stance hotkey without Ctrl (`SelectionManager._set_armed_mode`) sets one shared
`_armed_mode` field -- not attached to any unit, and never cleared or consumed after an
order uses it (`_issue_order` reads `_armed_mode` directly and leaves it unchanged).
Once armed, EVERY order issued afterward -- regardless of which unit is selected, and
regardless of how many orders come after the arming click -- carries that stance until
something re-arms `_armed_mode` to a different value (including back to `NORMAL`).

**How to apply:** in a scripted-input demo staging two units with DIFFERENT
stances/orders for contrast (e.g. one armed with a stance, one on a plain order),
issue every plain-order unit's order FIRST, and arm a non-default stance LAST, on
whichever unit needs it -- never arm a stance and then issue a later, unrelated unit's
order without re-arming (or explicitly re-arming NORMAL) first. Verify with a state
dump (`order_mode` per uid) rather than assuming the script's click order maps
directly onto "this stance applies to only this unit." (`Lacaedemon/sparta` PR #974,
`stern-chase-canter.json`: the first staging attempt armed Chase on the west cavalry
BEFORE issuing the east cavalry's plain attack order, and the dump showed both units
reading `order_mode: Chase` instead of the intended contrast -- fixed by reordering so
the plain attack order is issued first and Chase is armed last.)

## Line endings are MIXED across this repo's own files -- a multi-line Edit `old_string` copied from Read's numbered output can silently fail to match

Some `scripts/*.gd` files are CRLF (`Battle.gd`, confirmed via `od -c`), others are LF
(`test/unit/test_soldier_enemy_proximity.gd`) -- there's no single repo-wide convention,
likely from different authoring tools over time. `git config core.autocrlf` is `true`,
so `git diff`/`git status` always normalize and never surface this as noise -- it's
invisible from git's own tooling.

The Edit tool's `old_string` match is exact-byte, and a multi-line `old_string` typed
with plain `\n` between lines never matches a CRLF file's actual `\r\n` line endings --
it fails with a generic "String to replace not found in file" error that gives no hint
the cause is line endings specifically (indistinguishable from a genuine typo or a
stale read). This bit repeatedly on `Battle.gd`: even a SINGLE-line `old_string` failed
at first, traced to accidentally including an extra leading tab (visually
indistinguishable when reading Read's `NNNN\t<content>` numbered-line output, since
the line-number/content separator tab and the file's own leading indentation tab look
identical at a glance).

**How to apply:** if an Edit call fails with "String to replace not found" on a target
you can SEE in a fresh Read of the exact same file, don't assume it's a stale read or a
transcription typo first -- check `git show HEAD:<path> | grep -c $'\r'` (or `od -c` on
the specific line) for CRLF before spending time re-comparing characters by eye. Once
confirmed CRLF, split the edit into single-line `old_string`/`new_string` pairs (a
single line never contains an embedded `\n`, so CRLF-vs-LF never matters within it) --
the `new_string` can still be multi-line; only `old_string` needs to stay within one
line when the file is CRLF. `sed -n 'N,Mp' <file> | cat -A | sed 's/\^I/[TAB]/g'` is the
fastest way to confirm exact tab counts before retyping an `old_string` that failed for
this reason. A pure trailing-content deletion (no replacement text) is safe via
`head -n N file > tmp && cp tmp file` instead, since it copies raw bytes and never
needs to match multi-line content at all. (`Lacaedemon/sparta` PR #981, 2026-07-18:
lost real time on this before isolating the cause via `od -c` and a string of
single-line control edits.)

## `tools/check.sh`: a wrapping check needs a dedicated result key to short-circuit its wrapped check safely

A check that internally reuses another check's expensive work (`check_patch_coverage`
calling `check_coverage` so both don't independently re-run the full GUT suite) creates
a trap for any THIRD check that wants to reuse the same work: don't key the reuse
decision off the wrapping check's own overall pass/fail, because "the wrapping check's
own gate failed" and "the underlying operation it wrapped failed" are different
questions, and only the second one is safe to propagate.

**Concrete case (PR #990, closes the `test`/`coverage`/`patch_coverage` double-run):**
`check_test`'s short-circuit originally read `get_result coverage`/`get_result
patch_coverage` directly to decide whether to skip a redundant `test` run. But
`patch_coverage`'s PRIMARY, intended failure mode is its own coverage PERCENTAGE
landing below target -- not a suite problem at all, and the single most common way for
`patch_coverage` to legitimately fail. Reading its overall `fail` result as "the suite
must also be broken" wrongly reported `test` as failed on a perfectly clean run --
exactly the common case, since CLAUDE.md's own recommended invocation runs `test` and
`patch_coverage` together. `check_coverage`'s own overall result has the same problem
from a different angle: a clean suite run followed by a failed `coverage/lcov.info`
write (the post-run hook's `push_error()` doesn't fail the Godot process) still makes
`check_coverage` return non-zero, again for a reason that says nothing about `test`.

**Fix:** `check_coverage` now records the GUT suite's own health under a dedicated
internal key (`_suite_health`, never surfaced in the printed summary since that loop
only iterates the top-level requested `checks` array) at the exact point the suite run
itself is known clean -- separate from, and set BEFORE, the function's own final
return value (which still depends on the lcov write succeeding). `check_test` reads
`_suite_health` instead of `coverage`'s/`patch_coverage`'s own result. This works
correctly regardless of which top-level check reached `check_coverage` first
(`run_check` calling it directly for a requested `coverage`, or `check_patch_coverage`
calling it internally as its own reuse path) since `set_result` always updates the
same key.

**How to apply:** any time you're tempted to short-circuit check B by reading check A's
overall pass/fail/skip result, first ask whether A's own gate (a threshold, a
post-processing step, anything beyond "did the expensive shared operation succeed")
can fail independently of that operation. If so, the shared operation needs its own
result key that only the operation's own outcome writes to -- not A's summary result,
which conflates the operation with A's own additional judgment on top of it.

**Verifying a check.sh logic fix without a full ~18-min Godot re-run:** when a fix is
purely bash control-flow (case statements, `set_result`/`get_result` calls) with zero
change to the actual Godot/GUT invocation, extract just `set_result`/`get_result` plus
the changed case statement into a small standalone throwaway script (no `main "$@"` at
the bottom to guard against -- check.sh has none, so sourcing it runs the whole thing),
seed `RESULT_NAMES`/`RESULT_STATUSES` by hand for each relevant scenario, and assert
the short-circuit's return code. This proves the LOGIC correctly without paying for a
real suite run every iteration; reserve an actual `tools/check.sh test coverage`
invocation (or trust CI's own real run on the pushed PR) for confirming the Godot
invocation itself still behaves once the logic is settled.

## Composite-action CI refactors: `workflow_dispatch` a path-filtered/tag-gated workflow to verify it before merging -- but read its full job list first

A CI-critical refactor (e.g. extracting shared Godot/GUT setup steps into
`.github/actions/setup-godot-project/action.yml`, PR #989) touches workflow files that
a normal PR's own CI often can't exercise: `benchmark.yml`/`demo-video.yml` are
path-filtered to sim/game files (a docs-only or CI-only PR never triggers them) and have
**no `workflow_dispatch:` trigger at all** -- a PR that doesn't happen to touch their path
filters can't spot-check them by any means short of a real trigger.
`publish-site.yml`/`refresh-benchmark-baseline.yml`/`release.yml` only run on
`push: branches: [main]`, `schedule`, or `push: tags: v*` respectively (never on a
plain `pull_request`), but all three DO have `workflow_dispatch:` -- that's the way to
verify the refactor actually works in real CI before merging, rather than shipping it
untested and finding out at the next real trigger (a tag push, for `release.yml`, is
an especially expensive place to discover a broken composite-action call).

**But check what the workflow's LATER jobs do before dispatching -- not every
workflow with a `workflow_dispatch` trigger is side-effect-free to run manually.**
`release.yml` is genuinely safe: its own header comment states a dispatch run builds
every artifact "without touching a release," and its "Publish to the GitHub Release"
step is explicitly gated `# Only on a version tag` -- confirmed both in prose and in
the actual `if:` condition before dispatching. `publish-site.yml` is NOT safe the same
way: its `publish` job (the live GitHub Pages deploy) is gated only by `needs:
[demos]` + `if: always()` -- no trigger-type condition at all -- so a `workflow_dispatch`
run deploys to the live site exactly the same as a real `push: branches: [main]` would.
Dispatching it to spot-check the composite-action call crossed into "modifying public
content" territory without recognizing it up front; caught mid-run (only the `demos`
job had started) and cancelled before the `publish` job's turn came up.

**How to apply:** before `gh workflow run`-ing an unfamiliar/rarely-manually-triggered
workflow to spot-check a change, read its full job list and look specifically for a
deploy/publish/release job's own gating condition (or lack of one) -- don't infer
safety from the workflow's general purpose or from one job's own header comment
without checking the actual `if:`. If a dispatched run's job list shows something that
could reach a live-effect step with no confirmed gate, cancel it (`gh run cancel`)
before that job starts and ask before re-dispatching.

## `tools/check.sh`'s comments/units/patch_coverage steps are diff-scoped -- commit before running them, not after

`check_comments`/`check_units`/`check_patch_coverage` all compute
`git diff --no-color -U0 "$(git merge-base HEAD "$base")" HEAD -- '*.gd'` (or a
narrower glob) -- a diff against **HEAD**, not the working tree. Running the bundled
`tools/check.sh validate test chars comments units patch_coverage` invocation against
**uncommitted** changes (reasoning "verify before I commit") means these three steps
compare HEAD against itself and find nothing to check -- they silently print a clean
pass ("No GDScript changes in this diff") without having examined the actual edits at
all. Only `validate`/`test`/`chars` are disk-based and give real signal in that case.

This cost one delegated agent roughly two hours and ~1M tokens in one session: real,
working code sat as an uncommitted diff for two full turns while the agent repeatedly
re-ran the bundled check (each pass ~15-20 min) against it, never noticing three of
the five requested checks were no-ops. Caught only because the orchestrating session
noticed the mismatch directly (`git log`/`git status` showed no commits and no
uncommitted changes despite two turns of claimed work) and asked why.

**How to apply:** commit (even a rough, not-yet-polished draft) before running the
bundled check, not after -- re-commit/amend once the check's own findings are
addressed. When briefing a subagent to implement-and-verify a feature in this repo,
say this explicitly in the brief. If an agent (or you) burns much more wall-clock than
a diff's size would justify, check `git log`/`git status` directly before trusting
"still verifying" -- it's a fast, decisive way to catch this class of problem.
(`Lacaedemon/sparta` PR #999, 2026-07-19.)

## Benchmark check reports PASS regardless of content -- and the baseline goes stale for a whole week after any PR with an accepted cost increase

`benchmark.yml`'s own posted comment can show a real regression (`:warning: Regressed
beyond the 20% threshold`) while `gh pr checks`/the GitHub check conclusion still
reports the job as **PASS** -- this is deliberate (the threshold is "a human call, not
an auto-block"), but it means the check's own green color carries **zero** signal
about whether there's a real finding to read. Always fetch and read the actual posted
comment body (`gh api repos/.../issues/<N>/comments --jq '...sparta-benchmark...'`),
never trust the check conclusion alone, for this specific check.

Separately: `tools/benchmark/baseline.json` is refreshed only by a **weekly schedule**
(`refresh-benchmark-baseline.yml`), not on every `main` push. When a PR's own cost
increase is investigated and accepted as a legitimate, deliberate consequence of a new
feature (not a bug -- e.g. a costlier maneuver firing more often by design), merging it
does NOT refresh the baseline immediately. Every subsequent PR then shows a **false**
"regression" against the now-stale, pre-merge baseline until the next weekly refresh
(or a manual `workflow_dispatch` of that workflow) runs. Before spending time
investigating a benchmark-regression finding as if it were new/PR-specific, check
whether `main` gained an accepted cost increase since `baseline.json`'s own header
comment date -- if so, the "regression" is very likely just baseline staleness, not
something the current PR's own diff caused. (Sequence observed 2026-07-19: PR #922's
moving-wheel maneuver accepted a ~38.8% mean-tick-time increase as an intended cost of
the feature; PRs #995 and #999, merged shortly after, each showed a near-identical
~35-40% "regression" against the same pre-#922 baseline, attributable to neither PR's
own code.)

**A third case, distinct from both above: a genuine same-machine before/after comparison
settles whether a flagged regression is real, when the change is too small to plausibly
cause it and the baseline isn't stale.** CI's baseline is CI-runner-relative and can't be
reproduced locally byte-for-byte, but a LOCAL before/after comparison on the SAME machine,
SAME seed, SAME scenario sidesteps that -- it doesn't need to match CI's absolute numbers,
only to show whether the PR branch is faster/slower than its own merge-base:
```sh
GODOT_BIN=... SPARTA_BENCHMARK_WARMUP_TICKS=60 SPARTA_BENCHMARK_TICKS=300 \
  bash tools/benchmark/run-benchmark.sh   # on the PR branch
git checkout <merge-base-sha>             # detached HEAD; safe when no Godot job is running
GODOT_BIN=... SPARTA_BENCHMARK_WARMUP_TICKS=60 SPARTA_BENCHMARK_TICKS=300 \
  bash tools/benchmark/run-benchmark.sh   # same scenario, same seed, same machine
git checkout <pr-branch>
```
(`SPARTA_BENCHMARK_WARMUP_TICKS`/`_TICKS` at 60/300 match `benchmark.yml`'s own CI-tuned
window, not `BenchmarkRunner`'s local 120/600 defaults -- match CI's window for the
comparison to mean anything.) On PR #1009 (three float instance-field reads added to
`Unit.gd`/`FarTierRules.gd` -- no plausible mechanism for a real slowdown), CI reported a
25.7%/29.2% regression labeled "CI-runner-noisy -- a human call, not an auto-block"; the
local comparison showed the PR branch **faster** (mean 28.9ms vs merge-base's 32.4ms) on
identical inputs, conclusively confirming pure runner noise rather than tracking down a
phantom regression in code that couldn't have caused one. This is the concrete instance of
`baseline.json`'s own documented ~20% swing between functionally-identical runs (see its
`_comment`, citing #755) -- when a flagged regression's magnitude is in that same ~20-30%
band AND the diff has no plausible causal mechanism, suspect noise first and verify this
way rather than assuming the label is wrong or right without checking.

## File-major casualty reflow: verifying "which file stays shallow" needs de-rotation into local frame, and beware odd/even parity between remainder and file count

Two lessons from independently re-verifying PR #995's own file-major-reform demo and
authoring a follow-up demo for PR #999's AUTO mode, worth keeping in mind for ANY
future formation-geometry verification via `dump-state.sh`:

1. **Bucketing `soldiers_full.slots` by raw world-space x is unreliable once a unit's
   facing has rotated even slightly** (an engage-turn, a maneuver in progress) --
   de-rotate each soldier's position into the unit's own local frame first
   (`ang = atan2(facing.y, facing.x) + pi/2`, then rotate `(pos - unit.position)` by
   `-ang`) before bucketing by file. Skipping this makes a perfectly clean 7-file
   layout look like 13+ noisy buckets once facing drifts even a few degrees off-axis.
2. **When the live soldier count's remainder (`count mod files`) and the file count
   itself have OPPOSITE parity (one odd, one even), the partial rank's soldiers sit on
   HALF-file-spacing offsets, not aligned with the full-frontage grid at all** -- this
   is `UnitFormation.block_slots`' own documented behavior for a partial rank whose
   count/frontage parity differs, and it applies to `file_major_block_slots`' fully-
   populated files as a residual layout artifact too. A naive de-rotated bucket-and-
   snap-to-nearest-file-spacing analysis can misattribute which column looks
   "shallow" in this specific case (a genuinely rare accident of exact soldier counts,
   not a bug) -- if a quick verification script gives a confusing/inconsistent
   "shallowest file" reading, check the remainder/file-count parity before assuming
   the underlying feature is broken. The *decisive* proof for this mechanism should
   always be a dedicated GDScript test asserting on the persistent per-soldier file
   array directly (`test_file_major_reform_battle.gd`,
   `test_auto_reform_mode_battle.gd`), not a demo clip eyeballed or bucketed after the
   fact -- a demo just needs to show the feature existing and applying, and its
   caption should say so explicitly when a specific seed's counts hit this parity
   case rather than overclaiming a precise per-file numeric proof it can't actually
   support. (`Lacaedemon/sparta` PR #995/#999, 2026-07-19.)

## `SoldierBodies.step()` and `couple()` both independently recompute `soldier_world_slots` every tick -- a pre-existing redundancy a costlier code path can expose as a benchmark regression

`Battle`'s per-tick soldier-layer pipeline runs `step_all_sim_soldiers` (calls
`SoldierBodies.step()` per unit) to completion for every unit, THEN separately runs
`couple_all_sim_soldiers` (calls `SoldierBodies.couple()` per unit) -- two full passes
over every unit, and both `step()` and `couple()` independently call
`unit.soldier_world_slots(unit.soldiers)`, recomputing the exact same result a second
time with nothing in between that could have changed it (nothing mutates a unit's
position/facing/formation state between the two passes finishing/starting). This
redundancy predates any specific feature and applies to BOTH row-major and file-major
reflow -- but `file_major_reform`'s own per-call cost (an extra O(soldiers) pass in
`UnitFormation.file_major_block_slots` vs. the historical single-pass `block_slots`)
made the existing 2x-redundant computation expensive enough to surface as a real,
measured 45.2% CI benchmark regression on PR #995.

**Fix pattern, not a general cache:** rather than caching `soldier_world_slots`
broadly (risky -- any OTHER caller that mutates position/facing mid-tick in a way not
yet audited could read stale data), scope the fix narrowly to the two specific call
sites: `SoldierBodies.step()` stashes the slots it already computed
(`Unit._step_slots_for_couple` / `_step_slots_for_couple_valid`), and `couple()`
consumes-and-clears that single-use handoff instead of recomputing, falling back to a
fresh computation if the handoff is missing or size-mismatched. Verified this dropped
the regression from 45.2% to 4.3% against the same CI baseline.

**When a new/costlier code path triggers a benchmark regression, check for a
pre-existing redundant-computation pattern like this BEFORE assuming the new code
itself needs optimizing** -- the new code's own cost may be fine in isolation; it's
often just exposing an existing 2x (or more) waste that was previously too cheap to
notice. (`Lacaedemon/sparta` PR #995, 2026-07-19.)

## Orchestrating multiple Godot-touching agents in parallel worktrees: the shared-process hazard bites BETWEEN agents, not just between manual sessions -- and self-checking via `tasklist` is not by itself sufficient

Sparta tolerates only one Godot process running anywhere on the machine at a time
(shared `user://settings.cfg`, keyed by project name, not path -- see the "shared
ACROSS worktrees" entries above). Those entries already document the hazard for a
single human/session switching contexts; it recurs identically, and more easily,
when an orchestrating session dispatches SEVERAL background subagents that each
own their own worktree and each independently run `tools/check.sh`. Worktree
isolation prevents FILE-level collisions; it does nothing for this PROCESS-level
one.

**What actually went wrong, concretely (GII session, 2026-07-19/20, two
subagents -- one fixing #979, one implementing #1014):** the orchestrator
launched both agents' Godot-heavy verification work without serializing them.
Two full sets of `check.sh` processes ended up running concurrently for real
(confirmed via `Get-CimInstance Win32_Process -Filter "Name LIKE '%Godot%'"`
showing two distinct console+engine PID pairs at two different `CreationDate`
timestamps). Both runs had to be discarded and redone.

**The self-checking discipline that ultimately worked, after two false
resolutions:**
1. A bare `tasklist //FI "IMAGENAME eq ...console.exe"` snapshot is not enough
   evidence on its own -- it can't distinguish a genuinely separate second agent's
   process from (a) a parent/child console+engine pair from ONE process (misread as
   "two"), or (b) a brief gap between SEQUENTIAL Godot sub-invocations within a
   single `check.sh` script (validate exits, then test/coverage starts fresh a few
   minutes later -- misread as "the whole script finished" when only one phase
   did). Both misreads happened in this session, in both directions -- once
   trusting a stale "cleared" signal too early, once nearly discarding a
   perfectly good result because of a wrong-time check.
2. **The decisive tool is `Get-CimInstance Win32_Process -Filter "Name LIKE
   '%Godot%'" | Select ProcessId, ParentProcessId, CreationDate, CommandLine`**
   (not plain `tasklist`, not `Get-Process`) -- it gives the parent/child
   relationship (rules out the console/engine misread) and the exact
   `CreationDate` (lets you correlate a PID pair against a specific agent's own
   push/commit timestamp instead of guessing from clustering).
3. **A subagent that already has a background check running should verify the
   claim independently before acting on an orchestrator's "it's clear, go
   ahead" or "it collided, stop" message** -- in both directions. One subagent
   caught the orchestrator's premature "exited" signal by re-querying itself
   and correctly kept waiting; another caught a genuinely-overlapping process
   the orchestrator had missed. Neither blindly trusted the other party's
   claim, and that's what actually prevented a THIRD contaminated run.
4. **A run that genuinely overlapped with another process is not automatically
   worthless** -- check the actual OUTPUT for internal coherence (specific
   line-numbers/counts tied to files the diff actually touches; a real GDScript
   parse error or garbled/nonsensical numbers is the actual contamination tell,
   e.g. scrambled keybinding values) before discarding a result just because
   the timing was bad. The documented corruption failure mode (shared
   `settings.cfg` keybinding scramble, a coverage report reflecting a stale
   test set) is specific and detectable; a coherent, diff-relevant result that
   merely ran during an overlap window is not automatically suspect.
5. **Killing a stray/colliding process is a destructive action the harness's
   own permission classifier blocks** (`Stop-Process`/`taskkill`, from either
   the orchestrator or a subagent) -- don't try to work around that block.
   Prevention (serialize launches) is the only real lever available; cleanup
   after the fact requires waiting the process out, not killing it.

**How to apply, as an orchestrator dispatching 2+ Godot-touching agents:**
never assume worktree isolation is sufficient and let them self-serialize by
individually checking `tasklist` -- that's exactly the mechanism that produced
both misreads above. Instead, actively coordinate turns yourself: hold every
agent but one, verify with `Get-CimInstance` (not `tasklist`) that the machine
is genuinely clear, release exactly one agent, wait for ITS OWN completion
report (not an external process-exit guess, which is unreliable across a
multi-phase script), then release the next. The lesson from this session
isn't "check less" -- both agents' own diligence in re-verifying rather than
blindly trusting a claim is what actually avoided a third wasted run -- it's
"check with the right tool, at the moment closest to the actual action, and
let each party verify independently rather than trust-and-proceed."
(`Lacaedemon/sparta`, GII+mwc session, 2026-07-19/20, PRs #1020/#1024.)

## A new per-soldier render-easing value needs its OWN trigger in `_process`'s refresh gate, not just the existing ones

When adding a new eased (never-snap) per-soldier render value -- mirroring the
existing `_render_alpha`/`ROUTING_ALPHA` idiom -- don't assume the existing
`Unit._process()` refresh gate (`_render_dirty or facing changed or state ==
FIGHTING or instance-count drift`) will keep calling `_refresh_flock_render`
often enough for the NEW value to finish easing. Those four conditions are
tuned for what they already cover (body movement, turning, combat, casualty
compaction) and have no reason to correlate with an unrelated timer's own
decay.

**Concrete case:** the prone-soldier render fix (`_render_prone_progress`,
easing a soldier's fallen-pose transform/tint instead of snapping) initially
relied on those four existing conditions alone. `_render_dirty` is set ONLY
when a soldier body's velocity exceeds `SoldierBodies.REST_SPEED` -- a
knockback's initial impulse sets it (so the ease correctly *starts*), but the
body settles to near-zero velocity well before `_render_prone_progress`
finishes converging, and once the unit's own `state` drops out of `FIGHTING`
(immediate, no linger) none of the four conditions fire again. Result: the
ease froze mid-transition -- a soldier permanently stuck half-fallen/half-risen
-- which is a WORSE visible defect than the original instant-snap bug the fix
set out to solve. This is the same "inert number" failure class as the
`_current_speed`/coasting bugs above, just on a different field. Caught by
`claude-review`, not by the original implementation or its own tests (which
called `_refresh_flock_render` directly, bypassing `_process`'s gate entirely,
so the frozen-forever path was never exercised).

**Fix pattern:** add a dedicated boolean (`_prone_easing_active`) set by the
easing function's OWN per-soldier loop (`still_easing = true` whenever
`progress != target` for any soldier), read as an additional OR-condition in
`_process`'s gate. `move_toward` clamps exactly to the target once within
range, so the flag reliably goes false on convergence -- no risk of getting
stuck true from float drift.

**Test gotcha this surfaced:** a test that exercises the easing function
directly (`u._refresh_flock_render(delta)` in a loop) proves the MATH is
right but does NOT prove `_process` actually keeps calling it -- write a
second test that drives the fix through `_process` itself with every OTHER
gate condition deliberately held inactive (state != FIGHTING, `_render_dirty`
false, no facing change, no instance-count drift), so the new trigger is the
only thing making it advance. And when staging that test, remember the
kickoff itself needs a real trigger too: directly setting the underlying sim
field (`_sim_prone[i] = 1.0`) with no accompanying `_render_dirty`/velocity
pulse never starts the ease in the first place (in real play, a knockback's
own velocity always provides that first kick) -- call the easing function
once directly to simulate that one real-world kickoff tick, THEN loop
`_process` alone to prove the *continuation* works with nothing else active.
(`Lacaedemon/sparta` PR #1054, 2026-07-23.)

## Grep your OWN new comments for issue-number citations before every commit, not just after `check.sh` catches it

CLAUDE.md's "Comments: no issue-number references" rule is well-documented,
but self-checking against it is easy to skip when writing a fix's own
explanatory comments (especially ones that narrate *why* a bug happened,
which naturally wants to reference "the issue this fixes"). In one session,
`tools/check.sh comments` caught this same self-inflicted mistake three
separate times across three different PRs (#1042, #1053, #1054) -- each
time costing a full extra `check.sh` cycle (15-20 min for the coverage-
instrumented suite) purely to re-discover something a 5-second grep would
have caught immediately after writing the comment.

**How to apply:** after writing any new/edited comment block explaining a
fix's root cause (the kind of comment most likely to want to say "this is
what issue #N was about"), grep the diff yourself before committing:
`git diff --cached | grep -E '^\+.*#[0-9]{2,4}\b'` (or just re-read what you
wrote with this rule specifically in mind) -- don't rely on `check.sh`'s
`comments` check to be the first line of defense; treat it as the last-resort
safety net, not the primary catch.

## `gh pr merge --delete-branch` failing locally with "'main' is already checked out" is benign in a session worktree -- the merge itself still lands

`gh pr merge <N> --squash --delete-branch`, run from a session worktree (not
the primary checkout), can fail with `failed to run git: fatal: 'main' is
already checked out at '<primary-checkout-path>'` -- this is `gh`'s own
post-merge convenience step trying to switch the LOCAL checkout to `main`
(exactly the hazard this file's own "never checkout main in a worktree"
entries already warn about), not a failure of the merge itself. The remote
merge (and `--delete-branch`'s remote branch deletion) completes before that
local step runs, so it always succeeds regardless of the error message.

**How to apply:** after seeing this error, don't retry or investigate the
merge -- just verify directly (`gh pr view <N> --json state,mergedAt`, and
the closing issue's `state`/`stateReason`) and proceed to the normal
post-merge tidy (`git fetch origin --prune`; don't touch the local `main`
branch in this worktree at all, matching the existing convention of never
checking it out here). Hit twice in one session (PRs #1051 and #1054,
2026-07-23), both simple confirms-and-moves-on once checked.

## A "PR Status Report" review reply can be a stub in disguise -- restating old context instead of independently re-checking the current diff

Adds a specific symptom to the existing stub-review family already
documented above: a re-review triggered right after a fix push can come back
formatted as a "PR State / Is Draft / Prior Claude Review" status summary --
quoting the EARLIER finding and the author's OWN follow-up commit message
almost verbatim -- rather than an independent line-by-line re-check of
whether the fix actually resolves the finding. It still carries a
plausible-looking structure and doesn't obviously read as empty the way
"Test content line." does, so it's easy to mistake for a genuine re-verdict
at a glance.

**How to apply:** when a review reply mostly restates PR metadata/history
you already know (title, description, "yes it was reviewed before, here's
what happened") rather than tracing the specific code change against the
specific finding, treat it the same as any other stub: don't accept its
implicit "looks fine" as a verdict. One manual re-dispatch
(`gh workflow run claude-code-review.yml -f pr_number=<N>`) is usually
enough to get a genuine fresh pass that explicitly traces the fix (verified:
the second dispatch on the same PR produced a real line-by-line
verification and an explicit `### Verdict`). (`Lacaedemon/sparta` PR #1054,
2026-07-23.)
