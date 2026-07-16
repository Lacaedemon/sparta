extends GutTest
## Unit.atomic_response_delay: the beat between an atomic drill command (wheel, about-face,
## quarter-turn, countermarch) and the men actually starting the evolution. The drill's order
## installs immediately (is_wheeling()/is_order_turning() reads true, so a second command is
## refused exactly as mid-drill), but _think holds the unit frozen for the delay -- the same
## _order_response_timer freeze move orders already count down, so the two delays compose via
## max rather than stacking. A per-unit characteristic: an elite regiment drills snappier
## than a raw levy.

const DELTA := 1.0 / 60.0
# Comfortably inside / past a 0.2 s (12-tick) beat, with margin against the timer's
# hit-zero-and-fall-through tick and float rounding on either side.
const TICKS_INSIDE_BEAT := 10
const TICKS_WELL_PAST_BEAT := 30


func _make_unit(uid: int, delay: float) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	u.atomic_response_delay = delay
	u.seed_sim_soldiers()
	return u


func _tick(u: Unit, ticks: int) -> void:
	for _i in range(ticks):
		u._physics_process(DELTA)
		u.step_sim_soldiers(DELTA)


func test_wheel_holds_for_the_response_beat_then_swings() -> void:
	var u := _make_unit(1, 0.2)
	u.wheel(1)
	assert_true(u.is_wheeling(), "the wheel order installs immediately")
	_tick(u, TICKS_INSIDE_BEAT)
	assert_true(u.facing.is_equal_approx(Vector2.DOWN),
		"the men have not started the evolution inside the response beat")
	_tick(u, TICKS_WELL_PAST_BEAT)
	assert_false(u.facing.is_equal_approx(Vector2.DOWN),
		"the swing is under way once the beat expires")


func test_conversio_holds_for_the_response_beat() -> void:
	var u := _make_unit(1, 0.2)
	u.conversio()
	assert_true(u.is_order_turning(), "the about-face order installs immediately")
	_tick(u, TICKS_INSIDE_BEAT)
	assert_true(u.facing.is_equal_approx(Vector2.DOWN),
		"no man turns inside the response beat")
	_tick(u, TICKS_WELL_PAST_BEAT)
	assert_false(u.facing.is_equal_approx(Vector2.DOWN),
		"the reversal is under way once the beat expires")


func test_quarter_turn_holds_for_the_response_beat() -> void:
	var u := _make_unit(1, 0.2)
	u.quarter_turn(1)
	_tick(u, TICKS_INSIDE_BEAT)
	assert_true(u.facing.is_equal_approx(Vector2.DOWN),
		"no man pivots inside the response beat")
	_tick(u, TICKS_WELL_PAST_BEAT)
	assert_false(u.facing.is_equal_approx(Vector2.DOWN),
		"the quarter-turn is under way once the beat expires")


func test_countermarch_holds_for_the_response_beat() -> void:
	var u := _make_unit(1, 0.2)
	u.countermarch(Unit.CountermarchVariant.MACEDONIAN)
	_tick(u, TICKS_INSIDE_BEAT)
	assert_true(u.facing.is_equal_approx(Vector2.DOWN),
		"the countermarch's opening about-face waits out the response beat")
	_tick(u, TICKS_WELL_PAST_BEAT)
	assert_false(u.facing.is_equal_approx(Vector2.DOWN),
		"the about-face is under way once the beat expires")


func test_zero_delay_keeps_the_drill_instant() -> void:
	var u := _make_unit(1, 0.0)
	u.wheel(1)
	_tick(u, 1)
	assert_false(u.facing.is_equal_approx(Vector2.DOWN),
		"a zero-delay unit starts the swing on the very first tick, the pre-delay behavior")


func test_elite_regiment_steps_off_before_the_raw_levy() -> void:
	# The same drill command lands on both regiments the same tick; only the veteran has
	# begun the evolution twelve ticks later. This is the characteristic's whole point:
	# elite bonus, raw-levy malus.
	var elite := _make_unit(1, 0.1)
	var levy := _make_unit(2, 0.4)
	elite.wheel(1)
	levy.wheel(1)
	_tick(elite, 12)
	_tick(levy, 12)
	assert_false(elite.facing.is_equal_approx(Vector2.DOWN),
		"the veteran regiment (0.1 s beat) is already swinging at tick 12")
	assert_true(levy.facing.is_equal_approx(Vector2.DOWN),
		"the raw levy (0.4 s beat) is still bracing at tick 12")


func test_scenario_spec_overrides_the_drill_beat_at_spawn() -> void:
	# The spawn path reads an optional `atomic_response_s` key, layered from a scenario
	# spec onto the loadout dict exactly like `disciplined` -- so a demo can stage an
	# elite regiment's snappier drill without a code change.
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": 300.0, "y": 300.0, "count": 20,
			"atomic_response_s": 0.05},
		{"team": 0, "type": "Infantry", "x": 600.0, "y": 300.0, "count": 20},
	]
	add_child_autofree(battle)
	await get_tree().physics_frame
	var by_type: Dictionary = {}
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null:
			by_type[unit.unit_name.split(" ")[0]] = unit
	assert_almost_eq((by_type["Spearmen"] as Unit).atomic_response_delay, 0.05, 0.0001,
		"the spec's atomic_response_s override lands on the spawned unit")
	assert_almost_eq((by_type["Infantry"] as Unit).atomic_response_delay, 0.2, 0.0001,
		"a spec without the key keeps the Unit default")
