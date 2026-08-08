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
- **No top-down RESOLUTION AUTHORITY either, not just no top-down mechanics.** The
  bullets above are all about a mechanic's *effect* (a flat modifier, a snap, an inert
  number, a synthetic force). The same principle governs *who computes an outcome at
  all*. A regiment-level formula that turns a stat difference into an absolute soldier
  count is the same shortcut aimed at arithmetic instead of at forces -- the regiment is
  an unnecessary abstraction over something the individual soldiers already determine.
  The owner's framing: **no unnecessary abstractions**. Worked instance: #1151, where
  `UnitCombat.strike`'s regiment formula annihilates a 10-man unit in one blow because
  the damage number IS the casualty count, sized for an 80-man regiment. Casualties
  should be resolved individually; morale may stay a regiment scalar for now (owner
  directive, 2026-07-30). Ranged is the same shape and is tracked separately in #1186
  (by individuals, at individuals, with per-soldier range).
  This now has three instances -- gameplay mechanics, cosmetic VFX (the Fallen-heap
  redesign), and resolution authority -- so treat it as the general rule rather than a
  list of special cases.

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

**An orphaned Godot process (e.g. a `bash tools/check.sh | head -N` pipe
SIGPIPE-killing the wrapper script but leaving its spawned Godot child
running detached) is a lock the same way a live foreground run is — and this
repo's own `tools/kill-orphan-godot.ps1`/`.sh` cleanup tool (dry-run by
default) can be BLOCKED OUTRIGHT by the Claude Code auto-mode permission
classifier on the name alone, even in dry-run mode.** Don't fight that block
by retrying or improvising a workaround. `Get-CimInstance Win32_Process
-Filter "Name LIKE '%Godot%'" | Select ProcessId, ParentProcessId,
CreationDate, CommandLine` (Windows) surfaces the candidates, but
`CreationDate` alone can't tell a stalled process from one still working --
it's the process's fixed start time, unchanged for the whole life of ANY
still-running process. Use it for AGE instead (`now - CreationDate` well past
the suite's normal completion time, not a delta between two checks), or check
a genuinely progress-tracking signal: whether the run's own output artifact
(e.g. `coverage/lcov.info`, the GUT log) is still growing, or the process's
CPU-time counters (`KernelModeTime`/`UserModeTime`) advancing between checks.
When blocked from cleaning up and
unable to guarantee a local run is uncontaminated, fall back to CI's own
clean-runner results (`gh pr checks`) as the authoritative signal instead of
trusting a local re-verify. (`Lacaedemon/sparta` PR #1106, 2026-07-27.)

**The contending process isn't always yours — a GENUINELY EXTERNAL Godot
process on the same dev machine (a different session, a different tool, an
unrelated scheduled job) can collide the exact same way, and it's easy to
mistake for your own stray/orphaned run at first.** `Get-CimInstance
Win32_Process -Filter "Name LIKE '%Godot%'" | Select ProcessId, CommandLine`
disambiguates: check the **binary path** and **working-directory-implied
args** in `CommandLine`, not just the process name. A process invoking a
binary you never referenced this session (e.g. a Downloads-folder copy when
every command you ran used a Documents/apps one) is definitively not yours --
don't try to kill it (same permission-classifier block as an orphan of your
own, and it's not yours to kill regardless), just wait for it to clear before
running your own suite, exactly as if it were a sibling worktree's job. This
recurred repeatedly across roughly 40 minutes in one PR's final-verification
pass, each time truncating the local run's log with no error message at the
truncation point -- distinguishable from a genuine hang in your own code
(which also produces a truncated/no-summary log) only by re-running the
SPECIFIC test alone, in isolation, once the machine is confirmed clear; if it
completes fine standalone, the earlier truncations were contention, not a
real regression. (`Lacaedemon/sparta` PR #1137, 2026-07-27.)

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

## `git worktree remove` needs `--force` on a worktree containing a submodule

sparta vendors `.ai-config` as a git submodule,
so any `.claude/worktrees/<name>` worktree with it checked out
refuses the plain removal:
`fatal: working trees containing submodules cannot be moved or removed`.

This is a FLAT REFUSAL, not a dirty-tree complaint --
the worktree can be perfectly clean and still hit it.
It is distinct from the two failure modes already documented above:
the partial success that leaves an empty, orphaned directory,
and the fake worktree whose directory has no `.git` of its own.

**`--force` is the whole fix, and it is one command.**

```bash
git worktree remove --force <path>
```

git's own `git-worktree` docs say so under `remove`:
"Unclean worktrees or ones with submodules can be removed with `--force`."
Only `git worktree move` refuses a submodule worktree unconditionally;
`remove` accepts `--force` exactly as it does for an unclean tree.

Measured on git 2.37.2.windows.2, against a throwaway worktree with
`.ai-config` checked out: the plain form exits 128 with the error above,
and `--force` exits 0, deletes the directory,
and drops the entry from `git worktree list` with no prune needed.

Verify disposability before forcing, since `--force` is the point of no
return: `git status --short` comes back empty and
`git merge-base --is-ancestor <head> origin/main` returns true.
An empty `git rev-list origin/main..<head>` is the same fact in another
form, so run one or the other rather than both.

- **Do:** reach for `--force` as soon as a routine sweep reports this error.
- **Do:** verify disposability first -- `--force` discards without asking.
- **Don't:** read the refusal as "the worktree is busy" -- nothing holds it.
- **Don't:** conclude `--force` is refused without running it.
  The plain refusal's wording says nothing about what `--force` does,
  and a hand deletion plus `git worktree prune` is a longer road to the
  same place.

(2026-08-05, a local working-directory cleanup sweep:
7 of 8 worktrees were removed normally by `git worktree remove`;
`gii-mwc-4b00e5` refused with this error alone,
was verified clean with 0 unique commits and an ancestor of `origin/main`,
and was cleared via PowerShell `Remove-Item` plus `git worktree prune`.
That hand deletion was unnecessary: `--force` was never attempted,
and this entry originally asserted from that omission that it "does not
help".
Review challenged the claim against git's own docs, and the measurement
above -- run afterwards, on a purpose-built submodule worktree -- confirmed
the reviewer was right.
The reusable lesson is the narrower one:
a refusal message describes the command you ran,
not the flag you did not try.)

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

## `claude-code-review.yml` auto-fires on every PR again (re-enabled #1122, was off #1051-#1122)

PR #1062 (issue #1061, 2026-07-23) removed `.github/workflows/claude-code-review.yml`'s
`pull_request:` trigger, on the reasoning that GitHub Copilot code review (enabled
repo-wide via the `main` branch ruleset's `copilot_code_review` rule) already reviews
every PR automatically, making an automatic Claude pass redundant. Issue #1122
(2026-07-27) reversed that call at the user's direct request — the `pull_request:`
trigger (`types: [opened, synchronize, ready_for_review, reopened]`) is back, so a fresh
PR again gets an automatic `claude[bot]` review comment, in addition to Copilot's.

**What this means for ARDI going forward:** a fresh PR gets BOTH an automatic Copilot
review and an automatic Claude review — check both (`gh pr view <N> --json reviews` and
`gh api repos/<owner>/<repo>/pulls/<N>/comments`, per the "Re-check for latest review
findings" convention) rather than assuming only one fired. All of this file's and
ai-config's stub-review / "do the review yourself when @claude doesn't produce a verdict"
handling still applies to Claude's automatic pass, same as before it was ever disabled.
`claude.yml`'s own re-dispatch-after-push mechanism and a manual
`gh workflow run claude-code-review.yml -f pr_number=<N>` both still work as before —
useful for an ad-hoc re-review after a push, since `synchronize` already re-fires
automatically now.

If this ever needs disabling again, PR #1062's diff (`git show 17fab72a`) is the exact
prior workflow-config change to reference.

**A PR that edits `claude-code-review.yml` (or a workflow file the review action reads)
gets no inline Claude review at all — by design, not a stub.** The `review/claude-review`
job still runs and reports `pass`, but posts a run annotation instead of a review comment:
"PR #N edits `.github/workflows/claude-code-review.yml` — skipping self-review (the action
401s on workflow validation until merged; it runs after merge)." **The exact mechanism is
unconfirmed** (not verified against `d-morrison/gha`'s own implementation) — the plausible
read is that GitHub only lets the review action validate against the workflow version
already on the base branch, so a PR changing that same file can't be validated pre-merge and
the action detects this and defers review to post-merge instead of failing or posting a
stub — but that's inference from a single annotation, not a confirmed cause. Regardless of
the exact mechanism, don't treat the skip as a broken/stub review needing a manual
re-dispatch (per the existing stub-review handling above) — check the run's own annotations
(`gh run view <run-id>`) before assuming a self-review is missing for the usual reasons.
(`Lacaedemon/sparta` PR #1123, 2026-07-27.)

**The corollary, and it is the dangerous half: that self-skip means a PR which BREAKS the
review config gets no review OF that breakage — so on a PR editing `claude-code-review.yml`,
a fully green board is the WEAKEST assurance available, not the strongest.** The skip fires
before the config is exercised, so a broken `plugins:`/`plugin-marketplaces:` ref sails
through with `review / require-review` itself reporting `pass`. The failure then lands on the
NEXT PR opened, where that same required check dies at plugin install and blocks the whole
repo. Nothing on the introducing PR points at it.

This is not hypothetical: PR #1176 (a Jules-authored one-line `distance_squared_to`
micro-optimization) carried a commit that changed `plugins: ai-config@Morrison-Lab` back to
`ai-config@d-morrison`, whose own message described it as *"fixes a Claude plugin marketplace
reference bug"* — inverted, since the marketplace declares `"name": "Morrison-Lab"` (see the
account-move entry below). It reverted #1172 and would have reintroduced #1171, making every
subsequent PR unmergeable. All 14 checks were green, and the comment block *directly above the
changed line* already warned against exactly that value, error string included. Three failures
had to stack for it to get that far: the bot's inverted "fix", the self-skip suppressing the
only reviewer that would have caught it, and Copilot simultaneously quota-exhausted.

**How to apply.** Treat any diff touching `claude-code-review.yml` as review-exempt by
construction and hand-verify it, no matter how green CI is or how plausible the commit message
sounds. Concretely, diff the file against the **merge-base**, matching this file's own
convention for every other diff-scoped check (the `codecov/patch`-gap and `check.sh`
diff-scoping entries) — not against `origin/main`'s tip:

```bash
git diff "$(git merge-base HEAD origin/main)" HEAD -- .github/workflows/claude-code-review.yml
```

That distinction is load-bearing rather than pedantic here. `main` has itself moved on this
exact file (#1172 landed the `d-morrison` -> `Morrison-Lab` fix there), so a tip diff on any
branch forked before that reports a spurious "revert" of the marketplace ref for a branch that
never touched the workflow at all — noise shaped exactly like the anomaly this entry teaches
you to hunt. The natural response to that false alarm is to "fix" a file the PR never touched,
which is what would *create* a real self-skip condition out of nothing.

For a plugin/marketplace ref, then check it against the marketplace's own live declared name
rather than reasoning from the URL (the ref resolves by declared name; the URL still resolves
via GitHub's transfer redirect and so tells you nothing):
`gh api repos/<owner>/ai-config/contents/.claude-plugin/marketplace.json --jq .content | base64 -d`.

Best outcome when the workflow edit is unrelated collateral (as here): drop it entirely. The
file then becomes byte-identical to `main` and falls out of the PR's diff, which retires the
skip condition — confirmed on #1176, where the review went from a 6s skip to a genuine 11m
run and verdict on the very next push. That **narrows** the older "cannot verify itself" note
in the account-move section below rather than retiring it, and the distinction matters: when
the edit is collateral, dropping it restores review; when the edit *is* the fix (#1172 itself),
dropping it would delete the very thing being verified, so that note still holds in full —
confirm on the next PR's run. (`Lacaedemon/sparta` PR #1176, 2026-07-29.)

**Copilot's own review can also fail closed, not just Claude's.** Copilot's review comment
can read `Copilot was unable to review this pull request because the user who requested the
review has reached their quota limit.` — repeatedly, across many pushes. This is a distinct
failure mode from Claude's own quota-skip message, but the same handling applies: it's not an
approval, don't wait on it, self-review or manually dispatch Claude instead.

**A manual `gh workflow run "Claude Code Review" -f pr_number=<N>` dispatch can silently run
against `main`'s ref instead of the PR branch and post NO comment at all — a distinct, quieter
failure than the documented stub-review pattern.** The run itself reports `success` (all three
jobs green), and every run so far has carried a `The process '/usr/bin/git' failed with exit
code 128` annotation regardless of whether it actually posted a review — that annotation is
benign, expected noise, not a sign anything went wrong. The real tell is the run's own
`head_branch`: a manually-triggered run that resolves to `main` (rather than the PR's actual
branch) reviews nothing PR-specific and produces no comment, even on `success`. Meanwhile, this
repo's automated re-dispatch mechanism (`claude.yml`'s push-triggered re-dispatch, attributed to
`github-actions[bot]`) fires its OWN `workflow_dispatch` correctly scoped to the PR's real branch
— and if a manual dispatch is still in flight when it queues, the `claude-review-<N>` concurrency
group cancels the manual one in favor of it (`Canceling since a higher priority waiting request
for claude-review-<N> exists`). **How to apply:** after pushing, check `gh run list
--workflow="Claude Code Review"` for a run whose `head_branch` matches the PR's actual branch
before manually dispatching — the automated re-dispatch usually beats you to it within a minute
or two. If you do dispatch manually and it lands on `main` with no resulting comment, that's the
signal to just wait for (or re-dispatch and confirm) a run scoped to the real branch, not to
suspect the PR itself. (`Lacaedemon/sparta` PR #1070, 2026-07-27.)

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

## After implementing a fix, verify it actually engages the reported bug's real code path

The entry above ("verify an issue's own stated root cause empirically") covers checking the
DIAGNOSIS before implementing. This is the companion check AFTER implementing: a fix can be
logically correct for the code path you touched, compile, pass its own new unit tests, and
still leave the originally-reported bug completely unfixed — because the real-world scenario
that triggers the bug turns out to route through a DIFFERENT code path than the one the fix
covers. Passing tests for the path you fixed proves nothing about whether that's the path
the bug actually takes.

**Concrete case:** issue #1072 diagnosed the Fallen casualty-heap VFX spawning at a stale
formation-geometry location instead of the dying soldiers' live position, and named
`SoldierMelee.reap()`'s per-soldier casualty path as the fix point (PR #1074). The first
implementation threaded the dying soldiers' exact live centroid through that path, added
passing unit tests, and looked done. Only building an actual before/after visual proof (the
same technique the issue's own investigation used — rendering the exact reported reproduction
script at the exact reported tick, on `main` vs the branch) revealed the two frames were
**pixel-identical** — the fix had zero effect on the reported scenario. Root cause:
`SoldierMelee.reap()` is only reached once a unit's engaged-tier latch has set
(`Unit.is_engaged()`), which requires at least one PRIOR tick of `state == FIGHTING` (the
latch, `tick_engaged()`, runs after `_think()` in the same physics step) — so the VERY FIRST
strike after fresh contact always falls through to the regiment-formula fallback path
instead. Every one of the reported scenario's three casualty events was exactly that first-
strike case; the per-soldier path the fix touched never fired at all for this bug. Required a
second fallback tier (anchoring on the unit's own live soldier bodies when exact per-death
data isn't available, instead of the stale formation geometry) to actually fix the reported
case — see the follow-up entry below for how even THAT fallback still needed a further round
of the same lesson, and how the whole mechanism was eventually redesigned away.

**How to apply:** before considering a fix complete, reproduce the ORIGINAL reported scenario
(not just a hand-built unit-test fixture) and confirm observably that the previously-buggy
behavior no longer occurs — a real before/after comparison (frame diff, state dump, or
equivalent), not just "my new tests pass." If a before/after comparison shows NO difference
at all where a real behavioral change was expected, that's a strong signal the fix's code
path isn't the one actually exercised by the report — instrument the specific branch/gate
(`is_engaged()`, a feature flag, an early return) to find out which path really fires before
assuming the fix needs to be bigger, smaller, or different. A unit test built around your own
mental model of "how the bug happens" inherits that same blind spot; only a reproduction of
the ORIGINAL report is immune to it. (`Lacaedemon/sparta` issue #1072, PR #1074, 2026-07-25.)

### Follow-up round: the same lesson recurred, then a design pivot to bottom-up physics

The Fallen-heap saga above didn't end with PR #1074. A separate demo (`spear-standoff.json`,
from PR #1075, an unrelated attack-cadence change) still showed casualties "appearing out of
nowhere" after #1074 merged — the user caught this directly by eye. Investigating it surfaced
TWO further lessons on top of the one above, both worth carrying forward:

1. **The same "verify against the real scenario" lesson bit a SECOND time, on the fallback
   tier itself.** #1074's second-tier fallback (anchoring on the unit's live soldier bodies
   when no exact per-death data exists) averaged the WHOLE regiment — a real, provable flaw
   (a unit test with a deliberately split formation showed the average landing in the gap
   between two clusters). The obvious fix was to bias that average toward the soldiers
   nearest the attacker instead. But re-verifying against the ACTUAL `spear-standoff` demo
   (not just the constructed unit-test case) showed the fix changed NOTHING for that specific
   scenario — the block wasn't spread into separate clusters at the casualty tick, so the old
   whole-block average and the new near-attacker-biased average came out nearly identical.
   The fix was still logically correct and worth keeping (proven by the isolated test), but it
   was not what was actually causing the visible symptom in the reported case. **How to
   apply:** even a fix built specifically IN RESPONSE to a "verify the real scenario" lesson
   still needs that same verification applied to itself — don't let fixing one instance of the
   lesson exempt the next fix from it.
2. **What actually explained the demo's symptom was a THIRD, distinct mechanism**: `Fallen.gd`
   already documented (in its own doc comment) that the heap is deliberately stationary once
   spawned, "fading into the ground as the fight moves on." A charging formation can advance
   far enough in under a second to visibly leave a CORRECTLY-spawned heap behind — confirmed
   by comparing the unit's own `soldier_summary.centroid` at the death tick against 40 ticks
   later (a ~40-world-unit advance in ~0.6s). This was filed as its own issue (#1076) rather
   than fixed unilaterally, since "should a cosmetic death-mark track the living formation" is
   a genuine design question, not a bug — then closed once the user confirmed directly that a
   fallen soldier's mark should reflect where it died, not follow the survivors afterward
   (the intended behavior all along, once the OTHER two issues were actually fixed).

**The design pivot.** Asked directly what the "heap" mechanic even was, and on hearing the
explanation, the user's call (echoing "remember: no top down abstractions") was to eliminate
the whole "compute one representative point per casualty event, then scatter a synthetic
pattern of marks around it" design outright — not just keep patching which point gets chosen.
PR #1078 replaced it: every dying soldier now gets its own mark at its own real live position
(exact positions from `SoldierMelee.reap()` when available; the real positions of the nearest
live soldiers to the attacker as a fallback when not). No more averaging, no more golden-angle
fake scatter. This is a DIRECT instance of this file's own "Standing design philosophy:
bottom-up physics, no top-down gimmicks" section (above) — previously stated and applied only
to gameplay/combat mechanics (knockback, collision, morale), but it turned out to apply just
as cleanly to a purely cosmetic rendering system: an aggregate-and-scatter VFX is the same
shape of top-down shortcut as a flat combat modifier, just one layer further from gameplay.
**How to apply:** when a cosmetic/rendering system is accumulating fallback tiers and
special-case math to approximate "where did this event actually happen," consider whether the
underlying real per-entity data (already computed, already available) can be shown directly
instead of being reduced to one synthetic representative point — the direct version is often
BOTH simpler and more correct than the aggregate one, on this codebase's own terms.
(`Lacaedemon/sparta` issues #1076/#1077, PRs #1078, 2026-07-25.)

## A "matches the issue's own framing" fix can be completely inert for the actual reported symptom — verify with the SAME artifact the report used

Building on the entries above: PR #1137 (closing #1129, reporting infantry visibly walking
through each other in the site's showcase clip) started by fixing exactly what the linked
issue described — NORMAL formation's zero containment margin (a real gap #1118 deliberately
left open). Implementing it, testing it, and even doing a live-battle probe render made it
LOOK like the fix worked. But a direct before/after render of the ACTUAL reported artifact
(`demos/showcase.json`, tick 600, unmodified vs. fixed) came back **pixel-identical** — the
exact same "zero effect" signal the Fallen-heap case above already documents. Root cause,
found only by then tracing WHY the probe render differed from the real artifact: the showcase
demo's player units were on a plain MOVE order with no attack target, which this repo's own
`_think()` deliberately treats as "disengage" — the units never entered `state == FIGHTING`
at all, so `is_engaged()`-gated `engaged_soldier_indices()` (which the containment margin
widens) never fired for them regardless of any margin value. The real fix needed a second,
deeper layer: decoupling PHYSICAL collision from combat state entirely
(`Unit._in_enemy_contact`, a pure-proximity flag).

**How to apply:** when a reported bug names a specific mechanism/issue, and a fix matching
that framing "looks right" (passes new tests, even improves a HAND-BUILT reproduction), still
render the SAME artifact the bug report itself pointed at (not a look-alike scenario you
construct) before declaring it fixed. A hand-built probe scenario inherits your own mental
model of the bug — same blind spot the entry above names — and can pass even when the real
artifact wouldn't. (`Lacaedemon/sparta` issue #1129, PR #1137, 2026-07-27.)

## Widening a validated is_engaged()-OR-proximity gate to an ADJACENT function isn't automatically safe — position-anchor code has its own sensitivity

PR #1137 decoupled several functions from combat-state-only gating (`is_engaged()`) to
`is_engaged() OR _in_enemy_contact` — a pure-proximity flag — so a "disengaging" unit's
soldier BODIES still physically resist an enemy even though the unit itself never fights.
This worked cleanly for `SoldierEnemyContact.accumulate`, `_separate()`'s enemy branch, and
the new `contact_soldier_indices()` selection: full test suite green, no regressions.

Applying the IDENTICAL pattern to `Unit.position_anchor_indices()` / `near_front_soldier_
indices()` (the selection `SoldierBodies.couple()` anchors a regiment's `position` on)
looked like the natural, structurally-identical next step — and #783/#784 already
established the exact real-world need (a fighting regiment's charge "rides through" a braced
line because `couple()` dilutes its resisted front rank's signal over the whole unengaged
block; the same dilution applies to a merely-in-contact-not-fighting unit, unfixed). It
compiled, passed `validate`/`comments`/`units`/`chars`, and even a quick isolated live-battle
unit test. Only running the FULL test suite (specifically `test_collision_knockback_battle.gd`,
a live 900-tick showcase-scenario regression guard) revealed it hung INDEFINITELY (reproduced
with a 90s timeout in isolation, never completes; the same test normally runs in ~17s).

**How to apply:** two functions sharing the SAME surface pattern (a combat-state gate, a
near-front selection) are not interchangeable in risk just because the fix mechanism looks
identical. `Unit.ANCHOR_RANKS`' own doc comment already documents a history of subtle
swirl/instability regressions from narrowing this SPECIFIC selection's DEPTH; widening WHICH
UNITS qualify for it turned out to be an untested new axis on that same sensitive surface,
not a safe copy of a pattern proven elsewhere. Before extending a validated fix to an
adjacent function, specifically re-run any LIVE, LONG-RUNNING (not just isolated/short)
regression tests that already exist for that function's own subsystem — a hang can hide
behind every fast/isolated check passing. Reverted rather than root-caused under time
pressure; tracked as issue #1136 for whoever investigates further with per-tick
instrumentation.

## Even well-documented anti-patterns get re-violated under complexity/time pressure — a targeted pre-push grep still pays for itself

PR #1137's first review round found 5 real findings — two of which are mistakes THIS FILE
already documents in detail before this PR even started: the asymmetric
`maxf(self_reach, candidate_reach)` contact-check convention (see "A symmetric 'is X near Y'
contact check" below) and the `demos/demo.json` shared-file-is-a-perennial-merge-conflict-
point / use-a-per-PR-numbered-manifest convention (see "record-demos.sh DEMOS conflicts are
ADDITIVE" above and CLAUDE.md's own demo-authoring section). Both got violated anyway,
despite being demonstrably already in front of the session (they were even cited correctly,
from memory, elsewhere in the SAME session's own reasoning, just not cross-checked against
the specific lines being written).

**How to apply:** having read a memory file once earlier in a session is not the same as
re-checking it at the moment of writing the specific code it warns about. For any PR
touching `SoldierEnemyContact`/`_separate`/proximity-style contact checks, or any PR
touching `demos/demo.json`, grep this file for the relevant section NAME right before the
final push (not just recall it from earlier context) — a 10-second grep is cheaper than a
full review round. (`Lacaedemon/sparta` PR #1137, 2026-07-27.)

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

**Recurred, despite this exact entry already existing:** PR #1137's own new
`Unit._in_enemy_contact` proximity check shipped with `c_dist = attack_range + RADIUS +
u.RADIUS` -- only the QUERYING unit's own `attack_range`, the identical one-sided mistake
this entry already documents, in the same file's own memory the session had access to.
Caught by review, not self-caught. Fixed the same way: `maxf(attack_range, u.attack_range)`.
See "Even well-documented anti-patterns get re-violated under complexity/time pressure"
above for the broader lesson about re-checking memory at write time, not just recalling it
from earlier in the session. (`Lacaedemon/sparta` PR #1137, 2026-07-27.)

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

## FOUR distinct root causes behind "formation visibly spins" -- don't assume it's one bug

There are at least four separate mechanisms that each independently make a regiment's
soldier block visibly rotate or smear: two swirls discovered investigating #724 and #774 in
the same session (both unresolved as of this writing), a third -- the pre-contact
approach-march blob -- found and fixed later (#921), and a fourth, the LATE-WINDOW rotation
of a head-on locked melee, attributed under #1213. All show up as `facing` and the soldier
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

- **A FOURTH mechanism -- the late-window rotation of a head-on LOCKED melee (#1213,
  measured 2026-08-07):** two matched 100-soldier Infantry regiments clashing head-on with
  no orders rotate up to 58 deg by tick 700 on clean `main`. Attribution, by sampling
  between every stage of `Battle._on_soldier_tick` and converting each stage's effect into
  BEARING rotation of the inter-unit vector: `SoldierBodies.couple` carries -59.163 of the
  -59.16 total, and the whole `_physics_process` channel -- `_press_into` plus
  `Unit._separate()`, which also writes `position` (`:3396`, a capped displacement) --
  carries **0.002** between them. `couple` is only the conduit (it
  follows the bodies); the origin is a persistent one-signed TANGENTIAL differential
  velocity injected into the two body clouds, +2.82 from `SoldierEnemyContact` and +3.04
  from the body-integration step, against 0.00 from every other stage. That is the same
  suspect the #724 bullet above already names, reached independently on a different
  scenario -- so treat the two as likely the same underlying shear, not as separate finds.

**How to apply:** don't assume a "formation spins" report is the same bug as a previously
diagnosed one just because the symptom looks similar. Reproduce fresh with the SAME
cumulative-torque-instrumentation technique (temporary `print()`s in
`Battle._on_soldier_tick()`, one running total per stage, printed every N ticks -- always
revert before committing) to find which specific subsystem is the source for THIS
reproduction before assuming a fix that didn't work for one case will work for the other.


### Attributing a two-regiment orbit: measure the BEARING, not a fixed world axis

Four traps in the disconnect-and-drive-by-hand probe, each of which produced a confident
wrong answer during #1213 before the next one caught it. The first is the important one.

1. **Projecting onto a FIXED world axis is only valid at t=0.** In the #1213 clash the
   separation starts along +Y, which makes plain world-X displacement look like the whole
   signal. Once the bearing has rotated tens of degrees, world X carries a large RADIAL
   component. Measured that way `_press_into` appears to contribute +/-152 wu of exactly
   anti-symmetric displacement and reads as the dominant driver -- and it is not a driver at
   all. Attribute the bearing angle directly instead: `dtheta = cross(r_hat, dr) / |r|`,
   with `r` re-read immediately before each stage.
2. **Exact anti-symmetry is not evidence of a driver -- it is the signature of a CENTRAL
   pair, the one thing that cannot rotate anything (unless something breaks the symmetry --
   `_press_into`'s two INDEPENDENT `clampf` calls on `position.x`/`position.y` do exactly that
   against a field edge, though they never bind mid-field).** `_press_into(enemy.position)` aims at
   the enemy's centre, so it displaces both regiments along the line joining them and
   changes only the separation's LENGTH. The radial magnitude really is large (-1023 wu by
   tick 700 against couple's +937), which is exactly why it dominates a world-axis
   projection while the whole channel contributes 0.002 deg of rotation. Both figures are
   channel-scoped: `Unit._separate()` shares `_physics_process` and pushes centrally too, so
   neither the -1023 nor the 0.002 is `_press_into`'s alone.
3. **The torque proxy the #724 bullet above uses measures a different quantity.** It sums
   `cross(r_i, delta_v_i)` about each unit's OWN centroid, i.e. internal SPIN. What rotates
   a two-regiment orbit is the tangential DIFFERENTIAL velocity between the two clouds. Both
   are worth measuring; do not substitute one for the other.
4. **Two vacuity traps.** A cumulative DELTA on `_sim_steer` telescopes to ~0, because
   `SoldierSteering` clears and rewrites that array every tick -- so `SoldierSteering`/
   `SoldierMeleeStandoff`/`SoldierEncirclement` read a vacuous `0.00` and are not separately
   attributable that way (their effect folds into the integration step's own figure). And a
   battle that is not the FIRST in the process does not reproduce the trajectory: the same
   seed measured 28.55 deg as a second battle against 56.14 as the first, so a separate
   preceding CONTROL run is worthless and the control has to be the measured run's own
   value. The manual drive itself IS faithful once it is the first battle -- it reproduced
   the connected run's 56.14 exactly. That 56.14 is headless WINDOWS, and the 58 deg in the
   mechanism bullet above is the headless Linux figure recorded in #1213 for the same seed
   and tick; the gap is the local/CI divergence this file's own "precise-tick caption claim"
   section documents for a 700-tick 200-soldier melee, not a discrepancy in the measurement.
   Reproduce against 56.14 on Windows and 58.0 on Linux.

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

## FIXED: a fresh worktree's first `tools/check.sh test` run used to need a manual second import pass

**Fixed by `ensure_project_imported()` in `tools/check.sh`** (issue #1130, PR #1131, filed after
this bug was reported directly against a fresh `sparta-auto-review` worktree). `check_test()` (and
`check_coverage()`) now run Godot's `--import` themselves, right after `ensure_gut`, caching the
result under the `_project_imported` result key so a same-invocation `validate` isn't paid for
twice. `has_script_errors()` also now matches "class_names have not been imported" directly, and
both GUT-driving checks assert a `gut_ran_tests()` smoke check (GUT's own "Scripts   N" summary
line, N > 0) as a backstop independent of the import fix. A bare `tools/check.sh test` (or
`coverage`) in a brand-new worktree is now self-sufficient and no longer needs `validate` (or a
manual `godot --headless --import`) to run first.

Kept here as the historical record of the failure mode, since it recurred across many sessions
before the fix: `tools/check.sh test` vendors GUT on demand (clones into `addons/gut`) when a
fresh worktree doesn't have it yet, but Godot's `class_name` registration only happens during
project import. Without an import, the very first `tools/check.sh test` call in a brand-new
worktree used to fail with:

```
ERROR: Some GUT class_names have not been imported.  Please restart the Editor or run godot --headless --import
Missing class_names:  ["GutErrorTracker", ... "GutTest", ...]
```

`== summary == PASS test` / `All checks passed.` still printed -- the script didn't treat this as
a failure (none of `has_script_errors`' patterns matched the class_name-guard text, and nothing
checked GUT's own summary for a non-zero test count), so it silently reported PASS with zero
tests run. Hit repeatedly across many fresh worktrees during the 2026-07-09/2026-07-13 GIA
batch-cleanup and independent-verification passes, and again when reported directly as a bug.

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

## One failing test suppresses the whole `codecov/patch` signal -- and an absent check looks like one that has not run yet

The entry above assumes Codecov reported a gap and asks which lines.
This is the prior question: whether it reported at all.

A single failing test in `test-coverage.yml` costs two red checks AND the entire server-side
coverage signal, from one root cause that has nothing to do with coverage.
`-gexit` fails the "Run unit tests with coverage" step, and no later step carries
`if: always()`, so both "Verify coverage report was written" and "Upload coverage to Codecov"
are **skipped**.
The post-run hook has already written `coverage/lcov.info` by then -- the log says so in as
many words -- but nothing ever uploads it, so Codecov posts no status and no check run and the
PR simply has no `codecov/patch`.

It is silent in the direction that matters: an absent check is indistinguishable from one that
has not run yet, and nobody is told that coverage reporting was suppressed.
That also makes a local `tools/check.sh patch_coverage` run the only evidence available,
exactly when it is easiest to forget which instrument produced the number -- CLAUDE.md
documents that local run as matching Codecov's own figures, so it is a legitimate substitute,
but "patch coverage is green" is a claim about the wrong instrument if CI never computed it.

The decisive query is the job's per-step conclusions, not the job's own red status.
Confirm the absence itself against the paginated check-runs endpoint and the commit's statuses.
Prefer those over `gh pr checks` for a counting question, because its row count and the
endpoint's run count are not the same number: measured on PR #1210's head, `gh pr checks`
printed 12 rows where the endpoint returned 13 runs, the extra being a second run named
`claude / claude`.
Every distinct check name did appear in both, so on this repo the gap is a collapsed duplicate
name rather than a hidden check -- enough to make a count misleading, not enough to hide a
check outright:

```bash
gh api repos/Lacaedemon/sparta/actions/jobs/<job-id> --jq '.steps[] | "\(.name) => \(.conclusion)"'
gh api --paginate "repos/Lacaedemon/sparta/commits/<sha>/check-runs?per_page=100" \
  --jq '.check_runs[].name' | sort | grep -i codecov
gh api "repos/Lacaedemon/sparta/commits/<sha>/status" --jq '{state, n: (.statuses|length)}'
```

`skipped` on the upload step (rather than `failure`) is the tell that an earlier step's exit
suppressed it.

Generalizes past coverage: when a test fails in a job that also produces an artifact or uploads
to an external service, check whether the failure suppressed that side effect.
A job's red status describes its tests and says nothing about whether its *other* outputs were
produced.
This is the same shape as the `push_error()` bullet in `CLAUDE.md`, inverted: there the step
passes while the artifact is missing, here the artifact exists while the step that consumes it
never runs.

- **Do:** check the per-step conclusions of any red job that also uploads or emits an artifact,
  and treat a `skipped` publish step as a suppressed signal rather than a missing one.
- **Do:** say explicitly that a coverage number came from a local run whenever the `Coverage`
  job is red, since CI computed nothing.
- **Don't:** read an absent `codecov/patch` as "no patch-coverage gap" or as "still pending" --
  on a red `Coverage` job it means the upload never happened.
- **Don't:** report patch coverage as green on CI's authority when only a local run produced
  the figure.

(`Lacaedemon/sparta` PR #1199, 2026-08-05, head `a9fff0d8`: one failing test out of 2597
(`test_residual_melee_swirl_battle.gd`, a pre-existing mis-calibrated guard, tracked as issue
#1207) turned `Validate & test` and `Coverage` red as expected.
The unexpected part was `codecov/patch` never posting: the paginated check-runs list holds 16
entries and none is a Codecov one, and `commits/<sha>/status` returns
`{"state":"pending","statuses":[]}`.
That response carries no `contexts` field at all -- its array is `statuses`, exactly as the
recipe above queries.
An earlier revision of this entry named it `contexts`, which was a `jq` projection written by
the session that measured it (`--jq '{state, contexts:[.statuses[]|...]}'`) mistaken for the
API's own shape; caught in review.
Coverage job `92475169686` logged `Wrote lcov coverage for 77 files to res://coverage/lcov.info`
and then reported step 4 `failure`, step 5 `skipped`, step 6 `skipped`.
The claim "patch coverage is green" was made on this PR from a local run before the gap was
caught.)

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

## A new per-soldier physics quantity added alongside an already-correct pipeline should derive from that pipeline's OUTPUT, not recompute independently from raw inputs

PR #1143 (collision damage: converting a hard contact's dissipated kinetic energy into health
loss) shipped a first version that computed damage independently per contact pair, straight
from each pair's raw closing speed and effective masses -- a parallel calculation living
alongside (not reusing) `SoldierEnemyContact.accumulate`'s existing, carefully-engineered
velocity-impulse pipeline (the multi-pair torque-neutral trim, the per-tick `KNOCKBACK_SPEED_MAX`
cap). Review found the independent recompute had re-derived, and gotten wrong, THREE separate
properties the velocity pipeline already gets right:

1. **No cap across a soldier's simultaneous contacts** -- exactly the "Multi-pair force
   accumulation needs a write-back clamp, not just a per-pair cap" bug class documented earlier
   in this file, just on the new damage channel instead of the velocity one. The velocity
   pipeline has `body_trim_scale` + a final safety-net clamp specifically for this; the parallel
   damage formula had no equivalent.
2. **No memory across ticks during a multi-tick arrest** -- exactly the "compounds ACROSS TICKS"
   bug class immediately above, again just on damage instead of velocity. A fast pair takes
   several ticks to fully arrest (the impulse pipeline caps velocity reduction at
   `KNOCKBACK_SPEED_MAX` per tick), but the damage formula recomputed the COMPLETE inelastic-stop
   energy from the CURRENT closing speed every tick, overcounting total damage ~1.4-2x for a
   realistic charge -- decision-changing in the worked example (a soldier who should survive at
   14 HP instead died).
3. **A mass-weighted split that inverted the intended asymmetry** -- the formula split a shared
   total by `jn^2/mass_i_eff`, which the reviewer derived (and verified numerically against real
   game constants) makes a BRACED/HEAVIER defender take MORE absolute damage against a much
   heavier attacker, not less -- opposite of what bracing is supposed to do, and opposite of the
   PR's own website prose.

**Fix:** derive damage from each soldier's ACTUAL, already-resolved velocity change this tick --
read `owner._sim_body_vel[slot]` (after the existing multi-pair trim and per-tick cap have run)
minus the pre-tick snapshot -- instead of an independent formula from raw closing speed and
mass. This fixed all three findings AT ONCE, not as three separate patches: the multi-pair cap
and the per-tick bound come along for free since they're the SAME bounded number the velocity
pipeline already computed, and the bracing direction self-corrects because a heavier/braced body
already receives a smaller velocity change from the same contact (`enemy_contact_impulse`'s own
effective-mass split) -- so `damage = SCALE * delta_v^2` automatically gives it less damage too,
with no separate asymmetry formula left to get backwards.

**How to apply:** when adding a NEW per-soldier physics quantity (damage, stamina drain, a
cosmetic effect) that logically depends on the SAME contact/impulse an existing pipeline already
resolves, check first whether that pipeline's OUTPUT (its final, already-bounded per-body delta)
can be read and reused, rather than writing a second formula from the same raw inputs the
pipeline itself consumes. A parallel recompute doesn't just risk bugs the original pipeline
already solved (multi-pair caps, cross-tick memory) -- it risks re-deriving the WRONG formula
for a property (like the mass-split direction here) the existing pipeline already encodes
correctly in its own math, and getting the two implementations to agree by construction is far
more reliable than getting them to agree by careful parallel tuning. (`Lacaedemon/sparta` PR
#1143, 2026-07-28.)

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

**A subtler variant of the same mistake: running the check against uncommitted edits
when a PRIOR commit's diff is already on the branch doesn't fail loudly at all --
it silently reports against the stale prior commit instead.** The "no GDScript changes
in this diff" message above only fires when HEAD has no diff against the base AT ALL
(a brand-new branch with nothing committed yet). Mid-PR, after several review-fix
rounds, HEAD already has a real diff from earlier commits -- so re-running the bundled
check against a NEW uncommitted edit (a further review-fix, made without committing
first) doesn't produce an obvious "nothing to check" signal. It just silently
evaluates the OLD diff (as of the last commit) and reports plausible-looking but
WRONG line numbers/coverage percentages for code that no longer matches what's on
disk -- much harder to notice than the "no changes" case, since nothing looks broken
at a glance. Caught only by directly reading the file at the reported line number and
finding it didn't match the reported content. **How to apply:** treat "commit before
running the bundled check" as absolute, not just for a check's very first run on a
branch -- re-verify with `git status --short` immediately before EVERY invocation of
`tools/check.sh comments/units/patch_coverage`, not just the first one in a PR's
review-iteration loop, especially when working through several rapid review-fix
rounds where committing can get skipped in the rush to re-verify quickly.
(`Lacaedemon/sparta` PR #1063, 2026-07-23: a review-fix round for #1047 ran the
bundled check against an uncommitted `UnitCardTray.gd` edit; the report named a
"missing" line whose reported content, when checked, was `_on_placement_toggled`'s
body from the OLD committed diff, not anything in the actual uncommitted edit.)

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
separate times across three different PRs (#1051, #1053, #1054) -- each
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

## A Control anchored to a corner with a KNOWN fixed size should set explicit offsets, not `.position=`

`scripts/HUD.gd`'s own `_settings_panel_raise()` doc comment (renamed from
`_info_panel_raise()` by the same PR this entry describes) documents that
`.position=` on an anchored Control "just works" ONLY because it's set once
during `_ready()`, before the CanvasLayer's real viewport size is
established (so `anchor * parent_size == 0` at that moment) — and warns that
calling it again later, once the real size is baked in, silently shoves the
Control far off-screen. There's a SECOND, distinct trap in the same
territory: setting `.position=` once at `_ready()` time, then ALSO setting
`custom_minimum_size` on the same Control right after, for a corner anchor
where BOTH the width and height are already known up front (not
content-derived).

**Concrete case:** moving the unit card tray from center-bottom to
bottom-right (#1049), the new build code mirrored the `_ctrl_bar`/
`_legend_panel` pattern — `set_anchors_preset(PRESET_BOTTOM_RIGHT)`, then
`.position = Vector2(-14, -14)`, then `custom_minimum_size = Vector2(500,
0)` — and the tray ended up rendering almost entirely OFF the right edge of
the screen, with only a ~15-20px sliver visible; confirmed via a direct
screenshot, not caught by any unit test (GUT's headless dummy renderer
never surfaces a rendered-position bug like this — see the "How to apply"
note below). The `_ctrl_bar`/`_legend_panel` precedent this pattern
was copied from never sets an explicit `custom_minimum_size` on the
anchored Control ITSELF (only on a child, or not at all) — they rely
entirely on the Control's own natural content size, which `.position=`'s
"resolve against size-0-at-_ready()-time" trick tolerates because there's
no OTHER competing size assignment landing after it.

**Fix:** for a corner-anchored Control whose full size is known up front
(a fixed-width tray, a fixed-size panel), set `offset_left`/`offset_right`/
`offset_top`/`offset_bottom` explicitly instead of `.position=` +
`custom_minimum_size` — exactly the pattern the settings/info panels
already use elsewhere in `HUD.gd`. Explicit offsets are unambiguous
regardless of assignment order or when the CanvasLayer's real viewport size
becomes available; `.position=` is only safe when nothing else touches the
Control's size afterward.

**How to apply:** before copying the `.position=`-based corner-anchor
pattern to a NEW Control, check whether that Control also needs an
explicit `custom_minimum_size` (or any other size-affecting property) set
after the position — if so, use explicit offsets instead. And always
confirm a new/moved HUD panel's ACTUAL on-screen position with a real
screenshot (a throwaway tool scene + `--rendering-driver opengl3`, per
"Throwaway tool-scene screenshots" in `sparta-demos.md`) before considering
a layout change done — a GUT test asserting anchor/grow-direction
properties (as `test_hud_layout.gd` does) proves the CONFIGURATION is
correct but says nothing about where the Control actually renders.
(`Lacaedemon/sparta` PR #1057, 2026-07-23.)

## When moving a HUD panel to a new corner, re-check its collision footprint against EVERY other panel, not just the one obvious neighbor

Rearranging where panels sit (#1049: distance legend, info panel, settings
panel, and unit tray each moved to a different screen margin) can introduce
TWO independent kinds of new collision that are easy to miss by only
reasoning about the panel you're actively moving:

- **A panel you moved now shares a corner with something that was already
  there.** Moving the distance legend to top-left put it directly on top of
  the frame-rate counter's DEFAULT corner (`Settings.fps_corner` defaults to
  `FPS_CORNER_TOP_LEFT`, chosen specifically because nothing else lived
  there — a comment in `Settings.gd` said so explicitly, and went stale the
  moment the legend moved in without anyone updating it). This wasn't the
  legend's own move breaking something about ITSELF — it broke a completely
  different, unrelated feature's implicit assumption about that corner
  being free.
- **A panel's own growth/reach calculation doesn't account for a NEW
  neighbor sharing its column/row.** The info panel's `grow_vertical =
  GROW_DIRECTION_BOTH` symmetric-growth budget (`_info_panel_available_height()`)
  was computed purely against the raw screen edges, with no reference to
  the settings panel (bottom-left) or legend (top-left) now sharing its
  same `offset_left = 14.0` column. A tall enough stat sheet could grow
  down into the settings panel or up into the legend — confirmed
  mathematically (not just eyeballed) by an existing test that already
  exercised a 200-line stat sheet pinning to the (wrong) 680px ceiling.
  Fixed by having the growth-budget function actively query each
  sibling's live footprint (`_legend_panel.position.y +
  get_combined_minimum_size().y`, `_settings_panel.get_combined_minimum_size().y
  + _ctrl_bar_clearance()`) rather than a screen-edges-only constant.
  A similar tray-vs-control-bar collision (the control bar reaches far
  enough from screen center at the default 1280px width to overlap the
  bottom-right tray) was ALSO found this same way — by direct screenshot,
  not by reasoning about the numbers ahead of time.

**How to apply:** after any HUD panel reposition, don't just verify the
moved panel's own rect looks right — grep the file for every OTHER
Settings-driven or dynamically-sized element (default corners, growth
budgets, raise/lower clearances) and ask whether it implicitly assumed the
old layout. A real before/after screenshot (not just a description of the
intended positions) is what actually catches these — both collisions in
this PR were found by a human/reviewer looking at an actual rendered frame,
not by static code review of the anchor math. (`Lacaedemon/sparta` PR
#1057, 2026-07-23.)

## A throwaway (non-GUT) Godot process also contaminates the real `settings.cfg` — not just GUT test runs

The existing "Settings.gd setters persist to the REAL user://settings.cfg
in tests" entry above covers GUT test runs calling a `Settings.*` setter.
The SAME contamination happens from a throwaway tool-scene script (`godot
--rendering-driver opengl3 res://tools/demo/_shot_*.tscn`, per the
screenshot-capture recipe) that directly sets `Settings.show_unit_card_tray
= true` (or any other setter) to force a UI element visible for a
screenshot — it's a REAL game process, not a sandboxed test run, so the
setter's own `_save()` call writes straight to the actual
`user://settings.cfg` on disk, exactly like a real play session would.

This bit silently: a `show_unit_card_tray defaults to false` GUT test
started failing in a LATER, unrelated check.sh run, with no connection
visible in the test's own diff — root-caused only by remembering an
earlier screenshot-capture step in the SAME session had set that setting
directly. (`Lacaedemon/sparta` PR #1057, 2026-07-23.)

**How to apply:** after running ANY throwaway tool scene that touches
`Settings.*` (directly, or indirectly via a UI interaction the scene
simulates) for a screenshot or manual verification, delete
`user://settings.cfg` (path is machine-specific — see the "shared ACROSS
worktrees" entries above for how to find it) before trusting the NEXT
`tools/check.sh test`/`patch_coverage` run's results, or diff the file's
`show_*`/`tray_row_order_placement`/etc. values against known defaults
first. Prefer avoiding the setter path entirely when the scene doesn't
need real persistence: mutate whichever downstream field the setter would
have set instead (e.g. call `hud._sync_unit_card_tray_visibility()` after
setting `Settings.show_unit_card_tray` inside `Settings._loading = true` /
`= false` guards, matching the pattern `test_hud_unit_card_tray.gd`
already uses to force a known starting state without persisting it).

## A two-pass same-seed determinism test needs the tree PAUSED across `add_child`, or the two passes start one body-step out of phase

A GUT test that instantiates `scenes/Battle.tscn` **twice** with the identical
seed/scenario (to prove the sim is deterministic — no leaked global static,
no stray RNG draw) can still see the two passes' per-tick state diverge by a
sub-pixel amount at the same tick number, even with every known global sim
static (`PathField.active`, `SoldierEnemyProximity`, etc.) correctly reset
between passes. The cause isn't a leaked static at all: whether
`_on_soldier_tick` (which steps the soldier bodies) fires on the SAME frame
as the first `_physics_process` call (which advances `_tick`) is a startup
phase race against the engine's own node-ready scheduling — so one pass can
get a body-step and a tick-increment on the same frame while the other gets
them a frame apart, leaving the two passes permanently one body-step out of
sync relative to `_tick` even though both started from byte-identical state.

**Fix:** pause the tree, `add_child(_battle)`, await one `physics_frame` (the
armies spawn; nothing steps while paused — `_physics_process` doesn't run at
all under pause, and the soldier tick early-returns), then unpause:

```gdscript
get_tree().paused = true
add_child(_battle)
await get_tree().physics_frame   # spawn the armies; nothing steps while paused
get_tree().paused = false
```

This gives both passes a single shared start line — the unpause, not
whatever frame `add_child` happened to land on — so the tick-increment and
body-step both begin in lockstep in both passes. Apply this any time a test
needs two (or more) `Battle` instances, run sequentially or otherwise, to
produce genuinely comparable per-tick state — not just the lockstep A/B
sim-hash instrument this was found for, but any future test built the same
way. (`Lacaedemon/sparta` PR #1068 / issue #1067, 2026-07-24: diagnosed with
a throwaway per-unit diagnostic comparing body-step counts against `_tick`
across the two passes, not guessed.)

## Formation slot assignment is by ARRAY INDEX -- a recurring bug family, not a one-off

`UnitFormation.block_slots` maps soldier index `i` to grid cell `i` (`file = i % files`,
`rank = i / files`). Nothing in the reform path solves an assignment problem: there is no
nearest-slot pairing, no angular pairing, no minimum-travel matching anywhere. So any
reshape that changes `files` reassigns most soldiers to distant cells, and they walk there
under the normal bounded-arrival body steering -- physically correct motion toward a
geometrically arbitrary destination.

This has now produced the same visible defect four separate times. The first three were
each diagnosed and fixed only for their own maneuver; the fourth is still open: #541 (about-face swapped soldier identities, 0/40 held
position), #668 (countermarch reform swapped soldiers to the opposite flank rather than
just reversing rank order), #802 (target-slot reassignment cadence), and #1146 (the
NORMAL -> SQUARE reform: 28% of soldiers cross the centreline, mean travel 33.8 wu, about
2x the greedy-nearest-slot optimum, on a block only 90 wu wide once squared).

**Before assuming a given reshape is safe, check whether its path has its own pairing
logic or falls through to raw index order.** `Unit.formation_slots()` is the dispatcher.
The square branch is bare `block_slots(...)`. The file-major branch preserves a persistent
per-soldier file (`_sim_soldier_file`), which is the one real identity-preserving
mechanism in the file -- and it is deliberately OFF for squares, on the stated grounds
that `formation_files()` recomputes continuously as casualties shrink the live count so
there is no stable file to preserve. That rationale is sound for CASUALTY REFLOW and does
not transfer to a DELIBERATE RESHAPE, which is a discrete one-off event where a pairing
could be computed once and held. Don't let the docstring's reasoning talk you out of
checking the reshape case.

The right primitive already exists unused for this purpose:
`UnitFormation.sort_indices_by_angle()` pairs soldiers to ring slots by angle about the
centroid, described in its own docstring as lining up "each live defender with the ring
slot nearest its own actual side of the block" -- currently wired only into engaged-soldier
selection, not into any reform's slot assignment. #547 (explicit per-soldier slot
ownership) would subsume the whole family.

Verification technique for any fix here is the per-index, local-frame comparison described
under "The identity checks are real, but they are blind DURING a reshape" in
`sparta-demos.md`. The scan's identity metrics do exist and work, but they only judge a
SETTLED block -- and every one of these bugs reaches a correct end state by a wrong route,
which is why all four instances were caught by eye rather than by a check.

## One selector, two questions: reach answers "who can strike", geometry answers "whose body is shoved"

`Unit.engaged_soldier_indices()` derives its depth from `engaged_ranks()`, which scales with
the regiment's own WEAPON REACH. That is the correct answer to the question it exists for --
a spear phalanx really does project six ranks of points into contact, and all six deal and
take blows. It is the wrong answer to a question about BODIES, and reusing it for one is a
recurring trap: a sixth-rank spearman strikes past five ranks of his own men without anything
touching him.

The failure only becomes visible when a block is SHALLOWER THAN ITS OWN REACH DEPTH. A 40-man,
9-file spear regiment is 5 ranks deep against an engaged depth of 6, so every soldier lands in
the tier and any "the rest of the block is the unengaged bulk" assumption silently evaporates.
`SoldierBodies.step()` had exactly that assumption baked in -- an engaged body drops the march
feed-forward and is re-paired onto a canonical target slot, both meaningful only RELATIVE to a
bulk still tracking the formation's own slots. With no bulk left, every body free-floats under
continuous contact impulses while its slot identity is globally re-sorted by lateral position,
so rank/file order churns indefinitely instead of recovering (soldiers visibly sliding sideways
through a sustained melee).

Fixed by `body_tier_soldier_indices()` / `body_tier_ranks()`: same gate, same geometry, but
depth = how many ranks one body DIAMETER spans at this formation's own rank pitch (1 at the
standard 0.45 m pitch; 2 for SHIELD_WALL/TESTUDO, which compress below a body width; 1 for
cavalry's roomy 3.0 m pitch). Derived from constants the soldier layer already scales off, so
no tuned number.

**How to apply:** before consuming `engaged_soldier_indices()` in a NEW caller, ask which
question that caller is really asking. If it is about physical contact, crowding, or body
motion -- not about who can land a blow -- it wants a geometry-derived depth, and it needs its
own selector. This is the same class of bug PR #1137 fixed one layer over (a combat selector,
`is_engaged()`, silently gating physical collision), so it has now bitten twice; expect a third
site. Note also that two tuned alternatives were tried and rejected on measurement first --
"leave one rear rank as bulk" barely moved the churn, and "cap at half the block depth" fixed
one unit but not the other -- only the geometry derivation landed symmetrically.

## Capping a selection must narrow WITHIN the meaningful candidate set, never re-select over the whole population

When adding a size cap to a selection that already computed a MEANINGFUL candidate set, apply
the cap to that set. Falling back to a fresh ranking over the whole population is a different
answer, not a smaller one.

Concretely: `Unit._select_near_front_indices()`'s Square/Schiltron branch computes `threatened`
(soldiers with an enemy actually in reach). A first cut handled the capped case by falling
through to `UnitFormation.live_perimeter_indices()`, which ranks purely by distance from the
block's own centroid -- i.e. the corners -- with no reference to enemy position at all. For a
pressed square that is the ORDINARY case, not an edge case (a 100-soldier square caps around
`ceil(sqrt(100)) = 10` while a one-sided press typically threatens 30-40), and it returns
soldiers with nothing near them while dropping soldiers genuinely in contact -- inverting the
selection's own meaning and breaking the body-tier subset engaged-tier invariant.

Fixed with `UnitFormation.most_exposed_among(positions, candidates, target_count)`: ranks by
exposure WITHIN the candidate set, centroid still taken over the whole block (the subset filters
who may be picked, it does not move the middle). `live_perimeter_indices` delegates to it, so
there is one heap selection rather than two copies.

**How to apply:** any time a bounded and unbounded caller share a selection function, check that
the bounded path returns a SUBSET of what the unbounded path would. If it can return something
the unbounded path would never return, the cap is re-selecting rather than narrowing. Caught by
review, not by the implementation or its first test -- see the vacuous-test entry below for why
that test did not catch it either.

## A guard test can be vacuous ONLY under full-suite ordering -- single-test runs can hide it

The standing habit of reverting a fix to prove its test bites has a failure mode worth naming:
the test can fail correctly in a SINGLE-TEST run and still pass in a FULL-SUITE run, because a
frame-keyed static cache served it another test's data. So "I reverted and it failed" is not
sufficient evidence unless the revert was run the same way CI runs it.

Concretely: a new test for the square capping path above passed against the reverted fix in a
full `test_unit.gd` run, while failing correctly when selected alone. Root cause was the already
documented hazard above -- `SoldierEnemyProximity` is keyed by `Engine.get_physics_frames()`, so
a synchronous test inherits whatever grid the previous test built, and the enemy this test
staged was never in it, leaving `threatened` empty and the capped branch unreached. Adding
`SoldierEnemyProximity.reset()` made it fail against the bug in BOTH modes (4 failures, indices
33/43/44/54, matching an independent probe's prediction of exactly 4 leaked soldiers).

**How to apply:** run the revert check the way CI runs the suite, not just with `-gunit_test_name`.
A guard that only bites in isolation is not a guard. Also add a positive sanity assertion that the
branch under test is genuinely reached (here `assert_gt(melee.size(), u.body_tier_cap(n))`), so the
test cannot quietly go vacuous later when geometry or constants shift. Note this hazard's own
`reset()` rule was ALREADY documented in this file and still got missed while writing a fresh
test -- treat "does this test construct fixtures that a frame-keyed cache reads?" as a checklist
item on every new test, not a thing to recall.

## A caching fallback outlives the window that produced it -- never commit a placeholder as an answer

A lazily-rebuilt per-soldier assignment (the `_ensure_*_assignment` family) guards its rebuild
on a committed key: `if _sim_soldier_square_slot.size() == count and _square_slot_files == files:
return`. If the rebuild has a fallback branch for "the inputs could not be read this tick," and
the function commits the key unconditionally afterwards, the fallback **satisfies the guard
forever after** -- the placeholder is never reconsidered, long after the condition that produced
it has passed. The bug is not the fallback; it is committing the key on the fallback path.

Shipped and caught in review on PR #1158: `_ensure_square_slot_assignment` fell back to
`identity_assignment` (the exact pre-fix layout the PR existed to remove) whenever
`_slot_frame_positions` returned empty, then set `_square_slot_files = files` regardless. A
settled square hit that window on its first melee strike and stayed on the index-order layout
for the rest of its life -- strictly worse than the bug being fixed, and in exactly the
anti-cavalry scenario the PR targeted.

**How to apply:** any lazy-rebuild function with both a real path and a degraded path must commit
its freshness key only on the real path (`_square_slot_files = files if not live.is_empty()
else -1`). Leaving the key invalid costs a recompute per tick until the inputs are readable
again, which is the correct trade: a cheap repeated attempt beats a permanent wrong answer.

## There are TWO casualty paths and they have opposite array-sync semantics

Easy to miss, and it makes a whole class of test structurally unable to reach a whole class of bug:

- **Per-soldier path** -- `SoldierMelee.reap()` splices every per-soldier array at the dead man's
  index, so `soldiers` and the arrays stay in sync, and per-soldier identity survives.
- **Regiment path** -- `UnitCombat.take_casualties` (`scripts/UnitCombat.gd`) does `u.soldiers -=
  total` and touches NO per-soldier array. It never says which man died. `SoldierBodies.step`
  then queries `soldier_world_slots(unit.soldiers)` BEFORE resizing `_sim_soldier_pos` to match
  later in the same call, so there is a guaranteed window where the body layer is LARGER than the
  live count.

The regiment path is not an edge case: the per-soldier path is gated on `is_engaged()`, a latch
that arms one tick after `FIGHTING` starts, so the **first strike of every fresh contact** goes
through the regiment path (as does every strike for a ranged unit in melee, plus `absorb()` and
`disengage_with_sacrifice()`).

**How to apply:** any new per-soldier state must be correct across BOTH paths, and a test that
only drives `SoldierMelee.reap()` proves nothing about the regiment path -- it is the one path
that keeps the arrays in sync, so it cannot reach a desync bug at all. Drive the regiment shape
explicitly (drop `soldiers` with the body arrays left untouched, then step) as its own test.
Note also that a body layer larger than `count` is real data, not a fault: `resize()` trims at
the tail, so the leading `count` entries are exactly the survivors, still index-aligned.
(PR #1158.)

## Never pin a benchmark number in PR prose -- the comment updates in place

The `sparta-benchmark` PR comment is rewritten in place on every push, so any figure copied out
of it into a PR description, a commit message, or a review reply goes stale silently and reads
as a live measurement. Worse, the run-to-run spread is large enough that the number was never
meaningful: across three pushes of essentially identical code on PR #1158 the same comment
reported **-7.0%, -0.2%, and -1.8%** against the same baseline -- the CI-runner variance
`tools/benchmark/baseline.json`'s own `_comment` already documents.

Quoting one of those produced a wrong claim in the PR description (caught by review), and then a
wrong correction of the correction. **Describe the result qualitatively ("neutral, inside the
threshold") and point at the live comment** rather than freezing a figure. Reserve actual numbers
for a same-machine local before/after comparison, which is the only form that controls for runner
noise.

## GitHub Actions does NOT follow a repo-transfer redirect for `uses:` -- and `gh api` DOES, which hides it

When the shared CI repo moved from `d-morrison/gha` to `Morrison-Lab/gha` (2026-07-28), every
sparta workflow calling a gha reusable workflow broke at once, repo-wide, on every push. The
failure signature is distinctive and easy to misread:

- The run **fails instantly at startup**: zero jobs scheduled, `created_at == updated_at`, and no
  check-run annotations to read (`gh run view --log-failed` reports "log not found").
- `gh run list` shows the run's name as the raw **`.github/workflows/x.yml` path** instead of the
  workflow's own `name:` field -- the tell that GitHub could not resolve the workflow at all.
- `gh run rerun` refuses outright: *"cannot be rerun; its workflow file may be broken."* A
  startup-failed run needs a **fresh trigger** (a push, or close/reopen); it can never be re-run
  in place.

**The trap that cost the most time:** `gh api repos/d-morrison/gha` transparently follows the
transfer redirect and returns `"full_name": "Morrison-Lab/gha"`, and every content path still
resolves under the old owner. So a check of "does the reference still work?" via `gh api` says
YES while Actions says no. Actions is the only authority here. On the first occurrence this was
misdiagnosed as a transient migration window and reported as self-healed; the very next push
failed identically, which is what forced the real diagnosis.

**How to spot it:** if several unrelated workflows fail at startup simultaneously, check what
they have in common -- here, every failing workflow was an external `uses: <owner>/<repo>/...`
caller and every passing one was self-contained. Confirm repo-wide (not PR-specific) by listing
one workflow's runs across all branches and finding the timestamp where success turns to failure.

**Fix:** retarget the references to the new owner, keeping the `@vN` pin, and verify every
distinct referenced path resolves at the new owner's tag before pushing. The consuming repo's own
CI is the real test -- if the previously-dead workflows schedule jobs and report their real names
again, the diagnosis and the fix are both confirmed. (sparta #1159/PR #1160: 11 call sites.)

**A still-open PR branch cut BEFORE the retarget carries the stale refs itself, and `gh run
rerun` reproduces the failure rather than recovering from it.** `main` being fixed does not help a
branch whose own `.github/workflows/` still says `d-morrison/gha`: every fresh trigger on it
startup-fails with zero jobs scheduled, no logs, and no annotations, and re-running that branch's
last SUCCESSFUL run on the same head startup-fails too -- which makes it look intermittently
broken rather than deterministically so. The fix is to merge `main` into the branch. Diagnose with
`git merge-base --is-ancestor <retarget-commit> <branch>` and confirm with
`git show <branch>:.github/workflows/<wf>.yml | grep uses:` (on Windows Git Bash that needs
`MSYS_NO_PATHCONV=1`, or the revision:path argument gets mangled into a Windows path).
(`Lacaedemon/sparta` PR #1135, 2026-07-29: stuck five review rounds, and the sixth could not
be triggered at all
until `main` was merged in -- after which the review ran normally and passed.)

**Related gotcha:** a PR that edits `claude-code-review.yml` makes the `@claude` review self-skip
by design (every step reports `skipped`; the action 401s validating a workflow file from a PR
ref). That is the benign skip, NOT a stub review -- read the run's step list to tell them apart.
Combined with Copilot being quota-exhausted, such a PR can have no automated verdict at all, in
which case the standing rule applies: do the review yourself and post it before merging.

**The account move was not limited to `gha` -- `ai-config` followed, and the thing that
actually breaks CI is the MARKETPLACE NAME, not the URL.** `d-morrison/ai-config` moved to
`Morrison-Lab/ai-config` the next day (2026-07-29) and, in the same move, its
`.claude-plugin/marketplace.json` renamed the marketplace itself from `d-morrison` to
`Morrison-Lab`. Those are two independent changes, and only the second one is fatal: git and
`gh` both follow GitHub's transfer redirect, so the marketplace CLONE still succeeds from the
old URL -- but a plugin ref is resolved by the marketplace's DECLARED name, which no longer
matches. `review / claude-review` then dies at plugin install, before reviewing anything:

```
Action failed with error: Failed to install plugin 'ai-config@d-morrison' (exit code: 1)
Claude review did not complete successfully and was not eligible for a stub-review retry
```

`review / require-review` fails with it, and it is required -- so the whole repo is
unmergeable. The signature differs from every other review failure documented above: the job
posts **no review comment at all**, so there is no stub body to read and no verdict to
mistake for one.

**The fix is NOT in this repo's `.claude/settings.json`.** That file's marketplace
registration governs LOCAL Claude Code sessions only; the review job never reads it. The
plugin ref the job installs is hardcoded as a built-in default in the reusable workflow
(`Morrison-Lab/gha`'s `claude-code-review.yml`, its `use-ai-config` input). A caller
overrides it with the trio `use-ai-config: false` plus `plugin-marketplaces` /`plugins`
naming the marketplace's current name -- and the workflow's own docs warn that the name
"must match the name that marketplace declares in its own .claude-plugin/marketplace.json --
it is not derived from the URL". Retargeting `settings.json` is still correct for local
sessions, it just fixes a different thing; the first attempt at this fixed only that and the
review failed again identically, with the error still naming the OLD `ai-config@d-morrison`
even though the PR's own settings.json said `Morrison-Lab` -- which is the tell that the ref
comes from upstream, not the checkout.

**Generalize rather than patching one repo at a time:** when ANY repo under a consumed
account moves, grep your own repo for **every** reference to that account -- `uses:` refs,
marketplace sources, submodule URLs, prose links -- and then check whether the moved repo
also renamed anything a consumer resolves BY NAME rather than by URL. Distinguish real repo
paths from lookalikes: a `reviewer: d-morrison` workflow comment is a GitHub **username**
(unaffected by a transfer), and `website/_extensions/d-morrison/equation-anchors/` is a
Quarto extension install path that only changes via a Quarto reinstall. Note also that a PR
editing `claude-code-review.yml` makes the review self-skip by design, so a fix applied there
cannot verify itself -- confirm it on the NEXT PR's review run instead.
(`Lacaedemon/sparta` #1171/PR #1172, 2026-07-29: caught when the first PR pushed after the
move failed review; the last green run was 30 minutes earlier.)


## A PR-description edit can duplicate the CI-managed demo block

`demo-video.yml` upserts its clip into the PR **description**, between `<!-- sparta-demo -->` and
`<!-- /sparta-demo -->`. A programmatic description edit that disturbs the whitespace around those
markers makes the next upsert fail to match, so it **appends a second block** instead of replacing
the first -- leaving a superseded commit's GIF live alongside the current one, rendering as two
"Gameplay demo" sections.

After any `gh api .../pulls/N -X PATCH` on a body, check `grep -c '<!-- sparta-demo -->'` is
exactly 1 and that no superseded SHA remains. When rebuilding a body programmatically, capture the
block with a regex and re-append it verbatim, newlines included.
(`Lacaedemon/sparta` PR #1135, 2026-07-29.)

**That check has to run again after the NEXT demo workflow completes --- immediately after your
own PATCH it passes even when the damage is already done.** The duplication is not something your
edit writes; it is something `demo-video.yml` writes later, when its next upsert fails to match
the markers you disturbed and appends a second block instead of replacing the first. So the
sequence is: you edit, you check, the count is 1 and the check looks satisfied, and the second
block appears minutes later on the next push or re-run.

Concretely, the count is a lagging indicator of an edit you already made, so treat a passing check
immediately after a PATCH as establishing nothing. Re-read the body once the demo job for the
following push has finished --- or simply before reporting the PR ready, which is the moment the
description gets read anyway:

```bash
gh pr view <N> --json body --jq .body | grep -c '<!-- sparta-demo -->'   # expect 1
```

Repairing it is a dedupe rather than a rewrite: strip every block with a regex, then re-append the
**last** one verbatim, since that is CI's most recent upsert and the earlier copies are stale.
Confirm afterwards that whatever else you had added to the body (an embedded image, a corrected
claim) survived the strip --- the naive `re.sub` that removes the blocks will happily remove
anything you nested between them.

(`Lacaedemon/sparta` PR #1196, 2026-08-07: a description edit adding a required UI screenshot and
correcting two stale claims was checked immediately afterwards and read exactly 1 block. The
round-5 review then found 2, from CI's own re-upsert in between. The rule above was followed to
the letter and still missed it, which is why the timing needs saying rather than the check.)

## An `.import` diff that reads as deletion is a headless-Godot rewrite, not a removal

`.jules/bolt.md`'s own 2024-11-20 entry already says to revert `.import` sidecars a headless run
regenerated. The tell is easy to misread: in `--stat` and in `gh pr view --json files` the churn
shows as `0+ 6-` per file -- pure removals, which reads as *deleted files*. They are not deleted.
They are modified, losing engine-version-specific keys (`compress/uastc_level`,
`process/channel_remap/*`). Confirm with `--diff-filter=D` (returns nothing) before describing
them as deletions, and restore with `git checkout origin/main -- <paths>`. (Misdescribed twice on
`Lacaedemon/sparta` PR #1165 before checking, 2026-07-29.)

## Grep `main` before stripping a "noise" pattern a PR appears to introduce

Before removing a stylistic pattern a PR adds -- a narration comment, a redundant annotation --
`git grep` it on `origin/main` first. On `Lacaedemon/sparta` PR #1165 three
`# OPTIMIZATION: ...` comments looked
like that PR's own noise; 17 identical ones were already on `main` from earlier merged work.
Stripping only the PR's three is inconsistent, and stripping all 20 drags eight unrelated files
into a PR whose whole purpose at that moment was being minimal -- the exact collateral-scope
problem being criticised on that same PR. Leave the pattern and note it, or raise it as its own
sweep. (2026-07-29.)

## A report-generating workflow's data-gathering step needs `continue-on-error` plus `if: always()` downstream -- and a salvaged partial report must say so

A scheduled workflow whose whole deliverable is "a durable signal posted every week" is
defeated by the default GitHub Actions behaviour that a job stops at its first failing
step. If the data-gathering step can fail on one bad input out of many, and the
report-posting steps have no `if: always()`, then a single flaky input costs the entire
run's report -- with no diagnostic beyond a red scheduled run nobody is watching.

This is easy to ship because the *consuming* script is often written to handle missing
data gracefully, which makes the pipeline feel robust when it is not. `website/tools/
dump-demo-states.sh` `exit`s at the first clip that fails, times out, or writes no
snapshots (only two genuinely-skippable cases `continue`), leaving every later clip
undumped. The sweep script consuming it buckets a missing transcript as a `no transcript`
finding rather than something fatal -- but that bucket was unreachable for exactly the
failure it was written to describe, because the job never reached the sweep step.

**The second-order trap, which the obvious fix alone does not cover:** because the dump
aborts at the FIRST bad input rather than skipping it, everything after that point is
missing too. A salvaged report therefore renders as a wall of "no data" rows that read
like a mass regression rather than absent data. Thread the gathering step's own
`steps.<id>.outcome` into the report and prepend a warning when it is not `success`, so a
partial run is legible as partial. Verify by simulating the report body for both outcomes,
including that the success path renders identically to before.

(`Lacaedemon/sparta` PR #1175, 2026-07-29: caught in review, not by the implementation.)

## Extract a workflow's `run:` blocks and `bash -n` them -- valid YAML does not imply valid shell

Parsing a workflow as YAML proves the file's structure, not that the shell inside each
`run:` block is syntactically valid. Extract every `run:` body, stub the GitHub
expressions (`re.sub(r'\$\{\{[^}]*\}\}', 'EXPR', run)` -- they are not bash and will
fail the check spuriously), write each to a file, and `bash -n` it. On Windows write those
files to a RELATIVE path in the worktree: a Python `tempfile` path hands bash a
backslashed Windows path it silently mangles into "No such file or directory", which reads
as a syntax failure.

The same pass also catches a distinct and nastier failure: a generated block whose
intended backslash-n ESCAPES became REAL newlines. If any resulting line then starts at
column 1 inside a `run: |` block the YAML itself breaks -- a line beginning `>` (e.g. a
`> [!WARNING]` GitHub callout) is read as a block-scalar indicator, not text. Confirm with
`sed -n 'A,Bp' file | cat -A` that every line of the block is indented.

**The mechanism, which bit twice while writing this entry.** A doubled backslash inside a
shell heredoc that feeds Python collapses to a SINGLE backslash before Python parses it,
so `\\n` arrives as `\n` and Python turns it into a real newline. The tell is a
`SyntaxWarning: invalid escape sequence` on a sibling sequence: `\\$` survives as `\$`
precisely because it is not a valid Python escape, while `\\n` silently does not. To emit a
literal backslash-n through that path, build it from `chr(92)` (or quadruple the backslash),
or reword to avoid the literal entirely -- do not trust a doubled backslash to survive.

(`Lacaedemon/sparta` PR #1175, 2026-07-29: a warning-callout `printf` broke the workflow
this way; the YAML parse caught the column-1 case and the extraction pass confirmed the
repair.)

## The no-issue-numbers-in-comments rule does not cover generated issue/PR body text

CLAUDE.md's "Comments: no issue-number references" rule is scoped to code comments -- its
own rationale is that "a reader shouldn't need to open a tracker to understand the code"
-- and it explicitly allows issue numbers in commit messages, PR descriptions, and
`TODO`/`FIXME` markers. A workflow step that BUILDS a tracking-issue body is producing
tracker-facing content, not a code comment, so a cross-reference there is appropriate and
has direct precedent: `godot-ci.yml`'s own failure-issue `printf` cites the issue that
motivated its check. A reviewer flagging such a line is worth rebutting rather than
complying with; this rebuttal was accepted on re-review after the reviewer independently
confirmed the precedent.

The rest of the rule still bites, and this file already records it recurring. When a review
flags it, **grep the whole diff** (`grep -n '#[0-9]\{3,4\}'` over every changed file)
rather than patching only the flagged lines -- that is how the code-comment instances and
the legitimate issue-body one get correctly separated in a single round instead of two.

(`Lacaedemon/sparta` PR #1175, 2026-07-29.)

## `tools/check.sh file_length` is scoped to `scripts/*.gd` -- new `.sh`/`.yml` files are not capped

`check_file_length`'s `SPARTA_CHECK_MAX_NEW_FILE_LINES` budget (default 100) applies only
to files ADDED under `scripts/` with a `.gd` extension -- deliberately not `test/`, and not
shell or workflow files. A CI/tooling PR adding a 115-line script and a 117-line workflow
passes it untouched, reporting "No new scripts/*.gd files in this diff". Worth knowing
before restructuring a new tool to fit a budget that does not apply to it.

## A stubbed fixture built from your own premise tests the code, not the premise

The two entries above cover verifying a bug's stated ROOT CAUSE, and verifying that a fix
engages the reported bug's real CODE PATH. This is the third member of that family, and it
bites when the thing under test is CI tooling rather than sim code: when you stand up a
stub or a fixture to exercise a script in isolation, the fixture encodes your model of the
system, so any assumption baked into it is exactly what the test cannot check. It returns
the answer it was built to return, and reads as a clean verification.

Two instances in one PR (#1180, closing #1179), both caught by review rather than by the
verification itself:

- **An unconstructible state.** The fix bounded the demo defect delta to ticks before two
  runs diverge, and a stub "proved" it worked by returning DIFFERENT failing metrics for the
  two sides inside that window. That state cannot exist: `div_tick` comes from
  `DemoStateHash.cheap_tick_hash`, which hashes each unit's `position` plus the whole
  `_sim_soldier_pos` byte array EVERY tick -- the same data the position metrics read -- so
  below it the two sides are bit-identical by construction. The bound did not narrow the
  comparison, it emptied it, and the one fixture row that fired was the one row reality
  forbids.
- **A filename format nobody writes.** The rework read a clip's last tick out of
  `state_<tick>.json` names, and the fixture created them as `state_8.json`. Both producers
  (`DemoInputRecorder.gd`, `DemoStateSink.gd`) write `state_%05d.json`, and bash reads a
  leading-zero numeral as OCTAL: `00900` raises "value too great for base" and, under
  `set -euo pipefail`, aborts the whole step, while an all-octal-valid `01260` silently
  evaluates to 688 and prints a plausible-looking wrong percentage.

**How to apply.** When a fixture stands in for real data, derive its shape from the PRODUCER,
not from memory or from the consumer's expectations -- open the code that writes the
filenames, emits the field, or defines the invariant, and generate the fixture the same way
(here, `printf %05d`). Then prove the fixture bites: run it against the unfixed code and
confirm it actually fails. A fixture that passes both before and after has told you nothing.
And when a stub asserts two things DIFFER, first check whether the system permits them to --
an impossible fixture is worse than no fixture, because it manufactures confidence.

## The regiment damage formula is load-bearing for the regiment ENGAGEMENT gate

Do not try to make the opening melee blow resolve per-soldier while the engagement
gate stays regiment-level. The two are entangled, and removing one without the other
replaces a violent bug with a silent one.

`UnitCombat.strike()` picks per-soldier resolution only when both sides pass
`is_engaged()`. Two independent ordering artifacts make the DEFENDER fail that test on
the exact tick contact is made, so the opening blow of every melee falls through to the
regiment damage formula -- where the damage number is used as an ABSOLUTE soldier count
(`take_casualties` does `u.soldiers -= total`):

1. **The latch arms a tick late.** `_physics_process` runs `_think()` -- where a unit
   enters FIGHTING and lands its first strike -- BEFORE `tick_engaged()` sets
   `_engaged_linger`. So an attacker is fighting but not "engaged" during its own first
   strike, even though `ENGAGED_LINGER`'s doc says a regiment is engaged "while FIGHTING
   and for ENGAGED_LINGER seconds after".
2. **`_in_enemy_contact` is stale for whoever has not run yet.** Each unit fills it in at
   the top of its OWN `_think()`. Units resolve one after another within a tick, so the
   unit that goes first strikes while its target still carries LAST tick's value. This
   ordering asymmetry is also why the loser takes 100% of the casualties: it is dead
   before it ever gets a tick of its own.

Fixing both does stop the wipe. But combat then never resolves at all: **400 ticks of
FIGHTING, zero casualties, both sides at full strength and morale 100**, with the pair
locked at a 28.30 wu centre gap. That is the load-bearing part: the regiment formula is
currently the only thing producing melee casualties on first contact, so removing it
without replacing it stops the fight rather than fixing it.

**The reason the per-soldier path then lands no wounds is NOT yet established -- do not
assume it is a reach shortfall.** Check the real numbers before theorising. Cavalry's
`attack_range` is **30.0 wu**, not the `@export` default of 26.0 that `Unit.gd` declares:
`Battle.gd` overwrites it per loadout (`u.attack_range = weapon_type.reach_m *
WORLD_UNITS_PER_METER`), and the Spatha's `reach_m` is 1.5 m at 20 wu/m.
`soldier_reach()` just returns `attack_range`, so per-soldier reach is 30.0 wu too, and
the regiment gate is `attack_range + RADIUS + enemy.RADIUS` = 30 + 18 + 18 = **66 wu**
(`RADIUS` is `0.9 * WU_PER_M` = 18). At a 28.30 wu separation the men are therefore
INSIDE reach, not outside it -- so "they cannot quite touch" does not explain the stall,
and whatever does is still open. (An earlier draft of this entry asserted exactly that
wrong explanation off the unused 26.0 default; caught by fact-checking the constants
rather than by any test.)

Either way the entanglement stands, and it is the deferred "retire the regiment circle"
work (#296), not an independent bug. Note #296 is **not** blocked on #783 any more --
that was the `SoldierBodies.couple()` averaging-dilution bug, fixed and closed by #784
on 2026-07-12. #296's own thread records the current blocker as a residual ~1-2 px
overshoot transient at first contact, which is still unfiled, and explicitly advises
against reusing #783's number for it.

- **Do:** sequence per-soldier casualties AFTER per-soldier engagement, and measure the
  post-fix battle far enough forward (hundreds of ticks) to prove casualties still accrue.
- **Don't:** remove or bypass the regiment casualty formula while the engagement gate is
  still regiment-level -- the fight silently stops instead of resolving.

**Instrument after the FIRST zero-effect result, not the third.** This file already says
a before/after showing no difference means the fix's path is not the one being exercised.
Two successive fixes here produced byte-identical output before the gate was instrumented;
a single `print()` of the gate's own operands then settled it in one run, showing
`u.eng=true e.eng=false e.inContact=false` -- the attacker half fixed, the defender half
not. A temporary print at the branch you believe you changed is cheaper than another
reasoning pass.

(`Lacaedemon/sparta` #1151, draft PR #1187, 2026-07-30. Reproduced with seed `40002`,
two 10-soldier Cavalry regiments: tick 94 gap 68.29 wu matching the issue's own figure,
one unit gone at tick 96 while the survivor kept full strength, full HP and morale 100.)


## `dump-state.sh` includes routers, and merges the script's own `state` ticks

Two things worth knowing before reading a state dump as evidence:

- **A unit missing from a snapshot really has left play.** `DemoState.build_snapshot`
  walks `COMBAT_GROUPS`, which covers `routers` as well as `units` -- a routing unit still
  appears, distinguished by `state: "ROUTING"`. So an absent uid means `_remove_from_play()`
  (death or merge), not a group change. Do not spend a round wondering whether the dump
  simply does not show routers.
- **The tick list is the UNION of the CLI argument and the input script's own `state`
  array.** Passing `96,100` to a script that declares `"state": [80, 88, 92, ...]` dumps
  all of them. Handy, but it means the dumped set can be wider than you asked for, and a
  run can hit its snapshot budget on ticks you did not request.

## Re-check a cited blocker's CURRENT state before writing it into durable prose

An issue number cited as "blocked on #N" is a claim with an expiry date, and nothing
warns you when it lapses. Copying such a citation from an existing doc inherits its
staleness silently, and the copy then reads as freshly verified.

A memory entry asserted `#296` was "blocked on #783". `#783` had been CLOSED/COMPLETED
for 18 days, fixed by `#784` -- and `#296`'s own thread recorded a different, still-
unfiled blocker (a residual ~1-2 px first-contact overshoot), explicitly advising against
reusing `#783`'s number for it. The phrasing came from
`docs/individual-collision-design.md`, which carried that stale phrasing in five of its
eight `#783` mentions (#1189).

The failure is worse than a dangling reference: a future reader who checks `#783` and
finds it closed has two plausible readings, and both are wrong -- "this is fixed now" or
"this whole entry is stale, ignore it". The genuinely useful state (still blocked, by
something narrower) survives only in a comment thread.

- **Do:** run `gh issue view <N> --json state,stateReason` on every issue cited as a
  blocker, and skim the blocked issue's own recent comments for what it currently says is
  blocking it, before the citation goes into a memory file, design doc, or code comment.
- **Do:** when a cited issue turns out closed, say so explicitly in the prose ("#783 was
  fixed by #784; the live blocker is X") rather than just swapping the number, so the next
  reader is not left re-deriving why a closed issue was mentioned.
- **Don't:** carry a "blocked on #N" phrase over from another file on the assumption that
  whoever wrote it checked -- inheriting it is exactly how it spreads.
- **Do:** when FIXING stale citations, classify every occurrence before changing any of
  them. Some are legitimate history ("#783 documented X", "#784 fixed it") and are exactly
  what tells a later reader why a closed issue is mentioned at all.
- **Don't:** blanket find-and-replace the stale issue number. That destroys the accurate
  mentions along with the wrong ones, and the accurate ones are the more useful half.

**Expect PARTIAL refresh, not uniform staleness.** When an issue closes, whoever updates
the doc tends to fix the section they were reading and miss the summary. The result is a
file that contradicts itself: `docs/individual-collision-design.md` simultaneously said
the work "stays blocked on #783" (the header summary, and the phase-5 "Enemy collision"
bullet) and that "#783 closed via #784 ... but still needs its own residual-transient fix"
(the level-of-detail section's authority-slices paragraph, the doc's only use of that
phrase).
It reads as authoritative in whichever section you happen to open, so grep the whole file
and reconcile the occurrences against each other -- do not assume the first one you find
represents the document's position.

(`Lacaedemon/sparta` PR #1188, 2026-07-30: caught by the automated reviewer, not by
drafting. Fixed one file over in #1191/#1189, where the count was ALSO wrong at first --
reported as five occurrences because a `grep | head -5` truncation was read as the total;
there were eight, of which five were stale and three were already accurate.)


## A script-inserted markdown block needs an EXPLICIT blank line, not just a newline

Inserting a block into a markdown file programmatically (a `python` splice, a `sed`
insertion, an anchor `replace`) terminates the last line but does not create a paragraph
break. Under CommonMark/GFM lazy continuation, a non-indented paragraph that directly
follows a list item's text with no blank line is folded INTO that list item rather than
rendered as its own top-level paragraph.

Building a bullet as `nl.join([...lines..., ''])` looks like it ends with a blank line; it
does not. `join` only puts the separator BETWEEN elements, so a trailing `''` merely ends
the final line. The result splices straight onto whatever followed the anchor.

Nothing in this repo's checks catches it: `tools/check.sh chars` scans characters, the
GDScript lint ignores markdown, and there is no conflict marker to point at -- the damage
is invisible in the raw text and shows up only in the rendered output. It was caught by
review reading the rendered semantics.

- **Do:** after any scripted insertion into markdown, print the seam (`sed -n 'A,Bp' file`)
  and confirm a blank line separates the block from what FOLLOWS it -- that is the half
  that fixes the swallowed paragraph.
- **Do:** add one BEFORE it too, unless the insertion is a new item continuing an existing
  TIGHT list. Per CommonMark, tightness is a property of the whole list: one blank line
  between any two items makes every sibling loose and `<p>`-wrapped, so a leading blank
  line silently reformats bullets the diff never touched.
- **Don't:** trust a trailing empty element in a `join` to produce a blank line.

(`Lacaedemon/sparta` PR #1188, 2026-07-30: the inserted bullet swallowed the closing
paragraph of the whole "no top-down X" list, which applies to the list rather than to any
one bullet.)

## Calibrate a threshold guard against a deliberately-regressed build, not just healthy seeds

A live-battle guard picks a threshold from measurements, and the measurements almost always
come from the healthy build alone -- "main sits at ~20 degrees, so gate at 28". That says
nothing about whether the metric MOVES when the fix is removed, and a metric that does not
move is a pass path indistinguishable from a failure path.

`test_residual_melee_swirl_battle.gd` measured each regiment's facing rotation at tick 700
of a matched 100v100 Infantry grind, gated at 28 degrees on one seed. Re-measuring across
six seeds showed clean main spanning 17.8-58.0 degrees (it exceeded its own gate at two of
them, and was outright red on Linux while green on Windows). The decisive measurement,
though, was a deliberately regressed build -- the canonical-slot mapping disabled in both
`SoldierBodies.step()` and `couple()`, behind a temporary `OS.has_environment` hook -- which
came out WORSE at three seeds and BETTER at three. The gated quantity carried no signal
about the fix at all, on any seed.

The same scenario measured in its OPENING window (300 ticks) separates cleanly: healthy
holds a 2.84-3.44 degree band across eight seeds while the regressed build ranges 1.94 to
14.45 (means 2.98 vs 6.52). Two regressed seeds still land under the healthy band, so the
gate has to be the SEED MEAN with a looser per-seed backstop, not a per-seed ceiling.

- **Do:** before trusting a threshold, break the fix behind a temporary env hook and re-run
  the same measurement. Ratio of regressed to healthy IS the guard's discriminating power;
  if it is near 1, the threshold is decoration whatever its value.
- **Do:** prefer the window where the two builds separate. Long chaotic battles diverge
  between platforms (this file already documents that for demo transcripts) and fan out
  seed to seed, so a late absolute bound is unportable on top of being uninformative.
- **Do:** assert the window is not vacuous -- here, that casualties actually occurred, since
  casualty-driven array compaction is what arms the defect.
- **Don't:** quietly widen a threshold to make a red guard green. Widening is only honest
  once you know the metric moves; otherwise it converts a wrong answer into no answer.

## `.gemini/` holds TWO configs for two different consumers -- and reviews are currently paused there

`.gemini/config.json` is the **Antigravity/Gemini CLI workspace** config (its `skills`/`memories`
path lists, written by ai-config's `bootstrap.sh`). `.gemini/config.yaml` is the **Gemini Code
Assist GitHub App** config -- a different schema read by a different consumer. Editing one does
nothing to the other, and the names are close enough to conflate at a glance.

As of PR #1214 (2026-08-06) the GitHub App's automated review is **off**: `code_review.disable:
true`, quota exhausted. A quota-exhausted reviewer posts nothing or a "could not review" stub,
which this file already documents as easy to misread as an approval (the Copilot quota case, the
review self-skip case) -- so the pause is deliberate and documented rather than a silent gap.
Claude's own `claude-code-review.yml` and Copilot review are untouched and still gate every PR.

Worth knowing before hunting for a lever that isn't there: sparta has **no** Actions-based
Antigravity reviewer (nothing under `.github/workflows/` references one) and no Gemini/Antigravity
bot has ever posted a review comment or check run on a recent PR. So `.gemini/config.yaml` is the
only in-repo switch; a reviewer driven from the Antigravity dashboard or IDE is toggled there, not
here. `GEMINI.md` carries the same note, since that is the file a Gemini/Antigravity session
actually reads.

## A "how to restore this" note must not pin a copy of an upstream product's defaults

When disabling a third-party feature by overriding its config, the natural way to document the
reversal is to write down what the defaults were, so a future reader can put them back. That is
exactly the wrong shape: the pinned copy is a second source of truth for a value you do not own,
it cannot be verified from inside the repo, and it rots silently when upstream changes it.

The failure is not hypothetical -- it happened in the same commit that introduced the note. The
reversal comment claimed `pull_request_opened` defaults of `help: false, summary: true,
code_review: true`; the real default for `summary` is `false`. Anyone following it to "restore the
defaults" would have left PR-open summaries on. Review caught it (`claude[bot]`, PR #1214), and the
web docs confirmed it independently.

Correcting the value would have left the mechanism intact. The fix that removes the failure mode is
to say **delete the overriding block** on re-enable, so whatever the product default is at that
time applies, with today's values quoted as context rather than as instructions.

- **Do:** phrase a reversal as "delete the override" whenever the pre-override behaviour is an
  upstream default rather than something this repo chose.
- **Do:** verify a documented third-party default against that product's own docs before writing
  it down at all -- and prefer not writing it down.
- **Don't:** treat a reviewer's `suggestion` block as the whole fix. Here the suggestion corrected
  the wrong value, which was right as far as it went; the better change was structural, and taking
  the suggestion verbatim would have re-armed the same trap for the next drift.
- **Don't:** forget the PR description carries the same claim. Fixing the files and leaving the
  description asserting the old values just moves the stale copy somewhere a reader still finds it.

## A PR can revert merged `main` content through a perfectly clean merge -- trial-merge onto `main` before trusting a green board

The standing sync rules all assume the hazard announces itself as a conflict. It does not
have to. A commit that lands on a PR branch *after* `main` was merged in can undo that
merge's content, and the result then merges back onto `main` cleanly, with no conflict, no
red check, and no signal in the PR's own diff view -- which shows the PR against its base,
not what merging it would do to `main`.

**Concrete case:** on `Lacaedemon/sparta` PR #1194 (2026-08-07), `google-labs-jules[bot]`
pushed `870e199e` on top of a session's own `main`-sync commit. Its diffstat read as
ordinary deletions; what it actually did was revert every file the sync had brought in.
Trial-merging the PR head onto `main` produced **14 files changed, 77 insertions, 484
deletions**, undoing merged work from five PRs: #1199 (shield defense by defender skill,
across `scripts/Shield.gd` / `SoldierCombat.gd` / `Battle.gd` / `test_soldier_combat.gd`),
#1212 (`test_residual_melee_swirl_battle.gd`, 193 lines), #1210/#1208/#1205 (memory
entries), and #1214/#1215 (`GEMINI.md`, `.gemini/config.yaml`). Only `+24/-24` in
`scripts/SelectionManager.gd` was the PR's actual subject.

**Why the usual checks miss it.** `mergeable: MERGEABLE` / `mergeStateStatus: CLEAN` only
say there is no textual conflict. `gh pr diff` shows the PR against its merge-base. CI runs
on the PR head, where the reverted state is internally consistent and passes. Even
`git merge-base --is-ancestor <main-commit> <pr-head>` returns **true** for every reverted
commit, because the merge really is in the ancestry -- the revert sits on top of it. That
last one is the trap: the obvious ancestry check actively reassures you.

**The check that works** is a real trial merge in a throwaway worktree, then a diff against
`main`:

```bash
git worktree add --detach /tmp/mt origin/main
cd /tmp/mt && git merge --no-commit --no-ff <pr-head>
git diff origin/main --stat        # net effect on main; large deletions == revert
git merge --abort; cd - && git worktree remove --force /tmp/mt
```

Run it before merging any PR whose branch gained commits after a `main` sync -- especially
one pushed by a different agent, since a bot with a stale working tree can commit its whole
tree state and silently revert anything newer.

- **Do:** trial-merge onto `main` and read the net diffstat before merging a PR you did not
  drive end to end.
- **Do:** treat a large deletion count against `main` as a revert until proven otherwise.
- **Don't:** read `MERGEABLE`/`CLEAN`, a green board, or a true `--is-ancestor` result as
  evidence that merging preserves `main`'s content.

## `tools/check.sh chars` scans only `*.qmd` and `*.R` -- `docs/*.md` is outside every net

`check_chars` (and the `check / check-chars` CI job) is scoped to the website docs. A brand
new Markdown file under `docs/` can therefore land banned punctuation with every check
green. `CLAUDE.md`'s ASCII-punctuation rule covers *every* tracked source file including
`.md`, so the rule and its enforcement disagree, and the gap is invisible from CI.

Found on PR #1198 (2026-08-07): `docs/square-formation-design.md`, a new 238-line file
added by that PR, carried **33 em-dashes**, plus one on its added `PLAN.md` line. All
checks were green and the automated review did not flag them either. Because the whole file
is the PR's own added lines, these were in scope for that PR rather than grandfathered.

When editing or adding `.md` under `docs/`, check the added lines by hand:

```bash
git diff origin/main -- <paths> | grep "^+" | python -c "
import sys; d=sys.stdin.buffer.read().decode('utf-8')
print(sum(d.count(c) for c in u'\u2014\u2013\u201c\u201d\u2018\u2019\u00d7'))"
```

Scope the fix to lines the PR actually added: a whole-file replace on a pre-existing file
(`PLAN.md` has 55 other em-dashes) is the scope-creep the punctuation rule itself warns
against.

## `main` has no required status checks -- a red `require-review` does not block merging

Easy to assume the opposite from the check's name, and the assumption changes how urgently
a broken reviewer gets treated. Verified 2026-08-07:

```bash
gh api repos/Lacaedemon/sparta/branches/main/protection      #=> 404 Branch not protected
gh api repos/Lacaedemon/sparta/rules/branches/main --jq '[.[].type]'
#=> ["deletion","non_fast_forward","pull_request","copilot_code_review"]  -- no required_status_checks
```

A PR whose `claude-review` and `require-review` are both red still reads
`mergeable: MERGEABLE`, `mergeStateStatus: UNSTABLE`. So a reviewer outage removes review
*silently* rather than gating merges, which is the more dangerous shape: nothing stops an
unreviewed PR being merged, and the merge button gives no hint. Don't report a red review
check as a merge blocker without querying protection first.

Note the `copilot_code_review` ruleset in that list: per `pr-on-claim`, that means Copilot
is re-requested automatically on push, which is why an explicit request's pending entry
disappears moments after a `201`.

## A `claude-review` that dies at ~40s with `total_cost_usd: 0` is not necessarily quota

`fully-clean`'s zero-cost signature (`is_error: true`, `num_turns: 1`, `total_cost_usd: 0`,
short duration) genuinely covers quota exhaustion and expired credentials. It also covers a
third cause that never reaches the model at all: a **plugin-install failure**.

```
##[error]Action failed with error: Failed to install plugin 'ai-config@Morrison-Lab' (exit code: 1)
##[error]Claude review did not complete successfully and was not eligible for a stub-review retry
TOTAL_COST: 0.0000
```

Same cost, same rough duration, completely different fix -- and unlike quota it will never
clear on its own. Read the job's own `##[error]` lines before classifying by the fingerprint;
a retry-and-wait on this one waits forever.

**Root cause when it appeared (2026-08-07):** `Morrison-Lab/ai-config` commit `6dc0cb49`
renamed the marketplace `"name"` from `Morrison-Lab` to `morrison-lab`, authored 02:53Z but
only reaching `main` when ai-config#1238 merged at 05:32Z. A plugin ref resolves by the
marketplace's **declared name**, which is case-sensitive, so every consumer pinning
`ai-config@Morrison-Lab` broke. Sparta's own runs bracket the landing exactly: #1194's
review passed at 02:53:55Z, #1198's failed at 05:56:48Z. Tracked as ai-config#1246/#1248.

The authored-versus-landed distinction is the part worth keeping: a `git log` date on the
offending commit will predate the breakage by hours, which makes the timeline look
inconsistent until you check when it merged.

## Before fixing a finding by clearing state, list every OTHER caller of the function you are clearing it in

The narrow lesson --- implement exactly what a review asked for and no more --- has now
produced four regressions in this repo across two PRs, so the prose version is not enough
on its own. What actually catches it is one mechanical question, asked before the edit:

> Which other call sites reach this function, and does the state I am about to clear mean
> something different for them?

The failure shape is always the same. A review names a real defect ("cancelling an order
does not stop the unit"). The obvious fix is to clear the stale execution state. The
function that seems to own that state turns out to be **shared**, so the clearing lands on
callers the finding never mentioned, and their behaviour changes silently --- no conflict,
no failing test, nothing in the diff that looks wrong.

**PR #1125 (2026-07-28)** was the first instance: an unprompted extra reset added to
`Unit._start_promoted_move()` defeated the `ENGAGED_FRACTION_ABOVE` disengage guard,
contradicting the field's own doc comment, which states the opposite contract in as many
words.

**PR #1196 (2026-08-07)** produced three more, all from a single round-1 fix that added
four clears to `Unit._interrupt_current_order()`:

1. `_move_order_peak_engaged_fraction = 0.0` --- the *same field and same guard as #1125*,
   defeated again, from a different function one call earlier.
2. `target_enemy = null` / `support_target = null` --- the severe one.
   `_interrupt_current_order()` is reached from `set_current_order()`, which **every fresh
   order in the game goes through**, and `Battle._apply_order_cmd` writes those two fields
   immediately *before* calling it for the ATTACK, SUPPORT and relief-fallback branches
   (`Battle.gd` 2086-2091, 2096-2099, 2133-2136). So a fresh attack order on any non-idle
   unit had its own target nulled a moment after assignment, and `_update_current_order()`
   retired the order on the next tick. Ordering a busy unit to attack silently did nothing.
3. `SelectionManager.cancel_selected_order_at` applied one order-tree row index across every
   selected unit's own queue, while the tree it indexes is built from a single unit
   (`_hud.show_unit(_selected[0], ...)`).

**The check, concretely.** Before adding a clear/reset to a function in order to fix a
finding:

```bash
grep -n "_the_function_name(" scripts/*.gd        # every caller, not just the flagged one
git show origin/main:scripts/Unit.gd | sed -n '<range>p'   # what did it do BEFORE this PR?
```

If more than one caller reaches it, the clearing usually belongs in the *specific* caller
the finding is about, not in the shared function. In #1196 the fix was to move all four
clears out of `_interrupt_current_order()` and into `cancel_order_at()`, which is the one
caller with no incoming order to supply fresh state --- and to leave a comment at *both*
sites saying why the split exists, since the natural tidying instinct is to put them back.

**Two things that do not catch this.** CI stays green: the reverted or cleared state is
internally consistent, and the existing suite has no test for "a fresh order on a busy
unit". And a field's doc comment stating the contract does not prevent it either --- #1125
and #1196's first regression both contradicted a doc comment that said the opposite
explicitly. Only enumerating the callers, or a test that exercises the other caller, does.

**When you do fix it, prove the guard bites.** Re-introduce the clearing, confirm the new
test fails, then restore. Every guard added for the three #1196 regressions was verified
this way; without it a regression test is a guess about what it covers.
