## Standing AI Workflow & Orchestration Rules (All AI Models)

Our lab's work rules encoded throughout `ai-config` apply unconditionally to all AI models and agents (Gemini, Claude Code, Codex, Copilot, etc.) across all repositories and sessions:


1. **Main session acts as orchestrator**: Delegate heavy research, multi-file searches, complex sub-tasks, or parallel branch operations to subagents (`invoke_subagent`) or background tasks (`run_command`), keeping main context clean and focused on high-level direction, triage, and review.
2. **Proactive corrective actions & PR workflow**: Whenever a gap, missing PR, or workflow instruction is identified, or when a capability/memory instruction is given:
   - **Act immediately without asking**: Never wait for a user prompt or ask "Should I do X?" when the requirement is clear -- branch, commit, open the PR, request review from `d-morrison`, and drive to clean in the exact same response turn.
   - **Auto-merge under `mwc`**: If `mwc` is active for the session, once CI passes AND the code review comment payload is verified clean (its review-data block says `"verdict": "CLEAN"`, its trailing `Reviewed commit:` line names the PR's current head, its prose verdict reads **Ready for merge**, and no other reviewer has unresolved findings, read from `pulls/<N>/comments` and the review threads per part file 12's "A green review check is not an approval" section), execute the merge and post-merge wrap-up immediately without stopping.
   - **Never merge over Needs more work**: a green check-run status does not override a **Needs more work** verdict, and a clean verdict counts only for the head its `Reviewed commit:` line names.
3. **Mandatory Timers for Async Work**: Whenever waiting on in-flight CI runs, background tasks, or subagents before completing a task or merge, **ALWAYS** schedule a timer (`schedule`) or proceed to other active work. Never end a turn waiting on asynchronous execution without a scheduled wakeup handle.
4. **Memory & Skill PR Discipline**: Every addition or update to memories, instructions, or skills (including `cai`, `memorize`, and `push-memory`) **MUST** be delivered via a branch + PR with requested reviewer (`d-morrison`) and driven to clean. Never edit configuration or memory files directly on `main` or disk without a PR.

## agy dispatches carry the mistake ledger

Every brief sent to the `agy` CLI starts with the block between the marker lines in `13-agy-mistake-ledger.md`.
When a checker or reviewer finds a defect in agy's output, the same agent is re-dispatched with the finding and appends the new rule to that ledger on the PR branch.
The orchestrator names each such mistake in the recap and merges the ledger additions on `main`, so no learning stays on one branch.

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
  switching instantly (merged) -- scoped to the regimental flag only, per design
  feedback: the per-soldier marks and other chrome stay fully opaque.
- **No inert numbers.** A quantity that represents real motion must actually cause
  motion -- a decaying speed that doesn't move the unit is a display artifact, not
  physics. #742/#743 (merged) made residual `_current_speed` coast the unit
  forward as it decelerates, instead of counting down while `position` sits
  frozen; the fix consolidates onto `_approach_velocity` (the unit's actual travel
  velocity, already read by the soldier-body feed-forward and combat charge bonus --
  never truly combat-only, just under-documented as one) rather than adding a
  parallel velocity field. #747 (merged) fixed a gap #743's own tests never
  exercised: `UnitCombat`'s "spend the charge" strike reset zeroed
  `_approach_velocity` on the exact tick a unit's last opponent died, leaving the
  idle-coast guard with no travel direction -- see "A prior PR's own claimed
  verification can be wrong even after merge" below. #749 (merged, closes #745's
  first slice) went further: added real soldier-to-soldier enemy-contact collision
  physics (`SoldierCollision.enemy_contact_impulse` /
  `SoldierEnemyContact.accumulate`), and made the regiment's own `position` a pure
  function of its soldier bodies' actual positions (`SoldierBodies.couple`) rather
  than an independently-controlled point the bodies must return to -- see "Regiment
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
  push-back this was meant to deliver already exists -- every landed strike already
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
  mechanic -- tracked separately as its own order/stance (#983) rather than folded into
  the default per-soldier physics. Before adding a new per-soldier bias/force, check
  whether an existing mechanism (knockback, reach-based hit resolution, contact impulses)
  already produces the intended outcome as a side effect -- if so, the new mechanic should
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
layer's own rules -- the kind of work the "bottom-up physics" philosophy above
governs. Polish is everything that makes the existing simulation more presentable or
more convenient without changing what it computes: rendering/art/asset quality,
camera behavior, HUD/UI layout, new platforms (3D mode, mobile), demo/tooling
convenience, or documentation-only issues with no mechanic attached.

This mirrors ai-config's own infra-over-feature tie-breaker (`pr-prioritization.md`)
-- a priority nudge, not an override: an explicit `P0`-`P3` label, a blocking
relationship, or a direct instruction from the user still ranks above it. Apply it
only when candidates are otherwise close in priority, the same scope the
infra-over-feature tie-breaker uses.

Concretely, from the backlog as surveyed 2026-07-11: #164/#296 (individual-level
collision), #240 (weapon-reach standoff), #453/#458/#480/#718 (maneuvers,
formations, move-order types, disciplined-vs-undisciplined march behavior), #724
(engage-turn swirl bug), and #750 (crowding-pressure evaluation) are core mechanics.
#69 (3D mode), #131 (smartphone version), #386 (terrain art), #414 (fog of war --
mostly a rendering/visibility-of-information feature once the underlying detection
already exists), #467 (demo options), #496 (comb wikipedia for ideas), and #756-style
CI/tooling issues are polish or infrastructure, not core mechanics specifically
(infrastructure still gets its own tie-breaker per `pr-prioritization.md`, applied
before this one when the candidates are CI/tooling rather than gameplay UI/art).

## GII grabbability is a separate axis from priority: a design-blocked issue is not grabbable

The section above orders candidates that are all workable.
It says nothing about whether a candidate is workable at all, and in a GII sweep
that is the question that actually decides the pick --- because GII's terminal
action is a PR driven to a clean review verdict, and an issue whose next step is
an unmade **design decision** cannot reach one.

That is not the same thing as being low priority.
A design-blocked issue is frequently core mechanics and frequently the highest
thing on the board, so the mechanics-over-polish rule ranks it first and the
grabbability check rules it out --- two axes, evaluated separately, in that
order.
Collapsing them produces the wrong move in both directions: grabbing an issue
that cannot be closed, or demoting one whose design question is already settled.

The tell is in the issue body rather than in its labels.
Phrases like "needs a design pass", "we should decide whether", "owner directive
pending", or a body that enumerates options without picking one all say the next
artifact is a **decision**, which is human-gated (see `daytb`/`mwc` scope), not a
diff.
An issue addressed to a specific bot or person by name is the same shape for a
different reason --- it is claimed, so GII's unclaimed-only rule already excludes
it.

What to do with one rather than silently skipping it: say in the session report
which issues were ruled out and on what grounds, so the thin-backlog condition is
visible instead of looking like a stalled sweep.
A design question worth answering is worth surfacing to the owner as a question,
which is a real deliverable even though it is not a PR.

- **Do:** run the grabbability check before the priority ordering, and report
  which candidates it removed.
- **Do:** surface a blocking design question to the owner rather than picking a
  lower-priority issue silently.
- **Don't:** grab an issue whose next step is a decision --- GII cannot deliver
  one, so the loop stalls with a claim posted and nothing to push.
- **Don't:** read "core mechanics" as implying grabbable; the two axes are
  independent, and the highest-priority item is often the one that is blocked.

(GII session, 2026-08-16: after PR #1257 merged, four candidates were looked at
--- #1152, #1095, and #1134, each stating in its own body that it needs a design
pass, plus #1110, addressed to the Jules bot.
All four rank as core mechanics under the section above, and none is grabbable,
which is the rule this entry states.

Issue #1152 has since closed, and reads `COMPLETED` to anyone who follows the
citation --- but it was not resolved.
PR #1259, a spec-only design pass whose own body says "#1152 stays open to carry
the implementation", auto-closed it two seconds after merging
(`02:16:36Z` and `02:16:38Z`), via a `(closes #1152)` keyword left in its
squashed claim commit.
That is the keyword hazard this file documents further down, landing on this
entry's own worked example, so the citation is kept with this note rather than
dropped.
Note that GitHub's own `closed_by_pull_requests` names **#1276** rather than the
PR that performed the close, since #1276 quotes the offending keyword line while
documenting it --- so the linkage field points at the PR that described the
auto-close instead of the one that did it.

The conclusion drawn from them was **wrong**, and the way it was wrong is worth
keeping, because it is the failure mode a grabbability check invites.
"The tractable unclaimed backlog is thin" was reported on the strength of those
four, and a later derived list returned **91 open issues**, of which #1279
(orphaned `.gd.uid` sidecars), #1277 (weapon-switch flash message), #1271
(`check.sh` versus `config/features`), and #1269 (banned-glyph set drift) are
each bounded, unclaimed, and grabbable --- confirmed unclaimed by intersecting
against the six open PRs at that moment, none of which referenced them.

So run the grabbability check over a **derived** candidate set, not over the
handful you happened to open.
Ruling four issues out says nothing about the eighty-seven you did not look at,
and "the backlog is thin" is a claim about the population --- see
[`derive-dont-enumerate`](https://github.com/Morrison-Lab/ai-config/blob/main/shared/workflow/derive-dont-enumerate.md)'s
own section on asserting a set is empty.
Report the examined count alongside the removed count, so a genuinely thin
backlog stays distinguishable from a narrow look at a deep one.)

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
features present on the current branch's ancestry -- grep first").

**Concrete case:** in the terrain-speed PR (#185), website docs were written for the
order-response delay feature (from `feat/order-response-delay`, a separate branch also
targeting `main`). That code was never in `feat/terrain-speed`'s ancestry, so the
reviewer correctly flagged it as a "hallucinated feature." Before documenting a feature,
`grep` for its symbol/constant (e.g. `order_response_delay`) on the current branch; if
it's absent, move the docs to the branch where the code lives.

## Demo scenario design -- team 0 is stationary by default

Only team 1 (enemy AI, `_run_enemy_ai()`) auto-advances. Team 0 (player units) stays
**stationary** until given an explicit order, so any hand-authored
`demos/scenarios/*.json` replay that needs team 0 engaged must issue a move (or attack)
order early -- at tick 0 or close to it. This bit the line-relief scenario (PR #200): the
relief order fired before any engagement because the player unit never advanced.

After writing a scenario, work out the engagement timing on paper before relying on the
CI clip to confirm it -- a mistimed scenario wastes a CI run and may silently record an
unrelated moment.

The reference tables a scenario author needs -- spawn positions and UIDs, effective unit
speeds, and the order `target`-field semantics -- live with the code in sparta's
`demos/README.md` and `REPLAY.md`, not here. A memory copy of constants like
`SPEED_SCALE` and the spawn layout would rot silently when the game changes them.

## Demo camera path -- record it like a human operator

When recording the camera presentation track for a demo (the track played back by
`tools/demo/DemoRunner.gd`), move the camera the way a person would, not a robot.
Repeated reviewer feedback on PR #232:

- **Don't chase the unit centroid recomputed every frame** -- it drifts both ways as
  units shuffle and die, so the pan constantly *reverses direction* and reads as
  jerky even when smoothed. Sample a fixed focus point **once**, or don't anchor to
  the centroid at all.
- **Hold, then move once in one direction, then hold** -- script holds plus single
  eased (smoothstep) moves; aim for ~1 direction-reversal per axis over the whole
  clip.
- **End on a multi-second stable hold** -- finish all camera motion well before the
  recording ends (set `max_frames` to cover the motion *plus* the hold) so the clip
  doesn't cut off mid-move.
- **Raise the framerate for a moving camera** -- `fixed_fps` 30 / GIF `fps` 12 suit a
  static-camera battle, but a panning/zooming camera looks choppy at 12 fps. Use
  `"fixed_fps": 60, "fps": 30` and bump `max_frames` to keep the duration.

Playback also low-passes the track (`Battle.camera_smoothing`, default `CAMERA_SMOOTHING`), but that smooths
magnitude, not direction -- fix the *path*, not just the filter. Verify by logging
the played-back camera and counting velocity sign-changes and per-tick jerk, not by
eyeballing one frame. The committed `demos/camera-showcase.json` is baked keyframes
(no centroid logic); author the recorder as a throwaway off-screen scene.

## Demo media in PRs -- inline play-once GIF + link to the MP4

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
  fresh random battle -- so the clip records the wrong thing (units at spawn, no
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
recording + extracting a few frames -- don't trust a CI run to catch a mistimed
scenario.

## Release workflow -- tag-gated publish, and the NSIS installer path

The `Release builds` workflow (`.github/workflows/release.yml`) builds on
`push: tags: v*` **and** on manual `workflow_dispatch`. A dispatch run builds
every artifact -- including the NSIS installer step -- and only the final
*publish to the GitHub Release* is tag-gated. So you can validate the installer
build without cutting a release; just don't expect a dispatch run to publish one.
A bug in the tag-only publish path, though, only surfaces when you actually tag.

- **The relative `OutFile` in `tools/installer/sparta.nsi` landed in the `.nsi`'s
  own directory (`tools/installer/`), not the workflow's working dir.** makensis
  ran from the repo root with the script path, yet the built installer wasn't in
  the repo root -- a `mv "sparta-…setup.exe" build/` from there failed with
  *cannot stat*. (NSIS docs are muddy on whether a relative `OutFile` is cwd- or
  script-relative, and it varies -- don't rely on either.) This was the first tag
  to run the installer step (added after v0.1.0). Fix pattern: make the path an
  overridable define (`!ifndef OUTFILE` / `!define OUTFILE …` / `!endif`) and pass
  an absolute `-DOUTFILE="$(pwd)/build/…"` from the workflow, matching how
  `EXE_PATH` is already absolute -- then makensis writes straight into `build/`
  regardless.
- **The release workflow runs from the *tagged* tree.** Fixing `main` is not
  enough: re-point the tag at the fixed commit (`git tag -f -a v0.2.0 <sha>` +
  `git push origin v0.2.0 --force`) to re-trigger. Reusing a tag is fine when no
  release ever published under it.
- **A backgrounded `gh run watch … ; echo EXIT $?` exits 0 even when the run
  failed** -- the wrapper's exit code is the `echo`'s, not the run's. Read the run
  `conclusion` explicitly afterward; don't trust the task's exit code.

## Local testing -- repo targets Godot 4.7 (no more 4.6 dance)

As of PR #420 ("Upgrade engine target from Godot 4.6.x to Godot 4.7", merged
2026-06-30), Sparta **targets Godot 4.7** -- `project.godot`'s `config/features`
is committed as `"4.7"` on `main`. Local machines run 4.7 too, so target and
binary match.

- **No more 4.6↔4.7 bump/restore.** The old workflow (bump `config/features`
  4.6→4.7 before a local run, then `git checkout project.godot` to restore 4.6)
  is **obsolete and now actively wrong** -- restoring to 4.6 regresses the
  committed target. Run the suite directly; leave `project.godot` alone.
- **Getting the binary:** point `GODOT_BIN` at a 4.7 binary (the `_console`
  variant gives terminal output on Windows), e.g.
  `GODOT_BIN=<path> bash tools/check.sh validate test chars`, or run GUT
  straight: `<binary> --headless -s addons/gut/gut_cmdln.gd -gdir=res://test
  -ginclude_subdirs -gexit`.
- **The `test_settings.gd` doubler quirk** is the same GUT-on-4.7 issue
  described just below -- if a lone `test_settings.gd` doubler parse error
  appears it's that known quirk, not a regression. Since the #420 upgrade the
  full suite has been observed passing every test, so don't assume that failure
  is still present, and don't pin an exact test total; the suite grows.

## A `cd` in one shell call resolves the NEXT call's `res://`, and Godot reports it as a missing file

The Bash tool's working directory **persists between calls** while its
environment does not, so a `cd` typed for one purpose silently becomes the
launch directory for every command after it.
Godot finds the project by walking up from the directory it was started in, so a
later `godot ... res://tools/demo/DemoRunner.tscn` run from anywhere outside the
checkout resolves `res://` against a different root, or none, and fails with a
**File not found** naming the path.

The message points at the wrong half of the problem, which is the whole
difficulty.
The path is correct, the file exists, and the checkout is the right one --- so
the natural next move is to re-derive the path, verify the scene, or suspect the
import cache, none of which can find anything wrong.
Nothing in the error mentions the working directory, because from Godot's side
there is nothing to mention: it looked where it was standing.

This is not one of the worktree hazards elsewhere in this file.
Those are all about **which checkout** a path names --- a fake worktree, a
double-checked-out branch, a stale sibling.
Here there is one checkout, it is correct, and the only wrong thing is the
directory the process was launched from.
So the worktree checks (`git worktree list`, `ls -la .git`) all come back clean
and settle nothing.

Two habits remove it outright.
Pass the project explicitly rather than relying on where you happen to be ---
`godot --path /home/user/sparta ...` --- so the resolution is stated in the
command.
And treat a trailing `cd` as a side effect on the session rather than a
convenience: a status sweep or a `/tmp` inspection that ends by leaving the
shell somewhere else has changed the meaning of every later relative path and
every later `res://`, minutes or hours afterwards, with nothing to connect the
two.

- **Do:** pass `--path <checkout>` to Godot, so `res://` resolves from the
  command rather than from the session's history.
- **Do:** run `pwd` before a command whose paths are relative or `res://`-rooted,
  when anything earlier in the session may have moved the shell.
- **Don't:** read a `res://` "File not found" as a fact about the path --- check
  the working directory before re-deriving the path or suspecting the import
  cache.
- **Don't:** end a Bash call with a bare `cd`; the next call inherits it, and the
  failure it causes surfaces far from the command that set it.

(GII session, 2026-08-16: a `cd /tmp` in an earlier call left the shell outside
the checkout, and a later `DemoRunner.tscn` invocation reported the scene
missing; the same command re-run from the project root worked unchanged.
The persistence itself is documented in the Bash tool's own description --- "Working
directory persists between calls" --- so the gap is not the fact but its
consequence for `res://`, which no error message connects back to it.)

## Reproducing a reported hang cross-platform: WSL gives a genuine native-Linux Godot binary

CI runs on `ubuntu-latest`; local development on this machine is Windows. When
a prior session reports a live-battle test hanging and reverts a change
"un-root-caused," don't assume the report is stale or trust it at face value
either -- reproduce it fresh, and if the platform might matter (this repo's own
`ANCHOR_RANKS` docstring documents at least one prior case where a chaos-
sensitive test passed locally on Windows while failing on Linux CI), get a
genuine native-Linux run rather than reasoning about the gap from Windows
alone.

WSL (`wsl.exe -d Ubuntu`) makes this cheap on a machine that already has it
installed: download a Linux Godot binary directly (same version tag as the
Windows one, so the comparison is apples-to-apples), clone the repo into WSL's
**native filesystem** (not `/mnt/c/...` -- that path is a slow 9p/DrvFs bridge
and import/test runs on it are painfully slow), vendor GUT the same way
`tools/check.sh` does, and run the suite there.

```bash
wsl.exe -d Ubuntu -- bash -lc "mkdir -p ~/godot && cd ~/godot && curl -fsSL -o godot.zip \
  https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip \
  && python3 -c \"import zipfile; zipfile.ZipFile('godot.zip').extractall('.')\" \
  && chmod +x Godot_v4.7-stable_linux.x86_64"
wsl.exe -d Ubuntu -- bash -lc "cd ~ && git clone --quiet https://github.com/Lacaedemon/sparta.git sparta && cd sparta && git checkout -q <branch>"
```

Then vendor GUT (mirroring `tools/check.sh ensure_gut`) and run the same
`godot --headless -s addons/gut/gut_cmdln.gd ...` invocation used locally.

**Windows Git Bash mangles `/tmp/...` paths passed to `wsl.exe`.** MSYS
auto-translates POSIX-looking absolute-path *arguments* to a program it treats
as "native" (which `wsl.exe` is, from Git Bash's point of view) into a Windows
path -- so `wsl.exe -d Ubuntu -- bash /tmp/foo.sh` silently becomes
`bash C:/Users/.../AppData/Local/Temp/foo.sh` and fails inside WSL with "no
such file." Prefix the whole call with `MSYS_NO_PATHCONV=1` whenever a
`wsl.exe` command line carries a `/`-rooted path as an argument (a script
path, a directory), and prefer `/mnt/c/Users/...` (which WSL resolves without
any translation needed on the Windows side) when handing a Windows-side file
into a WSL command directly, rather than round-tripping it through a UNC
copy.

**This settled a real question, not just a hypothetical one.** On issue #1136
(a reverted position-anchor fix reported to hang `test_collision_knockback_battle.gd`
indefinitely), the identical diff reproduced cleanly on both Windows and this
WSL-native-Linux setup -- same Godot build (`4.7.stable.official.5b4e0cb0f`) on
both, three runs each, the single test and the full 2642-test suite both
clean in under seven minutes. That is real, falsifiable evidence the reverted
finding wasn't a deterministic property of the diff on the builds actually
tested -- evidence a Windows-only re-check could not have produced, since a
clean Windows run alone would leave open exactly the cross-platform
possibility this repo has already documented once before.

## GUT's doubler breaks on void-returning methods under Godot 4.7

`partial_double()`/`double()` can fail to parse under Godot 4.7 + GUT v9.7.0:
some generated wrapper methods still emit an invalid `return` for void-returning
or default-parameter methods, which 4.7's stricter return-type checking now
rejects ("A void function cannot return a value"). This is bitwes/Gut#816 -- GUT
9.7.0's fix for the underlying Godot change doesn't cover every method shape.
Hit while migrating to 4.7 (#420): `test_settings.gd`'s one `partial_double()`
use on `Settings.gd` (which has several void methods and default-valued params)
failed this way. Fix: skip the doubler for the affected script -- write a small
hand-rolled subclass that overrides just the method you need to spy on (GDScript
dispatches it virtually from the base class's own calls), e.g. a counter in an
overridden `_save()` instead of `assert_not_called`. Check before reaching for
GUT's doubler on any script with void or default-valued-param methods.

## Verify maneuvers/soldier bodies tick by tick, not by eyeballing GIFs

For maneuver/soldier-body work, **verify by stepping the simulation tick by tick
-- in the real Battle scene -- and asserting on actual body positions**, not by
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
  footprint drift / no reposition. Make it permanent -- it's the regression guard.
- Treat demo GIFs as a *presentation* check only, never the correctness signal.
  A clean tick-by-tick test + a bad-looking GIF means the bug is in rendering,
  not the sim.

## Settings.gd setters persist to the REAL user://settings.cfg in tests

`Settings.gd`'s setter methods (`set_order_binding`, and the property setters
like `edge_scroll =`, `show_unit_speed =`, `form_up_dist_default =`) all call
`_save()` internally, which writes the **real** `user://settings.cfg` on whatever
machine runs the test -- GUT tests are not sandboxed. A test that calls a setter
to trigger `Settings.changed` (e.g. to verify a UI element repaints on a live
rebind) persists that change to the developer's actual config, contaminating real
gameplay and every later test run until manually fixed.

**Why this matters:** caught on `test_shortcuts_overlay.gd` -- a test called
`Settings.set_order_binding("skirmish", KEY_J)` to verify the overlay repaints;
this silently rewrote the `skirmish=` binding from the default (KEY_K) to KEY_J.
The editor and later playtests then loaded skirmish bound to J. Required manually
editing `settings.cfg` to restore.

**How to apply:**
- To trigger `Settings.changed` **without** the disk write, mutate the backing
  dict/property directly and emit by hand:
  `Settings.order_bindings["slug"] = KEY_X; Settings.changed.emit()` -- NOT
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
clobber the second run's keybindings mid-verification -- the state dump then
shows the WRONG stance armed (or none at all), looking exactly like a code
bug in the just-resolved merge, when the actual cause is the other worktree's
concurrent GUT run persisting its own (possibly test-scrambled) keybinding
overrides to the same shared file. If a state-dump result looks wrong right
after a merge-conflict resolution, `rm -f
~/.local/share/godot/app_userdata/Sparta/settings.cfg` and re-run the dump
before concluding the fix itself is broken -- don't trust a single dump when
another worktree's Godot process could have been running concurrently.
(Session running parallel background agents across `pr-704`/`pr-707`/`pr-713`
worktrees, 2026-07-10: a `sweep-routers.json` sanity dump showed
`order_mode: "All-out attack"` -- a completely unrelated PR's stance -- at the
exact tick its own `Ctrl+,` should have armed `Sweep routers`, traced to a
`settings.cfg` on disk holding scrambled keybinding values from a concurrent
test run in a sibling worktree.)

**The same collision fires WITHIN one worktree too: never launch a second
Godot suite (test/coverage) anywhere while one is still running.** Two
background `tools/check.sh` runs in the SAME worktree share not just
`settings.cfg` but the `.godot` import cache and the single
`coverage/lcov.info` output path -- the second run's results are garbage
without erroring (a coverage report that silently reflects a stale test set,
a spurious single-test failure elsewhere in the suite). The contamination
tell in `settings.cfg` is keybinding overrides holding scrambled values
(e.g. `chase=65`/'A', `sweep_routers=87`/'W'); delete the file and rerun
alone before believing any failure. One Godot process at a time, machine-wide
-- treat a running background check task as a lock. (GII batch endgame,
2026-07-15: launched a patch_coverage rerun while the prior one was still
going in the same worktree; the "rerun" reported the pre-edit coverage
number, and a later full-suite run failed one unrelated test until the
scrambled `settings.cfg` was deleted.)

**An orphaned Godot process (e.g. a `bash tools/check.sh | head -N` pipe
SIGPIPE-killing the wrapper script but leaving its spawned Godot child
running detached) is a lock the same way a live foreground run is -- and this
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

**The contending process isn't always yours -- a GENUINELY EXTERNAL Godot
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
under the running process -- the results are silently a mix of two trees and
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
wheel hinges against the grid as physically laid out -- required for chained
quarter turns (±PI/2 folds). But a completed conversio folds
`_formation_angle` to ±PI, which spins BOTH axes 180°: "front" points at the
physical rear and the `signf(dir)` flank flips, so the hinge lands at the
rear corner of the WRONG flank and the whole block wheels BACKWARD around it
(every soldier backpedaling, cos(facing) = -0.99 across the swing). The
rectangular lattice is identical under a 180° spin, so the fix is to re-pick
the other representative when the folded front axis opposes facing -- and the
threshold must be `dot < -0.5`, NOT `< 0.0`: a quarter-turn fold's dot is
zero only mathematically, and in 32-bit float the sign is noise, so a bare
sign check mirrors the tested chained-quarter-turn hinge at random (the full
suite caught exactly that on the first attempt; the file's own 16 wheel tests
all passed over the backward wheel because none asserted hinge POSITION).
Watching the recorded demo caught what the tests missed -- the user asked why
soldier 8 was backpedaling. Any new consumer that folds `_formation_angle`
into a direction calculation needs the same ±PI re-pick, a hinge/anchor
POSITION assertion in its tests, and edge-case runs at both fold values.
(`Lacaedemon/sparta` PR #871, 2026-07-15.)

## MultiMesh instance transforms don't read back in headless tests

`MultiMesh.set_instance_transform_2d(i, t)` followed immediately by
`get_instance_transform_2d(i)` in a headless GUT test returns identity, not the
value just set -- even for `Unit._mm_body`, whose write path is proven correct in
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
func` (plain values in, `Transform2D` out) and unit-test *that* -- e.g.
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
  the *next* free value independently -- e.g. #469 added `ORDER_NUDGE := -5` and
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
trusting the merge -- a redeclaration or shadow surfaces only at parse time.
Learned resyncing #469 (arrow-key nudge) after main merged #474 (wheel).

**At cascade scale: resolving once doesn't mean the sentinel collision is
over -- merging ANY sibling into `main` re-conflicts every OTHER sibling a
second time.** When several `OrderMode`-adding PRs are open at once (five,
2026-07-10: `ALL_OUT_ATTACK` #704, `PIN_DOWN` #707, `ROLL_THE_LINE` #708,
`SWEEP_ROUTERS` #711, `CHASE` #713), each one independently claims the next
free enum value/hotkey against whatever `main` looked like when it was last
resynced -- so resolving PR A against PR B's already-merged value doesn't
settle anything permanently. The moment PR B (or C, or D) itself merges to
`main`, every other still-open sibling's `mergeable_state` flips back to
`dirty`, because `main` just moved again and picked up yet another occupied
enum/hotkey slot. This isn't a one-time fan-out to absorb; it's a recurring
tax that hits once per merge in the cascade -- expect to re-run this same
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
rebind it to a different free key -- a hotkey is just an integer with no
cross-branch invariant, so this permanently removes that specific collision
regardless of merge order. **Don't try the same trick on the enum value**
(e.g. reserving `CHASE = 11` on one branch so it won't collide with
`ALL_OUT_ATTACK = 10` on the other): `test_hud_stance.gd`'s
`test_stance_entry_ids_are_sequential_and_unique` asserts each branch's own
`HUD._STANCE_ENTRIES` ids run `0..N-1` with no gaps, so a branch can only
place its newest stance at exactly `(highest existing value) + 1` -- it can't
reserve a future slot for a sibling it can't see. That half of the collision
stays real and can only resolve at actual merge time, via the normal cascade
process above. (`Lacaedemon/sparta` PR #713, 2026-07-10: attempted
`CHASE = 11` to preemptively dodge #704, immediately failed
`test_stance_entry_ids_are_sequential_and_unique` with
`[0..9, 11] != [0..9, 10]`; reverted the enum change, kept the hotkey
rebind to `KEY_BACKSLASH`.)

