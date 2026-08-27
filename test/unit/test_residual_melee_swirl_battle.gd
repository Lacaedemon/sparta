extends GutTest
## Regression guard for the melee-lock swirl left over after the enemy-contact impulse
## symmetry fix. Two matched Infantry regiments clash head-on and grind; neither regiment's
## `facing` should pivot away from its start heading while the clash is still forming.
## Live-battle, tick by tick, per this repo's own convention of verifying maneuver/collision
## physics against real sim state rather than eyeballing demo frames -- see
## .claude/memories/sparta.md.
##
## The mechanism being guarded: `Unit.engaged_soldier_indices()` selects the engaged front
## rank/perimeter by LIVE POSITION, but once a casualty compacts the per-soldier arrays
## (SoldierMelee.reap's remove_at splice), a live-selected body's own array index no longer
## maps to a front/perimeter formation slot. SoldierBodies.step()'s arrival term and
## SoldierBodies.couple()'s drift measurement both read `slots[i]` for that same (possibly
## reindexed) `i`, comparing each live-engaged body against a mismatched target, and the
## drift that leaks out of the mismatch turns the whole block. Fixed via
## `Unit.canonical_target_slot_indices()`, which scores the STATIC slot grid with the same
## selection functions so step() and couple() agree on a like-for-like target. Casualties
## are what arm the defect, so the window below is asserted to contain real ones -- a
## bloodless window would pass this guard for the wrong reason.
##
## ## Why the opening window, across several seeds, rather than one seed at tick 700
##
## This file used to assert a single seed's rotation at tick 700 against a fixed 28-degree
## ceiling. That formulation was measured against a deliberately regressed build (the
## canonical-slot mapping disabled in both step() and couple()) and carries no signal:
##
## | seed     | fix in place | fix disabled |
## | -------- | ------------ | ------------ |
## | 12345    | 39.9         | 41.4         |
## | 99999    | 17.8         |  2.3         |
## | 424242   | 20.5         | 31.8         |
## | 1        | 23.7         |  0.6         |
## | 777      | 58.0         | 90.5         |
## | 20260805 | 37.5         | 36.3         |
##
## Removing the fix makes tick 700 worse at three of six seeds and BETTER at the other
## three, and the healthy column alone spans 17.8 to 58.0 degrees -- so no threshold
## anywhere in that range separates a healthy build from a regressed one, and a
## single-seed gate there passes or fails on which seed it pins. That quantity is also
## platform-divergent (a 700-tick 200-soldier melee is exactly the chaotic regime this
## repo's memories document as diverging between local and CI runs of an identical seed),
## which is why the old ceiling passed locally while failing on CI.
##
## The OPENING of the clash does separate, and is stable seed to seed. Worst deviation
## reached within the first 300 ticks, same two builds, same eight seeds
## (headless Linux, Godot 4.7.stable; measured at the PRE-REBALANCE pace -- superseded by
## the recalibration in the next section, kept as the record of the method):
##
## | seed     | fix in place | fix disabled |
## | -------- | ------------ | ------------ |
## | 12345    | 2.84         | 14.45        |
## | 99999    | 2.86         |  5.20        |
## | 424242   | 2.85         |  1.97        |
## | 1        | 2.85         |  5.50        |
## | 777      | 3.44         | 12.09        |
## | 20260805 | 3.06         |  6.76        |
## | 31337    | 3.06         |  4.26        |
## | 5150     | 2.86         |  1.94        |
## | **mean** | **2.98**     | **6.52**     |
##
## A healthy build holds a 2.84-3.44 degree band across every seed -- the contact transient
## itself, not swirl -- while the regressed one ranges 1.94 to 14.45. Two of its seeds land
## UNDER the healthy band, so a per-seed ceiling cannot be the discriminator here: the SEED
## MEAN is (2.98 against 6.52), and the per-seed ceiling is a looser backstop so one blown
## seed cannot hide behind seven good ones. Both bounds are stated below with the margin
## they carry.
##
## ## Recalibrated for the close-order density rebalance
##
## The 2x-pyknosis default slowed the whole arc (an intended pace change, per the owner's
## ruling): contact now forms around tick 151 on every seed, and the FIRST CASUALTY lands
## between tick 439 and 727 across the eight seeds -- entirely outside the old 300-tick
## opening window, which had become bloodless and therefore vacuous (its own casualty
## assert caught exactly that). A fixed-length window cannot be stretched to compensate:
## by tick 900 a healthy build's deviation already spans 0.50 to 44.28 degrees (the
## documented tangential-shear fan-out below), so a fixed late window loses discrimination
## the same way the old tick-700 gate did.
##
## The defect this file guards is ARMED by casualty compaction, so the window is now
## anchored on each run's own arming event: the asserted span is [0, first_cas +
## ARMED_WINDOW_TICKS]. Same two builds (the canonical-slot mapping disabled in both
## step() and couple()), same eight seeds, worst deviation within that span, measured
## headless on Windows under the rebalanced density:
##
## | seed     | fix in place | fix disabled |
## | -------- | ------------ | ------------ |
## | 12345    |  38.46       | 179.96       |
## | 99999    |  21.79       | 179.79       |
## | 424242   |   7.76       | 178.16       |
## | 1        |  16.08       | 176.65       |
## | 777      |   0.11       |   0.11       |
## | 20260805 |  11.95       | 177.52       |
## | 31337    |  16.54       | 179.84       |
## | 5150     |  15.18       | 178.90       |
## | **mean** | **15.98**    | **156.37**   |
##
## The regressed build reaches the full melee-lock spin (176.7-180.0 degrees) on seven of
## eight seeds; seed 777 arms late (its spin arrives after the armed window closes) and
## lands under the healthy band, so -- exactly as in the original calibration -- the SEED
## MEAN is the discriminator and the per-seed ceiling is the backstop. At first_cas + 150
## BOTH builds still read ~0.0-0.07 degrees (the spin needs upwards of 150 post-compaction
## ticks to develop), which is why the armed tail is 300 ticks and not shorter.
##
## What this file deliberately does NOT assert: any bound on the late-window rotation. Clean
## main really does reach tens of degrees by tick 700 on some seeds (the first table above),
## and pretending to bound that would put the old silent-pass back.
##
## ## What drives the late window (measured)
##
## The late rotation is NOT this guard's own mechanism, and not a facing-logic feedback loop
## either. Measured on seed 777, sampling between every stage of Battle._on_soldier_tick and
## attributing each stage's contribution to the BEARING of the inter-unit vector.
##
## * `facing` is perfectly SLAVED to that bearing. Each regiment's facing-to-enemy residual
##   holds at ~0.3 degrees or less at every sample, and `turned_a`, `turned_b` and the
##   bearing's own rotation agree to a few hundredths. The two regiments' CENTRES orbit each
##   other at a locked separation (~34-45 wu) and each simply re-aims. `_face_for_action` is
##   a follower here, not a driver -- so the earlier mutual-re-facing-feedback family,
##   offered as the likely candidate, is ruled out.
## * Three things write `position` here: `_press_into` (from `_think`'s in-contact branch),
##   `Unit._separate()` (`:3396`, a capped displacement -- the velocity there bounds the write
##   rather than replacing it), and `SoldierBodies.couple`. The first two both run inside
##   `Unit._physics_process`, and the probe's `think` channel captures that whole function, so
##   they are bounded together rather than split. Of the -59.16 degrees of bearing rotation
##   accumulated by tick
##   700, `couple` carries -59.163 and the whole `_physics_process` channel carries **0.002**
##   -- every regiment-level position write combined, so no split between them can matter at
##   that scale. `_press_into` aims
##   exactly at the enemy's centre, so it displaces both regiments along the line joining
##   them; a purely central displacement changes the separation's LENGTH and never its
##   direction, so it cannot rotate the pair however large it is -- with one caveat that does
##   not bite here: `_press_into` ends with two INDEPENDENT `clampf` calls on `position.x` and
##   `position.y`, so against a field edge one component truncates and the other does not, and
##   the displacement stops being central. This clash runs mid-field, so neither clamp ever
##   binds and the measurement is unaffected; a scenario pressed against a boundary needs the
##   argument re-derived. The radial magnitude is in
##   fact large (-1023 wu by tick 700, against couple's +937) -- but that figure belongs to
##   the same `_physics_process` channel, so it covers `_separate()`'s central push too and
##   is not `_press_into`'s alone. Radial either way, which is why the split does not matter
##   to the rotation.
## * `couple` is the conduit, not the origin: it only follows the bodies. The tangential
##   DIFFERENTIAL velocity injected into the two body clouds, projected perpendicular to the
##   current separation, is +2.82 from `SoldierEnemyContact` and +3.04 from the body
##   integration step, against 0.00 from every other stage. So the rotation originates as a
##   persistent one-signed tangential shear between the two engaged fronts, and reaches the
##   regiment centres through `couple`.
##
## Two limits on that attribution, stated because each is a place a reader could over-read
## it. The three steer-writing stages (`SoldierSteering`, `SoldierMeleeStandoff`,
## `SoldierEncirclement`) contribute 0.00 on the velocity channel BY CONSTRUCTION -- they
## write `_sim_steer`, which the integration step consumes as feed-forward -- so their
## effect is folded into that step's +3.04 and is not separately attributed here. And the
## split between `SoldierEnemyContact` and the integration step is a split between an
## impulse and the arrival term that partly answers it, not two independent sources.
##
## Not gated here, deliberately: bounding the shear would need a threshold calibrated
## against a build with that mechanism regressed, which is the method this file's own
## opening-window bounds came from. A bound added without that is decoration.
##
## Method note, for whoever picks that up. The attribution came from disconnecting
## `Battle._on_soldier_tick` and driving its six stages by hand from a test, sampling
## between them. Four traps, each of which produced a confident wrong answer first:
##
## 1. Projecting onto a FIXED world axis. The separation starts along +Y, which makes world
##    X look like the whole signal -- true only at t=0. Once the bearing has rotated tens of
##    degrees, world X carries a large RADIAL component, and the radial channel is dominated
##    by `_press_into`. Measured that way, `_press_into` appears to contribute +/-152 wu of
##    exactly anti-symmetric displacement and reads as the driver. It is not: project onto
##    the perpendicular of the CURRENT separation, or attribute the bearing angle directly
##    via `cross(r_hat, dr) / |r|`.
## 2. Reading exact anti-symmetry as evidence of a driver. It is the signature of a CENTRAL
##    pair, which is the one thing that cannot rotate anything.
## 3. A cumulative DELTA on `_sim_steer` telescopes to zero, because SoldierSteering clears
##    and rewrites that array every tick -- a vacuous 0.00, not an absence of contribution.
## 4. A battle that is not the FIRST in the process does not reproduce the trajectory (the
##    same seed measured 28.55 degrees as a second battle against 56.14 as the first), so a
##    separate preceding control run is worthless; the control has to be the measured run's
##    own tick-700 value.
## 5. An `awk '/^func NAME/,/^func .../' | grep` range over a GDScript function returns EMPTY
##    when the closing pattern also matches the opening line -- which it does whenever the
##    function's own signature has the return-type shape the closing pattern looks for. That
##    empty result reads as "this function does not do X". It cost a published false claim
##    about `_separate()` here. Print the range's own line count before grepping it, per this
##    repo's standing rule that a check must report what it examined and not only what it
##    found.
##
## Measured headless on Windows; the tables above are headless Linux. Seed 777 reproduces at
## 56.14 against the 58.0 recorded there, within the local/CI divergence this repo's memories
## document for a 700-tick 200-soldier melee.


# Seeds are arbitrary but FIXED: the point of several is that no single one decides the
# verdict, and the calibration above is only meaningful against the same set.
const SEEDS: Array = [12345, 99999, 424242, 1, 777, 20260805, 31337, 5150]
# The first casualty must land within this many ticks, or the run is vacuous (the defect
# is armed by casualty compaction). Measured 439-727 across the seeds locally; budgeted
# ~1.5x over the local worst for the local/CI divergence this file documents.
const FIRST_CAS_BUDGET: int = 1100
# The asserted window runs from tick 0 through first casualty plus this armed tail. The
# regressed build reads ~0.0-0.07 degrees at first_cas + 150 and 176.7-180.0 at
# first_cas + 300 (seven of eight seeds), so the tail must be long enough for the spin
# to develop; the healthy fan-out documented above is what rules out making it longer.
const ARMED_WINDOW_TICKS: int = 300
# Ceiling on the seed MEAN of the worst deviation within the anchored window. Healthy
# measures 15.98 (3.75x of headroom); the regressed build measures 156.37 and misses by
# 2.6x.
const MEAN_TURN_MAX_DEG: float = 60.0
# Backstop ceiling on any ONE seed's worst deviation. Healthy's worst single seed is
# 38.46 (3.1x of headroom); every non-laggard regressed seed reads 176.7+ and misses by
# 1.5x. Deliberately looser than the mean gate: it exists to catch a single regiment
# spinning out -- the melee-lock spin sweeps ~180 degrees inside this window -- not to
# re-litigate the seed-to-seed spread the mean gate covers.
const SEED_TURN_MAX_DEG: float = 120.0
# The clash: two identical regiments, head-on, close enough to meet early in the window.
const REGIMENT_COUNT: int = 100
const CLASH_X: float = 800.0
const CLASH_Y_TEAM0: float = 440.0
const CLASH_Y_TEAM1: float = 560.0

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _team_unit(team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			return unit
	return null


## Run one seed's clash and report the worst facing deviation either regiment reached at
## any point inside the anchored window [0, first_cas + ARMED_WINDOW_TICKS], plus what the
## fight actually did (so the caller can prove the window wasn't vacuous). Peak rather
## than end-of-window value: the deviation wanders, so a single end sample can read low on
## a block that swung wide mid-window. first_cas is -1 when no casualty landed inside
## FIRST_CAS_BUDGET, which the caller asserts against -- a bloodless run never armed the
## defect and must fail rather than pass empty.
func _clash_window(seed_value: int) -> Dictionary:
	Replay.forced_seed = seed_value   # before add_child; Battle._ready folds it into the RNG
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": CLASH_X, "y": CLASH_Y_TEAM0,
			"count": REGIMENT_COUNT},
		{"team": 1, "type": "Infantry", "x": CLASH_X, "y": CLASH_Y_TEAM1,
			"count": REGIMENT_COUNT},
	]
	add_child(_battle)
	await get_tree().physics_frame

	var a: Unit = _team_unit(0)
	var b: Unit = _team_unit(1)
	if a == null or b == null:
		return {"worst": INF, "fought": false, "casualties": 0, "first_cas": -1}

	var start_a: Vector2 = a.facing
	var start_b: Vector2 = b.facing
	var worst: float = 0.0
	var first_cas: int = -1
	var casualties: int = 0
	var tick: int = 0
	while true:
		await get_tree().physics_frame
		tick += 1
		if not (is_instance_valid(a) and is_instance_valid(b)):
			break   # a fully annihilated regiment frees its node; stop sampling freed refs
		worst = maxf(worst, rad_to_deg(absf(a.facing.angle_to(start_a))))
		worst = maxf(worst, rad_to_deg(absf(b.facing.angle_to(start_b))))
		casualties = (REGIMENT_COUNT - a.soldiers) + (REGIMENT_COUNT - b.soldiers)
		if first_cas < 0 and casualties > 0:
			first_cas = tick
		if first_cas < 0 and tick >= FIRST_CAS_BUDGET:
			break
		if first_cas > 0 and tick >= first_cas + ARMED_WINDOW_TICKS:
			break
	var fought: bool = is_instance_valid(a) and is_instance_valid(b) \
		and (a.state == Unit.State.FIGHTING or a.state == Unit.State.DEAD) \
		and (b.state == Unit.State.FIGHTING or b.state == Unit.State.DEAD)
	return {"worst": worst, "fought": fought, "casualties": casualties, "first_cas": first_cas}


func _free_battle() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func test_matched_infantry_clash_keeps_facing_close_to_its_start_heading() -> void:
	var total: float = 0.0
	var worst_seed: float = 0.0
	var report := ""
	for seed_value in SEEDS:
		var run: Dictionary = await _clash_window(int(seed_value))
		var worst: float = run["worst"]
		total += worst
		worst_seed = maxf(worst_seed, worst)
		report += " %d=%.2f@%d" % [int(seed_value), worst, int(run["first_cas"])]
		assert_true(run["fought"],
			"seed %d: both regiments made and held contact inside the window" % seed_value)
		# The defect this guards is armed by casualty-driven array compaction, so a run
		# whose window never contains a dead man would satisfy the bounds below without
		# exercising it at all. The window is anchored on the first casualty, so the
		# arming event has to actually arrive.
		assert_gt(int(run["first_cas"]), 0,
			"seed %d: the first casualty lands within %d ticks, so the arrays did compact inside the asserted window"
				% [seed_value, FIRST_CAS_BUDGET])
		assert_lt(worst, SEED_TURN_MAX_DEG,
			"seed %d: neither regiment spins out during the clash (worst %.2f deg)"
				% [seed_value, worst])
		await _free_battle()

	var mean: float = total / float(SEEDS.size())
	# Report the metric whether or not it passes: the seed-by-seed numbers are what a future
	# recalibration needs, and a bare pass/fail throws them away.
	print("[residual swirl] worst deviation within first_cas+%d ticks --%s | mean %.2f, worst %.2f"
		% [ARMED_WINDOW_TICKS, report, mean, worst_seed])
	assert_lt(mean, MEAN_TURN_MAX_DEG,
		"the regiments hold their heading through the opening of the clash (seed mean %.2f deg over %d seeds)"
			% [mean, SEEDS.size()])
