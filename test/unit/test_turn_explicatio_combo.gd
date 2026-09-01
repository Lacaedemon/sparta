extends GutTest
## Chained maneuver combos (docs/orders-queue-design.md, "Macro expansion") and their first
## concrete instance, the quarter-turn -> explicatio: Unit.begin_combo chains drill primitives
## as the children of one COMBO composite, the tree cascade (Unit._advance_order_tree) arms
## each step as it is promoted, and a relative file-double step resolves its width in the
## frame of the facing the turn left it in. Isolated per-unit tests: _think() plus
## SoldierBodies.step() driven tick by tick, no Battle scene -- see
## test_turn_explicatio_battle.gd for the full-scene proof.

const TICK: float = 1.0 / 60.0


## A seeded 40-man unit at 8 files: 5 full ranks, so the frontage the block presents after a
## quarter-turn (its old rank count) is 5, and an explicatio measured against the new facing
## lands on 10 files -- not on 16, which is what doubling the grid's own file count would give.
func _make_unit(count: int = 40, files: int = 8) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = files
	u.seed_sim_soldiers()
	return u


## One sim tick of the isolated unit: the unit layer plus the soldier-body arrival, the same
## two layers Battle drives each physics tick. Mirrors test_countermarch_maneuver.gd's helper.
func _tick(u: Unit) -> void:
	u._physics_process(TICK)
	SoldierBodies.step(u, TICK)


## Run the composite to completion (current_order retires), or give up after `budget` ticks.
func _run_to_completion(u: Unit, budget: int = 600) -> void:
	for _i in range(budget):
		if u.current_order == null:
			return
		_tick(u)


## Extent of the soldier bodies along `axis` (a unit vector): max minus min projection.
func _extent_along(u: Unit, axis: Vector2) -> float:
	var lo: float = INF
	var hi: float = -INF
	for p in u._sim_soldier_pos:
		var d: float = (p - u.position).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return hi - lo


func _max_step(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(mini(a.size(), b.size())):
		m = maxf(m, a[i].distance_to(b[i]))
	return m


# --- gating: the standalone drill contract every drill shares --------------

func test_combo_noops_while_fighting() -> void:
	var u := _make_unit()
	u.state = Unit.State.FIGHTING
	assert_false(u.quarter_turn_explicatio(1), "a fighting unit refuses the combo")
	assert_null(u.current_order, "...and installs nothing, like conversio/wheel")


func test_combo_noops_before_bodies_are_seeded() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	# No seed_sim_soldiers() call: _can_drill() requires seeded bodies.
	assert_false(u.quarter_turn_explicatio(1), "a pre-seed unit refuses the combo")
	assert_null(u.current_order)


func test_begin_combo_refuses_an_empty_chain() -> void:
	var u := _make_unit()
	var none: Array[Order] = []
	assert_false(u.begin_combo(none), "nothing to chain -> nothing installed")
	assert_null(u.current_order)


func test_begin_combo_refuses_an_unsupported_step_kind() -> void:
	# A MOVE is not a drill primitive the combo mechanism knows how to arm, so the whole
	# chain is refused up front (a push_error names the kind) rather than the march being
	# skipped silently once the cascade reaches it.
	var u := _make_unit()
	var steps: Array[Order] = [Order.new_quarter_turn(1), Order.new_move(Vector2(0, 100))]
	assert_false(u.begin_combo(steps), "an unsupported step refuses the chain")
	assert_null(u.current_order, "...and nothing is installed, not even the valid prefix")
	assert_push_error("unsupported combo step MOVE")


func test_combo_refuses_while_another_drill_runs() -> void:
	var u := _make_unit()
	u.quarter_turn(1)
	assert_true(u.is_order_turning(), "sanity: the plain drill armed")
	assert_false(u.quarter_turn_explicatio(1), "a unit mid-turn refuses to re-arm")
	assert_eq(u.current_order.type, Order.Type.QUARTER_TURN, "the running drill is untouched")


# --- the composite's shape and how it reads out --------------------------------------------

func test_combo_installs_a_composite_with_the_turn_armed_first() -> void:
	var u := _make_unit()
	assert_true(u.quarter_turn_explicatio(1))
	assert_eq(u.current_order.type, Order.Type.COMBO)
	assert_eq(u.current_order.children.size(), 2, "a turn step, then the file-double step")
	assert_eq(u.active_leaf().type, Order.Type.QUARTER_TURN, "the cursor starts on the turn")
	assert_true(u.is_order_turning(), "the turn armed on the live unit")
	assert_true(u.active_leaf().turn_target.is_equal_approx(Vector2.DOWN.rotated(PI * 0.5)),
		"the turn goal is a quarter to the right of the CURRENT facing")
	assert_eq(u.current_order.children[1].frontage, -1,
		"the file-double is still unresolved -- its width is read only once the turn completes")
	assert_eq(UnitFormation.frontage(u), 8, "the frontage has NOT changed yet")


func test_combo_reads_as_a_quarter_turn_while_turning() -> void:
	var u := _make_unit()
	u.quarter_turn_explicatio(-1)
	assert_eq(u.current_maneuver(), Unit.Maneuver.QUARTER_TURN)
	assert_eq(u.order_summary(), "Quarter-turning (step 1 of 2)",
		"the panel names the running step and its place in the chain")
	assert_eq(u.current_order.effective_phase_name(), "QUARTER_TURN",
		"the transcript's order_phase names the active step")


# --- the whole combo, tick by tick ---------------------------------------------------------

func test_combo_turns_then_doubles_the_frontage_across_the_new_facing() -> void:
	var u := _make_unit()
	var start_facing: Vector2 = u.facing
	u.quarter_turn_explicatio(1)
	_run_to_completion(u)
	assert_null(u.current_order, "the whole combo retired within its budget")
	assert_true(u.facing.is_equal_approx(start_facing.rotated(PI * 0.5)),
		"the unit ended a quarter-turn right of its start heading")
	assert_eq(UnitFormation.frontage(u), 10,
		"explicatio doubled the frontage the block presents AFTER turning (5 -> 10), not the grid's old 8")
	assert_lt(absf(wrapf(u._formation_angle, -PI, PI)), 0.01,
		"the reshape re-squared the grid to the new heading (no quarter fold left behind)")
	assert_true(u._last_reshape_widened, "the reshape registered as a widen")

	# Let the bodies ease onto the reshaped slots, then check the footprint is a LINE across
	# the new facing: 10 files x 4 ranks reads as wide-across / shallow-deep in the new frame.
	for _i in range(240):
		_tick(u)
	var lateral: Vector2 = u.facing.rotated(PI * 0.5)
	assert_gt(_extent_along(u, lateral), 2.0 * _extent_along(u, u.facing),
		"the settled block is much wider across the new facing than it is deep")


func test_combo_bodies_never_jump_between_the_turn_and_the_reshape() -> void:
	var u := _make_unit()
	u.quarter_turn_explicatio(-1)
	var prev: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var worst := 0.0
	for _i in range(400):
		_tick(u)
		worst = maxf(worst, _max_step(prev, u._sim_soldier_pos))
		prev = u._sim_soldier_pos.duplicate()
	assert_null(u.current_order, "sanity: the combo finished inside the window")
	assert_lt(worst, 6.0,
		"the bodies hold their ground through the turn and walk to the reshaped slots at velocity (worst %.3f px)"
			% worst)


func test_a_chain_of_two_turns_arms_the_second_from_the_first_turns_result() -> void:
	# An about-face then a quarter-turn right: the second step must read its goal from the
	# facing the FIRST step left (the reverse of the start), not from the issue-time facing.
	var u := _make_unit()
	var start_facing: Vector2 = u.facing
	var steps: Array[Order] = [Order.new_about_face(), Order.new_quarter_turn(1)]
	assert_true(u.begin_combo(steps))
	assert_eq(u.current_maneuver(), Unit.Maneuver.CONVERSIO, "the about-face runs first")
	var prev: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var worst := 0.0
	for _i in range(200):
		if u.current_order == null:
			break
		_tick(u)
		worst = maxf(worst, _max_step(prev, u._sim_soldier_pos))
		prev = u._sim_soldier_pos.duplicate()
	assert_null(u.current_order, "both turns completed within the budget")
	assert_true(u.facing.is_equal_approx((-start_facing).rotated(PI * 0.5)),
		"the second turn started from the reversed heading, so it ends three quarters round")
	assert_true(u._holds_quarter_fold(),
		"two in-place turns leave the grid a quarter off the heading (PI - PI/2)")
	assert_lt(worst, 0.5,
		"nobody moves through two in-place turns -- the hand-off tick included (worst %.3f px)" % worst)


func test_a_single_instant_step_combo_completes_on_issue() -> void:
	var u := _make_unit()
	var steps: Array[Order] = [Order.new_file_double(-1)]
	assert_true(u.begin_combo(steps))
	assert_null(u.current_order, "a lone instantaneous step is spent on arming and retires at once")
	assert_eq(UnitFormation.frontage(u), 4, "the duplicatio halved the (unturned) frontage")


func test_a_fresh_order_mid_turn_drops_the_pending_explicatio() -> void:
	var u := _make_unit()
	u.quarter_turn_explicatio(1)
	for _i in range(5):
		_tick(u)
	u.set_current_order(Order.new_move(Vector2(0, 300)))
	assert_eq(u.current_order.type, Order.Type.MOVE, "the move replaced the combo")
	# In isolation nothing arms the march (Battle does that at the apply site), so the bare
	# MOVE retires on its first tick -- what matters is that the combo, and with it the
	# queued explicatio, never comes back.
	for _i in range(30):
		_tick(u)
	assert_true(u.current_order == null or u.current_order.type != Order.Type.COMBO,
		"the combo is gone for good")
	assert_eq(UnitFormation.frontage(u), 8,
		"the queued explicatio died with the combo -- an interrupt never fires a stale reshape")


# --- the file-double step's own frame arithmetic --------------------------------------------

func test_file_double_step_transposes_a_quarter_fold_before_widening() -> void:
	var u := _make_unit()
	u._formation_angle = -PI * 0.5   # what a completed quarter-turn right folds in
	u._apply_file_double_step(Order.new_file_double(1))
	assert_eq(UnitFormation.frontage(u), 10,
		"5 files across the turned facing (the old 5 ranks), doubled -> 10")
	assert_eq(u._formation_angle, 0.0, "the fold is dropped: the grid is re-squared to the heading")


func test_file_double_step_narrows_in_the_turned_frame_too() -> void:
	var u := _make_unit()
	u._formation_angle = PI * 0.5   # a completed quarter-turn LEFT
	u._apply_file_double_step(Order.new_file_double(-1))
	assert_eq(UnitFormation.frontage(u), 2, "5 files across the turned facing, halved -> 2")
	assert_eq(u._formation_angle, 0.0)


func test_file_double_step_keeps_a_half_turn_fold_and_widens_the_grids_own_files() -> void:
	# An about-face leaves the file axis lateral, so no transposition applies -- and the fold
	# must be kept: dropping a +-PI fold outright would swap every man to the opposite flank
	# (see Unit.reform_ranks' own doc on the point-reflection hazard).
	var u := _make_unit()
	u._formation_angle = PI
	u._apply_file_double_step(Order.new_file_double(1))
	assert_eq(UnitFormation.frontage(u), 16, "8 lateral files doubled -> 16")
	assert_true(is_equal_approx(absf(u._formation_angle), PI), "the half-turn fold survives")


func test_file_double_step_with_no_fold_matches_the_plain_explicatio() -> void:
	var u := _make_unit()
	u._apply_file_double_step(Order.new_file_double(1))
	assert_eq(UnitFormation.frontage(u), UnitFormation.widened_files(40, 8),
		"a square grid widens exactly as Battle.enqueue_file_double would")


func test_an_absolute_frontage_step_applies_its_own_count() -> void:
	var u := _make_unit()
	u._formation_angle = -PI * 0.5
	u._apply_file_double_step(Order.new_frontage(6))
	assert_eq(UnitFormation.frontage(u), 6, "dir == 0 means the count is absolute, not relative")
	assert_true(is_equal_approx(absf(u._formation_angle), PI * 0.5),
		"an absolute step performs no frame arithmetic, so it leaves the fold alone")


# --- Battle.enqueue_turn_explicatio: the recorded-order path ---------------------------

## Unlike the plain quarter-turn (visual-only, never recorded), the combo reshapes the block,
## so Battle.enqueue_turn_explicatio must respect the same playback guard every other
## recorded order (enqueue_file_double, enqueue_countermarch, ...) has.
func test_enqueue_turn_explicatio_noops_during_playback() -> void:
	var b = load("res://scripts/Battle.gd").new()
	autofree(b)
	var u := _make_unit()
	u.uid = 77
	b._by_uid[77] = u
	var prev_mode: int = Replay.mode
	Replay.mode = Replay.Mode.PLAYBACK
	b.enqueue_turn_explicatio([77], 1)
	Replay.mode = prev_mode
	assert_null(u.current_order, "a combo command issued during playback is dropped")


func test_enqueue_turn_explicatio_ignores_a_zero_direction() -> void:
	var b = load("res://scripts/Battle.gd").new()
	autofree(b)
	var u := _make_unit()
	u.uid = 78
	b._by_uid[78] = u
	b.enqueue_turn_explicatio([78], 0)
	assert_null(u.current_order, "no side to turn to -> no command")
