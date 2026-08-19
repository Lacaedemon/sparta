## Multi-pair force accumulation needs a write-back clamp, not just a per-pair cap

When a per-tick force resolves in **pairs** (soldier-vs-soldier contact, not a single
discrete strike) and the same body can appear in more than one pair simultaneously, a cap
applied ONLY inside the per-pair resolution function is not enough -- the pair-wise caps
compose additively across pairs unless the SUMMED result is also clamped before it's
written back to the body's velocity.

**Concrete case:** `SoldierCollision.enemy_contact_impulse()` caps its own
`effective_closing_speed` at `KNOCKBACK_SPEED_MAX`, with a docstring explicitly scoped to
"one enemy-contact pair." `SoldierEnemyContact.accumulate()` sums that impulse into each
body's `delta_v` across every simultaneously-overlapping enemy, but originally applied the
sum with a raw `+=` -- a soldier touching 2-3 enemies at once (e.g. a Square-perimeter
defender pressed by several attackers from one side -- MORE likely after #749's own fix
making `engaged_soldier_indices()` return the whole perimeter for Square/Schiltron, not
just a front wedge) could receive 2-3x the stated per-tick cap. No downstream clamp rescues
this for an actively-fighting body (`SoldierBodies._cap_body_speed()` only runs when idle
or reforming). Caught by `claude[bot]` review, not the original implementation or its test
(which only budgeted one `KNOCKBACK_SPEED_MAX` term per tick in
`test_collision_knockback_battle.gd`'s displacement bound).

**Fix pattern:** apply the write-back through `SoldierCombat.capped_knockback_velocity`
(which clamps the RESULTING velocity -- `max(current speed, cap)` -- after adding the
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
into `target_enemy` -- so a unit with no explicit attack order re-ran a full nearest-enemy
scan from scratch EVERY tick. Under a multi-attacker press, tiny jostles in relative
distance flip which enemy is "nearest" tick to tick, and each flip re-arms
`_face_for_action`'s engage-turn toward a new direction -- the whole grid sweeps back and
forth at the turn rate instead of settling on one foe (visible as soldiers "flying" once
body coupling is fast enough to track it -- see #749 above).

**The gotcha:** persisting the auto-acquired pick (`target_enemy = enemy`, in `_think()`'s
gated combat-engagement branches) fixes that whipsaw, but `Unit.gd`'s chase branch
(`elif target_enemy != null or (chasing and not in_contact): ... _move_to(goal, delta)`)
has **no `ORDER_HOLD` guard** -- because until this change, `target_enemy` only ever went
non-null via an EXPLICIT order, which `ORDER_HOLD` is specifically meant to still obey
("HOLD only suppresses chasing a DETECTED foe, not an explicitly-set target"). Committing
an auto-acquired pick unconditionally reclassifies it as that kind of explicit target: the
instant the fought enemy leaves contact (retreats, gets knocked back, routs --
`current_target()` still returns a routing unit, only `state != DEAD` is checked), the
melee/ranged branch stops firing but `target_enemy` is still set, so the HELD unit marches
off after it. Caught by `claude[bot]` review, not by the original fix or its own tests
(which only called `_think()` once, never reaching the tick where the enemy has left
contact).

**Fix:** skip the `target_enemy = enemy` commit specifically when `order_mode == ORDER_HOLD`
-- this preserves the pre-existing contract at the cost of not fixing the facing-whipsaw for
an un-squared HELD unit under a multi-attacker press specifically (not a regression, since
that combination was never fixed by the persistence change in the first place -- Square is
exempted from engage-turning entirely regardless of order_mode, so the common case is
covered anyway). **How to apply:** any time a field's "only ever set by an explicit order"
invariant is broken by a new auto-commit path, grep every consumer of that field for logic
that assumes the old invariant (here: an unguarded chase branch) before shipping -- a single
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
clear it. `_engage_turn_target` then stays stuck non-zero forever, which -- per
`is_maneuver_turning()`'s own docstring -- permanently freezes `SoldierBodies.step`'s
slot-approach term: the squared body never eases onto its new slots. Caught by `claude[bot]`
review (reachable via the exact anti-cav-square flow #749 is built around: a unit turning
to face an approaching charger, then squared reactively before the turn finishes), not by
the original implementation.

**Fix:** settle any in-progress turn before taking the early return:
`if _engage_turn_target != Vector2.ZERO: _settle_engage_turn()` before `return true`.
**How to apply:** any new early return added to a stateful turn/maneuver function in this
file (anything tracking `_engage_turn_target`, `is_wheeling()`, `is_order_turning()`, or
similar) needs to settle or explicitly account for whatever in-progress state it might be
short-circuiting past -- grep the function for every OTHER path that clears the same state
before assuming a new early return is safe. (`Lacaedemon/sparta` PR #749, 2026-07-11.)

## A bare `Unit.new()` test fixture defaults to `uid -1` -- soldier-id collisions across fixtures

`Unit.soldier_id(index)` computes `uid * SOLDIER_ID_STRIDE + index`, and `Unit.gd`'s `uid`
field defaults to `-1` (only ever assigned a real, unique value by `Battle`'s spawn path).
A GUT test that constructs TWO bare `Unit.new()` fixtures (never spawned through Battle) and
exercises any logic keyed on `soldier_id()` -- e.g. `SoldierEnemyContact.accumulate()`'s pair
canonicalization, `if sgids[b] <= sgids[a]: continue` -- will see BOTH fixtures' soldier 0
resolve to the identical id (`-1 * STRIDE + 0`), so the pair gets silently treated as
already-resolved/duplicate and skipped, regardless of what the test actually intended to
exercise. This doesn't fail loudly -- a test asserting "nothing changed" can pass for the
WRONG reason (id collision) instead of the reason its docstring claims (e.g. a same-team
skip, or a dead-unit skip).

**How to apply:** any GUT test constructing more than one bare `Unit.new()` fixture and
exercising soldier-id-keyed logic must assign each a distinct `uid` explicitly (e.g.
`u.uid = 1`, `u.uid = 2`), matching what a real `Battle`-spawned unit always gets. Verify a
new cross-unit test isn't accidentally passing via this collision by checking the actual
resolved values (not just the top-level assertion) the first time it's written -- a debug
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
`reap()` removes dead soldiers by splicing the per-soldier arrays -- every index after a
removed soldier shifts down, so index `i` no longer sits where `block_slots` originally laid
it out. This is a **same-unit geometry bug**, not fundamentally about needing enemy-position
data (the issue's own proposed direction) -- the array is stale relative to itself.

**Fix, partial:** `UnitFormation.live_perimeter_indices(positions, target_count)` replaces
the slot-index selection with the `target_count` LIVING soldiers currently farthest from the
block's own LIVE centroid (`_sim_soldier_pos`, read directly -- same OUTPUT SIZE/target count
as the old ring, not the same runtime cost: selection itself is a bounded min-heap,
O(n log target_count), vs. the old O(n) index scan -- more work per call, though bounded and
small relative to a tick's other per-soldier costs at this game's regiment sizes). This
measurably improves the gated mismatch rate at every post-casualty tick checked (32%→22%,
78%→70%, 67%→60%, 67%→47%, 62%→45%) with no regression on the pristine (no-casualty) case.
**It does not fully
close #752** -- "farthest from live centroid" is still an approximation of "true outer ring,"
and under heavy multi-directional pressure (the block reflowing unevenly as different sides
take casualties at different rates) it can still misclassify a soldier pushed inward on one
side as "engaged" over a genuinely exposed soldier on a less-pressed side. The issue's
originally-proposed direction (each candidate's nearest ENEMY soldier within a contact
radius, via `SoldierSpatialHash`) is the fuller fix and remains open follow-up work
(#752 stays open).

**How to apply:** before implementing a "make this live/position-based instead of
index-based" fix, verify empirically whether the bug is (a) same-unit index/position
staleness (fixable by reading live positions, no cross-unit data needed) or (b) genuinely
needs cross-unit proximity data -- they look identical from the bug report alone
("this-N-vs-that-N mismatch under chaos") but have very different fix complexity. Gate any
such reproduction to pairs actually within contact/reach range -- an ungated "nearest globally"
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
(O(n log target_count) -- see `UnitFormation._worse`/`_heap_sift_up`/`_heap_sift_down`), which
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
keyword-based auto-close. **The exact mechanism is unconfirmed** -- the reopening comment
posted at the time guessed "repo automation matching the `#752` reference in the squash
commit title," but that's a guess, not a verified cause; a later review round flagged that
GitHub's PR "Development" sidebar auto-link (an alternative theory this entry originally
asserted) normally requires a *manually applied* link and doesn't auto-attach just because
an issue number appears in a PR title, so that theory is probably wrong too. `godot-ci.yml`'s
`resolve-main-failure` job ("Close tracking issue on green") IS ruled out, though -- it only
ever touches a separate marker-tagged `ci-failure` issue, confirmed by reading the workflow.

**How to apply:** after merging any "partial fix, issue stays open" PR that mentions the
issue number anywhere in its title or body, check the issue's state immediately --
`state_reason: "completed"` right around the merge timestamp is the tell. Reopen with an
explanatory comment if it auto-closed; don't assume stating "leaving this open" in the PR
body is sufficient to prevent it. (`Lacaedemon/sparta` PR #758 / issue #752, 2026-07-11:
#752 was closed at the exact merge timestamp despite both the PR body and an issue comment
stating it should stay open; reopened with an explanation.)

**A second, independent occurrence narrows the mechanism further.** Issue #296 was
auto-closed by PR #782's merge (2026-07-12, a real commit-message keyword match, since
#782's first commit read "...closes #296") and reopened with an explanation. It was
auto-closed a SECOND time by PR #981's merge (2026-07-18, 23:43:15Z -- 2 seconds after the
merge landed), even though NO commit in #981's entire squash-merge history contains a
`closes`/`fixes`/`resolves` keyword anywhere near "#296" (checked the full squash commit
body). `gh api repos/.../issues/296/events` shows this second close event's `commit_id` is
`null` -- unlike the first (keyword-matched) close, which had a real commit SHA attached.
A null `commit_id` rules out the standard commit-message-keyword auto-close for this
occurrence specifically, and points instead at something that fires off the PR's own
DESCRIPTION text: #981's body mentioned "#296" prominently in an "Also found and fixed in
passing" section -- not a closing-keyword sentence, but strong textual proximity to the word
"fixed". Still not a confirmed mechanism, but strengthens the case that merely naming an
issue number anywhere in a PR body (not just a commit message, and not just a literal
closing keyword) can trigger an auto-close on merge. Treat ANY issue-number mention
anywhere in a PR's commits OR its description as a close risk, not just literal
`closes #N` phrasing -- check the mentioned issue's state immediately after every merge.

**A THIRD occurrence confirms the mechanism for one of these shapes, and it is
systematic rather than mysterious: our own `pr-on-claim` claim commit.**
PR #1259 (2026-08-15) was spec-only, said `Refs #1152` in its body and in all four
of its later commit messages, and still closed #1152 at the merge instant.
The cause is readable in the merge commit itself.
`f913d5d6` on `main` opens with the squashed claim commit's own line,
`* start: couple knockback slide with the prone/fall roll (closes #1152)`.
That is the ordinary commit-message-keyword auto-close, not the unexplained shape
the entry above describes.
`pr-on-claim`'s template writes `(closes #<N>)` into the empty claim commit at
claim time, when the PR IS still expected to close the issue.
A squash merge then concatenates every commit message on the branch, so the
keyword reaches `main` however the scope ended up.
Switching the BODY to `Refs #N` does not undo it, because GitHub reads commit
messages independently of the body.
This retro-explains the #782/#296 case the entry above already notes
("#782's first commit read ...closes #296") as the same systematic cause.
It does NOT explain #758/#752 or #981/#296, which carried no keyword anywhere
and stay unconfirmed.

**The tell before merging is a closure risk with no PR linkage.**
As of the 2026-08-16 measurement, #1152 came back `closed_by_pull_requests: {"total_count": 0, "references": []}`,
correct since the body closed nothing, while still landing
`state_reason: "completed"` with `closed_by` naming the merger.
So the empty linkage array reads reassuringly and is silent about what the
branch's own commit messages say. (Note: `closed_by_pull_requests` later came to
reference #1276 because #1276's description quoted the commit line containing `(closes #1152)`
while documenting the mechanism.)

**How to apply:** whenever a sparta PR narrows to spec-only or partial after
being claimed, grep its own history before merging, and edit the squash body at
merge time if a keyword is already there.

```bash
git log origin/main..HEAD --format=%B | grep -niE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?) #'
```

The upstream fix is proposed in `Morrison-Lab/ai-config#1500`, open as of
2026-08-16: the claim-commit template would write `refs #<N>`, keeping the
closing keyword on the PR body, which is the surface each review round
re-reads.
Its own body invites a veto rather than absorption, so treat the template as
unchanged until that PR merges.

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
soldier strike foes who cannot strike back") -- but it's easy to re-introduce the same class of
bug in a NEW proximity check that doesn't reuse that exact code path.

**Concrete case:** PR #760's `SoldierEnemyProximity.has_enemy_within(pos, team, self_radius)`
computed `contact = self_radius + candidate_radius + candidate_reach` -- using only the
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

## The Coverage CI job shifts sim timing -- read spawn values PRE-tick and budget arcs in real sim ticks

Sparta's non-gating **Coverage** job (`test-coverage.yml`) runs the GUT suite through
`addons/coverage`, which reloads counter-injected copies of the game scripts. That
instrumentation slows and shifts sim stepping, so timing-bounded scenario assertions read
drifted values and flake there while the gating "Validate & test" job passes them. This
flaked on `main` itself (#508, fixed in PR #511), not tied to any one PR. Two patterns and
their fixes (both in `test/unit/test_battle_scenario.gd` and `test_rout_rally_demo_scenario.gd`):

- **Spawn/override-value asserts must read PRE-tick.** Reading a unit's `morale`/`facing`
  after `await get_tree().physics_frame` lets one recovery/rotation tick drift it off the
  exact spawn value (morale 30.0 read as 30.033; facing -1.0 read as -0.928). `Battle._ready()`
  runs **synchronously** during `add_child_autofree(battle)` -- it calls `_spawn_scenario()`,
  which registers each unit in the `"units"` group and sets `facing`/`morale` before returning.
  So delete the `await` and assert spawn values immediately; no tick can fire between
  `add_child` returning and the group query.
- **Budget scenario arcs in REAL sim ticks, not await-iterations.** Under instrumentation an
  `await physics_frame` no longer maps 1:1 onto a sim tick, so a `for i in range(N)` loop's
  index diverges from the sim's real tick. Bound the loop by `Battle.current_tick()` (incremented
  once per `_physics_process`) and derive the budget from sim constants with headroom, e.g.
  `ROUT_ONSET_BUDGET + ceil(Unit.ROUT_TIME * Replay.PHYSICS_TPS) + RALLY_MARGIN`. Prefer the
  canonical `Replay.PHYSICS_TPS` autoload over a duplicated `:= 60` local. Prefer read-pre-tick
  / real-tick budgets over loosening tolerances -- a wider tolerance still races the clock.

When widening such a budget, also account for OTHER in-flight PRs that shift the same sim
dynamics (a physics retune moves *when* the block breaks) so the later PR won't re-break the
test on resync -- widen via the named headroom constant, never by weakening an assertion.
(`Lacaedemon/sparta` #508/PR #511, coordinated with #497.)

## Soldier bodies ARRIVE at their slots under bounded force -- not a damped spring

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
follow, so the **post-step inbound clamp** -- not the desired-velocity cap -- is the real overshoot
guard; (2) tests asserting the old spring's single-step velocity magnitudes had to be re-derived
to the multi-tick ramp (a body ramps to top speed over many ticks, not in one step -- loop 120-360
ticks and assert the invariant throughout). Knockback impulses are untouched: a body holds the
push, then decelerates and returns under bounded force. This is the concrete mechanism behind the
"no snaps / bottom-up physics" philosophy at the top of this file; later PRs (#742/#743 coasting,
#749 body→position coupling) build on top of it rather than replacing it. (Physics constants and
exact function shapes will have moved further by the time you read this -- verify against current
`scripts/SoldierBodies.gd` before relying on specifics; the anti-spring invariant itself is durable.)

## Any live-Battle test that runs a fight must seed `Replay.forced_seed`

A scenario/integration test that instantiates `scenes/Battle.tscn` and lets it run a fight draws
all combat randomness through `Replay.rng` (SoldierMelee land/wound rolls). If the test does not
seed the RNG, those rolls draw from whatever `Replay.rng` state the *previously-run tests* left --
so the outcome varies with suite ordering and the test flakes. This is a latent non-determinism
bug independent of any one PR; a physics change just **exposes** it by shifting an arc onto a
decision boundary.

**Concrete case (#497/#465):** `test/unit/test_rout_rally_demo_scenario.gd` began flaking ~50% of
full-suite runs (passed 100% in isolation) after the spring→arrival physics merged: the routing
unit **shattered** instead of rallying, tripping `assert_not_null`. A seeded trace
(`forced_seed=12345`) showed the arc routs ~tick 413 and rallies ~tick 774 -- well within budget --
so the physics was fine; an unlucky casualty streak was grinding the router below
`SHATTER_STRENGTH_FRAC` or keeping an enemy inside `RALLY_CONTACT_RADIUS` at timer expiry.

**Fix:** seed deterministically in the spawn helper, exactly as the demo it guards does
(`Replay.forced_seed = 12345` **before** `add_child`; `Battle._ready()` folds it into `rng.seed`
via `Replay.start_recording()` and resets `forced_seed = -1`, one-shot per spawn). This is a
distinct failure mode from the coverage-timing budget flake above -- that's about *when* an arc
completes, this is about *whether* it completes the same way each run. When a physics/balance
change surfaces a scenario-test failure, first ask "is this test deterministic?" -- fix the
determinism, don't widen a budget to mask a boundary-brush. (`Lacaedemon/sparta` #497/#465.)

## Per-soldier sim cost scales SUPER-linearly -- the reference battle already sits at the 60fps budget

Measured via #549 (PR #551): `tools/benchmark/run-benchmark.sh` against
`benchmarks/scenarios/large-battle.json`, scaled by `SPARTA_BENCHMARK_SCALE`
(`BenchmarkStats.scale_scenario`). Headless, physics-step time only (no render):

| soldiers | mean tick | p95 tick | implied fps |
| --- | --- | --- | --- |
| 1,720 (1x, reference) | 16.97 ms | 21.28 ms | 58.9 |
| 3,440 (2x) | 52.92 ms | 63.79 ms | 18.9 |
| 6,880 (4x) | 207.82 ms | 235.29 ms | 4.8 |

Cost is **super-linear**: 2x soldiers → ~3.1x tick cost, 4x → ~12x -- consistent with PLAN.md's
O(n²) neighbor-scan note; the per-soldier layer (`_sim_soldier_pos`/`SoldierSpatialHash`) hasn't
fully escaped that shape. **The reference battle (1,720 soldiers) already sits at the 60fps budget
(16.67 ms/tick) on mean tick cost, and over budget on p95, before render cost.** So the current
architecture can't comfortably support a battle much larger than this at 60fps without a further
algorithmic win beyond the spatial hash. Treat this as a real, measured headroom constraint for
#550 (Cannae-scale) and any per-entity-granularity decision (per-soldier speed, weapon/shield
objects, individual orders): before adding another per-soldier array pass, re-run the benchmark and
check whether it pushes the curve further from linear -- that's the signal an O(n) win is needed
before growing headcount. The exact multipliers drift as the sim evolves; the super-linear *shape*
is structural. (One-machine local sweep, not the PLAN.md reference-hardware numbers; re-measure
before citing exact figures.)

**Concrete regression + fix, PR #981 (#240 melee standoff):** `SoldierMeleeStandoff.accumulate`
originally called `SoldierEnemyProximity.rebuild(units, frame)` unconditionally every tick -- a full
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
being enough -- verified here by benchmarking after each stacked fix rather than assuming.

## CI workflows render AUTHOR-controlled data -- keep it as data, never let it reach a shell as code

`demo-video.yml` and its siblings run against author-controlled input: a PR author writes the demo
manifest (`demos/demo.<slug>.json`), input scripts (`demos/inputs/*.json`), captions, tick lists.
On a same-repo PR this runs on a **write-privileged** runner (pushes `demo-media`, comments on the
PR), so shell injection is a real supply-chain hole. Conventions (follow them in any workflow that
renders author data -- established #506/PR #507, widened #549/PR #551):

1. **Author values reach steps via `env:`, never `${{ }}` interpolation** -- `${{ }}` expands into
   the script text *before* the shell parses it, so `"; rm -rf … #` becomes code. Pass as
   `env: CAPTION: ${{ … }}` and use `"$CAPTION"`.
2. **jq programs are fixed string literals; data goes in as `--arg`/file operands** -- never build a
   filter by interpolation (e.g. `jq -r '(.state // .frames // []) | map(tostring) | join(",")' "$SOURCE"`).
3. **Emit free text via `printf '%s'` with the value as an ARGUMENT**, not `echo`/`eval`; the
   `GITHUB_OUTPUT` heredoc uses a **random delimiter** (`caption_eof_$(openssl rand -hex 8)`) so
   author text can't smuggle extra outputs.
4. **A dynamic `export "${ENVVAR}=…"`** is safe only because `ENVVAR` is from a fixed set
   (`SPARTA_DEMO_REPLAY`/`SPARTA_DEMO_INPUT`), not author free-text.

**This isn't only about malicious input -- it silently breaks your OWN generated values too.** In
`benchmark.yml` a step built a markdown code span (`` `tools/benchmark/baseline.json` ``) from
trusted script output, stored it via `GITHUB_OUTPUT`, and a later step spliced it with `${{ }}`
inside a quoted bash string -- the backticks re-entered as live command substitution and the entire
span silently vanished from the posted comment (nothing errored). Route ANY `steps.*.outputs.*`
containing shell metacharacters through `env:`, not `${{ }}`-splicing. Also note `$()` strips
*trailing* newlines, so `BODY="$BODY"$(printf '\n\n')` is a no-op -- fold separators into the same
`printf` format string. Verify comment-body assembly by simulating it in bash and `cat -A`-ing the
result; a green job doesn't prove the posted message is correct.

## Gating a CI check on "does this posted artifact still match HEAD" needs a live re-read at job completion

A workflow job that posts something derived from `github.event.pull_request.head.sha` (a demo
comment, a state transcript) uses a SHA fixed at *trigger* time -- a push landing after trigger but
before the job finishes leaves a green job whose artifact cites a stale SHA.
`concurrency: cancel-in-progress` is the first defense but its propagation isn't instantaneous.

**Pattern (added to `demo-video.yml`, #542/PR #544):** as a final step in the *same* posting job,
re-read the PR's **live** head SHA from the API (`gh api repos/OWNER/REPO/pulls/$PR --jq .head.sha`)
-- not the event payload -- compare to the SHA the job posted against, and `exit 1` on mismatch. This
makes success self-verifying: green means the artifact was fresh as of the job's own completion.
Fold it into the posting job itself; a separate cross-check job just reintroduces the race one level
out. **Retry the lookup separately from the staleness verdict** -- under `set -euo pipefail` a
transient `gh api` failure aborts with a raw error that reads like "stale," so wrap the lookup in a
small retry loop and emit two distinct messages ("could not read PR head -- transient API failure,
not a staleness verdict" vs. "HEAD moved to X, evidence is for Y, failing as stale"). A bot reviewer
caught the missing-retry gap in round 1. (General CI pattern, but instantiated here in
`demo-video.yml`.)

