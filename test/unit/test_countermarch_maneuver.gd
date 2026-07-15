extends GutTest
## Countermarch (exelismos, issue #375): reverses which end of the block faces the enemy by
## marching files through each other -- built as a rear-move-style composite (about-face, then
## reform_ranks() brings a full rank to the new front, then a march) so it reuses that exact,
## already-tested machinery (see test_reform_ranks.gd / test_rear_move_conversio.gd). Isolated
## per-unit tests: _think() plus SoldierBodies.step() driven tick by tick, no Battle scene --
## see test_countermarch_battle.gd for the full-scene proof.

const TICK: float = 1.0 / 60.0


## A seeded unit whose grid has a PARTIAL last rank: 60 men at 8 files = 7 full ranks + 4.
## Same shape test_reform_ranks.gd uses, so the countermarch's reform step can be checked the
## same way: does a FULL rank end up leading, with the partial rank tucked to the new rear.
func _make_partial_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.seed_sim_soldiers()
	return u


## How many bodies stand in the unit's FRONT row: within half a rank spacing of the front-most
## body, measured by projection onto the unit's facing. Mirrors test_reform_ranks.gd's helper.
func _front_row_count(u: Unit) -> int:
	var best: float = -INF
	var proj: PackedFloat32Array = PackedFloat32Array()
	for p in u._sim_soldier_pos:
		var d: float = (p - u.position).dot(u.facing)
		proj.push_back(d)
		best = maxf(best, d)
	var count: int = 0
	for d in proj:
		if best - d < Unit.FORMATION_SPACING * 0.5:
			count += 1
	return count


## One sim tick of the isolated unit: the full unit layer plus the soldier-body arrival, the
## same two layers Battle drives each physics tick. Mirrors test_reform_ranks.gd's helper.
func _tick(u: Unit) -> void:
	u._physics_process(TICK)
	SoldierBodies.step(u, TICK)


## Run the whole countermarch composite to completion (current_order retires), or give up
## after `budget` ticks. Generous budget: an about-face (~0.5s), a reform hold sized to the
## unit's own depth/pace, and (for MACEDONIAN/LACONIAN) a real march at walk pace -- all
## comfortably inside a few hundred ticks for this test's small unit.
func _run_to_completion(u: Unit, budget: int = 900) -> void:
	for _i in range(budget):
		if u.current_order == null:
			return
		_tick(u)


# --- gating: the standalone drill contract every drill shares --------------

func test_countermarch_noops_while_fighting() -> void:
	var u := _make_partial_unit()
	u.state = Unit.State.FIGHTING
	u.countermarch(Unit.CountermarchVariant.CHORAL)
	assert_null(u.current_order, "a fighting unit refuses the drill, like conversio/wheel")


func test_countermarch_noops_before_bodies_are_seeded() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	# No seed_sim_soldiers() call: _can_drill() requires seeded bodies.
	u.countermarch(Unit.CountermarchVariant.CHORAL)
	assert_null(u.current_order, "a pre-seed unit refuses the drill")


# --- pure target-point geometry, one per variant ----------------------------

func test_countermarch_target_macedonian_advances_onto_the_new_facing_ground() -> void:
	var u := _make_partial_unit()
	var depth: float = u._countermarch_march_distance()
	assert_gt(depth, 0.0, "a multi-rank block has a real depth to march")
	var target: Vector2 = u._countermarch_target(Unit.CountermarchVariant.MACEDONIAN)
	assert_true(target.is_equal_approx(u.position - u.facing * depth),
		"Macedonian marches onto the ground the NEW (post-about-face) facing points at")


func test_countermarch_target_laconian_withdraws_along_the_old_facing() -> void:
	var u := _make_partial_unit()
	var depth: float = u._countermarch_march_distance()
	var target: Vector2 = u._countermarch_target(Unit.CountermarchVariant.LACONIAN)
	assert_true(target.is_equal_approx(u.position + u.facing * depth),
		"Laconian withdraws back along the OLD facing, away from the new-facing ground")


func test_countermarch_target_choral_stays_on_the_same_ground() -> void:
	var u := _make_partial_unit()
	var target: Vector2 = u._countermarch_target(Unit.CountermarchVariant.CHORAL)
	assert_eq(target, u.position, "Choral/Persian: no net translation at all")


func test_countermarch_march_distance_is_zero_for_a_single_rank() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 6
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.frontage_override = 8   # clamped to max_soldiers: 6 men in one single rank
	u.seed_sim_soldiers()
	assert_eq(u._countermarch_march_distance(), 0.0,
		"a single rank has no depth to march -- Macedonian/Laconian degenerate to Choral")


# --- full arc, one per variant: about-face, reform, (maybe) march ----------

func test_macedonian_countermarch_reverses_facing_reforms_and_advances() -> void:
	var u := _make_partial_unit()
	var start_facing: Vector2 = u.facing
	var start_pos: Vector2 = u.position
	var depth: float = u._countermarch_march_distance()
	u.countermarch(Unit.CountermarchVariant.MACEDONIAN)
	assert_true(u.is_order_turning(), "the about-face phase armed first")

	_run_to_completion(u)
	assert_null(u.current_order, "the whole composite retired within its budget")
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the unit ended facing the reverse of its start heading")
	assert_lt(u.position.distance_to(start_pos - start_facing * depth), 6.0,
		"the whole regiment advanced roughly one file-depth onto the new-facing ground")
	assert_eq(_front_row_count(u), 8,
		"a FULL rank fronts the new heading -- the reform brought it forward, not the 4-man partial")


func test_laconian_countermarch_reverses_facing_reforms_and_withdraws() -> void:
	var u := _make_partial_unit()
	var start_facing: Vector2 = u.facing
	var start_pos: Vector2 = u.position
	var depth: float = u._countermarch_march_distance()
	u.countermarch(Unit.CountermarchVariant.LACONIAN)

	_run_to_completion(u)
	assert_null(u.current_order, "the whole composite retired within its budget")
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the unit ended facing the reverse of its start heading")
	assert_lt(u.position.distance_to(start_pos + start_facing * depth), 6.0,
		"the whole regiment withdrew roughly one file-depth, away from the new-facing ground")
	assert_eq(_front_row_count(u), 8, "a FULL rank fronts the new heading here too")


func test_choral_countermarch_reverses_facing_reforms_and_stays_put() -> void:
	var u := _make_partial_unit()
	var start_facing: Vector2 = u.facing
	var start_pos: Vector2 = u.position
	u.countermarch(Unit.CountermarchVariant.CHORAL)

	_run_to_completion(u)
	assert_null(u.current_order, "the whole composite retired within its budget")
	assert_true(u.facing.is_equal_approx(-start_facing),
		"the unit ended facing the reverse of its start heading")
	assert_lt(u.position.distance_to(start_pos), 1.0,
		"Choral/Persian: the block reverses on the very ground it already stood on")
	assert_eq(_front_row_count(u), 8, "the reform still brings a full rank to the new front")


func test_countermarch_reports_order_summary_with_the_variant_name() -> void:
	var u := _make_partial_unit()
	u.countermarch(Unit.CountermarchVariant.LACONIAN)
	assert_eq(u.order_summary(), "Countermarching (Laconian)",
		"the HUD panel names the running variant, ahead of the generic about-facing text")


func test_countermarch_march_leg_targets_the_variant_destination() -> void:
	# Run just past the about-face + reform hold and confirm the parked march destination
	# (rather than re-deriving it from the final position, which the full-arc tests above
	# already cover) -- this pins down move_target directly, the same way
	# test_rear_move_conversio.gd's test_rear_move_about_faces_then_marches does.
	var u := _make_partial_unit()
	var depth: float = u._countermarch_march_distance()
	var expected: Vector2 = u.position - u.facing * depth   # Macedonian
	u.countermarch(Unit.CountermarchVariant.MACEDONIAN)
	var started := false
	for _i in range(600):
		if u.has_move_target:
			started = true
			break
		_tick(u)
	assert_true(started, "the parked march commits once the about-face and reform complete")
	assert_true(u.move_target.is_equal_approx(expected),
		"it marches to the Macedonian variant's computed destination")
