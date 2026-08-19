## Battle.gd order dispatch applies every live order exactly once (immediate-apply + tagged tick-drain)

`Battle.gd`'s live order paths (`enqueue_*()`) apply every order TWICE by default -- once
immediately at enqueue time (for zero-latency feedback + paused preview) and again when the
physics tick drains `_pending_orders`. Harmless for an absolute/idempotent order (formation,
frontage-resize), but corrupts any order whose effect is RELATIVE to state the first apply
already set (root cause of #517/#518: a rear-move about-face re-read the conversio the first
apply armed and fell into the wrong branch).

**Dedup pattern still in force** (`_apply_order_live`/`applied_live`, PR #519):
- `_apply_order_live(cmd)` applies the order via `_apply_order_cmd(cmd)` AND tags the in-memory
  dict: `cmd["applied_live"] = true`. Every live enqueue path routes through it instead of
  calling `_apply_order_cmd` directly.
- The tick drain still **records** every pending order for replay (unconditionally -- the replay
  stream must be complete) but only **applies** it `if not o.get("applied_live", false)`. An
  order NOT applied live (e.g. a waypoint append -- non-idempotent by nature, tick-authoritative)
  stays untagged and still drains-applies once, exactly as before.
- `Replay.record_order` copies EXPLICIT named fields (not the whole dict), so the `applied_live`
  tag never reaches the recorded stream -- a `PLAYBACK` order read via `orders_for_tick` is
  therefore always untagged and applies once, so the PLAYBACK path is untouched by this pattern
  and replay determinism carries over automatically.

**Test pattern for a Dictionary-tag dedup:** GDScript Dictionaries are reference types, so tagging
the SAME object that sits in `_pending_orders` is visible to a drain-mimicking test helper without
re-fetching -- but cross-reference the helper's gate condition to the production drain in a
comment, or the two silently diverge if the key/logic changes in only one place. Any NEW order
type added to `Battle.gd` (or an existing one you refactor) that goes through a live-enqueue path
must route through `_apply_order_live`, not call `_apply_order_cmd` directly, or it reintroduces
the double-apply bug this pattern exists to prevent. (`Lacaedemon/sparta` #517/#518, PR #519.)

## Form-up orders never use the smooth maneuvers -- a big reposition needs its own facing/reform handling

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

**In a remote/web session that probe is uninformative without a control, and its
failure mode is a confident FALSE NEGATIVE.** Claude Code on the web routes outbound
HTTPS through an agent proxy that blocks arbitrary hosts, so the `curl` above returns
exit 56 / `http=000` for the URL under test AND for a site that is plainly up. Read on
its own that looks exactly like "the site is down", which is the reading that argues
for a permanent `lychee.toml` exclusion. Probe a control host in the same command and
compare:

```bash
for u in "$url" "https://godotengine.org/"; do
  printf '%s ' "$u"
  curl -s -o /dev/null -w "http=%{http_code}\n" -L --max-time 20 \
    -A "Mozilla/5.0 (compatible; Lychee/0.15; +https://github.com/lycheeverse/lychee)" "$u"
done
```

A control that also fails means the probe measured the proxy rather than the site, so
it has established nothing either way -- fall back to the CI-side evidence in the
section below. Measured 2026-08-12 from a Claude-Code-on-the-web container:
`godotengine.org` returned exit 56 / `http=000`, identical to the URL under test, while
`github.com` returned `http=400` from the proxy itself. Neither is a fact about the site.

## A pre-existing URL that newly fails the link checker: check `main`'s own runs before excluding it

The section above covers a URL you are ADDING. The commoner case is the reverse:
`check / link-checker` goes red on an unrelated PR over a URL nobody touched, and
`lychee.toml`'s exclusion list is this repo's standing remedy for a site lychee cannot
reach. Reaching for a new exclusion there is wrong about as often as it is right, and
the cost is asymmetric -- an exclusion is permanent and silently stops checking a link
that may be perfectly fine.

A TRANSIENT failure is indistinguishable from a persistent one inside a single PR's
log, and two things make that log read as stronger evidence than it is. `max_retries
= 3` means lychee already retried within the failing run, so the error is not a
single-shot flake. And the failing URL sitting in a file the PR never touched proves
only that the PR did not CAUSE it -- the check scans the whole repo on every PR, so
scope never settles the question either way.

The discriminator needs no network access of your own, which is what makes it the
right tool in a proxy-restricted session: `check-links.yml` also runs on every push to
`main` (and on a schedule), over the same corpus and the same config. A `main` run
that PASSED after the PR's failure proves the URL was reachable, so the failure was a
blip -- re-run the PR's failed job rather than changing config. Read the recent runs
via `actions_list` / `list_workflow_runs` on `check-links.yml` and compare the newest
`main` run's conclusion and timestamp against the PR run's failure.

Every existing entry in `lychee.toml` documents a REPRODUCIBLE failure ("even after
re-runs", "confirmed reproducible across two separate CI re-runs", a specific status
code). Match that bar before adding one, and record the evidence in the comment the
same way.

(`Lacaedemon/sparta` PR #1237, 2026-08-12: `check / link-checker` failed on the
scheduled benchmark-baseline refresh with exactly one error --
`https://godotshaders.com/shader/vertex-animation-with-instancing/`, cited from
`docs/3d-conversion-design.md`, `Network error: Connection reset by peer (os error
104)`. The local probe was uninformative for the proxy reason above. The `main` run
pushed 24 minutes later passed the same URL, and a re-run of the PR's own failed job
then passed too -- so no exclusion was warranted, and adding one would have suppressed
a live link check over a 20-minute blip.)

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

