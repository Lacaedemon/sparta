extends GutTest
## The skirmisher-screen subcommander directive (docs/deployment-distance-design.md,
## "Skirmisher screening"): SkirmisherScreen.directives and the ScreenIntervals geometry it
## withdraws through, plus UnitLeader's own translation of the two directives into real
## order-commands. Exercised at the same level as test_subcommander.gd -- units built
## directly via the script (add_child_autofree so _ready() joins "units"), no full Battle
## scene, since every function under test reads only unit fields and the arrays it is
## handed. The live-battle half (the directive reaching a team-1 unit as a real order, and
## replaying identically on a forced seed) is test_battle_ai_skirmisher_screen.gd.

const UnitScript = preload("res://scripts/Unit.gd")
const ScreenScript = preload("res://scripts/SkirmisherScreen.gd")
const IntervalsScript = preload("res://scripts/ScreenIntervals.gd")
const UnitLeaderScript = preload("res://scripts/UnitLeader.gd")
const BattleScript = preload("res://scripts/Battle.gd")

## Every fixture below deploys team 1 at high y advancing on team 0 at low y, so the
## advance axis is exactly straight up and the (axis, perp) basis is (0,-1) / (1,0). That
## makes a directive's expected point readable by hand: lateral is x, and depth is the
## line's own y offset by the constant under test.
const AXIS := Vector2(0, -1)

## The heavy line's own y in the fixtures -- the median depth every expected point is
## measured from.
const LINE_Y := 700.0


func _unit(uid: int, pos: Vector2, team: int = 1) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins "units", sets the footprint
	u.uid = uid
	u.position = pos
	u.team = team
	return u


func _archers(uid: int, pos: Vector2, team: int = 1) -> Unit:
	var u: Unit = _unit(uid, pos, team)
	u.is_ranged = true
	return u


## Two heavy blocks either side of x = 600, the shape every screen fixture screens for.
func _heavy_line() -> Array:
	return [_unit(1, Vector2(500, LINE_Y)), _unit(2, Vector2(700, LINE_Y))]


# --- advancing to the contest line -------------------------------------------------

func test_light_troops_are_sent_forward_to_the_contest_line() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(600, 780))   # spawned behind its own heavy line
	group.append(light)
	var enemy := _unit(4, Vector2(600, 100), 0)   # far off: no withdraw trigger
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out)

	assert_true(out.has(light.uid), "the light unit is pushed out ahead of the line")
	assert_eq(out[light.uid]["type"], ScreenScript.DIRECTIVE_SCREEN)
	assert_almost_eq(float(out[light.uid]["x"]), 600.0, 0.1, "holds its own file")
	assert_almost_eq(float(out[light.uid]["y"]),
		LINE_Y - ScreenScript.SCREEN_LEAD_DISTANCE, 0.1,
		"one lead distance ahead of the heavy line's own median depth")
	assert_false(out.has(1), "the heavy blocks themselves get no screen directive")
	assert_false(out.has(2))


func test_the_lead_distance_is_caller_configurable() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(600, 780))
	group.append(light)
	var enemy := _unit(4, Vector2(600, 100), 0)
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out, 100.0)

	assert_almost_eq(float(out[light.uid]["y"]), LINE_Y - 100.0, 0.1,
		"a shorter lead puts the contest line nearer the heavy blocks")


func test_a_unit_already_claimed_this_tick_keeps_the_higher_priority_directive() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(600, 780))
	group.append(light)
	var enemy := _unit(4, Vector2(600, 100), 0)
	var out: Dictionary = {light.uid: {"type": Subcommander.DIRECTIVE_SUPPORT, "ward_uid": 1}}

	ScreenScript.directives(group, group + [enemy], AXIS, out)

	assert_eq(out[light.uid]["type"], Subcommander.DIRECTIVE_SUPPORT,
		"mutual support and flank coverage both run first and are not overwritten")


# --- the withdrawal trigger --------------------------------------------------------

func test_the_screen_holds_while_the_enemy_is_outside_the_trigger_range() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(600, 460))
	group.append(light)
	# One world unit further out than the trigger: still contesting the ground.
	var enemy := _unit(4, Vector2(600, 460 - (ScreenScript.WITHDRAW_TRIGGER_RANGE + 1.0)), 0)
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out)

	assert_eq(out[light.uid]["type"], ScreenScript.DIRECTIVE_SCREEN)


func test_the_screen_withdraws_once_the_enemy_is_inside_the_trigger_range() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(600, 460))
	group.append(light)
	# One world unit inside the trigger: the heavy line is closing, break off.
	var enemy := _unit(4, Vector2(600, 460 - (ScreenScript.WITHDRAW_TRIGGER_RANGE - 1.0)), 0)
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out)

	assert_eq(out[light.uid]["type"], ScreenScript.DIRECTIVE_WITHDRAW)
	assert_almost_eq(float(out[light.uid]["y"]), LINE_Y + ScreenScript.RALLY_DEPTH, 0.1,
		"rallies one rally depth BEHIND the heavy line it passed through")


func test_the_withdraw_trigger_range_is_caller_configurable() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(600, 460))
	group.append(light)
	var enemy := _unit(4, Vector2(600, 260), 0)   # 200 wu away
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out,
		ScreenScript.SCREEN_LEAD_DISTANCE, 300.0)

	assert_eq(out[light.uid]["type"], ScreenScript.DIRECTIVE_WITHDRAW,
		"a wider trigger recalls the screen earlier")


func test_a_routing_enemy_does_not_trigger_the_withdrawal() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(600, 460))
	group.append(light)
	var enemy := _unit(4, Vector2(600, 400), 0)
	enemy.state = Unit.State.ROUTING
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out)

	assert_eq(out[light.uid]["type"], ScreenScript.DIRECTIVE_SCREEN,
		"a fleeing enemy is not the closing heavy line the recall exists for")


# --- withdrawing THROUGH the intervals ---------------------------------------------

func test_the_withdrawal_path_passes_through_an_interval_not_through_a_block() -> void:
	# Three blocks, and the light unit standing directly in front of the middle one: the
	# straight-back path would walk through that block, so the recall must offset it onto
	# a gap. Livy 8.8's fall-back through the intervals of the line behind.
	var group: Array = [
		_unit(1, Vector2(400, LINE_Y)),
		_unit(2, Vector2(600, LINE_Y)),
		_unit(3, Vector2(800, LINE_Y)),
	]
	var light := _archers(4, Vector2(600, 460))
	group.append(light)
	var enemy := _unit(5, Vector2(600, 400), 0)
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out)

	assert_eq(out[light.uid]["type"], ScreenScript.DIRECTIVE_WITHDRAW)
	var x: float = float(out[light.uid]["x"])
	for heavy_x in [400.0, 600.0, 800.0]:
		assert_ne(x, heavy_x, "the path never runs back through a heavy block's own file")
	assert_almost_eq(x, 500.0, 0.1,
		"the nearest interval: equidistant gaps at 500 and 700 resolve to the lower")


func test_the_open_flank_counts_as_an_interval_for_the_end_of_the_line() -> void:
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(200, 460))   # well outboard of the left-hand block
	group.append(light)
	var enemy := _unit(4, Vector2(200, 400), 0)
	var out: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, out)

	assert_almost_eq(float(out[light.uid]["x"]),
		500.0 - IntervalsScript.FLANK_INTERVAL_OFFSET, 0.1,
		"falls back around the open flank rather than crossing the whole line")


# --- degenerate cases --------------------------------------------------------------

func test_no_axis_means_no_screen() -> void:
	var group: Array = _heavy_line()
	group.append(_archers(3, Vector2(600, 780)))
	var out: Dictionary = {}
	ScreenScript.directives(group, group, Vector2.ZERO, out)
	assert_true(out.is_empty(), "no living enemy to advance on, so nothing to screen")


func test_a_group_with_no_light_troops_gets_no_screen() -> void:
	var group: Array = _heavy_line()
	var enemy := _unit(4, Vector2(600, 100), 0)
	var out: Dictionary = {}
	ScreenScript.directives(group, group + [enemy], AXIS, out)
	assert_true(out.is_empty())


func test_a_group_with_no_heavy_line_gets_no_screen() -> void:
	var group: Array = [_archers(1, Vector2(500, LINE_Y)), _archers(2, Vector2(700, LINE_Y))]
	var enemy := _unit(4, Vector2(600, 100), 0)
	var out: Dictionary = {}
	ScreenScript.directives(group, group + [enemy], AXIS, out)
	assert_true(out.is_empty(), "a screen with no line behind it has no intervals to use")


func test_mounted_skirmishers_are_not_part_of_the_screen() -> void:
	var group: Array = _heavy_line()
	var horse := _archers(3, Vector2(600, 780))
	horse.is_cavalry = true
	group.append(horse)
	var enemy := _unit(4, Vector2(600, 100), 0)
	var out: Dictionary = {}
	ScreenScript.directives(group, group + [enemy], AXIS, out)
	assert_true(out.is_empty(), "a caracole is not a skirmisher screen")


func test_dead_and_routing_members_are_ignored() -> void:
	var group: Array = _heavy_line()
	var dead := _archers(3, Vector2(600, 780))
	dead.state = Unit.State.DEAD
	var routing := _archers(5, Vector2(620, 780))
	routing.state = Unit.State.ROUTING
	group.append(dead)
	group.append(routing)
	var enemy := _unit(4, Vector2(600, 100), 0)
	var out: Dictionary = {}
	ScreenScript.directives(group, group + [enemy], AXIS, out)
	assert_true(out.is_empty(), "neither a casualty nor a fugitive joins the screen")


func test_the_same_line_always_yields_the_same_directives() -> void:
	# Pure function of already-serialized positions: no RNG, no iteration-order dependence,
	# which is what lets a replay re-derive the screen rather than recording it.
	var group: Array = _heavy_line()
	var light := _archers(3, Vector2(640, 470))
	group.append(light)
	var enemy := _unit(4, Vector2(600, 420), 0)
	var first: Dictionary = {}
	var second: Dictionary = {}

	ScreenScript.directives(group, group + [enemy], AXIS, first)
	ScreenScript.directives(group, group + [enemy], AXIS, second)

	assert_eq(first, second)


# --- ScreenIntervals geometry ------------------------------------------------------

func test_median_depth_of_an_empty_line_is_zero() -> void:
	assert_almost_eq(IntervalsScript.median_depth([], AXIS), 0.0, 0.001)


func test_median_depth_averages_the_middle_pair_of_an_even_line() -> void:
	var line: Array = [
		_unit(1, Vector2(0, 600)), _unit(2, Vector2(0, 700)),
		_unit(3, Vector2(0, 800)), _unit(4, Vector2(0, 900)),
	]
	# Projected onto (0,-1), so depth is -y and the median of -900..-600 is -750.
	assert_almost_eq(IntervalsScript.median_depth(line, AXIS), -750.0, 0.001)


func test_median_depth_takes_the_middle_of_an_odd_line() -> void:
	var line: Array = [
		_unit(1, Vector2(0, 600)), _unit(2, Vector2(0, 700)), _unit(3, Vector2(0, 900)),
	]
	assert_almost_eq(IntervalsScript.median_depth(line, AXIS), -700.0, 0.001)


func test_interval_laterals_are_the_midpoints_plus_both_open_flanks() -> void:
	var line: Array = [
		_unit(1, Vector2(400, LINE_Y)),
		_unit(2, Vector2(800, LINE_Y)),
		_unit(3, Vector2(600, LINE_Y)),   # deliberately out of lateral order
	]
	var gaps: Array[float] = IntervalsScript.interval_laterals(line, Vector2(1, 0), 50.0)
	assert_eq(gaps, [350.0, 500.0, 700.0, 850.0] as Array[float],
		"sorted ascending regardless of the order the blocks arrive in")


func test_a_single_block_has_only_its_two_flanks() -> void:
	var gaps: Array[float] = IntervalsScript.interval_laterals(
		[_unit(1, Vector2(600, LINE_Y))], Vector2(1, 0), 50.0)
	assert_eq(gaps, [550.0, 650.0] as Array[float])


func test_an_empty_line_has_no_intervals() -> void:
	assert_eq(IntervalsScript.interval_laterals([], Vector2(1, 0)).size(), 0)


func test_nearest_falls_back_to_the_units_own_lateral_when_there_are_no_intervals() -> void:
	var none: Array[float] = []
	assert_almost_eq(IntervalsScript.nearest(none, 123.0), 123.0, 0.001)


func test_nearest_picks_the_closest_interval() -> void:
	var gaps: Array[float] = [100.0, 500.0, 900.0]
	assert_almost_eq(IntervalsScript.nearest(gaps, 560.0), 500.0, 0.001)
	assert_almost_eq(IntervalsScript.nearest(gaps, 860.0), 900.0, 0.001)


# --- UnitLeader's translation into order-commands ----------------------------------

func test_a_screen_directive_becomes_a_skirmish_stance_move() -> void:
	var u := _archers(1, Vector2(600, 780))
	var enemy := _unit(2, Vector2(600, 100), 0)
	var directive: Dictionary = {
		"type": ScreenScript.DIRECTIVE_SCREEN, "x": 600.0, "y": 460.0, "station": 140.0,
	}

	var cmd: Dictionary = UnitLeaderScript.decide(u, [u, enemy], directive)

	assert_eq(cmd["units"], [u.uid])
	assert_eq(int(cmd["target"]), -1, "a plain move, not an attack")
	assert_almost_eq(float(cmd["x"]), 600.0, 0.01)
	assert_almost_eq(float(cmd["y"]), 460.0, 0.01)
	assert_eq(int(cmd["mode"]), BattleScript.OrderMode.SKIRMISH,
		"the screen contests the ground at range instead of closing to melee")


func test_a_screener_already_on_station_is_left_to_fight_its_own_firefight() -> void:
	var u := _archers(1, Vector2(600, 470))   # 10 wu off the contest point
	u.facing = Vector2.UP                      # squared up on the enemy, so no flank threat
	var enemy := _unit(2, Vector2(600, 400), 0)
	u.target_enemy = enemy                     # already trading missiles
	var directive: Dictionary = {
		"type": ScreenScript.DIRECTIVE_SCREEN, "x": 600.0, "y": 460.0, "station": 140.0,
	}

	var cmd: Dictionary = UnitLeaderScript.decide(u, [u, enemy], directive)

	assert_true(cmd.is_empty(),
		"no fresh order inside the station radius, so a kite step cannot cancel the volley")


func test_a_withdraw_directive_recalls_a_screener_that_is_already_fighting() -> void:
	# The one directive that outranks the FIGHTING gate: light troops break off the missile
	# duel and pass back through the line rather than being caught by the heavy blocks.
	var u := _archers(1, Vector2(600, 460))
	u.state = Unit.State.FIGHTING
	u.facing = Vector2.UP                      # squared up, so the flank reaction stays quiet
	var enemy := _unit(2, Vector2(600, 400), 0)
	var directive: Dictionary = {
		"type": ScreenScript.DIRECTIVE_WITHDRAW, "x": 500.0, "y": 860.0,
	}

	var cmd: Dictionary = UnitLeaderScript.decide(u, [u, enemy], directive)

	assert_eq(cmd["units"], [u.uid])
	assert_almost_eq(float(cmd["x"]), 500.0, 0.01)
	assert_almost_eq(float(cmd["y"]), 860.0, 0.01)
	assert_false(cmd.has("mode"),
		"withdrawing in the default stance, so the march is not held up by kiting")


# --- how the screen composes with the subcommander's other behaviours --------------

func test_the_line_does_not_break_to_rescue_a_skirmishing_screen() -> void:
	# The screen's whole point is that the light troops fight out in front alone. A heavy
	# block sent to guard them would walk the line off its ground to do it.
	var a := _unit(1, Vector2(500, LINE_Y))
	var b := _unit(2, Vector2(700, LINE_Y))
	var light := _archers(3, Vector2(600, 460))
	light.state = Unit.State.FIGHTING          # skirmishing at the contest line
	var enemy := _unit(4, Vector2(600, 400), 0)

	var directives: Dictionary = Subcommander.decide_group(
		[a, b, light], [a, b, light, enemy], General.PLAN_ADVANCE_LINE, true)

	assert_false(directives.has(a.uid), "the heavy blocks hold their ground")
	assert_false(directives.has(b.uid))


func test_an_ally_in_a_real_fight_still_outranks_the_screen() -> void:
	# The exclusion above is one-way: a screener is not a ward, but it is still the nearest
	# available body when one of its own heavy blocks is in trouble.
	var a := _unit(1, Vector2(500, LINE_Y))
	a.state = Unit.State.FIGHTING
	a.facing = Vector2.UP
	var b := _unit(2, Vector2(700, LINE_Y))
	var light := _archers(3, Vector2(520, LINE_Y - 40))
	var enemy := _unit(4, Vector2(500, 100), 0)

	var directives: Dictionary = Subcommander.decide_group(
		[a, b, light], [a, b, light, enemy], General.PLAN_ADVANCE_LINE, true)

	assert_eq(directives[light.uid]["type"], Subcommander.DIRECTIVE_SUPPORT,
		"mutual support claims the nearest available ally, screen orders or not")


func test_the_screen_is_off_unless_the_general_asks_for_it() -> void:
	var a := _unit(1, Vector2(500, LINE_Y))
	var b := _unit(2, Vector2(700, LINE_Y))
	var light := _archers(3, Vector2(600, 780))
	var enemy := _unit(4, Vector2(600, 100), 0)

	var directives: Dictionary = Subcommander.decide_group([a, b, light], [a, b, light, enemy])

	assert_false(directives.has(light.uid),
		"a doctrine without the flag keeps the behaviour it had before the screen existed")
