extends GutTest
## DemoBitDump: the raw-bit per-tick position dump and its offline comparison.
##
## The hash stream says WHICH TICK first differs across platforms and, being a hash, can
## never say which value moved. This dump carries the bits themselves so a cross-platform
## diff names one function's output.
##
## The pin test below is load-bearing. The dump and the cheap hash must describe the same
## values, which is why both read DemoStateHash.cheap_tick_records. Pinning the hash of a
## fixed fixture guards that extracting that walk did not change what gets hashed -- a
## changed hash silently invalidates every committed stream, and nothing else in the
## suite would notice.


## A tree-registered unit with fully pinned per-soldier arrays, matching
## test_demo_state_hash.gd's fixture so the two files describe the same state.
func _make_unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 2
	add_child_autofree(u)
	u.uid = uid
	u.position = pos
	u._sim_soldier_pos = PackedVector2Array([pos + Vector2(1, 1), pos + Vector2(2, 2)])
	u._sim_soldier_facing = PackedVector2Array([Vector2.DOWN, Vector2.DOWN])
	u._sim_soldier_hp = PackedFloat32Array([1.0, 1.0])
	u._sim_prone = PackedFloat32Array([0.0, 0.0])
	u._sim_soldier_stamina = PackedFloat32Array([1.0, 1.0])
	return u


# --- the shared walk ------------------------------------------------------------

func test_records_are_in_uid_order_with_positions_and_soldiers() -> void:
	_make_unit(7, Vector2(300, 100))
	_make_unit(3, Vector2(100, 100))
	var records: Array = DemoStateHash.cheap_tick_records(get_tree())
	assert_eq(records.size(), 2, "one record per unit")
	assert_eq(int(records[0]["uid"]), 3, "records ascend by uid, not tree order")
	assert_eq(int(records[1]["uid"]), 7, "records ascend by uid, not tree order")
	assert_eq(records[0]["pos"], Vector2(100, 100), "the unit position rides along")
	assert_eq((records[0]["soldiers"] as PackedVector2Array).size(), 2,
			"the per-soldier positions ride along")


func test_far_tier_unit_records_no_soldiers() -> void:
	var u := _make_unit(1, Vector2(100, 100))
	u.tier = FormationTier.FAR
	var records: Array = DemoStateHash.cheap_tick_records(get_tree())
	assert_eq((records[0]["soldiers"] as PackedVector2Array).size(), 0,
			"a FAR-tier unit carries no soldier arrays, so its record carries none")


# --- the pin --------------------------------------------------------------------

func test_cheap_hash_byte_order_is_pinned() -> void:
	_make_unit(1, Vector2(100, 100))
	_make_unit(2, Vector2(300, 100))
	# PIN: the cheap hash of the fixture above, captured before cheap_tick_records was
	# extracted out of cheap_tick_hash. It exists so that refactor, or any later one,
	# cannot quietly change what gets hashed.
	assert_eq(DemoStateHash.cheap_tick_hash(get_tree()), "abece6bec74ef1b1b62a596b7dc1e9a8",
			"the cheap hash of the pinned fixture is unchanged")


# --- bit formatting -------------------------------------------------------------

func test_float_hex_is_raw_bits_not_text() -> void:
	# 1.0 is 0x3FF0000000000000 as a float64 and 0x3F800000 as a float32, little-endian
	# on every platform this runs on.
	assert_eq(DemoBitDump.f64_hex(1.0), "000000000000f03f", "float64 1.0 is its raw bits")
	assert_eq(DemoBitDump.f32_hex(1.0), "0000803f", "float32 1.0 is its raw bits")


func test_values_that_print_alike_still_differ_in_hex() -> void:
	# The whole reason the dump stores bits: these two render identically at any sane
	# precision, and a text dump would hide exactly the drift this exists to find.
	var a: float = 1.0
	var b: float = 1.0 + pow(2.0, -52)
	assert_eq("%.15f" % a, "%.15f" % b, "the two values print identically")
	assert_ne(DemoBitDump.f64_hex(a), DemoBitDump.f64_hex(b), "and still differ in hex")


# --- round trip -----------------------------------------------------------------

func test_format_and_parse_round_trip() -> void:
	_make_unit(1, Vector2(100, 100))
	var line: String = DemoBitDump.format_line(21, DemoStateHash.cheap_tick_records(get_tree()))
	var parsed: Array = DemoBitDump.parse_dump(line)
	assert_eq(parsed.size(), 1, "one line parses to one entry")
	assert_eq(int(parsed[0]["tick"]), 21, "the tick round-trips")
	var units: Array = parsed[0]["units"]
	assert_eq(int(units[0]["uid"]), 1, "the uid round-trips")
	assert_eq((units[0]["pos"] as Array).size(), 2, "a unit position is two hex components")
	assert_eq((units[0]["soldiers"] as Array).size(), 4,
			"two soldiers flatten to four hex components")


func test_parse_dump_skips_malformed_lines() -> void:
	var text: String = '{"tick": 1, "units": []}\nnot json\n{"tick": 2}\n{"tick": 3, "units": []}'
	var parsed: Array = DemoBitDump.parse_dump(text)
	assert_eq(parsed.size(), 2, "unparseable and shape-less lines are skipped, not fatal")


# --- comparison -----------------------------------------------------------------

func _entry(tick: int, uid: int, pos_hex: Array, soldiers: Array) -> Dictionary:
	return {"tick": tick, "units": [{"uid": uid, "pos": pos_hex, "soldiers": soldiers}]}


func test_identical_dumps_do_not_diverge() -> void:
	var e := _entry(21, 0, ["aa", "bb"], ["cc", "dd"])
	var out: Dictionary = DemoBitDump.compare_dumps([e], [e])
	assert_false(out["divergent"], "identical dumps do not diverge")
	assert_eq(int(out["compared"]), 1, "and report what was compared")


func test_reports_the_first_differing_soldier_component() -> void:
	var a := _entry(21, 4, ["aa", "bb"], ["cc", "dd", "ee", "ff"])
	var b := _entry(21, 4, ["aa", "bb"], ["cc", "dd", "ee", "00"])
	var out: Dictionary = DemoBitDump.compare_dumps([a], [b])
	assert_true(out["divergent"], "a differing soldier component diverges")
	assert_eq(out["field"], "soldier[1].y", "and is named by soldier index and axis")
	assert_eq(int(out["uid"]), 4, "and by the unit it belongs to")


func test_unit_position_is_reported_before_soldiers() -> void:
	var a := _entry(21, 0, ["aa", "bb"], ["cc"])
	var b := _entry(21, 0, ["aa", "99"], ["zz"])
	var out: Dictionary = DemoBitDump.compare_dumps([a], [b])
	assert_eq(out["field"], "pos.y",
			"the unit position is checked before the soldier array, so the outermost "
			+ "difference is the one reported")


func test_a_unit_present_on_only_one_side_is_a_difference() -> void:
	var a := _entry(21, 0, ["aa", "bb"], [])
	var b: Dictionary = {"tick": 21, "units": []}
	var out: Dictionary = DemoBitDump.compare_dumps([a], [b])
	assert_true(out["divergent"], "a unit missing on one side is a divergence, not a skip")
	assert_eq(out["field"], "unit", "and is named as a structural one")


func test_only_common_ticks_are_compared() -> void:
	var a := _entry(21, 0, ["aa", "bb"], [])
	var b := _entry(22, 0, ["zz", "zz"], [])
	var out: Dictionary = DemoBitDump.compare_dumps([a], [b])
	assert_false(out["divergent"], "ticks present on only one side are not a divergence")
	assert_eq(int(out["only_a"]), 1, "but are counted")
	assert_eq(int(out["only_b"]), 1, "on both sides")


# --- ulp distance ---------------------------------------------------------------

func test_adjacent_float32_values_are_one_ulp_apart() -> void:
	var a: String = DemoBitDump.f32_hex(1.0)
	# 0x3F800001 is the next representable float32 above 1.0.
	var b: String = "0100803f"
	assert_eq(DemoBitDump.ulps_between(a, b), 1,
			"one representable step reads as one ulp, which is what names a rounding "
			+ "difference rather than a different code path")


func test_ulps_is_null_across_a_sign_change() -> void:
	assert_null(DemoBitDump.ulps_between(DemoBitDump.f32_hex(1.0), DemoBitDump.f32_hex(-1.0)),
			"IEEE754 is sign-magnitude, so a raw subtraction across zero would report a "
			+ "huge distance that means nothing -- null says so instead")


func test_ulps_is_null_for_mismatched_widths_and_bad_input() -> void:
	assert_null(DemoBitDump.ulps_between("0000803f", "000000000000f03f"),
			"a float32 and a float64 pattern are not comparable")
	assert_null(DemoBitDump.ulps_between("zzzz", "0000"), "non-hex input reports null")
	assert_null(DemoBitDump.ulps_between("abc", "def"), "an odd-length pattern reports null")
