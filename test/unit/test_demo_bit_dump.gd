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
	assert_eq((units[0]["pos"] as Array)[0].length(), 8,
			"a unit position is dumped at float32, its true width")
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
	assert_null(DemoBitDump.ulps_between("zzzzzzzz", "00000000"), "non-hex input reports null")
	assert_null(DemoBitDump.ulps_between("abc", "def"), "an odd-length pattern reports null")


func test_adjacent_float64_values_are_one_ulp_apart() -> void:
	# The unit position is float64 and is checked before the soldier array, so it is
	# usually the FIRST field reported -- an earlier version capped the parser below 64
	# bits, which made the distance null for exactly that case.
	var a: String = DemoBitDump.f64_hex(1.0)
	var b: String = DemoBitDump.f64_hex(1.0 + pow(2.0, -52))
	assert_eq(DemoBitDump.ulps_between(a, b), 1,
			"one representable float64 step reads as one ulp")


func test_a_signed_hex_byte_is_not_read_as_agreement() -> void:
	# String.is_valid_hex_number() accepts a leading sign, so the byte pair "-0" would
	# parse to 0 and read as identical to a real "00" -- a corrupted dump byte reported
	# as agreement, which is the one answer this must never give.
	assert_null(DemoBitDump.ulps_between("0000-000", "00000000"),
			"a byte pair carrying a sign is unparseable, not zero")


func test_uppercase_hex_is_accepted() -> void:
	assert_eq(DemoBitDump.ulps_between("0000803F", "0000803f"), 0,
			"case does not change a raw byte's value")


# --- ordering and round trip ----------------------------------------------------

func test_a_missing_low_uid_outranks_a_high_uid_field_difference() -> void:
	# Walking side a's own order would report uid 5's position first and never look at
	# uid 2, though the missing unit is both lower-numbered and the more informative
	# difference.
	var a: Dictionary = {"tick": 21, "units": [
		{"uid": 5, "pos": ["aa", "bb"], "soldiers": []}]}
	var b: Dictionary = {"tick": 21, "units": [
		{"uid": 2, "pos": ["cc", "dd"], "soldiers": []},
		{"uid": 5, "pos": ["aa", "99"], "soldiers": []}]}
	var out: Dictionary = DemoBitDump.compare_dumps([a], [b])
	assert_eq(int(out["uid"]), 2, "the lower uid is reported first")
	assert_eq(out["field"], "unit", "and as the structural difference it is")


func test_compare_works_on_genuinely_json_round_tripped_entries() -> void:
	# The hand-built entries elsewhere in this file never exercise JSON's number typing:
	# a parsed tick or uid comes back as a float, and the production code leans on int()
	# casts to cope. Piping through parse_dump is what actually pins that.
	_make_unit(1, Vector2(100, 100))
	var line_a: String = DemoBitDump.format_line(21, DemoStateHash.cheap_tick_records(get_tree()))
	var parsed_a: Array = DemoBitDump.parse_dump(line_a)
	assert_false(DemoBitDump.compare_dumps(parsed_a, parsed_a)["divergent"],
			"a parsed dump does not diverge from itself")
	# Nudge one soldier by the smallest float32 step and confirm the parsed comparison
	# still localizes it.
	var records: Array = DemoStateHash.cheap_tick_records(get_tree())
	var soldiers: PackedVector2Array = records[0]["soldiers"]
	soldiers[0] = Vector2(soldiers[0].x + 0.001, soldiers[0].y)
	records[0]["soldiers"] = soldiers
	var parsed_b: Array = DemoBitDump.parse_dump(DemoBitDump.format_line(21, records))
	var out: Dictionary = DemoBitDump.compare_dumps(parsed_a, parsed_b)
	assert_true(out["divergent"], "a nudged soldier diverges through the JSON round trip")
	assert_eq(out["field"], "soldier[0].x", "and is still named by index and axis")
	assert_eq(int(out["uid"]), 1, "and by uid, despite JSON returning it as a float")


# --- the FAR-tier regression ----------------------------------------------------

func test_a_far_tier_unit_hashes_without_pushing_an_engine_error() -> void:
	# HashingContext.update() REJECTS a zero-length array and pushes an engine error,
	# which GUT surfaces as a failure. A FAR-tier unit is the one whose record carries no
	# soldiers, so the shared walk has to skip the call rather than pass an empty array.
	var u := _make_unit(1, Vector2(100, 100))
	u.tier = FormationTier.FAR
	var before: String = DemoStateHash.cheap_tick_hash(get_tree())
	assert_eq(before.length(), 32, "a FAR-tier unit still hashes to a full md5 digest")
	assert_eq(DemoStateHash.cheap_tick_hash(get_tree()), before,
			"and does so repeatably")


func test_adjacent_unit_positions_are_one_ulp_apart_end_to_end() -> void:
	# The whole point of dumping positions at float32: two units one representable step
	# apart must read as ONE step, not as the ~2^29 a float64 comparison of the same two
	# widened values would report -- which this file elsewhere tells a reader means a
	# different code path was taken.
	var a := _make_unit(1, Vector2(1.5, 3.0))
	var dump_a: Array = DemoBitDump.parse_dump(
			DemoBitDump.format_line(21, DemoStateHash.cheap_tick_records(get_tree())))
	var stepped: float = PackedFloat32Array([1.5]).to_byte_array().decode_float(0)
	var bits: int = PackedFloat32Array([stepped]).to_byte_array().decode_u32(0) + 1
	var nudged := PackedByteArray()
	nudged.resize(4)
	nudged.encode_u32(0, bits)
	a.position = Vector2(nudged.decode_float(0), 3.0)
	var dump_b: Array = DemoBitDump.parse_dump(
			DemoBitDump.format_line(21, DemoStateHash.cheap_tick_records(get_tree())))
	var out: Dictionary = DemoBitDump.compare_dumps(dump_a, dump_b)
	assert_true(out["divergent"], "one float32 step in a unit position is a divergence")
	assert_eq(out["field"], "pos.x", "and is named as the unit position")
	assert_eq(out["ulps"], 1, "and reads as ONE representable step, not as 2^29")
