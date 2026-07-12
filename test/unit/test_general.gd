extends GutTest
## Battle AI phase 3 (docs/battle-ai-design.md): General.decide_army's plan selection, group
## assignment, reserve pool, and reserve-commit threshold. Exercised at the same level as
## test_subcommander.gd -- units built directly via the script (add_child_autofree so
## _ready() joins "units" and sets soldiers = max_soldiers), no full Battle scene needed since
## General reads only unit fields and the arrays/doctrine dict it's handed. Each test checks
## the returned data (plan / groups / reserve_units / pursue_routers), not sim side effects --
## those are UnitLeader's own contract (test_unit_leader.gd) plus _apply_order_cmd's.

const UnitScript = preload("res://scripts/Unit.gd")
const GeneralScript = preload("res://scripts/General.gd")
const SubcommanderScript = preload("res://scripts/Subcommander.gd")


func _unit(uid: int, pos: Vector2, team: int = 1) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins "units", sets soldiers = max_soldiers
	u.uid = uid
	u.position = pos
	u.team = team
	return u


func _doctrine(overrides: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"name": "Test",
		"plans": ["advance_line", "envelop"],
		"envelop_ratio_threshold": 1.0,
		"reserve_fraction": 0.0,
		"reserve_commit_morale_threshold": 0.0,
		"pursue_routers": true,
	}
	for k in overrides:
		d[k] = overrides[k]
	return d


# --- empty/malformed doctrine falls back to phase 2 behaviour -----------------------------

func test_empty_doctrine_falls_back_to_one_group_no_reserves_pursue_routers() -> void:
	var a := _unit(1, Vector2(600, 700))
	var b := _unit(2, Vector2(700, 700))
	var decision: Dictionary = GeneralScript.decide_army([a, b], [a, b], {})
	assert_eq(decision["plan"], GeneralScript.PLAN_ADVANCE_LINE)
	assert_eq(decision["groups"], [[a, b]])
	assert_eq(decision["reserve_units"], [])
	assert_true(decision["pursue_routers"])


# --- plan selection ------------------------------------------------------------------------

func test_select_plan_picks_envelop_when_outnumbering_past_the_threshold() -> void:
	var a := _unit(1, Vector2(600, 700))
	var b := _unit(2, Vector2(700, 700))
	var enemy := _unit(3, Vector2(650, 300), 0)
	var doctrine := _doctrine({"envelop_ratio_threshold": 1.5})
	var plan: String = GeneralScript.select_plan([a, b], [a, b, enemy], doctrine)
	assert_eq(plan, GeneralScript.PLAN_ENVELOP, "2 vs 1 (ratio 2.0) clears a 1.5 threshold")


func test_select_plan_picks_advance_line_below_the_threshold() -> void:
	var a := _unit(1, Vector2(600, 700))
	var b := _unit(2, Vector2(700, 700))
	var enemy_a := _unit(3, Vector2(650, 300), 0)
	var enemy_b := _unit(4, Vector2(550, 300), 0)
	var doctrine := _doctrine({"envelop_ratio_threshold": 1.5})
	var plan: String = GeneralScript.select_plan([a, b], [a, b, enemy_a, enemy_b], doctrine)
	assert_eq(plan, GeneralScript.PLAN_ADVANCE_LINE, "2 vs 2 (ratio 1.0) misses a 1.5 threshold")


func test_select_plan_ignores_envelop_when_the_doctrine_doesnt_know_it() -> void:
	var a := _unit(1, Vector2(600, 700))
	var b := _unit(2, Vector2(700, 700))
	var enemy := _unit(3, Vector2(650, 300), 0)
	var doctrine := _doctrine({"plans": ["advance_line"], "envelop_ratio_threshold": 0.1})
	var plan: String = GeneralScript.select_plan([a, b], [a, b, enemy], doctrine)
	assert_eq(plan, GeneralScript.PLAN_ADVANCE_LINE, "doctrine has no envelop plan to pick")


func test_select_plan_advances_when_no_living_enemy_to_measure_against() -> void:
	var a := _unit(1, Vector2(600, 700))
	var b := _unit(2, Vector2(700, 700))
	var doctrine := _doctrine({"envelop_ratio_threshold": 0.01})
	var plan: String = GeneralScript.select_plan([a, b], [a, b], doctrine)
	assert_eq(plan, GeneralScript.PLAN_ADVANCE_LINE)


# --- group assignment -----------------------------------------------------------------------

func test_advance_line_keeps_one_group() -> void:
	var a := _unit(1, Vector2(500, 700))
	var b := _unit(2, Vector2(700, 700))
	var enemy := _unit(3, Vector2(600, 300), 0)
	var groups: Array = GeneralScript.assign_groups(
		[a, b], [a, b, enemy], GeneralScript.PLAN_ADVANCE_LINE)
	assert_eq(groups, [[a, b]])


func test_envelop_splits_the_team_into_a_left_and_right_wing() -> void:
	# 4 units so each wing clears General.MIN_WING_SIZE (2) -- see the next test for what
	# happens when a team is too small to split into two VIABLE wings.
	var left_a := _unit(1, Vector2(400, 700))
	var left_b := _unit(2, Vector2(450, 700))
	var right_a := _unit(3, Vector2(750, 700))
	var right_b := _unit(4, Vector2(800, 700))
	var enemy := _unit(5, Vector2(600, 300), 0)   # due north: axis is vertical, perp is horizontal
	var group: Array = [left_a, left_b, right_a, right_b]
	var groups: Array = GeneralScript.assign_groups(group, group + [enemy], GeneralScript.PLAN_ENVELOP)
	assert_eq(groups.size(), 2)
	# Which physical side ends up first in the array isn't the contract -- only that the
	# left-hand pair and right-hand pair land in different groups.
	var same_group: bool = groups[0].has(left_a) and groups[0].has(right_a)
	assert_false(same_group, "left-side and right-side units split into different wings")
	for g in groups:
		assert_true(g.size() >= GeneralScript.MIN_WING_SIZE, "every wing clears the minimum size")


func test_envelop_keeps_one_group_when_a_wing_would_be_under_strength() -> void:
	# Only 2 units total -- splitting would leave two one-unit "wings", each below
	# Subcommander.decide_group's own living.size() < 2 floor (no coordination at all for a
	# lone unit). A general wouldn't split a two-man command that way, so this stays one group
	# even though PLAN_ENVELOP was chosen. Regression coverage: a live 2-unit battle scenario
	# picked envelop mid-fight once the enemy took a casualty and the ratio crossed the
	# doctrine's threshold, silently losing all subcommander coordination for both units.
	var left := _unit(1, Vector2(400, 700))
	var right := _unit(2, Vector2(800, 700))
	var enemy := _unit(3, Vector2(600, 300), 0)
	var groups: Array = GeneralScript.assign_groups(
		[left, right], [left, right, enemy], GeneralScript.PLAN_ENVELOP)
	assert_eq(groups, [[left, right]], "too few units per wing -- stays one group")


func test_envelop_degenerates_to_one_group_with_no_living_enemy() -> void:
	var left_a := _unit(1, Vector2(400, 700))
	var left_b := _unit(2, Vector2(450, 700))
	var right_a := _unit(3, Vector2(750, 700))
	var right_b := _unit(4, Vector2(800, 700))
	var group: Array = [left_a, left_b, right_a, right_b]
	var groups: Array = GeneralScript.assign_groups(group, group, GeneralScript.PLAN_ENVELOP)
	assert_eq(groups, [group], "no axis to split across -- one group")


func test_envelop_degenerates_to_one_group_with_fewer_than_two_units() -> void:
	var solo := _unit(1, Vector2(600, 700))
	var enemy := _unit(2, Vector2(600, 300), 0)
	var groups: Array = GeneralScript.assign_groups(
		[solo], [solo, enemy], GeneralScript.PLAN_ENVELOP)
	assert_eq(groups, [[solo]])


# --- reserve pool ---------------------------------------------------------------------------

func test_reserve_fraction_holds_back_the_highest_uid_units() -> void:
	var a := _unit(1, Vector2(500, 700))
	var b := _unit(2, Vector2(600, 700))
	var c := _unit(3, Vector2(700, 700))
	var d := _unit(4, Vector2(800, 700))
	var enemy := _unit(5, Vector2(600, 300), 0)
	# 4 units, 0.5 fraction -> 2 held back: the two highest uids (c, d).
	var doctrine := _doctrine({"reserve_fraction": 0.5, "reserve_commit_morale_threshold": 0.0})
	var decision: Dictionary = GeneralScript.decide_army([a, b, c, d], [a, b, c, d, enemy], doctrine)
	var reserve_uids: Array = []
	for u in decision["reserve_units"]:
		reserve_uids.append(u.uid)
	reserve_uids.sort()
	assert_eq(reserve_uids, [3, 4])


func test_zero_reserve_fraction_holds_nothing_back() -> void:
	var a := _unit(1, Vector2(500, 700))
	var b := _unit(2, Vector2(600, 700))
	var doctrine := _doctrine({"reserve_fraction": 0.0})
	var decision: Dictionary = GeneralScript.decide_army([a, b], [a, b], doctrine)
	assert_eq(decision["reserve_units"], [])


func test_a_routing_unit_still_counts_toward_the_reserve_fraction_denominator() -> void:
	# Regression coverage: the reserve pool must stay stable across a teammate routing, or a
	# temporary rout silently shrinks the roster count and reclassifies a genuine reserve as
	# active by pure headcount arithmetic -- nothing to do with the doctrine's own
	# reserve_commit_morale_threshold. 5 units, one (uid 3) ROUTING: the reserve fraction must
	# still be computed against all 5 (roster), not the 4 that are actually fightable, so the
	# held-back set stays {4, 5} exactly as it would with no casualties at all.
	var a := _unit(1, Vector2(500, 700))
	var b := _unit(2, Vector2(550, 700))
	var c := _unit(3, Vector2(600, 700))
	c.state = Unit.State.ROUTING
	var d := _unit(4, Vector2(700, 700))
	var e := _unit(5, Vector2(800, 700))
	var doctrine := _doctrine({"reserve_fraction": 0.4, "reserve_commit_morale_threshold": -1.0})
	var decision: Dictionary = GeneralScript.decide_army([a, b, c, d, e], [a, b, c, d, e], doctrine)
	var reserve_uids: Array = []
	for u in decision["reserve_units"]:
		reserve_uids.append(u.uid)
	reserve_uids.sort()
	assert_eq(reserve_uids, [4, 5], "int(5 * 0.4) = 2 reserves, same as with no casualties at all")


func test_a_dead_unit_shrinks_the_reserve_fraction_denominator() -> void:
	# The counterpart to the ROUTING case above: a unit that's actually DEAD (not just
	# routing) is gone for good, so it's correct -- not a bug -- for it to no longer count
	# toward the roster. General.decide_army only ever receives living/routing nodes in
	# practice (a dead unit leaves both the "units" and "routers" groups Battle._team_roster
	# reads), so this documents the boundary directly against _roster()'s own DEAD filter.
	var a := _unit(1, Vector2(500, 700))
	var b := _unit(2, Vector2(550, 700))
	var c := _unit(3, Vector2(600, 700))
	c.state = Unit.State.DEAD
	var d := _unit(4, Vector2(700, 700))
	var doctrine := _doctrine({"reserve_fraction": 0.5, "reserve_commit_morale_threshold": -1.0})
	var decision: Dictionary = GeneralScript.decide_army([a, b, c, d], [a, b, c, d], doctrine)
	# 3 non-dead units (a, b, d) -- int(3 * 0.5) = 1 reserve: the highest surviving uid (4).
	var reserve_uids: Array = []
	for u in decision["reserve_units"]:
		reserve_uids.append(u.uid)
	assert_eq(reserve_uids, [4])


func test_reserve_units_are_excluded_from_the_active_groups() -> void:
	var a := _unit(1, Vector2(500, 700))
	var b := _unit(2, Vector2(600, 700))
	var c := _unit(3, Vector2(700, 700))
	var enemy := _unit(4, Vector2(600, 300), 0)
	# 3 units, 1/3 fraction -> 1 held back (uid 3); threshold impossibly high so it never commits.
	var doctrine := _doctrine({
		"reserve_fraction": 0.34, "reserve_commit_morale_threshold": -1.0,
	})
	var decision: Dictionary = GeneralScript.decide_army([a, b, c], [a, b, c, enemy], doctrine)
	var group_uids: Array = []
	for group in decision["groups"]:
		for u in group:
			group_uids.append(u.uid)
	assert_false(group_uids.has(c.uid), "the reserve unit is not in any subcommander group")
	assert_true(group_uids.has(a.uid) and group_uids.has(b.uid))


# --- reserve commitment ----------------------------------------------------------------------

func test_should_commit_reserves_fires_below_the_weighted_morale_threshold() -> void:
	var a := _unit(1, Vector2(500, 700))
	a.morale = 20.0
	var b := _unit(2, Vector2(600, 700))
	b.morale = 20.0
	assert_true(GeneralScript.should_commit_reserves([a, b], 50.0))


func test_should_commit_reserves_stays_false_above_the_threshold() -> void:
	var a := _unit(1, Vector2(500, 700))
	a.morale = 90.0
	var b := _unit(2, Vector2(600, 700))
	b.morale = 90.0
	assert_false(GeneralScript.should_commit_reserves([a, b], 50.0))


func test_should_commit_reserves_weights_by_soldier_count() -> void:
	# A nearly-wiped-out unit at 0 morale shouldn't single-handedly drag a full-strength
	# ally's fresh 100 morale below threshold -- the weighted average should stay high.
	var strong := _unit(1, Vector2(500, 700))
	strong.morale = 100.0
	strong.soldiers = 120
	var weak := _unit(2, Vector2(600, 700))
	weak.morale = 0.0
	weak.soldiers = 1
	assert_false(GeneralScript.should_commit_reserves([strong, weak], 50.0),
		"weighted average stays well above 50 when the wavering unit is nearly empty")


func test_should_commit_reserves_true_with_no_active_units_left() -> void:
	assert_true(GeneralScript.should_commit_reserves([], 50.0),
		"nothing left to check against -- commit whatever reserves exist")


func test_decide_army_folds_reserves_into_the_active_line_once_morale_drops() -> void:
	var a := _unit(1, Vector2(500, 700))
	a.morale = 10.0
	var b := _unit(2, Vector2(600, 700))
	b.morale = 10.0
	var c := _unit(3, Vector2(700, 700))   # would be the reserve at 1/3
	var enemy := _unit(4, Vector2(600, 300), 0)
	var doctrine := _doctrine({
		"reserve_fraction": 0.34, "reserve_commit_morale_threshold": 50.0,
	})
	var decision: Dictionary = GeneralScript.decide_army([a, b, c], [a, b, c, enemy], doctrine)
	assert_eq(decision["reserve_units"], [], "morale is well below threshold -- reserves committed")
	var group_uids: Array = []
	for group in decision["groups"]:
		for u in group:
			group_uids.append(u.uid)
	group_uids.sort()
	assert_eq(group_uids, [1, 2, 3], "the formerly-reserve unit now rides in an active group")


# --- reserve hold directives -----------------------------------------------------------------

func test_reserve_directives_pin_each_reserve_unit_at_its_own_position() -> void:
	var a := _unit(1, Vector2(500, 700))
	var b := _unit(2, Vector2(650, 720))
	var directives: Dictionary = GeneralScript.reserve_directives([a, b])
	assert_eq(directives[a.uid], {
		"type": SubcommanderScript.DIRECTIVE_HOLD_LINE, "x": 500.0, "y": 700.0,
	})
	assert_eq(directives[b.uid], {
		"type": SubcommanderScript.DIRECTIVE_HOLD_LINE, "x": 650.0, "y": 720.0,
	})


func test_reserve_directives_is_empty_for_no_reserves() -> void:
	assert_eq(GeneralScript.reserve_directives([]), {})
