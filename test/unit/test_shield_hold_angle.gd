extends GutTest
## Per-soldier shield hold-angle array (docs/soldier-loadout-design.md, phase 2):
## every spawned soldier starts at its shield TYPE's rest pose in a
## PackedFloat32Array index-aligned with _sim_soldier_pos, and the array stays
## aligned — per index, not just per size — through growth and casualty
## compaction. A formation change resets every soldier back to the rest pose.
## Representational only: nothing reads the array for combat or rendering yet,
## so these tests pin the data model, not a gameplay outcome.

const SEED: int = 12345


func before_each() -> void:
	Replay.rng.seed = SEED   # deterministic draws for any combat side effects


## One live battle covers the whole spawn path: every roster unit's hold-angle
## array is index-aligned with its bodies, and every soldier starts at the rest
## pose its unit's shield type defines (read from the registry, the source of
## truth, not a literal).
func test_spawned_soldiers_start_at_their_shields_rest_pose() -> void:
	Replay.forced_seed = SEED   # consumed by Battle's RNG setup before any roll
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	for _k in range(2):
		await get_tree().physics_frame   # let the soldier layer seed its arrays
	var checked: int = 0
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		var n: int = u._sim_soldier_pos.size()
		assert_gt(n, 0, "%s spawned soldier bodies" % u.unit_name)
		assert_eq(u._sim_soldier_shield_hold_angle.size(), n,
			"%s hold angles are index-aligned with the bodies" % u.unit_name)
		var rest: float = LoadoutRegistry.shield(u.shield_type_id).default_hold_angle
		assert_almost_eq(u.shield_rest_angle(), rest, 0.0001,
			"%s rest-angle lookup resolves its shield type" % u.unit_name)
		var off_rest: int = 0
		for i in range(u._sim_soldier_shield_hold_angle.size()):
			if absf(u._sim_soldier_shield_hold_angle[i] - rest) > 0.0001:
				off_rest += 1
		assert_eq(off_rest, 0,
			"every %s soldier starts at its shield's rest pose" % u.unit_name)
		checked += 1
	assert_gt(checked, 0, "the battle spawned roster units to check")


## Casualty compaction (SoldierMelee.reap) removes the dead soldier's hold-angle
## entry exactly like the other per-soldier arrays. Distinct per-index values
## prove the SURVIVORS keep their own angles in order — a per-index alignment
## pin, stronger than a size check.
func test_casualty_compaction_keeps_each_survivors_own_angle() -> void:
	var u: Unit = _bare_unit(1, 0, 12)
	u.seed_sim_soldiers()
	for i in range(u._sim_soldier_shield_hold_angle.size()):
		u._sim_soldier_shield_hold_angle[i] = 0.1 * float(i)   # distinct per soldier
	var killer: Unit = _bare_unit(2, 1, 4)
	u._sim_soldier_hp[3] = 0.0
	u._sim_soldier_hp[7] = 0.0
	SoldierMelee.reap(u, killer)
	assert_eq(u.soldiers, 10, "two casualties left ten soldiers")
	var n: int = u._sim_soldier_pos.size()
	assert_eq(u._sim_soldier_shield_hold_angle.size(), n,
		"hold angles compact in step with the bodies")
	var survivors: Array = [0, 1, 2, 4, 5, 6, 8, 9, 10, 11]
	for k in range(survivors.size()):
		assert_almost_eq(u._sim_soldier_shield_hold_angle[k],
			0.1 * float(survivors[k]), 0.0001,
			"survivor %d still carries its own hold angle" % k)


## Growth (SoldierBodies.step resizing to a larger live count) seeds every fresh
## tail body at the rest pose and leaves the existing bodies' angles untouched.
func test_growth_seeds_tail_bodies_at_rest_without_touching_the_rest() -> void:
	var u: Unit = _bare_unit(3, 0, 12)
	u.seed_sim_soldiers()
	for i in range(u._sim_soldier_shield_hold_angle.size()):
		u._sim_soldier_shield_hold_angle[i] = 0.1 * float(i)   # distinct per soldier
	u.soldiers = 15   # a merge/relief-style gain; step resizes to the live count
	u.step_sim_soldiers(1.0 / 60.0)
	assert_eq(u._sim_soldier_shield_hold_angle.size(), u._sim_soldier_pos.size(),
		"hold angles grew in step with the bodies")
	for i in range(12):
		assert_almost_eq(u._sim_soldier_shield_hold_angle[i], 0.1 * float(i), 0.0001,
			"existing body %d kept its own hold angle through the resize" % i)
	var rest: float = u.shield_rest_angle()
	for j in range(12, u._sim_soldier_shield_hold_angle.size()):
		assert_almost_eq(u._sim_soldier_shield_hold_angle[j], rest, 0.0001,
			"fresh tail body %d starts at the rest pose" % j)


## A formation change resets every soldier back to the shield's rest pose, so no
## stale posture angle survives a stance switch.
func test_formation_change_resets_every_angle_to_rest() -> void:
	var u: Unit = _bare_unit(4, 0, 12)
	u.seed_sim_soldiers()
	for i in range(u._sim_soldier_shield_hold_angle.size()):
		u._sim_soldier_shield_hold_angle[i] = 0.7   # a perturbed, non-rest posture
	u.set_formation(Unit.FORMATION_TIGHT)
	var rest: float = u.shield_rest_angle()
	for i in range(u._sim_soldier_shield_hold_angle.size()):
		assert_almost_eq(u._sim_soldier_shield_hold_angle[i], rest, 0.0001,
			"soldier %d snapped back to the rest pose on the formation change" % i)


## Before the bodies are seeded, a formation change is a no-op on the empty
## hold-angle array (the spawn path sets the stance before the soldier layer
## exists; seed() fills it from scratch afterwards).
func test_formation_change_before_seeding_is_a_noop() -> void:
	var u: Unit = _bare_unit(5, 0, 12)
	u.set_formation(Unit.FORMATION_SHIELD_WALL)
	assert_eq(u._sim_soldier_shield_hold_angle.size(), 0,
		"no hold-angle entries exist before the bodies are seeded")


## An unknown shield id resolves to a 0.0 rest angle instead of erroring, and
## the seed fill uses that same fallback.
func test_unknown_shield_id_falls_back_to_zero_rest_angle() -> void:
	var u: Unit = _bare_unit(6, 0, 4)
	u.shield_type_id = 999   # no such registry entry
	assert_almost_eq(u.shield_rest_angle(), 0.0, 0.0001,
		"an unknown shield id resolves to a 0.0 rest angle")
	u.seed_sim_soldiers()
	for i in range(u._sim_soldier_shield_hold_angle.size()):
		assert_almost_eq(u._sim_soldier_shield_hold_angle[i], 0.0, 0.0001,
			"soldier %d seeded at the fallback rest angle" % i)


func _bare_unit(uid: int, team: int, n: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = team
	return u
