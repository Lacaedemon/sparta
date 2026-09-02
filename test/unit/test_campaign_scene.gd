extends GutTest
## Smoke test for the campaign scene: instantiates Campaign.tscn so _ready,
## the CampaignMap/CampaignHUD signal wiring, and a click→move→end-turn round all run
## without error. Complements test_campaign_state.gd (which covers the rules in
## isolation) by exercising the Node/scene layer.

const CampaignScene = preload("res://scenes/Campaign.tscn")
const CampaignLoader = preload("res://scripts/campaign/CampaignLoader.gd")
const Campaigns = preload("res://scripts/campaign/Campaigns.gd")
const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")


# CampaignBattle is a process-wide static holder; clear it around every test so a
# campaign-launched battle set up in one test can't leak into another's scene
# load (where _ready would try to resume from it).
func before_each() -> void:
	CampaignBattle.clear()


func after_each() -> void:
	CampaignBattle.clear()


# A point guaranteed inside the polygon: the centroid of one triangle from its
# triangulation lies within that triangle, hence within the polygon. (The vertex
# average can fall outside a concave polygon.)
func _interior_point(poly: PackedVector2Array) -> Vector2:
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.size() >= 3:
		return (poly[tris[0]] + poly[tris[1]] + poly[tris[2]]) / 3.0
	var sum := Vector2.ZERO   # degenerate fallback
	for v in poly:
		sum += v
	return sum / poly.size()


# province id -> a point guaranteed inside its polygon.
func _centroids() -> Dictionary:
	var out := {}
	for p in CampaignLoader.load_map(Campaigns.DEFAULT_PATH)["provinces"]:
		out[int(p["id"])] = _interior_point(p["polygon"])
	return out


func _scene() -> Node:
	var s := CampaignScene.instantiate()
	add_child_autofree(s)   # runs _ready on CampaignMap + CampaignHUD
	# CampaignMap builds its state synchronously but defers the first HUD refresh
	# (its _ready runs before the sibling HUD's); let that deferred call run first.
	await get_tree().process_frame
	return s


func test_scene_comes_up() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_not_null(map._state, "campaign state is built on _ready")
	assert_eq(map._state.provinces.size(), 9, "the Gallic War map has 9 provinces")
	assert_eq(map._state.current_faction, 0, "Rome (player) moves first")
	assert_eq(map._selected, -1, "nothing selected initially")


func test_click_selects_then_orders() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var c := _centroids()

	# Use quick-resolve so a contested attack resolves on the map instead of launching
	# the tactical battle — this test exercises the move/attack order path.
	map._auto_resolve = true

	# Click a Roman, manned province (Narbonensis = id 0) -> it becomes selected.
	map._on_click(c[0])
	assert_eq(map._selected, 0, "clicking your own army selects it")

	# Click adjacent Gallic Helvetia (id 6) -> issues a move/attack, clears selection.
	var before_owner: int = map._state.owner_of(6)
	map._on_click(c[6])
	assert_eq(map._selected, -1, "issuing an order clears the selection")
	assert_eq(map._state.army_of(0), 0, "the ordered army left its origin")
	# Either it was taken (owner flips) or the assault failed (still Gallic) — both fine,
	# we only assert the order resolved without error and consumed the army.
	assert_true(map._state.owner_of(6) == 0 or map._state.owner_of(6) == before_owner,
			"the order resolved to a valid outcome")


func test_falls_back_to_default_when_selected_missing() -> void:
	# An unreadable selected campaign must fall back to the default, not crash.
	Campaigns.selected_path = "res://data/campaigns/__does_not_exist__.json"
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_eq(map._state.provinces.size(), 9, "fell back to the default Gallic War map")
	Campaigns.selected_path = Campaigns.DEFAULT_PATH   # restore for other tests


func test_restart_re_enables_end_turn() -> void:
	# Regression: show_victory disables End Turn; restarting must re-enable it and
	# clear the end overlay, or "New Campaign" leaves an unplayable board.
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var hud := s.get_node("CampaignHUD")
	hud.show_victory("test")
	assert_true(hud._end_turn_button.disabled, "End Turn is disabled at game over")
	map._restart()
	assert_false(hud._end_turn_button.disabled, "restarting re-enables End Turn")
	assert_false(hud._overlay.visible, "and hides the end overlay")


func test_diplomacy_toggle_declares_and_makes_peace() -> void:
	# The Germanic tribes (faction 2) start neutral; the HUD toggle declares war and
	# then sues for peace, and the change is reflected in the rules immediately.
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_false(map._state.at_war(0, 2), "Germanic tribes start at peace with Rome")
	map._on_diplomacy_toggled(2)
	assert_true(map._state.at_war(0, 2), "toggling at peace declares war")
	map._on_diplomacy_toggled(2)
	assert_false(map._state.at_war(0, 2), "toggling again sues for peace")


func test_player_sue_for_peace_imposes_truce() -> void:
	# the player's "Sue for Peace" toggle carries a truce, so the truce rules/UI
	# are reachable in normal play (not only via map-seeded peace).
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_true(map._state.at_war(0, 1), "Rome starts at war with the Gauls")
	map._on_diplomacy_toggled(1)
	assert_false(map._state.at_war(0, 1), "the toggle sues for peace")
	assert_gt(map._state.truce_remaining(0, 1), 0, "...and that peace carries a truce")


func test_truce_blocks_player_declare_war_toggle() -> void:
	# with an active truce, the HUD toggle can't re-declare war until it expires.
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	# Germanic tribes (faction 2) start at peace with Rome; seed a truce on the pair.
	map._state.make_peace(0, 2, 3)
	map._on_diplomacy_toggled(2)
	assert_false(map._state.at_war(0, 2), "the truce blocks declaring war via the toggle")


func test_end_turn_runs_enemy_and_returns_to_player() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	map._on_end_turn()
	# Unless the AI somehow won outright (it can't from the start position), play
	# returns to Rome and the turn counter advances.
	if map._state.winner() == -1:
		assert_eq(map._state.current_faction, 0, "play returns to the player")
		assert_eq(map._state.turn, 2, "a full round advances the turn")


func test_contested_attack_launches_battle_not_auto_resolve() -> void:
	# With auto-resolve off (the default), attacking a defended enemy province captures
	# the clash into CampaignBattle for the tactical battle instead of resolving it.
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	# Narbonensis (0, Rome, army 5) -> Helvetia (6, Gauls, army 4): a real contested fight.
	assert_true(map._is_contested(0, 6), "precondition: Helvetia is a defended enemy province")
	# _capture_clash is the testable half of _launch_tactical_battle (which also swaps
	# scenes); it fills the holder the battle scene reads.
	map._capture_clash(0, 6)
	assert_true(CampaignBattle.active, "a battle is now in flight")
	assert_eq(int(CampaignBattle.pending["from"]), 0)
	assert_eq(int(CampaignBattle.pending["to"]), 6)
	# Read expected strengths from the live state, not hardcoded map values, so a map
	# rebalance doesn't fail this with a misleading "capture is wrong" message.
	assert_eq(int(CampaignBattle.pending["attacker_strength"]), map._state.army_of(0),
			"attacker strength captured")
	assert_eq(int(CampaignBattle.pending["defender_strength"]), map._state.army_of(6),
			"defender strength captured")
	assert_false(CampaignBattle.snapshot.is_empty(), "the pre-battle state is snapshotted")


func test_resume_applies_won_battle_result() -> void:
	# Simulate returning from a battle the attacker won and confirm the map applies the
	# outcome (province captured with the reported survivors) and clears the holder.
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_true(map._state.can_move(0, 6), "precondition: a legal contested attack")
	CampaignBattle.active = true
	CampaignBattle.snapshot = map._state.snapshot()
	CampaignBattle.pending = {
		"from": 0, "to": 6,
		"attacker_strength": map._state.army_of(0),
		"defender_strength": map._state.army_of(6),
	}
	CampaignBattle.result = {"attacker_won": true, "survivors": 2}
	map._finish_battle_resume()
	assert_eq(map._state.owner_of(6), 0, "a won battle captures the province")
	assert_eq(map._state.army_of(6), 2, "with the battle's surviving strength")
	assert_eq(map._state.army_of(0), 0, "the attacking army left its origin")
	assert_true(CampaignBattle.result.is_empty(), "the holder is cleared after applying")


# --- campaign clock wiring -------------------------------------------------

func test_clock_starts_paused_and_reads_day_one() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var hud := s.get_node("CampaignHUD")
	assert_true(map._clock.is_paused(), "a freshly opened campaign waits for the player")
	assert_eq(map._clock.tick(), 0, "no campaign time has passed")
	assert_string_contains(hud._clock_label.text, "Day 1, 00:00", "the HUD shows the date")
	assert_string_contains(hud._clock_label.text, "paused", "and says time is stopped")
	assert_eq(hud._pause_button.text, "Resume", "the button offers to start time")


func test_hud_buttons_drive_pause_and_speed() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var hud := s.get_node("CampaignHUD")
	map._on_pause_pressed()
	assert_false(map._clock.is_paused(), "the pause button resumes a stopped clock")
	assert_eq(hud._pause_button.text, "Pause", "and the button now offers to stop it")
	map._on_speed_pressed()
	assert_eq(map._clock.speed(), 2.0, "the speed button steps up the ladder")
	assert_eq(hud._speed_button.text, "Speed 2x", "and the label follows")
	map._on_pause_pressed()
	assert_true(map._clock.is_paused(), "pressing pause again stops time")


func test_space_and_number_keys_control_time() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_true(map._on_clock_key(KEY_SPACE), "space is a time control")
	assert_false(map._clock.is_paused(), "space resumes a paused clock")
	assert_true(map._on_clock_key(KEY_3), "the number row is a time control")
	assert_eq(map._clock.speed(), 4.0, "the third rung of the ladder")
	map._on_clock_key(KEY_SPACE)
	assert_true(map._clock.is_paused(), "space pauses a running clock")
	assert_true(map._on_clock_key(KEY_2), "picking a speed while paused")
	assert_false(map._clock.is_paused(), "...also resumes time")
	assert_false(map._on_clock_key(KEY_K), "an unrelated key is not a time control")


func test_process_advances_the_clock_only_while_running() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var hud := s.get_node("CampaignHUD")
	map._process(1.0)
	assert_eq(map._clock.tick(), 0, "a paused clock ignores elapsed time")
	map._on_pause_pressed()
	map._process(1.0)
	assert_gt(map._clock.tick(), 0, "a running clock advances")
	assert_string_contains(hud._clock_label.text, "Day 1", "and pushes the new date")


func test_process_stops_the_clock_when_the_campaign_is_won() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	map._on_pause_pressed()
	# Hand every province to Rome, which is the victory condition.
	for id in map._state.provinces:
		map._state.provinces[id]["owner"] = 0
	map._process(1.0)
	assert_true(map._clock.is_paused(), "time stops for a decided campaign")


func test_move_announces_its_ground_distance() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	var hud := s.get_node("CampaignHUD")
	var c := _centroids()
	# Narbonensis (0) reinforcing Cisalpina (5): both Roman, so no battle launches.
	map._on_click(c[0])
	map._on_click(c[5])
	assert_string_contains(hud._flash_label.text, "Reinforced", "the move resolved")
	assert_string_contains(hud._flash_label.text, "km march", "and reported its distance")


func test_march_label_declines_an_unknown_province() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	assert_eq(map._march_label(0, 999), "", "no distance to a province that does not exist")
	assert_ne(map._march_label(0, 5), "", "but a real pair measures")


func test_clock_freezes_across_a_tactical_battle() -> void:
	var s = await _scene()
	var map := s.get_node("CampaignMap")
	map._on_pause_pressed()
	map._process(4.0)
	var launched_at: int = map._clock.tick()
	assert_gt(launched_at, 0, "precondition: time has passed before the clash")
	map._capture_clash(0, 6)
	assert_eq(CampaignBattle.campaign_tick, launched_at, "the tick rides the scene swap")

	# A second scene stands in for the post-battle reload, which rebuilds from scratch.
	CampaignBattle.result = {"attacker_won": true, "survivors": 2}
	var returned = await _scene()
	var resumed := returned.get_node("CampaignMap")
	assert_eq(resumed._clock.tick(), launched_at, "the campaign resumes where it stopped")
	assert_true(resumed._clock.is_paused(), "and hands the world back to the player")
