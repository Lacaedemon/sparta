extends GutTest
## Fog of war. Perception visibility query and last-known table, Unit type-derived
## sight defaults, the off-by-default Settings toggle, and Battle's fog pass -- which
## hides unseen enemies by CanvasItem.visible, syncs ghost markers with the recorded
## value driving playback, restores everything when switched off,
## and stays off under all-teams control. Fog is render-only and does not alter the
## retreat margin.

const Perception = preload("res://scripts/Perception.gd")
const FogGhostLayer = preload("res://scripts/FogGhostLayer.gd")
const WorldScale = preload("res://scripts/WorldScale.gd")
const HUDScript = preload("res://scripts/HUD.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const AllTeamsControl = preload("res://scripts/AllTeamsControl.gd")

# One foot unit's sight radius on the default battle: Unit.DEFAULT_SIGHT_SCALE x SIGHT_FOOT.
const FOOT_SIGHT: float = 15.0 * WorldScale.WU_PER_M

# A near enemy (inside foot sight of the friendly), a far one (outside every disc), and
# the friendly observer. Coordinates are on open ground between the forest and the hill.
const FRIENDLY_POS := Vector2(600.0, 300.0)
const NEAR_ENEMY_POS := Vector2(600.0, 500.0)    # 200 wu away: seen on open ground
const FAR_ENEMY_POS := Vector2(1200.0, 900.0)    # ~1000 wu away: unseen
var _staged_battles: Array[Node] = []


func after_each() -> void:
	Settings.set_fog_of_war_session(false)
	AllTeamsControl.clear()
	Replay.forced_seed = -1
	Replay.reset()
	for b in _staged_battles:
		if is_instance_valid(b):
			b.free()
	_staged_battles.clear()
	await get_tree().physics_frame


## A bare (out-of-tree) unit with just the fields Perception reads.
func _unit(uid: int, team: int, pos: Vector2, sight: float = FOOT_SIGHT) -> Unit:
	var u: Unit = autofree(Unit.new())
	u.uid = uid
	u.team = team
	u.position = pos
	u.sight_range = sight
	u.facing = Vector2.DOWN
	u.soldiers = 100
	return u


# --- Perception.perceives ------------------------------------------------------------


func test_perceives_inside_range_and_on_the_boundary_but_not_beyond() -> void:
	var o := Vector2(100.0, 100.0)
	assert_true(Perception.perceives(o, 50.0, o + Vector2(30.0, 0.0)), "inside the disc")
	assert_true(Perception.perceives(o, 50.0, o + Vector2(50.0, 0.0)), "on the boundary (inclusive)")
	assert_false(Perception.perceives(o, 50.0, o + Vector2(50.001, 0.0)), "just beyond")
	assert_false(Perception.perceives(o, 0.0, o), "a zero sight range sees nothing, not even itself")


func test_perceives_blocked_by_occluding_terrain() -> void:
	var o := Vector2(100.0, 100.0)
	var t := Vector2(100.0, 250.0)    # 150 wu away, inside 200 wu sight range
	var hill_patch := {"rect": Rect2(50.0, 150.0, 100.0, 20.0), "type": "hill", "kind": "block", "sight": "block"}
	assert_true(Perception.perceives(o, 200.0, t), "unobstructed target inside sight range is perceived")
	assert_false(Perception.perceives(o, 200.0, t, [hill_patch]), "occluding terrain patch blocks line of sight")


func test_perceives_clear_sight_override_on_block_terrain() -> void:
	var o := Vector2(100.0, 100.0)
	var t := Vector2(100.0, 250.0)    # 150 wu away
	var low_wall := {"rect": Rect2(50.0, 150.0, 100.0, 20.0), "type": "wall", "kind": "block", "sight": "clear"}
	assert_true(Perception.perceives(o, 200.0, t, [low_wall]), "sight: clear patch does not block line of sight")


func test_perceives_attenuated_by_screening_terrain() -> void:
	var o := Vector2(100.0, 100.0)
	var screen_patch := {"rect": Rect2(50.0, 130.0, 100.0, 40.0), "type": "forest", "kind": "slow", "sight": "screen"}
	# Sight range 200 wu, attenuated by 0.5 is 100 wu.
	var near_target := Vector2(100.0, 180.0)    # 80 wu away <= 100 wu
	var far_target := Vector2(100.0, 220.0)     # 120 wu away > 100 wu, but < 200 wu unattenuated
	assert_true(Perception.perceives(o, 200.0, near_target, [screen_patch]),
		"target inside attenuated screening range is perceived")
	assert_false(Perception.perceives(o, 200.0, far_target, [screen_patch]),
		"target beyond attenuated screening range is not perceived even if inside unattenuated radius")


func test_perceives_compounding_screening_attenuation() -> void:
	var o := Vector2(100.0, 100.0)
	var patch1 := {"rect": Rect2(50.0, 130.0, 100.0, 20.0), "type": "forest", "kind": "slow", "sight": "screen"}
	var patch2 := {"rect": Rect2(50.0, 170.0, 100.0, 20.0), "type": "forest", "kind": "slow", "sight": "screen"}
	# Sight range 400 wu, crossing 2 screening patches: 400 * 0.5 * 0.5 = 100 wu.
	var target_in := Vector2(100.0, 190.0)      # 90 wu away <= 100 wu
	var target_out := Vector2(100.0, 210.0)     # 110 wu away > 100 wu
	assert_true(Perception.perceives(o, 400.0, target_in, [patch1, patch2]),
		"target inside doubly-attenuated range is perceived")
	assert_false(Perception.perceives(o, 400.0, target_out, [patch1, patch2]),
		"target beyond doubly-attenuated range is not perceived")


# --- Perception.visible_enemy_uids ---------------------------------------------------


func test_visible_enemy_uids_holds_only_enemies_inside_some_friendly_disc() -> void:
	var friendly := _unit(1, 0, FRIENDLY_POS)
	var near := _unit(2, 1, NEAR_ENEMY_POS)
	var far := _unit(3, 1, FAR_ENEMY_POS)
	var other_friendly := _unit(4, 0, Vector2(800.0, 300.0))
	var seen: Dictionary = Perception.visible_enemy_uids(0, [friendly, near, far, other_friendly])
	assert_true(seen.has(near.uid), "an enemy inside a friendly sight disc is visible")
	assert_false(seen.has(far.uid), "an enemy outside every friendly disc is not")
	assert_false(seen.has(other_friendly.uid), "friendlies never appear in the enemy set")
	assert_false(seen.has(friendly.uid), "the observer itself never appears either")


func test_visible_enemy_uids_is_per_team() -> void:
	var friendly := _unit(1, 0, FRIENDLY_POS)
	var near := _unit(2, 1, NEAR_ENEMY_POS)
	var seen_by_1: Dictionary = Perception.visible_enemy_uids(1, [friendly, near])
	assert_true(seen_by_1.has(friendly.uid), "team 1 sees the team-0 unit inside its own disc")
	assert_false(seen_by_1.has(near.uid), "team 1's own unit is not an enemy to team 1")


func test_routing_observer_sees_a_shorter_disc() -> void:
	var observer := _unit(1, 0, FRIENDLY_POS)
	# Just inside the full disc, but outside the routing-penalised one.
	var edge := _unit(2, 1, FRIENDLY_POS + Vector2(0.0, FOOT_SIGHT * 0.9))
	assert_true(Perception.visible_enemy_uids(0, [observer, edge]).has(edge.uid),
		"a steady observer sees to its full range")
	observer.state = Unit.State.ROUTING
	assert_almost_eq(Perception.observer_range(observer), FOOT_SIGHT * Unit.SIGHT_ROUTING_PENALTY, 0.001,
		"a routing observer's range is cut by SIGHT_ROUTING_PENALTY")
	assert_false(Perception.visible_enemy_uids(0, [observer, edge]).has(edge.uid),
		"and so it no longer sees the enemy near the edge of its full disc")


# --- Perception.record_contacts ------------------------------------------------------


func test_contact_is_written_on_a_seen_tick_and_untouched_afterwards() -> void:
	var friendly := _unit(1, 0, FRIENDLY_POS)
	var enemy := _unit(2, 1, NEAR_ENEMY_POS)
	var units: Array = [friendly, enemy]
	var contacts: Dictionary = {}
	Perception.record_contacts(contacts, units, Perception.visible_enemy_uids(0, units), 10)
	assert_true(contacts.has(enemy.uid), "seen this tick: an entry is written")
	assert_eq(contacts[enemy.uid]["tick"], 10, "dated with the sighting tick")
	assert_eq(contacts[enemy.uid]["position"], NEAR_ENEMY_POS, "at the sighted position")
	assert_eq(contacts[enemy.uid]["strength"], 100, "with the sighted strength")
	assert_false(contacts.has(friendly.uid), "friendlies are never recorded")
	# The enemy walks out of sight and loses men: its entry must not change.
	enemy.position = FAR_ENEMY_POS
	enemy.soldiers = 40
	Perception.record_contacts(contacts, units, Perception.visible_enemy_uids(0, units), 20)
	assert_eq(contacts[enemy.uid]["tick"], 10, "an unseen enemy's entry keeps its old tick")
	assert_eq(contacts[enemy.uid]["position"], NEAR_ENEMY_POS, "and its old position")
	assert_eq(contacts[enemy.uid]["strength"], 100, "and its old strength")


func test_contact_survives_the_unit_leaving_play() -> void:
	var friendly := _unit(1, 0, FRIENDLY_POS)
	var enemy := _unit(2, 1, NEAR_ENEMY_POS)
	var contacts: Dictionary = {}
	Perception.record_contacts(contacts, [friendly, enemy], {enemy.uid: true}, 5)
	# The enemy dies unobserved: it is simply absent from later unit lists.
	Perception.record_contacts(contacts, [friendly], Perception.visible_enemy_uids(0, [friendly]), 50)
	assert_true(contacts.has(enemy.uid), "a unit that dies unobserved keeps its last-known entry")


# --- Unit sight defaults ---------------------------------------------------------------


func test_unit_sight_range_defaults_by_type_at_ready() -> void:
	var foot: Unit = autofree(Unit.new())
	var horse: Unit = autofree(Unit.new())
	horse.is_cavalry = true
	var bow: Unit = autofree(Unit.new())
	bow.is_ranged = true
	var pinned: Unit = autofree(Unit.new())
	pinned.sight_range = 123.0   # set before _ready: an explicit value is kept
	for u in [foot, horse, bow, pinned]:
		add_child(u)
	assert_almost_eq(foot.sight_range, Unit.DEFAULT_SIGHT_SCALE * Unit.SIGHT_FOOT, 0.001, "foot baseline")
	assert_almost_eq(horse.sight_range, Unit.DEFAULT_SIGHT_SCALE * Unit.SIGHT_MOUNTED, 0.001, "mounted sees farthest")
	assert_almost_eq(bow.sight_range, Unit.DEFAULT_SIGHT_SCALE * Unit.SIGHT_RANGED, 0.001, "ranged sees farther than foot")
	assert_almost_eq(pinned.sight_range, 123.0, 0.001, "a caller's own sight_range survives _ready")
	assert_gt(Unit.SIGHT_MOUNTED, Unit.SIGHT_RANGED, "mounted > ranged")
	assert_gt(Unit.SIGHT_RANGED, Unit.SIGHT_FOOT, "ranged > foot")
	assert_almost_eq(Unit.SIGHT_SCREEN_FACTOR, 0.5, 0.001, "screening multiplier default")


# --- Settings toggle -------------------------------------------------------------------


func test_fog_of_war_setting_is_off_by_default_and_session_setter_is_silent() -> void:
	assert_false(Settings.fog_of_war, "fog of war is off by default")
	var fired: Array = []
	var handler := func() -> void: fired.append(true)
	Settings.changed.connect(handler)
	Settings.set_fog_of_war_session(true)
	assert_true(Settings.fog_of_war, "the session setter flips the value")
	assert_eq(fired.size(), 0, "without emitting `changed` or persisting")
	Settings.changed.disconnect(handler)


# --- FogGhostLayer fade ----------------------------------------------------------------


func test_ghost_alpha_fades_from_fresh_to_stale_and_clamps() -> void:
	var layer: FogGhostLayer = autofree(FogGhostLayer.new())
	layer.fresh_alpha = 0.6
	layer.stale_alpha = 0.2
	layer.stale_ticks = 100
	assert_almost_eq(layer.alpha_for_age(0), 0.6, 0.001, "fresh on the sighting tick")
	assert_almost_eq(layer.alpha_for_age(50), 0.4, 0.001, "halfway through the fade")
	assert_almost_eq(layer.alpha_for_age(100), 0.2, 0.001, "stale at stale_ticks")
	assert_almost_eq(layer.alpha_for_age(5000), 0.2, 0.001, "and clamped there, never below")


# --- Battle rendering pass ------------------------------------------------------------


## A battle staged with one friendly foot unit, one near enemy, and one far enemy.
func _staged_battle(fog: bool, all_teams: bool = false) -> Node:
	Settings.set_fog_of_war_session(fog)
	Replay.forced_seed = 414
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = all_teams
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": FRIENDLY_POS.x, "y": FRIENDLY_POS.y},
		{"team": 1, "type": "Infantry", "x": NEAR_ENEMY_POS.x, "y": NEAR_ENEMY_POS.y},
		{"team": 1, "type": "Infantry", "x": FAR_ENEMY_POS.x, "y": FAR_ENEMY_POS.y},
	]
	_staged_battles.append(battle)
	add_child_autofree(battle)
	return battle


func _units_by_team() -> Dictionary:
	var out: Dictionary = {0: [], 1: []}
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null:
			out[u.team].append(u)
	return out


func _enemy_nearest(pos: Vector2) -> Unit:
	var best: Unit = null
	for u in _units_by_team()[1]:
		if best == null or u.position.distance_to(pos) < best.position.distance_to(pos):
			best = u
	return best


func test_fog_hides_the_far_enemy_and_shows_the_near_one_and_every_friendly() -> void:
	var battle := _staged_battle(true)
	for _k in range(3):
		await get_tree().physics_frame
	var near := _enemy_nearest(NEAR_ENEMY_POS)
	var far := _enemy_nearest(FAR_ENEMY_POS)
	assert_true(near.visible, "an enemy inside the friendly's sight disc renders")
	assert_false(far.visible, "an enemy outside every friendly disc is hidden")
	for u in _units_by_team()[0]:
		assert_true(u.visible, "the player's own units always render")
	assert_true(battle.fog_visible_uids().has(near.uid), "the visible set names the near enemy")
	assert_false(battle.fog_visible_uids().has(far.uid), "and not the far one")
	assert_true(battle.fog_contacts().has(near.uid), "the near enemy has a last-known entry")
	assert_false(battle.fog_contacts().has(far.uid), "the never-seen far enemy has none")
	assert_true(far.is_in_group("units"), "a hidden unit stays in the units group -- visibility does not alter group membership")
	assert_true(battle.get_node("HUD")._fog_label.visible, "the HUD shows the FOG OF WAR indicator")
	# The hidden enemy's sight_range came from the battle's own scale, not the bare default.
	assert_almost_eq(far.sight_range, battle.sight_scale * Unit.SIGHT_FOOT, 0.001,
		"spawned units take their sight from Battle.sight_scale")


func test_fog_off_by_default_renders_everything_and_records_nothing() -> void:
	var battle := _staged_battle(false)
	for _k in range(3):
		await get_tree().physics_frame
	for team in [0, 1]:
		for u in _units_by_team()[team]:
			assert_true(u.visible, "with fog off every unit renders")
	assert_true(battle.fog_visible_uids().is_empty(), "no visible set is computed")
	assert_true(battle.fog_contacts().is_empty(), "no contact is recorded")
	assert_false(battle.get_node("HUD")._fog_label.visible, "and the HUD indicator stays hidden")


func test_switching_fog_off_mid_battle_restores_every_hidden_unit() -> void:
	var battle := _staged_battle(true)
	for _k in range(3):
		await get_tree().physics_frame
	var far := _enemy_nearest(FAR_ENEMY_POS)
	assert_false(far.visible, "hidden while fog is on")
	Settings.set_fog_of_war_session(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(far.visible, "restored on the next tick after fog switches off")
	assert_true(battle.fog_visible_uids().is_empty(), "the visible set is cleared")
	assert_true(battle.fog_contacts().has(_enemy_nearest(NEAR_ENEMY_POS).uid),
		"but the contact table is kept, so switching back on remembers the sighting")


## A fog pass in one battle never mutates units belonging to a concurrent battle.
## Before the fix, get_nodes_in_group collected units across the entire SceneTree,
## so a fog pass in the first battle set visible = false on foreign enemies and
## _sync_rout_margin overwrote foreign retreat bounds with its own field_with_margin.
func test_fog_pass_does_not_mutate_units_in_concurrent_battle() -> void:
	var b_fog: Node = _staged_battle(true)
	var b_other: Node = _staged_battle(false, true)
	Settings.set_fog_of_war_session(true)
	await wait_frames(2)
	var foreign_units: Array = []
	for group in ["units", "routers"]:
		for node in get_tree().get_nodes_in_group(group):
			var u := node as Unit
			if u != null and b_other.is_ancestor_of(u):
				foreign_units.append(u)
	assert_gt(foreign_units.size(), 0, "concurrent battle has live units")
	for u in foreign_units:
		assert_true(u.visible, "concurrent battle units are visible under all-teams control")
		assert_eq(u.retreat_bounds, b_other.field_with_margin,
				"concurrent battle unit has its own battle's retreat bounds")
	b_fog._tick_fog()
	for u in foreign_units:
		assert_true(u.visible,
				"fog pass in first battle never hides a unit belonging to the second battle")
		assert_eq(u.retreat_bounds, b_other.field_with_margin,
				"retreat bounds sync in first battle never overrides foreign unit bounds")


## The toggle is refused under all-teams control for the same reason it is refused
## during playback: is_fog_active() answers from something other than the live setting,
## so flipping it changes nothing on screen while the toast claims it did -- and the
## flip persists into the next ordinary battle, which is the part that outlives the run.
func test_fog_toggle_is_refused_under_all_teams_control() -> void:
	var battle: Node = _staged_battle(false, true)
	await wait_frames(2)
	var hud = battle.get_node("HUD")
	assert_false(battle.is_fog_active(), "all-teams control forces fog off")
	hud._toggle_fog()
	assert_false(Settings.fog_of_war,
			"the live setting is untouched, so nothing leaks into the next battle")
	assert_eq(hud._flash_label.text, "Fog of war stays off while you control both armies",
			"and the toast says why rather than announcing a switch")
	assert_false(hud._fog_label.visible, "the indicator stays hidden")


## The F7 toggle is refused during playback, where is_fog_active() answers from the
## recording: flipping the live setting there would leave the indicator unchanged while
## the toast announced a switch, so the two would visibly disagree.
func test_fog_toggle_is_refused_during_playback() -> void:
	var battle: Node = _staged_battle(false)
	await wait_frames(2)
	var hud = battle.get_node("HUD")
	Replay.mode = Replay.Mode.PLAYBACK
	hud._toggle_fog()
	assert_false(Settings.fog_of_war, "playback leaves the live fog setting alone")
	assert_eq(hud._flash_label.text, "Fog of war is fixed by the recording during playback",
		"and says why instead of announcing a switch that did not happen")
	Replay.mode = Replay.Mode.IDLE
	hud._toggle_fog()
	assert_true(Settings.fog_of_war, "outside playback the same key still flips it")


## The menu toggle is also refused during playback and restores its checkmark,
## because PopupMenu auto-toggles check state before id_pressed fires.
func test_fog_menu_toggle_is_refused_during_playback() -> void:
	var battle: Node = _staged_battle(false)
	await wait_frames(2)
	var hud = battle.get_node("HUD")
	var popup: PopupMenu = hud._menu_button.get_popup()
	var idx: int = popup.get_item_index(hud.MENU_FOG_OF_WAR)
	Replay.mode = Replay.Mode.PLAYBACK
	# Simulate PopupMenu's auto-toggle flipping the item before id_pressed.
	popup.set_item_checked(idx, true)
	hud._on_menu_id(hud.MENU_FOG_OF_WAR)
	assert_false(Settings.fog_of_war, "playback leaves the live fog setting alone")
	assert_false(popup.is_item_checked(idx), "menu checkmark is restored on refusal")
	assert_eq(hud._flash_label.text, "Fog of war is fixed by the recording during playback",
		"and reports why playback refused the menu toggle")
	Replay.mode = Replay.Mode.IDLE
	hud._on_menu_id(hud.MENU_FOG_OF_WAR)
	assert_true(Settings.fog_of_war, "outside playback the menu item flips the setting")
	Settings.set_fog_of_war_session(false)


## F7 toggles fog of war during a live battle. Live battles always record for debug
## replays, but recording does not refuse the toggle.
func test_fog_toggle_works_during_recording() -> void:
	var battle: Node = _staged_battle(false)
	await wait_frames(2)
	assert_eq(Replay.mode, Replay.Mode.RECORD, "staged battle is recording")
	var hud = battle.get_node("HUD")
	hud._toggle_fog()
	assert_true(Settings.fog_of_war, "F7 flips fog on during a live battle")
	assert_eq(hud._flash_label.text, "Fog of war: on",
		"and reports the new state")
	hud._toggle_fog()
	assert_false(Settings.fog_of_war, "F7 flips fog back off")
	assert_eq(hud._flash_label.text, "Fog of war: off",
		"and reports the updated state")


## The menu toggle also flips fog during a live battle and keeps its checkmark in sync.
func test_fog_menu_toggle_works_during_recording() -> void:
	var battle: Node = _staged_battle(false)
	await wait_frames(2)
	assert_eq(Replay.mode, Replay.Mode.RECORD, "staged battle is recording")
	var hud = battle.get_node("HUD")
	var popup: PopupMenu = hud._menu_button.get_popup()
	var idx: int = popup.get_item_index(hud.MENU_FOG_OF_WAR)
	# Simulate PopupMenu's auto-toggle flipping the item before id_pressed.
	popup.set_item_checked(idx, true)
	hud._on_menu_id(hud.MENU_FOG_OF_WAR)
	assert_true(Settings.fog_of_war, "menu toggle flips fog on during a live battle")
	assert_true(popup.is_item_checked(idx), "menu checkmark remains checked")
	assert_eq(hud._flash_label.text, "Fog of war: on",
		"and reports the new state")
	popup.set_item_checked(idx, false)
	hud._on_menu_id(hud.MENU_FOG_OF_WAR)
	assert_false(Settings.fog_of_war, "menu toggle flips fog back off")
	assert_false(popup.is_item_checked(idx), "menu checkmark remains unchecked")
	assert_eq(hud._flash_label.text, "Fog of war: off",
		"and reports the updated state")
	Settings.set_fog_of_war_session(false)


## The menu checkmark derives from the battle's effective fog state rather than
## Settings.fog_of_war alone, staying in sync with the indicator during playback.
func test_fog_menu_checkmark_reflects_effective_battle_state() -> void:
	var old_mode: int = Replay.mode
	var old_map: Dictionary = Replay.map
	var prev_fog: bool = Settings.fog_of_war
	Settings.set_fog_of_war_session(false)
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.seed_value = 42
	Replay.rng.seed = Replay.seed_value
	Replay.map = BattleMap.serialize(Rect2(0, 0, 800, 600), [], [100.0, 500.0], -1.0, true)
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle: Node = scene.instantiate()
	add_child_autofree(battle)
	await wait_frames(2)
	var hud = battle.get_node("HUD")
	var popup: PopupMenu = hud._menu_button.get_popup()
	var idx: int = popup.get_item_index(hud.MENU_FOG_OF_WAR)
	assert_true(battle.is_fog_active(), "recorded map activates fog")
	assert_true(popup.is_item_checked(idx), "menu checkmark reflects active recorded fog")
	assert_true(hud._fog_label.visible, "FOG OF WAR indicator agrees with checkmark")
	Replay.mode = old_mode
	Replay.map = old_map
	Settings.set_fog_of_war_session(prev_fog)


## A non-finite sight_scale (NAN or INF) assigned before _ready is rejected
## and falls back to the default fraction of the short field dimension.
func test_battle_sight_scale_rejects_nan_and_inf() -> void:
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle_nan: Node = scene.instantiate()
	battle_nan.sight_scale = NAN
	add_child_autofree(battle_nan)
	assert_true(is_finite(battle_nan.sight_scale), "NAN sight_scale resolves to finite value")
	var expected_default: float = (
		BattleScript.DEFAULT_SIGHT_SCALE_FRACTION * minf(battle_nan.field.size.x, battle_nan.field.size.y)
	)
	assert_almost_eq(battle_nan.sight_scale, expected_default, 0.001,
		"NAN sight_scale falls back to default field-derived scale")

	var battle_inf: Node = scene.instantiate()
	battle_inf.sight_scale = INF
	add_child_autofree(battle_inf)
	assert_true(is_finite(battle_inf.sight_scale), "INF sight_scale resolves to finite value")
	assert_almost_eq(battle_inf.sight_scale, expected_default, 0.001,
		"INF sight_scale falls back to default field-derived scale")


func test_all_teams_control_disables_fog() -> void:
	var battle: Node = _staged_battle(true, true)
	for _k in range(3):
		await get_tree().physics_frame
	assert_true(_enemy_nearest(FAR_ENEMY_POS).visible,
		"a tester driving both armies sees both, whatever the setting says")
	assert_false(battle.get_node("HUD")._fog_label.visible,
		"and the HUD indicator stays hidden because fog is not active")


## Per-unit sim state that would diverge first if fog fed back into the simulation.
func _sim_fingerprint(battle: Node) -> Dictionary:
	var out: Dictionary = {}
	for group in ["units", "routers"]:
		for node in get_tree().get_nodes_in_group(group):
			var u := node as Unit
			if u != null and battle.is_ancestor_of(u):
				out[u.uid] = [u.position, u.soldiers, u.morale, u.state]
	return out


func _run_sim_pass(fog: bool) -> Dictionary:
	SpatialHash.reset()
	SoldierSpatialHash.reset()
	SoldierEnemyProximity.reset()
	SoldierEngagedEnemyProximity.reset()
	get_tree().paused = true
	var battle: Node = _staged_battle(fog)
	await get_tree().physics_frame
	get_tree().paused = false
	for _k in range(180):
		await get_tree().physics_frame
	var fp: Dictionary = _sim_fingerprint(battle)
	var has_seen: bool = not (battle.fog_visible_uids().is_empty() and battle.fog_contacts().is_empty())
	battle.free()
	await get_tree().physics_frame
	Replay.reset()
	return {"fingerprint": fp, "has_seen": has_seen}


func test_fog_never_changes_the_simulation() -> void:
	# The two enemies advance on the friendly under the AI, so this covers movement,
	# contact, and combat rolls -- everything RNG- and position-driven -- over 3 s.
	var plain_res: Dictionary = await _run_sim_pass(false)
	var plain: Dictionary = plain_res["fingerprint"]
	var fog_res: Dictionary = await _run_sim_pass(true)
	var foggy: Dictionary = fog_res["fingerprint"]
	assert_gt(plain.size(), 0, "the unfogged run has units to compare")
	assert_eq(foggy.keys(), plain.keys(), "the same units are in play")
	for uid in plain:
		assert_eq(foggy[uid], plain[uid], "unit %d matches position/strength/morale/state" % uid)
	assert_true(fog_res["has_seen"],
		"the fog pass actually ran on the fogged battle (it saw or remembered something)")


# --- FogGhostLayer draw --------------------------------------------------------------


## A last-known table with one lost contact (drawn), one that is still seen (skipped), and
## one whose recorded facing is zero (falls back to a default facing).
func _ghost_contacts(tick: int) -> Dictionary:
	return {
		2: {"position": NEAR_ENEMY_POS, "facing": Vector2.RIGHT, "strength": 100,
			"state": Unit.State.IDLE, "tick": tick, "team": 1, "color": Color.RED},
		3: {"position": FAR_ENEMY_POS, "facing": Vector2.DOWN, "strength": 100,
			"state": Unit.State.IDLE, "tick": tick, "team": 1, "color": Color.RED},
		4: {"position": Vector2(700.0, 700.0), "facing": Vector2.ZERO, "strength": 100,
			"state": Unit.State.IDLE, "tick": tick, "team": 1, "color": Color.RED},
	}


## Drive the layer the way the engine does (in the tree, a redraw request, a frame) so
## _draw actually runs under the real draw notification -- the render-only overlay
## pattern's own coverage approach.
func test_ghost_layer_draws_lost_contacts_without_error() -> void:
	var layer: FogGhostLayer = FogGhostLayer.new()
	add_child_autofree(layer)
	layer.update(_ghost_contacts(10), {3: true}, 100)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(layer._contacts.size(), 3, "the layer holds the table it was handed")
	assert_true(layer._seen.has(3), "and the seen set that masks the visible contact")
	assert_eq(layer._tick, 100, "and the tick that dates each entry's age")
	layer.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(layer._contacts.is_empty(), "clear drops every marker")
	assert_true(layer._seen.is_empty(), "and the seen set")


func test_ghost_layer_default_footprint_is_three_by_one_and_a_half_metres() -> void:
	var layer: FogGhostLayer = autofree(FogGhostLayer.new())
	assert_almost_eq(layer.half_size.x, 1.5 * WorldScale.WU_PER_M, 0.001, "half-width across the front")
	assert_almost_eq(layer.half_size.y, 0.75 * WorldScale.WU_PER_M, 0.001, "half-depth along the facing")


func test_ghost_layer_stale_ticks_zero_returns_stale_alpha() -> void:
	var layer: FogGhostLayer = autofree(FogGhostLayer.new())
	layer.stale_ticks = 0
	assert_almost_eq(layer.alpha_for_age(10), layer.stale_alpha, 0.001,
		"zero stale_ticks immediately returns stale_alpha")


# --- HUD toggle (F7 and the Menu check item) ------------------------------------------


func _key_event(physical_keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = true
	return event


## The persisted toggle is flipped twice, so a developer's saved preference ends where it
## started even though each flip writes the settings file.
func test_f7_toggles_fog_of_war_and_the_indicator_and_the_menu_item() -> void:
	var battle: Node = _staged_battle(false)
	await wait_frames(2)
	var hud = battle.get_node("HUD")
	var before: bool = Settings.fog_of_war
	hud._unhandled_input(_key_event(KEY_F7))
	assert_eq(Settings.fog_of_war, not before, "F7 flips the setting")
	assert_eq(hud._fog_label.visible, not before, "and the indicator follows it")
	var popup: PopupMenu = hud._menu_button.get_popup()
	assert_eq(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_FOG_OF_WAR)), not before,
		"and so does the Menu check item")
	hud._on_menu_id(HUDScript.MENU_FOG_OF_WAR)
	assert_eq(Settings.fog_of_war, before, "the Menu item flips it back")
	assert_eq(hud._fog_label.visible, before, "and the indicator hides again")


func test_is_fog_toggle_keypress_only_matches_a_real_f7_key_press() -> void:
	var hud: CanvasLayer = HUDScript.new()
	add_child_autofree(hud)
	assert_true(hud._is_fog_toggle_keypress(_key_event(KEY_F7)), "a plain F7 press matches")
	assert_false(hud._is_fog_toggle_keypress(_key_event(KEY_F6)), "a different function key does not")
	var released := _key_event(KEY_F7)
	released.pressed = false
	assert_false(hud._is_fog_toggle_keypress(released), "a key-release event does not")
	var echoed := _key_event(KEY_F7)
	echoed.echo = true
	assert_false(hud._is_fog_toggle_keypress(echoed), "a held-key echo does not")


func test_hud_sync_fog_label_guards_null_label() -> void:
	var hud: CanvasLayer = autofree(HUDScript.new())
	hud._fog_label = null
	hud._sync_fog_label()
	pass_test("null _fog_label is safely guarded")


func test_selection_manager_unit_at_ignores_hidden_enemy() -> void:
	var battle: Node = _staged_battle(true)
	for _k in range(3):
		await get_tree().physics_frame
	var near := _enemy_nearest(NEAR_ENEMY_POS)
	var far := _enemy_nearest(FAR_ENEMY_POS)
	var sm = battle.get_node("SelectionManager")
	assert_not_null(sm._unit_at(near.global_position, 1, true),
		"visible enemy is resolved by _unit_at")
	assert_null(sm._unit_at(far.global_position, 1, true),
		"hidden enemy is ignored by _unit_at")


func test_sight_scale_derives_from_final_field_or_preserves_override() -> void:
	var b1: Node = load("res://scenes/Battle.tscn").instantiate()
	b1.field = Rect2(0, 0, 800, 600)
	add_child_autofree(b1)
	assert_almost_eq(b1.sight_scale, BattleScript.DEFAULT_SIGHT_SCALE_FRACTION * 600.0, 0.001,
		"sight_scale derives from non-default field short side in _ready")

	var b2: Node = load("res://scenes/Battle.tscn").instantiate()
	b2.sight_scale = 450.0
	add_child_autofree(b2)
	assert_almost_eq(b2.sight_scale, 450.0, 0.001,
		"explicit caller sight_scale override is preserved")


func test_rout_margin_stays_at_rout_margin_when_fog_is_on() -> void:
	var b1: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(b1)
	assert_almost_eq(b1.rout_margin, b1.ROUT_MARGIN, 0.001,
		"rout_margin equals ROUT_MARGIN when fog is off")
	assert_eq(b1.field_with_margin, b1.field.grow(b1.ROUT_MARGIN),
		"field_with_margin matches pre-fog baseline when fog is off")

	var prev_fog: bool = Settings.fog_of_war
	Settings.set_fog_of_war_session(true)
	var b2: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(b2)
	assert_almost_eq(b2.rout_margin, b2.ROUT_MARGIN, 0.001,
		"rout_margin remains ROUT_MARGIN when fog is on")
	assert_eq(b2.field_with_margin, b2.field.grow(b2.ROUT_MARGIN),
		"field_with_margin matches baseline when fog is on")

	var b3: Node = load("res://scenes/Battle.tscn").instantiate()
	b3.sight_scale = 450.0
	add_child_autofree(b3)
	assert_almost_eq(b3.rout_margin, b3.ROUT_MARGIN, 0.001,
		"rout_margin remains ROUT_MARGIN even with custom sight_scale")
	assert_eq(b3.field_with_margin, b3.field.grow(b3.ROUT_MARGIN),
		"field_with_margin matches baseline even with custom sight_scale")

	Settings.set_fog_of_war_session(prev_fog)


func test_ghost_layer_ghost_records_reports_only_unseen_contacts() -> void:
	var layer: FogGhostLayer = FogGhostLayer.new()
	add_child_autofree(layer)
	layer.update(_ghost_contacts(10), {3: true}, 100)
	var records: Array = layer.ghost_records()
	assert_eq(records.size(), 2, "only contacts not in seen are reported as ghosts")
	var uids: Array = [records[0]["uid"], records[1]["uid"]]
	assert_true(uids.has(2), "contact 2 is reported")
	assert_true(uids.has(4), "contact 4 is reported")
	assert_false(uids.has(3), "currently seen contact 3 is excluded")


func test_capture_and_restore_snapshot_round_trips_fog_tables_and_layer() -> void:
	var battle: Node = _staged_battle(true)
	for _k in range(3):
		await get_tree().physics_frame
	var far := _enemy_nearest(FAR_ENEMY_POS)
	assert_false(far.visible, "far enemy hidden under fog before capture")

	var snap: Dictionary = battle.capture_snapshot()
	assert_true(snap.has("fog_contacts"), "snapshot records fog contacts")
	assert_true(snap.has("fog_seen"), "snapshot records fog seen uids")
	assert_true(snap.has("fog_active"), "snapshot records fog active flag")
	assert_true(bool(snap["fog_active"]), "fog was active at capture")

	Settings.set_fog_of_war_session(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(far.visible, "switching fog off makes unit visible")

	Settings.set_fog_of_war_session(true)
	battle.restore_snapshot(snap)
	var restored_far := _enemy_nearest(FAR_ENEMY_POS)
	assert_false(restored_far.visible, "restoring snapshot reapplies fog visibility immediately")


func test_pending_all_teams_control_preserves_default_rout_margin() -> void:
	var prev_fog: bool = Settings.fog_of_war
	Settings.set_fog_of_war_session(true)
	AllTeamsControl.pending = true
	var b: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(b)
	assert_almost_eq(b.rout_margin, b.ROUT_MARGIN, 0.001,
		"rout_margin stays at ROUT_MARGIN when all_teams_control is pending")
	assert_eq(b.field_with_margin, b.field.grow(b.ROUT_MARGIN),
		"field_with_margin matches baseline when all_teams_control is pending")
	var foot: Unit = b.get_tree().get_nodes_in_group("units")[0] as Unit
	assert_eq(foot.retreat_bounds, b.field.grow(b.ROUT_MARGIN),
		"spawned unit retreat_bounds matches baseline")
	AllTeamsControl.pending = false
	Settings.set_fog_of_war_session(prev_fog)


func test_mid_battle_fog_toggle_preserves_rout_margin_and_live_units() -> void:
	var battle: Node = _staged_battle(false)
	for _k in range(3):
		await get_tree().physics_frame
	assert_almost_eq(battle.rout_margin, battle.ROUT_MARGIN, 0.001,
		"initial rout_margin is baseline when fog is off")
	var unit: Unit = battle.get_tree().get_nodes_in_group("units")[0] as Unit
	assert_eq(unit.retreat_bounds, battle.field.grow(battle.ROUT_MARGIN),
		"initial unit retreat_bounds matches baseline")

	Settings.set_fog_of_war_session(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(battle.rout_margin, battle.ROUT_MARGIN, 0.001,
		"rout_margin remains unchanged after mid-battle fog toggle on")
	assert_eq(unit.retreat_bounds, battle.field.grow(battle.ROUT_MARGIN),
		"live unit retreat_bounds remains unchanged after toggle on")

	Settings.set_fog_of_war_session(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(battle.rout_margin, battle.ROUT_MARGIN, 0.001,
		"rout_margin remains unchanged after mid-battle toggle off")
	assert_eq(unit.retreat_bounds, battle.field.grow(battle.ROUT_MARGIN),
		"live unit retreat_bounds remains unchanged after toggle off")


func test_attack_overlay_respects_fog_visibility_and_shows_last_known_ghost() -> void:
	var battle: Node = _staged_battle(true)
	for _k in range(3):
		await get_tree().physics_frame
	var sm: SelectionManager
	sm = battle.get_node("SelectionManager") as SelectionManager
	assert_not_null(sm, "selection manager exists")
	var near := _enemy_nearest(NEAR_ENEMY_POS)
	var far := _enemy_nearest(FAR_ENEMY_POS)

	assert_true(near.visible, "near enemy is visible")
	var near_pos: Vector2 = sm._attack_overlay_target_pos(near)
	assert_eq(near_pos, near.global_position, "visible target reports live position")

	assert_false(far.visible, "far enemy is not visible")
	var far_pos: Vector2 = sm._attack_overlay_target_pos(far)
	assert_false(is_finite(far_pos.x), "unseen enemy with no contact has infinite overlay position")

	assert_true(battle.fog_contacts().has(near.uid), "near enemy contact was recorded")
	var recorded_pos: Vector2 = battle.fog_contacts()[near.uid]["position"]
	near.visible = false
	near.global_position = Vector2(99, 99)
	var hidden_pos: Vector2 = sm._attack_overlay_target_pos(near)
	assert_eq(hidden_pos, recorded_pos, "hidden target reports last-known ghost position")

	near.state = Unit.State.DEAD
	var dead_pos: Vector2 = sm._attack_overlay_target_pos(near)
	assert_false(is_finite(dead_pos.x), "dead target reports infinite overlay position")


func test_attack_overlay_uses_world_space_at_non_zero_battle_offset() -> void:
	var battle: Node = _staged_battle(true)
	battle.position = Vector2(250.0, 350.0)
	for _k in range(3):
		await get_tree().physics_frame
	var sm: SelectionManager
	sm = battle.get_node("SelectionManager") as SelectionManager
	assert_not_null(sm, "selection manager exists")
	var near := _enemy_nearest(NEAR_ENEMY_POS)
	assert_true(near.visible, "near enemy is visible")
	var last_seen_global: Vector2 = near.global_position
	assert_true(battle.fog_contacts().has(near.uid), "near enemy contact was recorded")
	near.visible = false
	near.global_position = Vector2(99.0, 99.0)
	var hidden_pos: Vector2 = sm._attack_overlay_target_pos(near)
	assert_eq(hidden_pos, last_seen_global,
		"hidden target overlay position matches target global position at last-seen spot")


func test_paused_fog_toggle_refreshes_battlefield_immediately() -> void:
	var battle := _staged_battle(false)
	for _k in range(3):
		await get_tree().physics_frame
	var far := _enemy_nearest(FAR_ENEMY_POS)
	assert_true(far.visible, "far enemy visible with fog off")
	assert_eq(battle.rout_margin, battle.ROUT_MARGIN, "rout margin at default floor with fog off")

	var before: bool = Settings.fog_of_war
	get_tree().paused = true
	Settings.fog_of_war = true
	assert_false(far.visible, "toggling fog while paused immediately hides unseen enemies")
	assert_eq(battle.rout_margin, battle.ROUT_MARGIN, "rout margin remains fixed while paused")
	assert_true(battle._fog_active, "fog active flag set immediately while paused")

	Settings.fog_of_war = false
	assert_true(far.visible, "toggling fog off while paused immediately restores visibility")
	assert_eq(battle.rout_margin, battle.ROUT_MARGIN,
			"rout margin remains fixed when toggled off while paused")
	assert_false(battle._fog_active, "fog active flag cleared immediately while paused")
	get_tree().paused = false
	Settings.fog_of_war = before


func test_replay_recorded_with_fog_on_reproduces_identically_when_live_fog_is_off() -> void:
	var old_mode: int = Replay.mode
	var old_map: Dictionary = Replay.map
	var prev_fog: bool = Settings.fog_of_war

	# 1. Record a battle with fog ON.
	Settings.set_fog_of_war_session(true)
	Replay.mode = Replay.Mode.RECORD
	var battle_rec: Node = load("res://scenes/Battle.tscn").instantiate()
	battle_rec.drill_mode = true
	battle_rec.terrain = []
	battle_rec.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 120, "count": 12},
	]
	_staged_battles.append(battle_rec)
	add_child(battle_rec)
	await get_tree().physics_frame

	var u_rec: Unit = battle_rec.get_tree().get_nodes_in_group("units")[0] as Unit
	assert_not_null(u_rec, "infantry spawned in recording")
	u_rec._rout()
	u_rec._shatter()

	for _k in range(250):
		await get_tree().physics_frame

	var live_u_rec: Node = null
	for n in battle_rec.get_tree().get_nodes_in_group("routers"):
		if (n as Unit).uid == u_rec.uid:
			live_u_rec = n
			break
	assert_not_null(live_u_rec, "router is still in play at tick 250")
	var rec_pos: Vector2 = (live_u_rec as Unit).position
	var recorded_map: Dictionary = Replay.map.duplicate(true)
	assert_true(bool(recorded_map.get("fog_of_war", false)), "recording map saved fog_of_war: true")

	battle_rec.free()
	await get_tree().physics_frame

	# 2. Playback with live fog setting OFF.
	Settings.set_fog_of_war_session(false)
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.seed_value = 42
	Replay.rng.seed = Replay.seed_value
	Replay.map = recorded_map

	var battle_play: Node = load("res://scenes/Battle.tscn").instantiate()
	battle_play.drill_mode = true
	battle_play.terrain = []
	battle_play.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 120, "count": 12},
	]
	_staged_battles.append(battle_play)
	add_child(battle_play)
	await get_tree().physics_frame

	var u_play: Unit = battle_play.get_tree().get_nodes_in_group("units")[0] as Unit
	assert_not_null(u_play, "infantry spawned in playback")
	u_play._rout()
	u_play._shatter()

	for _k in range(250):
		await get_tree().physics_frame

	var live_u_play: Node = null
	for n in battle_play.get_tree().get_nodes_in_group("routers"):
		if (n as Unit).uid == u_play.uid:
			live_u_play = n
			break
	assert_not_null(live_u_play, "router is still in play at tick 250 during playback")
	var play_pos: Vector2 = (live_u_play as Unit).position
	assert_almost_eq(play_pos.x, rec_pos.x, 0.01, "playback position x matches recorded run")
	assert_almost_eq(play_pos.y, rec_pos.y, 0.01, "playback position y matches recorded run")

	battle_play.free()
	await get_tree().physics_frame
	Replay.mode = old_mode
	Replay.map = old_map
	Settings.set_fog_of_war_session(prev_fog)


func _measure_rout_escape(fog_on: bool) -> Dictionary:
	Settings.set_fog_of_war_session(fog_on)
	Replay.mode = Replay.Mode.IDLE
	Replay.seed_value = 42
	Replay.rng.seed = Replay.seed_value
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.terrain = []
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 10, "count": 12},
	]
	_staged_battles.append(battle)
	add_child(battle)
	await get_tree().physics_frame

	var unit: Unit = battle.get_tree().get_nodes_in_group("units")[0] as Unit
	assert_not_null(unit, "unit spawned")
	var unit_bounds: Rect2 = unit.retreat_bounds
	var battle_bounds: Rect2 = battle.field_with_margin
	unit._rout()
	unit._shatter()

	var escape_tick: int = -1
	for tick in range(1, 600):
		await get_tree().physics_frame
		if not is_instance_valid(unit) or unit.state == Unit.State.DEAD or not unit.is_in_group("routers"):
			escape_tick = tick
			break

	battle.free()
	await get_tree().physics_frame
	return {
		"unit_bounds": unit_bounds,
		"battle_bounds": battle_bounds,
		"escape_tick": escape_tick,
	}


func test_fog_on_and_off_have_identical_retreat_bounds_and_escape_tick() -> void:
	var prev_fog: bool = Settings.fog_of_war
	var old_mode: int = Replay.mode
	var old_map: Dictionary = Replay.map

	var res_off: Dictionary = await _measure_rout_escape(false)
	var res_on: Dictionary = await _measure_rout_escape(true)

	assert_gt(res_off["escape_tick"], 0, "router escaped in fog-off run")
	assert_gt(res_on["escape_tick"], 0, "router escaped in fog-on run")
	assert_eq(res_on["unit_bounds"], res_off["unit_bounds"],
		"unit retreat_bounds is identical between fog on and fog off")
	assert_eq(res_on["battle_bounds"], res_off["battle_bounds"],
		"battle field_with_margin is identical between fog on and fog off")
	assert_eq(res_on["escape_tick"], res_off["escape_tick"],
		"routing unit escapes at the exact same tick whether fog is on or off")

	Replay.mode = old_mode
	Replay.map = old_map
	Settings.set_fog_of_war_session(prev_fog)


func test_battle_fog_terrain_occlusion_and_screening() -> void:
	var prev_fog: bool = Settings.fog_of_war
	Settings.set_fog_of_war_session(true)
	Replay.forced_seed = 414
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 600.0, "y": 300.0},
		{"team": 1, "type": "Infantry", "x": 600.0, "y": 500.0},
		{"team": 0, "type": "Infantry", "x": 1275.0, "y": 300.0},
		{"team": 1, "type": "Infantry", "x": 1275.0, "y": 600.0},
		{"team": 0, "type": "Infantry", "x": 325.0, "y": 300.0},
		{"team": 1, "type": "Infantry", "x": 325.0, "y": 500.0},
		{"team": 1, "type": "Infantry", "x": 325.0, "y": 420.0},
	]
	_staged_battles.append(battle)
	add_child_autofree(battle)
	for _k in range(3):
		await get_tree().physics_frame

	var open_enemy := _enemy_nearest(Vector2(600.0, 500.0))
	var hill_enemy := _enemy_nearest(Vector2(1275.0, 600.0))
	var forest_screened := _enemy_nearest(Vector2(325.0, 500.0))
	var forest_close := _enemy_nearest(Vector2(325.0, 420.0))

	assert_true(open_enemy.visible, "enemy on open ground inside sight range is visible")
	assert_false(hill_enemy.visible, "enemy behind hill occluder is hidden")
	assert_false(forest_screened.visible, "enemy across forest beyond attenuated sight range is hidden")
	assert_true(forest_close.visible, "enemy across forest within attenuated sight range is visible")
	Settings.set_fog_of_war_session(prev_fog)
