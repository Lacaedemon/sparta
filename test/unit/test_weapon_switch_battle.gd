extends GutTest
## The weapon-switch ORDER end to end in a live battle (docs/soldier-loadout-design.md,
## phase 4): Battle.enqueue_switch_weapon re-equips the named units, records a command a
## replay can reproduce the switch from, and occupies the order queue only when the unit is
## idle -- the same instantaneous-write shape as the stance and formation orders.
##
## test_weapon_switch.gd covers Unit.equip_weapon itself; this file covers the order that
## drives it and the roster data that gives a unit something to switch to.

const SEED: int = 12345


func before_each() -> void:
	Replay.rng.seed = SEED


## Infantry deploy holding the gladius and carry the pilum alongside it -- the pair the
## switch swaps between. Every other roster type carries no second weapon, so a switch
## simply isn't available to them rather than needing a branch of its own.
func test_the_roster_gives_infantry_a_second_weapon_and_nobody_else() -> void:
	var battle: Node = await _spawned_battle()
	var infantry_checked: int = 0
	var others_checked: int = 0
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		assert_eq(u.spawn_weapon_type_id, u.weapon_type_id,
			"%s deploys holding its spawn weapon" % u.unit_name)
		if u.unit_name.split(" ")[0] == "Infantry":
			assert_eq(u.weapon_type_id, LoadoutRegistry.WEAPON_GLADIUS,
				"Infantry still deploy holding the gladius -- spawn combat is unchanged")
			assert_eq(u.sidearm_type_id, LoadoutRegistry.WEAPON_PILUM,
				"Infantry carry the pilum as their second weapon")
			infantry_checked += 1
		else:
			assert_null(LoadoutRegistry.weapon(u.sidearm_type_id),
				"%s carries no second weapon" % u.unit_name)
			others_checked += 1
	assert_gt(infantry_checked, 0, "the battle spawned Infantry to check")
	assert_gt(others_checked, 0, "and other roster types to check against")
	battle.queue_free()


## The order re-equips every unit it names, and the sim reads the new type immediately:
## reach, cadence and per-soldier lethality all move together.
func test_the_order_re_equips_the_named_units() -> void:
	var battle: Node = await _spawned_battle()
	var u: Unit = _first_infantry()
	assert_not_null(u, "found an Infantry unit to switch")
	var reach_before: float = u.attack_range

	battle.enqueue_switch_weapon([u.uid], LoadoutRegistry.WEAPON_PILUM)

	assert_eq(u.weapon_type_id, LoadoutRegistry.WEAPON_PILUM, "the unit drew its pilum")
	assert_gt(u.attack_range, reach_before, "and reaches further with it")
	var stale: int = 0
	for i in range(u._sim_soldier_weapon_id.size()):
		if u._sim_soldier_weapon_id[i] != LoadoutRegistry.WEAPON_PILUM:
			stale += 1
	assert_eq(stale, 0, "every one of its soldiers carries the new weapon id")
	battle.queue_free()


## Switching back returns the unit to the weapon it deployed with -- the toggle's return
## leg, which reads spawn_weapon_type_id rather than remembering what was held.
func test_switching_back_restores_the_deployed_weapon() -> void:
	var battle: Node = await _spawned_battle()
	var u: Unit = _first_infantry()
	assert_not_null(u, "found an Infantry unit to switch")
	var reach_deployed: float = u.attack_range

	battle.enqueue_switch_weapon([u.uid], LoadoutRegistry.WEAPON_PILUM)
	battle.enqueue_switch_weapon([u.uid], u.spawn_weapon_type_id)

	assert_eq(u.weapon_type_id, LoadoutRegistry.WEAPON_GLADIUS, "the gladius is back in hand")
	assert_almost_eq(u.attack_range, reach_deployed, 0.0001, "with its own reach restored")
	battle.queue_free()


## The recorded command carries the two fields a replay reproduces the switch from: the
## order sentinel and, riding the always-recorded "mode" field, the target weapon id. That
## is what keeps the switch deterministic on replay without changing the replay format.
func test_the_order_records_the_target_weapon_in_the_mode_field() -> void:
	var battle: Node = await _spawned_battle()
	var u: Unit = _first_infantry()
	assert_not_null(u, "found an Infantry unit to switch")
	battle._pending_orders.clear()

	battle.enqueue_switch_weapon([u.uid], LoadoutRegistry.WEAPON_PILUM)

	assert_eq(battle._pending_orders.size(), 1, "the switch queued exactly one command")
	var cmd: Dictionary = battle._pending_orders[0]
	assert_eq(int(cmd["target"]), battle.ORDER_SWITCH_WEAPON,
		"tagged with the weapon-switch sentinel")
	assert_eq(int(cmd["mode"]), LoadoutRegistry.WEAPON_PILUM,
		"and carrying the target weapon id in the recorded mode field")
	battle.queue_free()


## An unregistered id is refused per-unit, so a malformed order records as a no-op rather
## than parking an order claiming a switch that never happened.
func test_an_unregistered_weapon_id_leaves_the_unit_and_its_queue_alone() -> void:
	var battle: Node = await _spawned_battle()
	var u: Unit = _first_infantry()
	assert_not_null(u, "found an Infantry unit to switch")
	u.retire_current_order()
	var held_before: int = u.weapon_type_id

	battle.enqueue_switch_weapon([u.uid], 9999)

	assert_eq(u.weapon_type_id, held_before, "the unit keeps the weapon it was holding")
	assert_null(u.current_order, "and no order was parked claiming otherwise")
	battle.queue_free()


## An idle unit takes the switch as its current order (so the transcript shows it), exactly
## like the stance and formation orders.
func test_an_idle_unit_takes_the_switch_as_its_current_order() -> void:
	var battle: Node = await _spawned_battle()
	var u: Unit = _first_infantry()
	assert_not_null(u, "found an Infantry unit to switch")
	u.retire_current_order()

	battle.enqueue_switch_weapon([u.uid], LoadoutRegistry.WEAPON_PILUM)

	assert_not_null(u.current_order, "the idle unit parked the switch as its order")
	assert_eq(u.current_order.type, Order.Type.SWITCH_WEAPON, "of the switch-weapon type")
	assert_eq(u.current_order.weapon, LoadoutRegistry.WEAPON_PILUM, "naming the drawn weapon")
	battle.queue_free()


func _spawned_battle() -> Node:
	Replay.forced_seed = SEED   # consumed by Battle's RNG setup before any roll
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(2):
		await get_tree().physics_frame   # let the soldier layer seed its arrays
	return battle


func _first_infantry() -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.unit_name.split(" ")[0] == "Infantry":
			return u
	return null
