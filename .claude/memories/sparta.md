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
  #740/#741 (open as of this writing) applies the same fix to routing translucency,
  fading it instead of switching instantly.
- **No inert numbers.** A quantity that represents real motion must actually cause
  motion — a decaying speed that doesn't move the unit is a display artifact, not
  physics. #742/#743 (open as of this writing) makes residual `_current_speed` coast
  the unit forward as it decelerates, instead of counting down while `position` sits
  frozen. Check whether #741/#743 have merged before citing this section as describing
  the current codebase state rather than the in-flight direction.
- **No top-down combat-multiplier gimmicks where a physical mechanism already exists.**
  Prefer deriving an outcome (a spear stopping a charge, a knockback felling a soldier)
  from mass/momentum/impulse over a flat "type X beats type Y" bonus. This is the
  standing rationale behind #164/#296 (move collision to the individual soldier level)
  and the long-horizon #550 (individual-level LOD simulation at Cannae scale).

When implementing or reviewing a new mechanic, ask: does this emerge from the
individual-level physics already in place, or is it a shortcut layered on top? Prefer
the former; flag the latter as a candidate for this list.

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

Playback also low-passes the track (`Battle.CAMERA_SMOOTHING`), but that smooths
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
- **Camera playback steps between keyframes, then EMA-smooths** (`Battle.CAMERA_SMOOTHING`).
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
like `edge_scroll =`, `walk_advance =`, `form_up_dist_default =`) all call
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
  `Settings.walk_advance = ...`) and replace with direct mutation + manual
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

When a PR is purely **"show an existing sim state on screen"** (e.g. #486: draw
shields for the SHIELD_WALL / TESTUDO `formation_mode` stances — the defensive
effects already existed, only the visual was missing), build it as a
**render-only overlay** so it never touches sim/combat/formation code and stays
conflict-free with the many in-flight PRs that DO touch that code.

**The pattern (mirrors `UnitSprites` / the emblem/flag chrome):**

1. **Pure geometry helper** in its own `class_name` script
   (`scripts/UnitShields.gd`). Static funcs taking plain shape inputs
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
