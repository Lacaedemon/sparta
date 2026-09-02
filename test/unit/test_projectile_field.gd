extends GutTest
## In-flight projectile field: a volley enqueues a projectile that flies its arc and lands
## its arrows on individual men (ranged fire has travel time). Verifies the flight delay, the
## on-landing resolution against the per-soldier health pool, the shield arc and the
## deflect/lodge/pierce split it gates, determinism, and the dead/degenerate guards. The
## shield roll draws from the one seeded stream, so a run restarts the seed where it compares
## two of them.

const SEED: int = 1234567


## Minimal stand-in for Battle (a Node, like the real caller): the field only needs the
## uid -> unit lookup.
class FakeBattle extends Node:
	var by_uid: Dictionary = {}
	func unit_by_uid(uid: int):
		return by_uid.get(uid, null)


func before_each() -> void:
	Replay.rng.seed = SEED


func _unit(uid: int, team: int, n: int, pos: Vector2, face: Vector2, ranged: bool) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.is_ranged = ranged
	u.state = Unit.State.FIGHTING
	if not ranged:
		u.seed_sim_soldiers()    # a melee target gets a soldier layer for the volley to bite
	return u


func _field_and_battle(shooter: Unit, target: Unit) -> Array:
	var field := ProjectileField.new()
	var battle := FakeBattle.new()
	add_child_autofree(battle)
	battle.by_uid[shooter.uid] = shooter
	battle.by_uid[target.uid] = target
	return [field, battle]


func test_launch_puts_one_projectile_in_flight() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	assert_eq(field.count(), 1, "the volley is now a projectile in flight")


func test_casualties_are_withheld_until_the_arrow_lands() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	var battle: FakeBattle = fb[1]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	field.step(0.05, battle)   # a sliver of the multi-second flight
	assert_eq(target.soldiers, 20, "no one falls while the arrows are still in the air")
	assert_eq(field.count(), 1, "the projectile is still flying")


func test_arrow_delivers_its_casualties_on_landing() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	var battle: FakeBattle = fb[1]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	field.step(10.0, battle)   # well past any flight time -> it lands
	assert_eq(target.soldiers, 15, "the five casualties land with the arrows")
	assert_eq(field.count(), 0, "the spent projectile is removed")
	assert_eq(target._sim_soldier_hp.size(), 15, "and the bodies compact around the survivors")


func test_landing_is_deterministic() -> void:
	var results: Array[int] = []
	for _run in range(2):
		Replay.rng.seed = SEED   # the shield roll draws from the seeded stream, so restart it
		var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
		var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
		var fb: Array = _field_and_battle(shooter, target)
		var field: ProjectileField = fb[0]
		field.launch(shooter.position, target.position, shooter.uid, target.uid, 6, 1.0, true)
		field.step(10.0, fb[1])
		results.append(target.soldiers)
	assert_eq(results[0], results[1], "same launch -> same survivors, every run")


func test_target_that_routs_in_flight_still_lands() -> void:
	# A routing (broken or shattered) target is still fair game --- fleeing doesn't dodge
	# an arrow already in flight (matches UnitCombat.take_casualties: only DEAD is skipped).
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	target.state = Unit.State.ROUTING   # routed away before the arrows arrive
	field.step(10.0, fb[1])
	assert_eq(field.count(), 0, "the projectile is consumed")
	assert_eq(target.soldiers, 15, "a routing target still takes the volley's casualties")


func test_target_that_dies_in_flight_is_skipped() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	target.state = Unit.State.DEAD   # actually gone before the arrows arrive
	field.step(10.0, fb[1])
	assert_eq(field.count(), 0, "the projectile is still consumed")
	assert_eq(target.soldiers, 20, "a dead target takes no further casualties")


func test_fallback_applies_the_flanked_count_without_re_flanking() -> void:
	# A target with no soldier layer (e.g. an archer regiment) takes the volley through the
	# regiment fallback. `casualties` already has the flank baked in, so soldiers must drop by
	# exactly that count -- not flank x it (the double-flank the review caught).
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, true)   # ranged -> no soldier layer
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	assert_true(target._sim_soldier_hp.is_empty(), "precondition: the target has no soldier layer")
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 2.0, true)
	field.step(10.0, fb[1])
	assert_eq(target.soldiers, 15, "drops by exactly the pre-flanked count (5), not 5x2")


func test_zero_distance_shot_still_lands() -> void:
	var shooter := _unit(1, 0, 10, Vector2(100, 100), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(100, 100), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	# Shields off: a point-blank shot arrives from inside the block itself, so which men it
	# covers is geometric noise -- this test is about the degenerate FLIGHT, not the gate.
	field.shield_block_scale = 0.0
	# from == to: solve_launch returns a 0 flight time; the field must still resolve it.
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 3, 1.0, true)
	field.step(1.0, fb[1])
	assert_eq(field.count(), 0, "a degenerate shot doesn't get stuck in flight forever")
	assert_eq(target.soldiers, 17, "it lands and delivers its casualties")


# --- shield arc + shield block ------------------------------------------------
# The archers stand due north of the target block, so an arrow arrives from straight in
# front of a unit facing UP and from straight behind one facing DOWN. The block scale is
# pushed to certainty in most of these so the outcome is the GATE's, not the roll's.

func _shot_from_the_north(target_facing: Vector2) -> Array:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 24, Vector2(0, 400), target_facing, false)
	var fb: Array = _field_and_battle(shooter, target)
	return [fb[0], fb[1], shooter, target]


func test_a_shield_facing_the_volley_stops_every_arrow_it_covers() -> void:
	var s: Array = _shot_from_the_north(Vector2.UP)   # shields toward the archers
	var field: ProjectileField = s[0]
	var target: Unit = s[3]
	field.shield_block_scale = 10.0   # every covered arrow is stopped, so the gate is the test
	field.launch(s[2].position, target.position, s[2].uid, target.uid, 8, 1.0, true)
	field.step(10.0, s[1])
	assert_eq(target.soldiers, 24, "a wall facing the archers loses nobody to the volley")


func test_the_same_volley_into_an_unshielded_back_kills_every_man_it_reaches() -> void:
	var s: Array = _shot_from_the_north(Vector2.DOWN)   # backs to the archers
	var field: ProjectileField = s[0]
	var target: Unit = s[3]
	field.shield_block_scale = 10.0   # identical shields, identical roll -- only facing differs
	field.launch(s[2].position, target.position, s[2].uid, target.uid, 8, 1.0, true)
	field.step(10.0, s[1])
	assert_eq(target.soldiers, 16, "arrows behind the shield arc all find a man")


func test_facing_the_archers_beats_turning_your_back_at_the_default_odds() -> void:
	# The same contrast without the certainty crutch: today's shipped probabilities.
	Replay.rng.seed = SEED
	var front: Array = _shot_from_the_north(Vector2.UP)
	front[0].launch(front[2].position, front[3].position, front[2].uid, front[3].uid, 10, 1.0, true)
	front[0].step(10.0, front[1])
	var front_losses: int = 24 - front[3].soldiers
	Replay.rng.seed = SEED
	var back: Array = _shot_from_the_north(Vector2.DOWN)
	back[0].launch(back[2].position, back[3].position, back[2].uid, back[3].uid, 10, 1.0, true)
	back[0].step(10.0, back[1])
	var back_losses: int = 24 - back[3].soldiers
	assert_eq(back_losses, 10, "every arrow into an exposed back tells")
	assert_lt(front_losses, back_losses, "facing the volley costs strictly fewer men")


func test_an_unshielded_regiment_takes_the_whole_volley_head_on() -> void:
	var s: Array = _shot_from_the_north(Vector2.UP)
	var target: Unit = s[3]
	target._sim_soldier_shield_id.fill(LoadoutRegistry.SHIELD_NONE)   # archers, skirmishers
	var field: ProjectileField = s[0]
	field.shield_block_scale = 10.0
	field.launch(s[2].position, target.position, s[2].uid, target.uid, 8, 1.0, true)
	field.step(10.0, s[1])
	assert_eq(target.soldiers, 16, "no shield, no arc, no reprieve -- facing changes nothing")


func test_zeroing_the_block_scale_restores_the_unshielded_resolution() -> void:
	# The knobs are caller-configurable, and this one turns the whole gate off: the volley
	# resolves exactly as it did before shields entered the landing path.
	var s: Array = _shot_from_the_north(Vector2.UP)
	var field: ProjectileField = s[0]
	field.shield_block_scale = 0.0
	field.launch(s[2].position, s[3].position, s[2].uid, s[3].uid, 8, 1.0, true)
	field.step(10.0, s[1])
	assert_eq(s[3].soldiers, 16, "with no block chance every arrow lands, shield or not")


func test_lodged_arrows_accumulate_as_weight_on_the_regiments_shields() -> void:
	var s: Array = _shot_from_the_north(Vector2.UP)
	var field: ProjectileField = s[0]
	var target: Unit = s[3]
	field.shield_block_scale = 10.0
	field.shield_lodge_share = 1.0   # every stop sticks rather than glancing off
	assert_eq(field.lodged_arrows(target.uid), 0, "precondition: nothing stuck in them yet")
	field.launch(s[2].position, target.position, s[2].uid, target.uid, 8, 1.0, true)
	field.step(10.0, s[1])
	assert_eq(field.lodged_arrows(target.uid), 8, "all eight stand in the shield faces")
	assert_almost_eq(field.lodged_weight_kg(target.uid), 8.0 * field.arrow_mass_kg, 0.0001,
		"and they weigh what eight arrows weigh")
	assert_eq(target.soldiers, 24, "a lodged arrow still spares the man behind the shield")


func test_deflected_arrows_leave_no_weight_behind() -> void:
	var s: Array = _shot_from_the_north(Vector2.UP)
	var field: ProjectileField = s[0]
	field.shield_block_scale = 10.0
	field.shield_lodge_share = 0.0   # every stop glances off instead
	field.launch(s[2].position, s[3].position, s[2].uid, s[3].uid, 8, 1.0, true)
	field.step(10.0, s[1])
	assert_eq(field.lodged_arrows(s[3].uid), 0, "an arrow that glances off is simply gone")
	assert_eq(field.shield_sag(s[3]), 0.0, "so the wall has lost no cover")


func test_lodged_weight_sags_the_wall_and_the_sag_is_capped() -> void:
	var s: Array = _shot_from_the_north(Vector2.UP)
	var field: ProjectileField = s[0]
	var target: Unit = s[3]
	field.shield_block_scale = 10.0
	field.shield_lodge_share = 1.0
	field.launch(s[2].position, target.position, s[2].uid, target.uid, 8, 1.0, true)
	field.step(10.0, s[1])
	assert_gt(field.shield_sag(target), 0.0, "arrows in the shields drag them off the line")
	assert_lt(field.shield_sag(target), field.shield_max_sag, "eight arrows is not yet the cap")
	field.arrow_mass_kg = 1000.0   # an absurd weight, to prove the cap is a cap
	assert_eq(field.shield_sag(target), field.shield_max_sag, "no bombardment erases cover entirely")


func test_a_regiment_with_no_lodged_arrows_reports_none() -> void:
	var s: Array = _shot_from_the_north(Vector2.UP)
	var field: ProjectileField = s[0]
	assert_eq(field.lodged_arrows(999), 0, "an unknown regiment has caught nothing")
	assert_eq(field.lodged_weight_kg(999), 0.0, "and carries no weight")
	assert_eq(field.shield_sag(s[3]), 0.0, "a fresh wall has lost no cover")
