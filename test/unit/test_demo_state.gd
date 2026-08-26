extends GutTest
## Pure serialization for the scripted-input demo state-dump path (tools/demo/DemoState.gd).
## The enum-name mapping and the per-soldier summary are functions of their arguments only —
## no recorder/battle instance — so they're directly unit-testable like DemoFrames. The live
## dump (walking the units, writing JSON) reads a running battle and is verified by dumping a
## demo, not headlessly here.


# --- enum name mapping -----------------------------------------------------

func test_state_name_maps_each_enum_member() -> void:
	assert_eq(DemoState.state_name(0), "IDLE")
	assert_eq(DemoState.state_name(1), "MOVING")
	assert_eq(DemoState.state_name(2), "FIGHTING")
	assert_eq(DemoState.state_name(3), "ROUTING")
	assert_eq(DemoState.state_name(4), "DEAD")


func test_state_name_unknown_int_is_visible_token() -> void:
	assert_eq(DemoState.state_name(9), "STATE(9)",
		"an out-of-range state surfaces as a greppable token, not a dropped field")


func test_formation_name_maps_each_member() -> void:
	assert_eq(DemoState.formation_name(0), "NORMAL")
	assert_eq(DemoState.formation_name(1), "TIGHT")
	assert_eq(DemoState.formation_name(2), "LOOSE")
	assert_eq(DemoState.formation_name(3), "SQUARE")
	assert_eq(DemoState.formation_name(4), "SHIELD_WALL")
	assert_eq(DemoState.formation_name(5), "TESTUDO")
	assert_eq(DemoState.formation_name(6), "SCHILTRON")


func test_formation_name_unknown_int_is_visible_token() -> void:
	# 9999, not a small int: a value the mode enum could plausibly grow into
	# would make this test fail the day that mode is legitimately added.
	assert_eq(DemoState.formation_name(9999), "FORMATION(9999)")


## test_formation_name_maps_each_member above pins today's members by hand, and it
## stays deliberately: scenario JSON (demos/inputs/*.json) stores the raw int, so
## the VALUE assignments are an external interface that test protects against
## renumbering. What it cannot catch is an eighth stance added to Unit.gd and left
## out of FORMATION_NAMES -- the new mode would serialize as the FORMATION(7)
## fallback in every transcript, silently, and a by-hand list is exactly what
## already left two skills and this table's own docstring a mode behind. So this
## test derives the mode set from Unit.gd's int-valued FORMATION_* consts instead
## of restating it. The int filter selects the modes exactly today (the other
## FORMATION_* consts -- SPACING, ASPECT, the two CONTAINMENT_SCALEs -- are
## floats). A future non-mode int const named FORMATION_* (a FORMATION_COUNT, say)
## would fail this test loudly the moment it lands; that is the intended
## direction -- rename it or teach the filter, in the open rather than silently.
func test_formation_names_cover_every_unit_formation_const() -> void:
	# Loaded into a Script-typed local rather than used via the preloaded const:
	# GDScript resolves `preload`ed script with a class_name as the TYPE Unit, and
	# refuses a non-static call on a type ("Make an instance instead").
	var unit_script: Script = load("res://scripts/Unit.gd")
	var consts: Dictionary = unit_script.get_script_constant_map()
	var modes: Array = []
	for key in consts:
		var const_name := String(key)
		if const_name.begins_with("FORMATION_") and typeof(consts[key]) == TYPE_INT:
			modes.append(const_name)
	# Negative control: an empty or shrunken derivation would pass the loop below
	# vacuously. Seven modes exist today; a genuine future removal updates this
	# floor alongside the by-hand test above.
	assert_gt(modes.size(), 6,
		"derived %d FORMATION_* int consts from Unit.gd, expected all 7 modes -- the filter or a refactor broke the derivation, not the table" % modes.size())
	for const_name in modes:
		var mode_value: int = consts[const_name]
		var mode_name: String = DemoState.formation_name(mode_value)
		# Equality against the const's own suffix, not merely "not the fallback":
		# a copy-pasted wrong name (6: "TESTUDO") or an empty string would sail
		# past a fallback-only check while corrupting every transcript.
		assert_eq(mode_name, String(const_name).trim_prefix("FORMATION_"),
			"Unit.%s = %d must serialize as its own name; %d modes examined"
				% [const_name, mode_value, modes.size()])


func test_order_mode_name_uses_supplied_table() -> void:
	var names := {0: "Normal", 1: "Hold"}
	assert_eq(DemoState.order_mode_name(names, 1), "Hold")


func test_order_mode_name_unknown_int_is_visible_token() -> void:
	assert_eq(DemoState.order_mode_name({0: "Normal"}, 5), "MODE(5)")


# --- combat groups / record ordering ----------------------------------------

func test_combat_groups_union_units_and_routers() -> void:
	assert_eq(DemoState.COMBAT_GROUPS, ["units", "routers"],
		"the snapshot walks the same union Battle._team_in_play scans; dropping 'routers' "
		+ "makes a ROUTING unit vanish from the transcript mid-rout")


func test_sort_records_by_uid_orders_and_returns_the_array() -> void:
	var records: Array = [{"uid": 3}, {"uid": 0}, {"uid": 2}]
	var out: Array = DemoState.sort_records_by_uid(records)
	assert_eq(out[0]["uid"], 0)
	assert_eq(out[1]["uid"], 2)
	assert_eq(out[2]["uid"], 3)
	assert_same(out, records, "sorts in place and returns the same array")


# --- rounding / vector formatting ------------------------------------------

func test_round_to_default_two_places() -> void:
	assert_almost_eq(DemoState.round_to(1.23456), 1.23, 0.0001)


func test_round_to_one_place() -> void:
	assert_almost_eq(DemoState.round_to(25.34, 1), 25.3, 0.0001)


func test_vec2_pair_rounds_both_components() -> void:
	var pair: Array = DemoState.vec2_pair(Vector2(1.23456, -7.891))
	assert_eq(pair.size(), 2)
	assert_almost_eq(pair[0], 1.23, 0.0001)
	assert_almost_eq(pair[1], -7.89, 0.0001)


# --- per-soldier summary ---------------------------------------------------

func test_soldier_summary_empty_is_zeroed() -> void:
	var s: Dictionary = DemoState.soldier_summary(PackedVector2Array(), PackedFloat32Array())
	assert_eq(s["count"], 0)
	assert_eq(s["centroid"], [0.0, 0.0])
	assert_eq(s["bbox"], [0.0, 0.0])
	assert_eq(s["prone_count"], 0, "a routed/empty unit still serializes without error")
	assert_eq(s["broken_count"], 0)


func test_soldier_summary_centroid_and_bbox() -> void:
	# A 10x4 box: corners at (0,0),(10,0),(0,4),(10,4). Centroid (5,2); bbox 10 wide, 4 tall.
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(0, 4), Vector2(10, 4)])
	var s: Dictionary = DemoState.soldier_summary(pos, PackedFloat32Array())
	assert_eq(s["count"], 4)
	assert_almost_eq(s["centroid"][0], 5.0, 0.0001)
	assert_almost_eq(s["centroid"][1], 2.0, 0.0001)
	assert_almost_eq(s["bbox"][0], 10.0, 0.0001)
	assert_almost_eq(s["bbox"][1], 4.0, 0.0001)


func test_soldier_summary_counts_prone() -> void:
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	# prone > 0 means down: index 0 and 2 prone, index 1 standing.
	var prone := PackedFloat32Array([0.5, 0.0, 1.2])
	var s: Dictionary = DemoState.soldier_summary(pos, prone)
	assert_eq(s["prone_count"], 2, "counts soldiers with a nonzero prone timer")


func test_soldier_summary_shorter_prone_array_is_safe() -> void:
	# A prone array shorter than the positions (index-aligned but truncated) must not overrun.
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	var prone := PackedFloat32Array([1.0])   # only index 0
	var s: Dictionary = DemoState.soldier_summary(pos, prone)
	assert_eq(s["count"], 3)
	assert_eq(s["prone_count"], 1, "missing prone entries treated as standing, no out-of-range read")


func test_soldier_summary_defaults_broken_count_to_zero_when_omitted() -> void:
	# Every pre-existing 2-argument call site keeps reading broken_count as 0.
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(1, 0)])
	var s: Dictionary = DemoState.soldier_summary(pos, PackedFloat32Array())
	assert_eq(s["broken_count"], 0)


func test_soldier_summary_counts_broken() -> void:
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	var broken := PackedByteArray([1, 0, 1])
	var s: Dictionary = DemoState.soldier_summary(pos, PackedFloat32Array(), broken)
	assert_eq(s["broken_count"], 2, "counts soldiers individually broken from their stance")


func test_soldier_summary_shorter_broken_array_is_safe() -> void:
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	var broken := PackedByteArray([1])   # only index 0
	var s: Dictionary = DemoState.soldier_summary(pos, PackedFloat32Array(), broken)
	assert_eq(s["count"], 3)
	assert_eq(s["broken_count"], 1, "missing broken entries treated as holding formation, no out-of-range read")


func test_metric_mirrors_convert_via_the_world_scale() -> void:
	assert_eq(DemoState.vec2_pair_m(Vector2(500.0, 380.0), 20.0), [25.0, 19.0])
	assert_eq(DemoState.mps(170.0, 20.0, 1.0), 8.5)
	assert_eq(DemoState.mps(170.0, 20.0, 2.0), 4.25,
		"speed_scale mirrors the loadout conversion, so the figure reads back as declared m/s")


func test_metric_soldier_summary_derives_from_the_same_positions() -> void:
	var pos := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 40)])
	var m: Dictionary = DemoState.soldier_summary_m(pos, 20.0)
	assert_eq(m["bbox_m"], [1.0, 2.0])
	assert_eq(m["centroid_m"], [0.667, 0.667])


func test_metric_soldier_summary_zeroes_for_an_empty_body_list() -> void:
	var m: Dictionary = DemoState.soldier_summary_m(PackedVector2Array(), 20.0)
	assert_eq(m["centroid_m"], [0.0, 0.0])
	assert_eq(m["bbox_m"], [0.0, 0.0])


func test_motion_ref_reports_both_grid_pitches_and_their_min() -> void:
	# The analyzer derives its blob/misslot thresholds from formation_spacing, which
	# must be the TIGHTER of the two axes so an anisotropic grid (cavalry's deep
	# ranks) keeps the thresholds conservative rather than triple-wide.
	var u: Unit = Unit.new()
	autofree(u)
	u.file_pitch = 20.0
	u.rank_pitch = 60.0
	var ref: Dictionary = DemoState.motion_ref(u)
	assert_eq(float(ref["file_pitch"]), 20.0, "file pitch dumped as-is")
	assert_eq(float(ref["rank_pitch"]), 60.0, "rank pitch dumped as-is")
	assert_eq(float(ref["formation_spacing"]), 20.0,
			"the threshold base is the tighter axis")


func test_unit_record_dumps_pitches_at_top_level() -> void:
	var u: Unit = Unit.new()
	add_child_autofree(u)
	u.file_pitch = 20.0
	u.rank_pitch = 60.0
	var rec: Dictionary = DemoState.unit_record(u, {}, 1.0, false)
	assert_eq(float(rec["file_pitch"]), 20.0, "HUD checks can read file pitch without FULL")
	assert_eq(float(rec["rank_pitch"]), 60.0, "and rank pitch for the anisotropic label")
	assert_eq(str(rec["formation_label"]), "1 x 3 m",
			"dumped caption matches the HUD so the analyzer need not load Unit")


func test_build_snapshot_captures_hud_when_present() -> void:
	var hud = preload("res://scripts/HUD.gd").new()
	add_child_autofree(hud)
	var snap: Dictionary = DemoState.build_snapshot(get_tree(), 15, {}, 1.0, false)
	assert_eq(snap["tick"], 15)
	assert_true(snap.has("hud"), "snapshot includes hud block when HUD is in scene tree")
	assert_eq(snap["hud"]["info_text"], "No unit selected")
	assert_null(snap["hud"]["shown_unit_uid"])

