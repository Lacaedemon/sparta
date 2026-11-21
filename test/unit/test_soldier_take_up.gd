extends GutTest
## SoldierTakeUp: a rider rides a routed man down only under an order to (an attack on the routed
## unit, or a standing order to pursue), or under the ON_SIGHT variant; each rider looks for
## himself, and one who sees no runner keeps to his order on his place.

const AT := Vector2(500, 500)
const TICK := 1.0 / 60.0


func _unit(team: int, count: int, at: Vector2, uid: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.team = team
	add_child_autofree(u)
	u.uid = uid
	u.position = at
	u.seed_sim_soldiers()
	return u


## A one-man router 100 wu north of a two-rider troop on the move; rider 1 stands beyond his sight
## of the runner.
func _scene() -> Array:
	var r := _unit(0, 1, AT, 1)
	r._sim_soldier_pos[0] = AT
	r._rout()
	var p := _unit(1, 2, AT + Vector2(0, 100), 2)
	p.is_cavalry = true
	p.state = Unit.State.MOVING
	p._sim_soldier_pos[0] = AT + Vector2(0, 100)
	p._sim_soldier_pos[1] = AT + Vector2(p.sight_range + 300.0, 100)
	return [r, p]


## Every rider of `p` looks round once, with the men of `units` held where they stand.
func _look_once(p: Unit, units: Array) -> void:
	var held: Array = units.map(func(u: Unit) -> Array: return [u._sim_soldier_pos.duplicate(),
			u.state])
	for k in range(p.rout_reaction_ticks()):
		await get_tree().physics_frame
		for m in range(units.size()):
			(units[m] as Unit)._sim_soldier_pos = held[m][0]
			(units[m] as Unit).state = held[m][1]
		SoldierFlight.tick = k
		SoldierFlight.prepare(Engine.get_physics_frames(), units, [], null)
		SoldierTakeUp.look_round(p, 2)


func _attack(p: Unit, r: Unit) -> void:
	var o := Order.new()
	o.type = Order.Type.ATTACK
	o.target_uid = r.uid
	p.current_order = o
	p.target_enemy = r


func test_a_troop_with_no_order_after_the_rout_rides_none_down() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	await _look_once(p, s)
	assert_false(SoldierPursuitStep.is_pursuing(p), "on the move with no order to pursue, none rides")
	p.target_enemy = s[0]   # a target taken up from contact is no order
	p.state = Unit.State.FIGHTING
	await _look_once(p, s)
	assert_false(SoldierPursuitStep.is_pursuing(p), "nor fighting it with no order")


func test_an_attack_on_the_routed_unit_sends_each_rider_who_sees_a_runner() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	_attack(p, s[0])
	await _look_once(p, s)
	assert_true(SoldierPursuitStep.chasing(p, 0), "the rider who sees the runner rides at him")
	assert_false(SoldierPursuitStep.chasing(p, 1), "the one who sees none keeps his place")
	assert_false(SoldierPursuitStep.all_chasing(p, 2), "so the troop is not all off its grid")
	p._sim_body_vel[1] = Vector2(50, 0)   # rider 1 is on the move with his troop
	var at: Vector2 = p._sim_soldier_pos[1]
	SoldierPursuitStep.step(p, 2, {}, TICK)
	assert_eq(p._sim_soldier_pos[1], at, "the pursuit moves only the rider who rides")


func test_an_attack_on_another_unit_rides_no_runner_down() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	var formed := _unit(0, 1, AT + Vector2(0, -900), 3)
	_attack(p, formed)
	await _look_once(p, [s[0], p, formed])
	assert_false(SoldierPursuitStep.is_pursuing(p), "an attack elsewhere is not an order to pursue")


func test_a_standing_order_to_pursue_or_on_sight_rides_runners_down() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	p.order_mode = Unit.ORDER_CHASE
	await _look_once(p, s)
	assert_true(SoldierPursuitStep.chasing(p, 0), "the chase stance sends him")
	p._sim_chase_dir = PackedVector2Array()
	p.order_mode = 0
	p.horse_pursuit = SoldierTakeUp.Mode.ON_SIGHT
	await _look_once(p, s)
	assert_true(SoldierPursuitStep.chasing(p, 0), "ON_SIGHT sends him unordered")
	p._sim_chase_dir = PackedVector2Array()
	p.order_mode = Unit.ORDER_HOLD
	await _look_once(p, s)
	assert_false(SoldierPursuitStep.is_pursuing(p), "but not off HOLD")


func test_the_chase_ends_when_no_rider_sees_a_runner() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	_attack(p, s[0])
	await _look_once(p, s)
	assert_true(SoldierPursuitStep.is_pursuing(p), "setup: a rider rides")
	(s[0] as Unit)._sim_soldier_pos[0] = AT + Vector2(0, -p.sight_range - 400.0)
	await _look_once(p, s)
	assert_true(p._sim_chase_dir.is_empty(), "the runner gone from sight, nothing is remembered")


func test_the_grid_follows_the_riders_on_their_places_not_the_one_riding_off() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	var slots: PackedVector2Array = p.soldier_world_slots(p.soldiers)
	p._sim_soldier_pos[0] = slots[0] + Vector2(0, -300)   # rider 0 rides off after a runner
	p._sim_soldier_pos[1] = slots[1]   # rider 1 keeps his place
	p._sim_chase_dir = PackedVector2Array([Vector2.UP, Vector2.ZERO])
	var at: Vector2 = p.position
	SoldierBodies.couple(p, TICK)
	assert_almost_eq(p.position, at, Vector2(0.001, 0.001), "the grid does not follow him off")
	p._sim_chase_dir = PackedVector2Array([Vector2.UP, Vector2.UP])
	SoldierBodies.couple(p, TICK)
	assert_almost_eq(p.position, (p._sim_soldier_pos[0] + p._sim_soldier_pos[1]) / 2.0,
			Vector2(0.001, 0.001), "with every rider riding, the troop is read off its men")


func _end_chase_by_step(p: Unit, s: Array, state: int, on_place: bool = false) -> void:
	_attack(p, s[0])
	await _look_once(p, s)
	assert_true(SoldierPursuitStep.is_pursuing(p), "setup: a rider rides")
	p._sim_chase_dir[1] = Vector2.ZERO
	(s[0] as Unit)._sim_soldier_pos[0] = AT + Vector2(0, -p.sight_range - 400.0)
	var slots: PackedVector2Array = p.soldier_world_slots(p.soldiers)
	if not on_place:   # the chase has left every rider far off his place
		p._sim_soldier_pos[0] = slots[0] + Vector2(0, -400)
		p._sim_soldier_pos[1] = slots[1] + Vector2(0, -400)
	else:   # rider 1 kept his place
		p._sim_soldier_pos[1] = slots[1]
	await get_tree().physics_frame
	SoldierFlight.tick = 0   # rider 0 looks round on this tick
	SoldierFlight.prepare(Engine.get_physics_frames(), s, [], null)
	p.state = state
	p.step_sim_soldiers(TICK)


func test_a_troop_left_standing_when_its_chase_ends_pulls_up_first() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	await _end_chase_by_step(p, s, Unit.State.IDLE)
	assert_true(p._sim_chase_dir.is_empty(), "no rider sees a runner: the chase is over")
	assert_true(p._rally_pending, "its riders pull up from the gallop before it forms up")


func test_a_troop_with_somewhere_to_go_when_its_chase_ends_forms_up_at_once() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	await _end_chase_by_step(p, s, Unit.State.MOVING)
	assert_true(p._sim_chase_dir.is_empty(), "the chase is over")
	assert_false(p._rally_pending, "it does not wait for its riders to pull up")
	assert_eq(p._last_redeal_tick, Engine.get_physics_frames(), "it forms up where they stand")


func test_a_troop_in_contact_anchors_on_its_riders_on_their_places() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	p._in_enemy_contact = true   # it anchors on its front (Unit.position_anchor_indices)
	var slots: PackedVector2Array = p.soldier_world_slots(p.soldiers)
	p._sim_soldier_pos[0] = slots[0] + Vector2(0, -300)   # rider 0 rides off after a runner
	p._sim_soldier_pos[1] = slots[1]
	p._sim_chase_dir = PackedVector2Array([Vector2.UP, Vector2.ZERO])
	var at: Vector2 = p.position
	SoldierBodies.couple(p, TICK)
	assert_gt(p.position.y, at.y - 0.001, "the anchor is not drawn after the rider riding off")


func test_only_a_rider_riding_a_runner_strikes_on_the_move() -> void:
	var s: Array = _scene()
	var r: Unit = s[0]
	var p: Unit = s[1]
	r._sim_soldier_pos[0] = p._sim_soldier_pos[1] + Vector2(0, 10)   # a runner by rider 1
	p._sim_soldier_facing[1] = Vector2.UP
	p._sim_chase_dir = PackedVector2Array([Vector2.UP, Vector2.ZERO])   # rider 0 rides elsewhere
	var hp: float = r._sim_soldier_hp[0]
	for _k in range(80):
		SoldierPursuitStep.strike(p)
	assert_true(r._sim_soldier_hp.size() == 1 and r._sim_soldier_hp[0] == hp,
			"rider 1, on his place, does not strike on the move")


func test_an_order_that_is_no_attack_on_the_runners_sends_no_rider() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	var o := Order.new()
	o.type = Order.Type.MOVE   # a march, though it names the routed unit
	o.target_uid = (s[0] as Unit).uid
	p.current_order = o
	p.target_enemy = s[0]
	await _look_once(p, s)
	assert_false(SoldierPursuitStep.is_pursuing(p), "a march is no order to pursue")
	var formed := _unit(0, 1, AT + Vector2(0, -900), 3)
	_attack(p, formed)
	p.target_enemy = s[0]   # its target taken up from contact is the routed unit
	await _look_once(p, [s[0], p, formed])
	assert_false(SoldierPursuitStep.is_pursuing(p), "an attack ordered on another unit sends none")


func test_a_rider_whose_chase_ends_rides_back_to_his_place_while_others_kept_theirs() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	await _end_chase_by_step(p, s, Unit.State.MOVING, true)
	assert_true(p._sim_chase_dir.is_empty(), "the chase is over")
	assert_eq(p._last_redeal_tick, -1, "with a rider on his place, the unit does not re-form")


func test_a_retarget_from_contact_leaves_the_attack_on_the_routed_unit_standing() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	_attack(p, s[0])
	p.target_enemy = _unit(0, 1, AT + Vector2(0, -900), 3)   # contact took up another foe
	await _look_once(p, s)
	assert_true(SoldierPursuitStep.chasing(p, 0), "the order, not the target taken up, sends him")


func test_a_chasing_rider_of_a_standing_unit_strikes() -> void:
	var s: Array = _scene()
	var r: Unit = s[0]
	var p: Unit = s[1]
	p.state = Unit.State.IDLE   # a standing troop on the chase stance, or ON_SIGHT
	r._sim_soldier_pos[0] = p._sim_soldier_pos[0] + Vector2(0, -10)   # a runner by rider 0
	p._sim_soldier_facing[0] = Vector2.UP
	p._sim_chase_dir = PackedVector2Array([Vector2.UP, Vector2.ZERO])
	var struck := false
	for _k in range(80):
		struck = SoldierPursuitStep.strike(p) or struck
	assert_true(struck, "the rider riding the runner down strikes")


func test_the_slotted_step_leaves_a_chasing_rider_to_the_pursuit() -> void:
	var s: Array = _scene()
	var p: Unit = s[1]
	p.order_mode = Unit.ORDER_CHASE
	var slots: PackedVector2Array = p.soldier_world_slots(p.soldiers)
	p._sim_soldier_pos[0] = slots[0] + Vector2(-300, 0)   # his place lies 300 wu east of him
	p._sim_body_vel[0] = Vector2.ZERO
	p._sim_chase_dir = PackedVector2Array([Vector2.UP, Vector2.ZERO])
	await get_tree().physics_frame
	SoldierFlight.tick = 1   # not rider 0's tick to look round: he keeps riding north
	SoldierFlight.prepare(Engine.get_physics_frames(), s, [], null)
	var x0: float = p._sim_soldier_pos[0].x
	p.step_sim_soldiers(TICK)
	assert_almost_eq(p._sim_soldier_pos[0].x, x0, 0.0001, "nothing draws him east toward his place")


func test_a_troop_is_scattered_when_most_of_its_men_stand_off_their_places() -> void:
	var p := _unit(1, 3, AT, 2)
	var slots: PackedVector2Array = p.soldier_world_slots(p.soldiers)
	for i in range(3):
		p._sim_soldier_pos[i] = slots[i]
	p._sim_soldier_pos[0] = slots[0] + Vector2(0, -400)
	assert_false(SoldierTakeUp.scattered(p, 3), "one man of three off his place: the ranks stand")
	p._sim_soldier_pos[1] = slots[1] + Vector2(0, -400)
	assert_true(SoldierTakeUp.scattered(p, 3), "two of three off: the ranks are where the men are not")
