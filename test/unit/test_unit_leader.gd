extends GutTest
## Battle AI phase 1 (docs/battle-ai-design.md): UnitLeader.decide's tactical
## repertoire. Exercised at the same level as test_battle.gd's order-dispatch tests --
## units built directly via the script (add_child_autofree so _ready() joins "units"),
## no full Battle scene needed since UnitLeader reads only unit fields and the
## "units" group. Each test checks the returned order-command Dictionary shape
## (what Battle._apply_order_cmd will apply), not sim side effects -- those are
## _apply_order_cmd's own contract, already covered by test_battle.gd.

const UnitScript = preload("res://scripts/Unit.gd")
const UnitLeaderScript = preload("res://scripts/UnitLeader.gd")
const BattleScript = preload("res://scripts/Battle.gd")


func _unit(uid: int, pos: Vector2, team: int = 1) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins "units", sets the footprint
	u.uid = uid
	u.position = pos
	u.team = team
	return u


func _all() -> Array:
	return get_tree().get_nodes_in_group("units")


# --- fallback: advance/attack the nearest living enemy -----------------------

func test_idle_unit_attacks_the_nearest_living_enemy() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	var near := _unit(2, Vector2(0, 50), 0)
	var far := _unit(3, Vector2(0, 500), 0)
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_eq(int(cmd["target"]), near.uid, "targets the nearer player unit")
	assert_eq(cmd["units"], [u.uid])
	assert_almost_eq(float(cmd["x"]), near.position.x, 0.01)
	assert_almost_eq(float(cmd["y"]), near.position.y, 0.01)


func test_no_decision_when_no_enemies_on_the_field() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_true(cmd.is_empty(), "no living enemy: nothing to decide this tick")


func test_dead_or_routing_leaders_decide_nothing() -> void:
	var dead := _unit(1, Vector2(0, 0), 1)
	dead.state = Unit.State.DEAD
	var router := _unit(2, Vector2(0, 0), 1)
	router.state = Unit.State.ROUTING
	_unit(3, Vector2(0, 50), 0)
	assert_true(UnitLeaderScript.decide(dead, _all()).is_empty(), "a dead unit issues no order")
	assert_true(UnitLeaderScript.decide(router, _all()).is_empty(), "a routing unit issues no order")


func test_already_targeting_the_nearest_enemy_decides_nothing_new() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	var near := _unit(2, Vector2(0, 50), 0)
	u.target_enemy = near   # already attacking the unit UnitLeader would pick
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_true(cmd.is_empty(), "no fresh order needed: already chasing the nearest enemy")


func test_fighting_unit_with_no_flank_threat_decides_nothing() -> void:
	# A unit already locked in melee shouldn't get a fresh advance/attack order each
	# tick -- its own _think loop keeps fighting target_enemy without Battle re-issuing.
	var u := _unit(1, Vector2(0, 0), 1)
	u.state = Unit.State.FIGHTING
	var foe := _unit(2, Vector2(0, 40), 0)
	u.target_enemy = foe
	u.facing = Vector2.DOWN   # foe is in front (facing dot ~1.0): no flank threat
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_true(cmd.is_empty(), "already fighting head-on: nothing new to decide")


# --- face a flank threat ------------------------------------------------------

func test_flank_contact_retargets_to_the_flanker() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	u.facing = Vector2.DOWN   # fronting downward
	u.attack_range = 100.0    # generous reach so both foes are "in contact"
	var front := _unit(2, Vector2(0, 40), 0)      # straight ahead: frontal
	var flanker := _unit(3, Vector2(60, 0), 0)     # to the side: flank
	u.target_enemy = front
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_eq(int(cmd["target"]), flanker.uid, "reacts to the flanking contact, not the frontal one")


func test_rear_contact_counts_as_a_flank_threat() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	u.facing = Vector2.DOWN
	u.attack_range = 100.0
	var rear := _unit(2, Vector2(0, -40), 0)   # directly behind
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_eq(int(cmd["target"]), rear.uid, "an enemy at the unit's back is a flank/rear threat")


func test_distant_flanker_outside_contact_is_not_a_flank_threat() -> void:
	# _flank_threat only reacts to a threat already in attack-range contact -- a
	# distant flanker is handled by the ordinary advance/attack fallback instead.
	var u := _unit(1, Vector2(0, 0), 1)
	u.facing = Vector2.DOWN
	var flanker := _unit(2, Vector2(500, 0), 0)   # far off to the side, out of range
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	# Falls through to the advance/attack fallback and targets the only enemy present.
	assert_eq(int(cmd["target"]), flanker.uid)


# --- form anti-cavalry square --------------------------------------------------

func test_anti_cavalry_unit_forms_square_when_cavalry_closes() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	u.anti_cavalry = true
	var cav := _unit(2, Vector2(100, 0), 0)
	cav.is_cavalry = true
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_eq(int(cmd["target"]), BattleScript.ORDER_FORMATION_ONLY)
	assert_eq(int(cmd["formation"]), Unit.FORMATION_SQUARE)
	assert_eq(cmd["units"], [u.uid])


func test_non_anti_cavalry_unit_does_not_form_square() -> void:
	var u := _unit(1, Vector2(0, 0), 1)   # anti_cavalry left false
	var cav := _unit(2, Vector2(100, 0), 0)
	cav.is_cavalry = true
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_ne(int(cmd.get("target", -99)), BattleScript.ORDER_FORMATION_ONLY,
		"only an anti-cavalry unit forms the anti-cav square")


func test_already_square_unit_does_not_re_form() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	u.anti_cavalry = true
	u.set_formation(Unit.FORMATION_SQUARE)
	var cav := _unit(2, Vector2(100, 0), 0)
	cav.is_cavalry = true
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_ne(int(cmd.get("target", -99)), BattleScript.ORDER_FORMATION_ONLY,
		"already square: no repeated formation order")


func test_distant_cavalry_does_not_trigger_square() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	u.anti_cavalry = true
	var cav := _unit(2, Vector2(2000, 0), 0)   # far outside SQUARE_TRIGGER_RANGE
	cav.is_cavalry = true
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_ne(int(cmd.get("target", -99)), BattleScript.ORDER_FORMATION_ONLY,
		"cavalry not yet closing: no square order")


# --- call for relief when wavering --------------------------------------------

func test_wavering_unit_in_contact_calls_a_fresh_ally_to_relieve_it() -> void:
	var tired := _unit(1, Vector2(0, 0), 1)
	tired.state = Unit.State.FIGHTING
	tired.morale = 10.0   # below RELIEF_MORALE_THRESHOLD
	var fresh := _unit(2, Vector2(50, 0), 1)   # nearby, idle, healthy morale
	fresh.morale = 100.0
	var foe := _unit(3, Vector2(0, 40), 0)
	tired.target_enemy = foe
	tired.facing = Vector2.DOWN   # foe is frontal: no flank-threat override
	var cmd: Dictionary = UnitLeaderScript.decide(tired, _all())
	assert_eq(cmd["units"], [fresh.uid], "the FRESH ally is the one ordered to relieve")
	assert_eq(int(cmd["target"]), tired.uid, "relief order names the wavering unit as the target")


func test_wavering_unit_with_no_fresh_ally_nearby_gets_no_relief_order() -> void:
	var tired := _unit(1, Vector2(0, 0), 1)
	tired.state = Unit.State.FIGHTING
	tired.morale = 10.0
	var foe := _unit(2, Vector2(0, 40), 0)
	tired.target_enemy = foe
	tired.facing = Vector2.DOWN
	var cmd: Dictionary = UnitLeaderScript.decide(tired, _all())
	assert_true(cmd.is_empty(), "no ally to call on: unit just keeps fighting")


func test_healthy_morale_unit_in_contact_does_not_call_for_relief() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	u.state = Unit.State.FIGHTING
	u.morale = 100.0
	var fresh := _unit(2, Vector2(50, 0), 1)
	fresh.morale = 100.0
	var foe := _unit(3, Vector2(0, 40), 0)
	u.target_enemy = foe
	u.facing = Vector2.DOWN
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_true(cmd.is_empty(), "morale is fine: no relief call")


func test_wavering_unit_ignores_an_ally_already_relieving_someone_else() -> void:
	var tired := _unit(1, Vector2(0, 0), 1)
	tired.state = Unit.State.FIGHTING
	tired.morale = 10.0
	var busy := _unit(2, Vector2(50, 0), 1)
	busy.morale = 100.0
	busy.set_current_order(Order.new_relief(99))   # already mid-swap for another ally
	var foe := _unit(3, Vector2(0, 40), 0)
	tired.target_enemy = foe
	tired.facing = Vector2.DOWN
	var cmd: Dictionary = UnitLeaderScript.decide(tired, _all())
	assert_true(cmd.is_empty(), "an ally already relieving someone else isn't called again")


func test_wavering_unit_ignores_an_ally_already_supporting_a_ward() -> void:
	var tired := _unit(1, Vector2(0, 0), 1)
	tired.state = Unit.State.FIGHTING
	tired.morale = 10.0
	var busy := _unit(2, Vector2(50, 0), 1)
	busy.morale = 100.0
	# The ward doesn't need to be "real" for this check -- support_target just needs to
	# be non-null so busy reads as already committed. Using tired itself avoids adding a
	# second idle ally that would otherwise qualify as its own relief candidate.
	busy.support_target = tired
	var foe := _unit(3, Vector2(0, 40), 0)
	tired.target_enemy = foe
	tired.facing = Vector2.DOWN
	var cmd: Dictionary = UnitLeaderScript.decide(tired, _all())
	assert_true(cmd.is_empty(), "an ally already guarding a ward isn't called away to relieve")


func test_wavering_unit_ignores_a_fresh_ally_that_is_itself_fighting() -> void:
	var tired := _unit(1, Vector2(0, 0), 1)
	tired.state = Unit.State.FIGHTING
	tired.morale = 10.0
	var busy := _unit(2, Vector2(50, 0), 1)
	busy.state = Unit.State.FIGHTING   # not "fresh" -- already committed elsewhere
	busy.morale = 100.0
	var foe := _unit(3, Vector2(0, 40), 0)
	tired.target_enemy = foe
	tired.facing = Vector2.DOWN
	var cmd: Dictionary = UnitLeaderScript.decide(tired, _all())
	assert_true(cmd.is_empty(), "the only ally nearby is busy fighting, so no relief call fires")


# --- a reliever's own RELIEF order must survive its own re-decide ---------------

func test_reliever_mid_advance_keeps_its_relief_order_on_a_later_decide() -> void:
	# UnitRelief.begin sets target_enemy but never touches state, so a reliever
	# advancing toward the swap is NOT yet FIGHTING -- exactly the state the
	# fallback branch normally issues a fresh ATTACK order for. Without the
	# RELIEF exclusion, this decide() call would clobber the reliever's own
	# current_order (and its relief_partner link) with an ATTACK order.
	var reliever := _unit(1, Vector2(0, 0), 1)
	reliever.set_current_order(Order.new_relief(99))   # already ordered to relieve `tired`
	var foe := _unit(2, Vector2(400, 0), 0)   # a living enemy the fallback could target
	reliever.target_enemy = foe   # UnitRelief.begin's effect: target set, state untouched
	var cmd: Dictionary = UnitLeaderScript.decide(reliever, _all())
	assert_true(cmd.is_empty(),
		"a unit already executing its own RELIEF order keeps it -- no fresh ATTACK order")
	assert_eq(reliever.current_order.type, Order.Type.RELIEF,
		"the RELIEF order itself is untouched by this decide() call")


func test_reliever_still_reacts_to_a_flank_threat_while_relieving() -> void:
	# The RELIEF exclusion only guards the advance/attack fallback -- a reliever
	# that picks up a flank/rear contact along the way still reacts to it, same
	# priority order as every other tactical case.
	var reliever := _unit(1, Vector2(0, 0), 1)
	reliever.set_current_order(Order.new_relief(99))
	reliever.facing = Vector2.DOWN
	reliever.attack_range = 100.0
	var flanker := _unit(2, Vector2(60, 0), 0)   # to the side: flank contact
	var cmd: Dictionary = UnitLeaderScript.decide(reliever, _all())
	assert_eq(int(cmd["target"]), flanker.uid,
		"a flank threat still overrides the relief order's advance, same as any other unit")


# --- a subcommander directive must not interrupt a live chase ------------------

func test_directive_does_not_interrupt_a_unit_already_chasing_a_live_target() -> void:
	# The unit has a live ATTACK order closing on a still-alive foe -- a subcommander
	# directive must not pull it off that pursuit mid-chase (it would leave the unit
	# defenseless with no target, the same self-preservation-first principle the
	# flank-threat/square/relief priorities above already apply).
	var u := _unit(1, Vector2(0, 0), 1)
	var foe := _unit(2, Vector2(200, 0), 0)   # not yet in contact, but alive
	u.set_current_order(Order.new_attack(foe.uid))
	u.target_enemy = foe
	var directive := {"type": Subcommander.DIRECTIVE_HOLD_LINE, "x": 999.0, "y": 999.0}
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all(), directive)
	assert_true(cmd.is_empty(),
		"already chasing the only living enemy: the directive doesn't interrupt it")


func test_directive_applies_once_the_chased_target_is_dead() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	var foe := _unit(2, Vector2(200, 0), 0)
	foe.state = Unit.State.DEAD
	u.set_current_order(Order.new_attack(foe.uid))
	u.target_enemy = foe
	var directive := {"type": Subcommander.DIRECTIVE_HOLD_LINE, "x": 50.0, "y": 60.0}
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all(), directive)
	assert_eq(int(cmd["target"]), -1, "the chased target is dead: the directive is free to apply")
	assert_almost_eq(float(cmd["x"]), 50.0, 0.01)
	assert_almost_eq(float(cmd["y"]), 60.0, 0.01)


func test_directive_applies_once_the_chased_target_is_routing() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	var foe := _unit(2, Vector2(200, 0), 0)
	foe.state = Unit.State.ROUTING
	u.set_current_order(Order.new_attack(foe.uid))
	u.target_enemy = foe
	var directive := {"type": Subcommander.DIRECTIVE_HOLD_LINE, "x": 50.0, "y": 60.0}
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all(), directive)
	assert_eq(int(cmd["target"]), -1, "the chased target is routing: the directive is free to apply")


func test_directive_applies_when_the_unit_has_no_attack_order_at_all() -> void:
	# A directive should not be over-blocked either -- with no ATTACK order in flight,
	# is_chasing_live_target must read false and the directive applies normally, same
	# as before this guard existed.
	var u := _unit(1, Vector2(0, 0), 1)
	var foe := _unit(2, Vector2(200, 0), 0)
	var directive := {"type": Subcommander.DIRECTIVE_HOLD_LINE, "x": 50.0, "y": 60.0}
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all(), directive)
	assert_eq(int(cmd["target"]), -1, "no live chase in progress: the directive applies")


# --- priority ordering ---------------------------------------------------------

func test_flank_threat_takes_priority_over_square_formation() -> void:
	var u := _unit(1, Vector2(0, 0), 1)
	u.anti_cavalry = true
	u.attack_range = 100.0
	u.facing = Vector2.DOWN
	var cav := _unit(2, Vector2(60, 0), 0)   # both a flank contact AND cavalry
	cav.is_cavalry = true
	var cmd: Dictionary = UnitLeaderScript.decide(u, _all())
	assert_eq(int(cmd["target"]), cav.uid, "facing the immediate contact wins over forming square")
