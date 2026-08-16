extends GutTest
## Mid-battle weapon switching (docs/soldier-loadout-design.md, phase 4): a switch order
## re-equips a regiment to another LoadoutRegistry weapon type, and every place the sim
## reads the equipped weapon follows in the same tick.
##
## Phase 1 built _sim_soldier_weapon_id for exactly this write, so the per-soldier half is
## the easy half. What these tests actually pin is the three consumers that would silently
## keep answering with the OLD weapon if the switch only touched that array: the seed
## source a casualty/growth resize refills from, the derived reach, and the spawn
## fingerprint's documented "spawn-time-stable fields only" contract.

const BattleScript = preload("res://scripts/Battle.gd")

const SEED: int = 12345


func before_each() -> void:
	Replay.rng.seed = SEED   # deterministic draws for any combat side effects


## The whole point of the phase: a switch rewrites the per-soldier ids strike-time
## lethality resolves through, the unit-level id, and the reach derived from the new
## type -- all three, not just the array.
func test_equip_weapon_rewrites_type_reach_and_every_soldier_id() -> void:
	var u: Unit = _bare_unit(1, 0, 12)
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.attack_range = 1.3 * BattleScript.WORLD_UNITS_PER_METER
	u.seed_sim_soldiers()

	assert_true(u.equip_weapon(LoadoutRegistry.WEAPON_PILUM), "the pilum is a registered type")

	assert_eq(u.weapon_type_id, LoadoutRegistry.WEAPON_PILUM,
		"the unit-level id names the newly held weapon")
	var pilum: Weapon = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_PILUM)
	assert_almost_eq(u.attack_range, pilum.reach_m * BattleScript.WORLD_UNITS_PER_METER, 0.0001,
		"attack_range is re-derived from the new type's reach")
	assert_almost_eq(u.soldier_reach(), u.attack_range, 0.0001,
		"soldier_reach reports the new reach with nothing else to update")
	var mismatched: int = 0
	for i in range(u._sim_soldier_weapon_id.size()):
		if u._sim_soldier_weapon_id[i] != LoadoutRegistry.WEAPON_PILUM:
			mismatched += 1
	assert_eq(mismatched, 0, "every soldier now carries the new weapon id")
	assert_almost_eq(u.soldier_lethality(0), pilum.lethality, 0.0001,
		"strike-time lethality resolves through the new type")
	assert_almost_eq(u.melee_attack_interval(), pilum.attack_interval_s, 0.0001,
		"the attack cadence follows the new type")


## The regression the unit-level write exists to prevent. SoldierBodies' growth resize (and
## TierTransition, and a fresh seed) refill new per-soldier entries from weapon_type_id --
## so a switch that rewrote ONLY the per-soldier array would quietly re-arm the old weapon
## on the next casualty resize, with nothing failing at the moment of the switch.
func test_a_growth_resize_after_a_switch_arms_the_new_weapon_not_the_old_one() -> void:
	var u: Unit = _bare_unit(2, 0, 12)
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.seed_sim_soldiers()
	u.equip_weapon(LoadoutRegistry.WEAPON_PILUM)

	u.soldiers = 15   # a merge/relief-style gain; step resizes to the live count
	u.step_sim_soldiers(1.0 / 60.0)

	assert_eq(u._sim_soldier_weapon_id.size(), u._sim_soldier_pos.size(),
		"the weapon ids grew in step with the bodies")
	var stale: int = 0
	for i in range(u._sim_soldier_weapon_id.size()):
		if u._sim_soldier_weapon_id[i] != LoadoutRegistry.WEAPON_PILUM:
			stale += 1
	assert_eq(stale, 0, "fresh tail bodies carry the switched-to weapon, not the deployed one")


## SpawnFingerprint.record_of documents itself as reading spawn-time-stable fields only, so
## its digest is the same taken at spawn or mid-battle. A switch moves weapon_type_id, so
## the record has to read the deployed weapon instead -- otherwise switching re-stamps a
## demo artifact's own fingerprint and fails its load check over a spawn layout that never
## moved.
func test_spawn_fingerprint_is_unchanged_by_a_mid_battle_switch() -> void:
	var u: Unit = _bare_unit(3, 0, 8)
	u.unit_name = "Infantry"
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.spawn_weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.seed_sim_soldiers()
	var before: Dictionary = SpawnFingerprint.record_of(u)

	u.equip_weapon(LoadoutRegistry.WEAPON_PILUM)
	var after: Dictionary = SpawnFingerprint.record_of(u)

	assert_eq(after, before, "the spawn fingerprint record survives a weapon switch intact")
	assert_eq(int(before["weapon"]), LoadoutRegistry.WEAPON_GLADIUS,
		"and it still hashes the weapon the unit deployed holding")


## A malformed order must not strand the regiment holding a type nothing resolves: an
## unregistered id is refused, leaving every weapon-derived field exactly as it was.
func test_equip_weapon_refuses_an_unregistered_id_and_changes_nothing() -> void:
	var u: Unit = _bare_unit(4, 0, 6)
	u.weapon_type_id = LoadoutRegistry.WEAPON_SPEAR
	u.attack_range = 2.4 * BattleScript.WORLD_UNITS_PER_METER
	u.seed_sim_soldiers()
	var reach_before: float = u.attack_range

	assert_false(u.equip_weapon(9999), "an unregistered weapon id is refused")

	assert_eq(u.weapon_type_id, LoadoutRegistry.WEAPON_SPEAR, "the held type is untouched")
	assert_almost_eq(u.attack_range, reach_before, 0.0001, "the reach is untouched")
	var changed: int = 0
	for i in range(u._sim_soldier_weapon_id.size()):
		if u._sim_soldier_weapon_id[i] != LoadoutRegistry.WEAPON_SPEAR:
			changed += 1
	assert_eq(changed, 0, "no soldier's weapon id moved")


## Re-issuing the same switch reports success without churning anything -- notably the
## figure meshes, which the switch rebuilds so the man stops brandishing the weapon he
## just put away.
func test_switching_to_the_held_type_succeeds_without_changing_anything() -> void:
	var u: Unit = _bare_unit(5, 0, 6)
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.seed_sim_soldiers()
	var mesh_before: ArrayMesh = u._figure_body_mesh

	assert_true(u.equip_weapon(LoadoutRegistry.WEAPON_GLADIUS),
		"re-equipping the held type reports success")

	assert_eq(u.weapon_type_id, LoadoutRegistry.WEAPON_GLADIUS, "the held type is unchanged")
	assert_eq(u._figure_body_mesh, mesh_before, "the figure meshes were not rebuilt")


## The pilum's numbers are chosen to make the switch a decision rather than a strict
## upgrade: it buys reach and pays for it in sustained killing power. Pinned here because
## a later tuning pass that inverted either half would silently turn the whole mechanic
## into "always hold the pilum" (or "never draw it") with no test failing.
func test_the_pilum_trades_sustained_rate_for_reach_against_the_gladius() -> void:
	var pilum: Weapon = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_PILUM)
	var gladius: Weapon = LoadoutRegistry.weapon(LoadoutRegistry.WEAPON_GLADIUS)
	assert_not_null(pilum, "the pilum is registered")

	assert_gt(pilum.reach_m, gladius.reach_m, "the pilum out-reaches the gladius")
	var pilum_rate: float = pilum.lethality / pilum.attack_interval_s
	var gladius_rate: float = gladius.lethality / gladius.attack_interval_s
	assert_lt(pilum_rate, gladius_rate,
		"but kills more slowly in sustained melee, so holding it too long costs casualties")


## Deeper reach means more ranks can reach forward into contact, so the switch visibly
## changes the engaged tier's depth -- a sim consequence, not just a stats readout.
func test_switching_to_a_longer_weapon_deepens_the_engaged_tier() -> void:
	var u: Unit = _bare_unit(6, 0, 40)
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.attack_range = 1.3 * BattleScript.WORLD_UNITS_PER_METER
	u.seed_sim_soldiers()
	var ranks_before: int = u.engaged_ranks()

	u.equip_weapon(LoadoutRegistry.WEAPON_PILUM)

	assert_gt(u.engaged_ranks(), ranks_before,
		"the longer weapon fields more ranks into the engaged tier")


## The order object carries its target, and the type is named -- so an order transcript
## reads "SWITCH_WEAPON" rather than a bare enum ordinal.
func test_the_order_carries_its_target_weapon_and_names_its_type() -> void:
	var o: Order = Order.new_switch_weapon(LoadoutRegistry.WEAPON_PILUM)
	assert_eq(o.type, Order.Type.SWITCH_WEAPON, "the factory builds a SWITCH_WEAPON order")
	assert_eq(o.weapon, LoadoutRegistry.WEAPON_PILUM, "carrying the target weapon id")
	assert_eq(Order.type_name(Order.Type.SWITCH_WEAPON), "SWITCH_WEAPON",
		"the type has a transcript name")


## Every other order type leaves `weapon` at the registry's reserved-invalid 0, so the
## field doubles as "unset" and can't be mistaken for a real type.
func test_other_order_types_leave_the_weapon_field_unset() -> void:
	assert_eq(Order.new_stance(0).weapon, 0, "a stance order carries no weapon")
	assert_eq(Order.new_formation(0).weapon, 0, "a formation order carries no weapon")


## The render half, and the one a state dump can't see: at the figure LOD the MultiMeshes
## hold their own reference to the silhouette pair they were last handed, and the code that
## re-hands it (_apply_lod_meshes) normally runs only when the LOD level or the facing side
## FLIPS -- neither of which a weapon switch does. So rebuilding the mesh resources alone
## leaves the block drawing the weapon it just put away until the camera happens to cross a
## zoom threshold. Asserted on `mesh` identity, the one MultiMesh property that does read
## back in a headless test (per-instance transforms don't).
func test_switching_at_figure_lod_re_hands_the_new_silhouette_to_the_multimesh() -> void:
	var u: Unit = _bare_unit(1, 0, 12)
	u.weapon_type_id = LoadoutRegistry.WEAPON_GLADIUS
	u.seed_sim_soldiers()
	# Stand in for a zoomed-in camera: _update_lod needs a real viewport camera, so pin the
	# level directly and hand the figure pair over the way an LOD flip would.
	u._detailed_lod = true
	u._apply_lod_meshes()
	var gladius_mesh: Mesh = u._mm_body.mesh
	assert_eq(gladius_mesh, u._figure_body_mesh, "the block is drawing the figure silhouette")

	assert_true(u.equip_weapon(LoadoutRegistry.WEAPON_PILUM), "the pilum is a registered type")

	assert_ne(u._mm_body.mesh, gladius_mesh,
		"the drawn silhouette changed -- the shaft is not still the old shield glyph")
	assert_eq(u._mm_body.mesh, u._figure_body_mesh,
		"and it is the pair the switch just rebuilt, not some other stale resource")
	assert_eq(u._mm_outline.mesh, u._figure_outline_mesh,
		"the outline follows the body, so the silhouette doesn't render half-swapped")


func _bare_unit(uid: int, team: int, n: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = team
	return u
