extends GutTest
## SoldierEncirclement: per-soldier encirclement detection and the break-to-individual-melee
## response (a SHIELD_WALL/TESTUDO soldier genuinely surrounded stops benefiting from its
## unit's shield-lock stance and steers toward the widest gap between its attackers instead of
## holding its formation slot). These pin: the pure geometry (is_surrounded's hemisphere-arc
## threshold, retreat_direction's largest-gap bisector), the accumulate() engaged-tier
## scoping and SHIELD_WALL/TESTUDO-only eligibility (SQUARE/SCHILTRON never break), the
## additive composition onto `_sim_steer`, the flag clearing the instant a soldier is no
## longer surrounded, reap() compaction, and the bounded-velocity (no-teleport) retreat.

const DT: float = 1.0 / 60.0


# --- pure is_surrounded() -------------------------------------------------------------

func test_is_surrounded_false_with_fewer_than_two_contacts() -> void:
	assert_false(SoldierEncirclement.is_surrounded(PackedVector2Array()), "no contacts at all")
	assert_false(SoldierEncirclement.is_surrounded(PackedVector2Array([Vector2.UP])),
		"a single contact can never span more than a point")


func test_is_surrounded_false_when_contacts_all_cluster_in_front() -> void:
	# Three contacts within a narrow ~20 degree cone -- easily covered by one facing hemisphere.
	var contacts := PackedVector2Array([
		Vector2.RIGHT.rotated(deg_to_rad(-10.0)),
		Vector2.RIGHT,
		Vector2.RIGHT.rotated(deg_to_rad(10.0)),
	])
	assert_false(SoldierEncirclement.is_surrounded(contacts), "a tight frontal cluster is not surrounded")


func test_is_surrounded_true_when_attacked_from_directly_front_and_rear() -> void:
	# The textbook case: two contacts exactly PI apart. No single facing hemisphere can keep
	# BOTH strictly in front (Unit._is_frontal_attack's own dot > 0.0 test) -- the only
	# candidate facing sits exactly on the knife-edge (dot == 0.0 for both), which that test
	# would already treat as not-frontal.
	var contacts := PackedVector2Array([Vector2.UP, Vector2.DOWN])
	assert_true(SoldierEncirclement.is_surrounded(contacts), "front + rear at once is surrounded")


func test_is_surrounded_true_with_three_contacts_evenly_spaced_around_the_circle() -> void:
	var contacts := PackedVector2Array([
		Vector2.RIGHT,
		Vector2.RIGHT.rotated(deg_to_rad(120.0)),
		Vector2.RIGHT.rotated(deg_to_rad(240.0)),
	])
	assert_true(SoldierEncirclement.is_surrounded(contacts),
		"three evenly-spaced attackers (120 degrees apart) can't all fit in one hemisphere")


func test_is_surrounded_false_for_two_contacts_well_short_of_opposite() -> void:
	# 90 degrees apart -- comfortably within a single 180-degree hemisphere.
	var contacts := PackedVector2Array([Vector2.RIGHT, Vector2.UP])
	assert_false(SoldierEncirclement.is_surrounded(contacts), "a 90-degree spread still fits in one hemisphere")


func test_is_surrounded_ignores_degenerate_zero_length_contacts() -> void:
	# A co-located contact (zero-length relative vector) has no defined bearing -- it must be
	# dropped rather than treated as a real direction that could flip the verdict.
	var contacts := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(5.0))])
	assert_false(SoldierEncirclement.is_surrounded(contacts),
		"the degenerate entry is dropped, leaving only a tight frontal pair")


# --- pure retreat_direction() ----------------------------------------------------------

func test_retreat_direction_is_zero_for_fewer_than_two_contacts() -> void:
	assert_eq(SoldierEncirclement.retreat_direction(PackedVector2Array()), Vector2.ZERO)
	assert_eq(SoldierEncirclement.retreat_direction(PackedVector2Array([Vector2.UP])), Vector2.ZERO)


func test_retreat_direction_points_into_the_widest_gap_opposite_a_tight_cluster() -> void:
	# Three contacts clustered near angle 0 -- the widest gap is the rest of the circle, whose
	# midpoint sits directly opposite the cluster.
	var contacts := PackedVector2Array([
		Vector2.RIGHT.rotated(deg_to_rad(-10.0)),
		Vector2.RIGHT,
		Vector2.RIGHT.rotated(deg_to_rad(10.0)),
	])
	var dir: Vector2 = SoldierEncirclement.retreat_direction(contacts)
	assert_lt(dir.x, -0.9, "retreats away from the cluster (roughly -x)")
	assert_almost_eq(dir.y, 0.0, 0.05, "no lateral component for a symmetric cluster")
	assert_almost_eq(dir.length(), 1.0, 0.01, "a unit vector")


func test_retreat_direction_bisects_an_asymmetric_gap() -> void:
	# RIGHT is at 0 degrees, UP is at -90 (Godot's Vector2.UP is (0, -1)): the two candidate
	# gaps between them are 90 (from -90 up to 0) and 270 (from 0 back around to -90+360=270)
	# -- the retreat heading bisects the WIDER one, at 0 + 270/2 = 135.
	var contacts := PackedVector2Array([Vector2.RIGHT, Vector2.UP])
	var dir: Vector2 = SoldierEncirclement.retreat_direction(contacts)
	var expected: Vector2 = Vector2.from_angle(deg_to_rad(135.0))
	assert_almost_eq(dir.x, expected.x, 0.01)
	assert_almost_eq(dir.y, expected.y, 0.01)


# --- accumulate() integration -----------------------------------------------------------

func _unit(uid: int, team: int, pos: Vector2, face: Vector2, formation: int, count: int = 1) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.uid = uid   # bare Unit.new() defaults to uid -1 -- soldier_id() would collide across units
	u.team = team
	u.position = pos
	u.facing = face
	u.attack_range = 26.0
	# file_major_reform's aspect-ratio ceiling would offset a small unit's lone soldier off
	# `position` -- row-major keeps these geometry-sensitive fixtures centred exactly there,
	# matching the established fixture pattern in test_soldier_melee.gd / test_soldier_melee_standoff.gd.
	u.file_major_reform = false
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)      # latch is_engaged() true
	u.seed_sim_soldiers()    # seed bodies (_sim_soldier_pos/_sim_steer/_sim_soldier_broken)
	u.set_formation(formation)
	return u


func before_each() -> void:
	SoldierEncirclementProximity.reset()   # frame-keyed static cache -- isolate each test


func test_accumulate_marks_a_soldier_broken_when_genuinely_surrounded() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([wall, front, rear], 1)
	assert_eq(wall._sim_soldier_broken[0], 1, "attacked from front and rear at once -- genuinely surrounded")


func test_accumulate_does_not_mark_broken_when_only_attacked_frontally() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([wall, front], 1)
	assert_eq(wall._sim_soldier_broken[0], 0, "a single frontal contact is not encirclement")


func test_accumulate_adds_the_retreat_bias_into_sim_steer_when_surrounded() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([wall, front, rear], 1)
	assert_almost_eq(wall._sim_steer[0].length(), SoldierEncirclement.RETREAT_STRENGTH, 0.01,
		"the retreat bias is full strength, matching SoldierMeleeStandoff's own bias magnitude convention")


func test_accumulate_does_not_touch_sim_steer_when_not_surrounded() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([wall, front], 1)
	assert_almost_eq(wall._sim_steer[0].length(), 0.0, 1e-4, "no retreat bias without genuine encirclement")


func test_accumulate_composes_additively_onto_an_existing_steer_bias() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	wall._sim_steer[0] = Vector2(0.0, 7.0)   # pretend an earlier pass already wrote a bias
	SoldierEncirclement.accumulate([wall, front, rear], 1)
	assert_almost_eq(wall._sim_steer[0].y, 7.0, 1e-4, "the pre-existing bias survives untouched")
	assert_gt(absf(wall._sim_steer[0].x), 0.0, "the retreat bias composes additively on top of it")


func test_accumulate_never_marks_a_square_unit_broken_even_when_fully_surrounded() -> void:
	# SQUARE is the deliberate all-around stance -- being surrounded is the design, not a
	# breakdown, so breaks_under_encirclement() excludes it entirely regardless of geometry.
	var square := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SQUARE)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([square, front, rear], 1)
	assert_eq(square._sim_soldier_broken[0], 0, "SQUARE never individually breaks under encirclement")
	assert_almost_eq(square._sim_steer[0].length(), 0.0, 1e-4, "and gets no retreat bias either")


func test_accumulate_never_marks_a_normal_formation_unit_broken() -> void:
	# NORMAL has no shield-lock stance bonus to lose in the first place.
	var line := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_NORMAL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([line, front, rear], 1)
	assert_eq(line._sim_soldier_broken[0], 0, "NORMAL formation is not eligible to break")


func test_accumulate_clears_a_previously_broken_flag_once_no_longer_surrounded() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([wall, front, rear], 1)
	assert_eq(wall._sim_soldier_broken[0], 1, "sanity: genuinely surrounded at first")
	rear._sim_soldier_pos[0] = Vector2(9000, 9000)   # the rear attacker withdraws -- an opening appears
	SoldierEncirclement.accumulate([wall, front, rear], 2)   # a new frame, so the grid rebuilds fresh
	assert_eq(wall._sim_soldier_broken[0], 0, "no longer surrounded -- rejoins immediately, no latch/hysteresis")


func test_accumulate_clears_a_stale_broken_flag_even_once_the_unit_fully_disengages() -> void:
	# Regression: the perf early-out (skip the expensive gather+grid rebuild when nobody is
	# currently engaged) must not also skip clearing already-set broken flags -- a unit that
	# stops fighting entirely (ENGAGED_LINGER decays to 0, or its attackers are wiped out)
	# must not keep rendering a stale broken tint forever, since nothing else ever clears
	# _sim_soldier_broken and the render path has no engagement gate of its own.
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	SoldierEncirclement.accumulate([wall, front, rear], 1)
	assert_eq(wall._sim_soldier_broken[0], 1, "sanity: genuinely surrounded at first")

	wall.state = Unit.State.IDLE
	wall._engaged_linger = 0.0   # fully out of the fight -- linger and FIGHTING both clear
	SoldierEncirclement.accumulate([wall, front, rear], 2)   # a new frame -- the perf early-out fires
	assert_eq(wall._sim_soldier_broken[0], 0,
		"the stale flag is cleared even though the expensive gather+rebuild was skipped entirely")


func test_accumulate_skips_a_dead_eligible_unit() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	wall.state = Unit.State.DEAD
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	var before: PackedByteArray = wall._sim_soldier_broken.duplicate()
	SoldierEncirclement.accumulate([wall, front, rear], 1)
	assert_eq(wall._sim_soldier_broken, before, "a DEAD unit is never checked for encirclement")


func test_accumulate_ignores_a_ranged_units_engaged_soldiers_from_the_candidate_pool() -> void:
	# Regression: a ranged (archer) unit's large weapon reach must not register as a melee
	# "contact" from a distance -- "surrounded" is a melee-structural concept, not "an archer
	# is shooting at me from somewhere". Reproduces the real testudo-under-fire.json defect:
	# a testudo unit ringed by pure-ranged archers must never show any broken soldiers.
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var ranged_rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	ranged_rear.is_ranged = true
	ranged_rear.attack_range = 160.0   # a typical ranged weapon's much longer reach
	SoldierEncirclement.accumulate([wall, front, ranged_rear], 1)
	assert_eq(wall._sim_soldier_broken[0], 0,
		"the ranged unit's soldiers never enter the candidate pool -- only the melee frontal attacker counts")


func test_accumulate_ignores_a_dead_units_engaged_soldiers_from_the_candidate_pool() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var dead_rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	dead_rear.state = Unit.State.DEAD
	SoldierEncirclement.accumulate([wall, front, dead_rear], 1)
	assert_eq(wall._sim_soldier_broken[0], 0,
		"a dead unit's soldiers don't count as contacts -- only the live frontal attacker remains")


func test_accumulate_is_a_no_op_when_nothing_is_engaged() -> void:
	var wall: Unit = Unit.new()
	wall.max_soldiers = 1
	add_child_autofree(wall)
	wall.uid = 1
	wall.team = 0
	wall.seed_sim_soldiers()
	wall.set_formation(Unit.FORMATION_SHIELD_WALL)   # state defaults to IDLE -- never engaged
	var before: PackedByteArray = wall._sim_soldier_broken.duplicate()
	SoldierEncirclement.accumulate([wall], 1)
	assert_eq(wall._sim_soldier_broken, before, "nothing engaged -- no crash from the perf-critical early return")


func test_accumulate_skips_a_unit_with_a_mismatched_broken_array() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	wall._sim_soldier_broken.resize(0)   # force the size-mismatch guard -- arrays mid-resize
	SoldierEncirclement.accumulate([wall, front, rear], 1)   # must not crash
	assert_eq(wall._sim_soldier_broken.size(), 0, "left untouched by the size-mismatch guard")


func test_accumulate_only_considers_the_engaged_tier_not_every_living_soldier() -> void:
	# The wall unit has two soldiers; only ONE index is flagged engaged (forced directly via
	# the unit's engaged-indices cache, bypassing the real formation-geometry computation, so
	# this isolates JUST the engaged-tier scoping, mirroring SoldierMeleeStandoff's own test).
	var wall := _unit(1, 0, Vector2(1000, 1000), Vector2.DOWN, Unit.FORMATION_SHIELD_WALL, 2)
	wall._sim_soldier_pos[0] = Vector2(1000, 1000)     # NOT engaged -- would be surrounded if it were
	wall._sim_soldier_pos[1] = Vector2(0, 0)           # engaged -- only frontally contacted
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(1000, 1020), Vector2.DOWN, Unit.FORMATION_NORMAL)   # only near soldier 0

	var frame: int = Engine.get_physics_frames()
	wall._engaged_indices_cache = PackedInt32Array([1])
	wall._engaged_indices_cache_frame = frame
	wall._engaged_indices_cache_count = 2
	wall._engaged_indices_cache_engaged = true

	SoldierEncirclement.accumulate([wall, front, rear], frame)

	assert_eq(wall._sim_soldier_broken[1], 0,
		"the engaged soldier (index 1) is only contacted frontally -- not surrounded")


func test_accumulate_skips_a_living_unit_with_zero_soldiers_in_the_gather() -> void:
	# A living (not DEAD) unit whose soldier arrays are empty (never seeded, or a full wipe
	# that hasn't been freed yet) must not crash the gather loop -- it simply contributes no
	# candidates, and the genuinely eligible wall unit still resolves normally alongside it.
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	var empty_unit: Unit = Unit.new()
	add_child_autofree(empty_unit)
	empty_unit.uid = 4
	empty_unit.team = 1
	empty_unit.state = Unit.State.FIGHTING
	empty_unit.tick_engaged(0.1)   # engaged, but seed_sim_soldiers() was never called -- _sim_soldier_pos.size() == 0
	SoldierEncirclement.accumulate([wall, front, rear, empty_unit], 1)
	assert_eq(wall._sim_soldier_broken[0], 1,
		"the zero-soldier unit contributes nothing but doesn't break the pass for anyone else")


func test_accumulate_ignores_a_living_but_non_engaged_units_soldiers_from_the_candidate_pool() -> void:
	# A living unit that simply isn't in the engaged tier (no tick_engaged latch, state IDLE)
	# must not contribute contacts either -- distinct from the DEAD-unit skip above.
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var bystander: Unit = Unit.new()
	add_child_autofree(bystander)
	bystander.uid = 3
	bystander.team = 1
	bystander.position = Vector2(0, 20)
	bystander.facing = Vector2.DOWN
	bystander.file_major_reform = false
	bystander.seed_sim_soldiers()   # state defaults to IDLE -- never engaged, so contributes no candidates
	SoldierEncirclement.accumulate([wall, front, bystander], 1)
	assert_eq(wall._sim_soldier_broken[0], 0,
		"the idle bystander's soldiers never enter the candidate pool -- only the frontal attacker counts")


func test_accumulate_skips_an_eligible_unit_that_is_not_itself_currently_engaged() -> void:
	# any_eligible only needs ONE breaks_under_encirclement unit to be engaged to proceed past
	# the perf early-out -- a SECOND eligible (SHIELD_WALL) unit that isn't engaged itself must
	# still be handled without crashing (its own engaged_soldier_indices() is empty).
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	var idle_wall: Unit = Unit.new()
	add_child_autofree(idle_wall)
	idle_wall.uid = 4
	idle_wall.team = 0
	idle_wall.position = Vector2(9000, 9000)
	idle_wall.file_major_reform = false
	idle_wall.seed_sim_soldiers()
	idle_wall.set_formation(Unit.FORMATION_SHIELD_WALL)   # eligible, but never engaged
	SoldierEncirclement.accumulate([wall, front, rear, idle_wall], 1)
	assert_eq(wall._sim_soldier_broken[0], 1, "the genuinely engaged wall still resolves correctly")
	assert_eq(idle_wall._sim_soldier_broken[0], 0, "the non-engaged eligible unit is simply skipped, no crash")


func test_reap_compacts_the_broken_flag_alongside_other_arrays() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL, 2)
	wall._sim_soldier_broken[0] = 1
	wall._sim_soldier_broken[1] = 0
	wall._sim_soldier_hp[0] = 0.0   # soldier 0 dies
	SoldierMelee.reap(wall, wall)
	assert_eq(wall.soldiers, 1, "one soldier died")
	assert_eq(wall._sim_soldier_broken.size(), 1, "the broken flag array tracks the live count")
	assert_eq(wall._sim_soldier_broken[0], 0,
		"the surviving soldier keeps its OWN flag (the dead soldier's index 0 slot, not a stale copy)")


# --- bounded-velocity retreat: no teleport ----------------------------------------------

func test_broken_soldier_retreats_at_bounded_velocity_never_teleporting() -> void:
	var wall := _unit(1, 0, Vector2.ZERO, Vector2.DOWN, Unit.FORMATION_SHIELD_WALL)
	var front := _unit(2, 1, Vector2(0, -20), Vector2.UP, Unit.FORMATION_NORMAL)
	var rear := _unit(3, 1, Vector2(0, 20), Vector2.DOWN, Unit.FORMATION_NORMAL)
	var frame: int = Engine.get_physics_frames()
	SoldierEncirclement.accumulate([wall, front, rear], frame)
	assert_eq(wall._sim_soldier_broken[0], 1, "sanity: genuinely surrounded")

	var start_pos: Vector2 = wall._sim_soldier_pos[0]
	wall.step_sim_soldiers(DT)
	var moved_one_tick: float = wall._sim_soldier_pos[0].distance_to(start_pos)
	assert_gt(moved_one_tick, 0.0, "the retreat bias moves the body")
	assert_lt(moved_one_tick, 1.0, "one tick under bounded acceleration moves only a tiny distance -- no teleport")

	for _i in range(59):   # the rest of the first second
		wall.step_sim_soldiers(DT)
	var moved_one_second: float = wall._sim_soldier_pos[0].distance_to(start_pos)
	assert_gt(moved_one_second, moved_one_tick, "the body keeps retreating over time")
	assert_lt(moved_one_second, 60.0, "still bounded -- nowhere near a teleport-scale jump")
	# The retreat direction is deterministic (a tie-break on the first-encountered widest gap,
	# see retreat_direction's own doc comment): straight along +x for this exactly-opposite
	# front/rear geometry.
	assert_gt(wall._sim_soldier_pos[0].x, 0.0, "retreats along the computed gap bisector (+x)")
	assert_almost_eq(wall._sim_soldier_pos[0].y, 0.0, 0.5, "no lateral drift for this symmetric setup")
