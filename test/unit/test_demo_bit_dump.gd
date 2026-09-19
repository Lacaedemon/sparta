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


func test_float32_ulps_are_exact_across_a_sign_change() -> void:
	# Refusing across a sign would drop the diagnostic for every negative coordinate, so
	# float32 patterns are reordered rather than rejected. Built from raw bit patterns
	# rather than from literals: this build does not preserve negative zero (measured --
	# -0.0, 0.0 * -1.0 and 0.0 all encode to 00000000), so a hand-written -0.0 would not
	# produce the sign-crossing pair this is about.
	var smallest_negative := PackedByteArray()
	smallest_negative.resize(4)
	smallest_negative.encode_u32(0, 0x80000001)   # the float32 just below -0.0
	var smallest_positive := PackedByteArray()
	smallest_positive.resize(4)
	smallest_positive.encode_u32(0, 0x00000001)   # the float32 just above +0.0
	var neg_hex: String = DemoBitDump.f32_hex(smallest_negative.decode_float(0))
	var pos_hex: String = DemoBitDump.f32_hex(smallest_positive.decode_float(0))
	assert_ne(neg_hex, pos_hex, "the two denormals sit on opposite sides of zero")
	# Three steps, not two: the run through zero is -denormal, -0.0, +0.0, +denormal,
	# and both zeros are their own representable values.
	assert_eq(DemoBitDump.ulps_between(neg_hex, pos_hex), 3,
			"they are three representable steps apart THROUGH zero, which a raw "
			+ "subtraction would have reported as roughly 2^31")


func test_adjacent_negative_float32_values_are_one_ulp_apart() -> void:
	# A same-sign negative pair: the sign contributes an identical offset to both
	# patterns, so nulling here would have discarded the figure for half the number line.
	var a_bits: int = PackedFloat32Array([-1.5]).to_byte_array().decode_u32(0)
	var nudged := PackedByteArray()
	nudged.resize(4)
	nudged.encode_u32(0, a_bits + 1)
	assert_eq(DemoBitDump.ulps_between(DemoBitDump.f32_hex(-1.5),
			DemoBitDump.f32_hex(nudged.decode_float(0))), 1,
			"two adjacent negative float32 values are one step apart")


func test_float64_still_refuses_across_a_sign_change() -> void:
	# float64's ordered key needs a full 64 unsigned bits, which a GDScript int cannot
	# hold, so the narrower same-sign rule stands for that width.
	assert_null(DemoBitDump.ulps_between(DemoBitDump.f64_hex(1.0), DemoBitDump.f64_hex(-1.0)),
			"a float64 pair across zero reports null rather than a wrapped number")
	assert_eq(DemoBitDump.ulps_between(DemoBitDump.f64_hex(-1.5),
			DemoBitDump.f64_hex(-1.5 - pow(2.0, -52))), 1,
			"but a same-sign float64 pair is still exact")


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


func test_a_non_far_unit_with_no_soldiers_hashes_without_an_engine_error() -> void:
	# The guard keys on emptiness, not on the FAR tier, and those are different sets:
	# HUD.gd handles a below-FAR unit whose per-soldier arrays are not seeded yet. A guard
	# keyed on tier alone would push the engine error in exactly this state, and no test
	# covering only the FAR case would notice.
	var u := _make_unit(1, Vector2(100, 100))
	u._sim_soldier_pos = PackedVector2Array()
	assert_ne(u.tier, FormationTier.FAR, "the fixture is deliberately below FAR tier")
	var first: String = DemoStateHash.cheap_tick_hash(get_tree())
	assert_eq(first.length(), 32, "an unseeded below-FAR unit still hashes to a digest")
	assert_eq(DemoStateHash.cheap_tick_hash(get_tree()), first, "and does so repeatably")


# --- SPARTA_DEMO_BITDUMP arming, shared by both dump paths --------------------
#
# Regression cover for the defect where the variable was read in DemoStateSink only, so a
# scripted-input clip -- 102 of the catalog's 106 rows, `sidestep` among them -- armed the
# dump, exited 0, and wrote no bit_dump.jsonl. Both paths now read ticks_from_env, and the
# recorder-side test below is what fails if that path stops doing so.

const RecorderScript = preload("res://tools/demo/DemoInputRecorder.gd")
const SinkScript = preload("res://tools/demo/DemoStateSink.gd")

const _ARMING_ENV := ["SPARTA_DEMO_BITDUMP", "SPARTA_DEMO_STATE"]

var _saved_env: Dictionary = {}


func before_each() -> void:
	# Snapshot/restore both arming variables, so a developer's shell (or another test) can't
	# leak state in either direction -- and so a failing assert below cannot leave
	# SPARTA_DEMO_STATE set for whatever runs next.
	_saved_env = {}
	for key in _ARMING_ENV:
		_saved_env[key] = OS.get_environment(key) if OS.has_environment(key) else null
		OS.unset_environment(key)


func after_each() -> void:
	for key in _saved_env:
		if _saved_env[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, _saved_env[key])


func test_ticks_from_env_is_empty_when_unset() -> void:
	assert_eq(DemoBitDump.ticks_from_env(), [],
			"an unset variable arms nothing, so a normal run never opens a dump")


func test_ticks_from_env_is_empty_for_a_blank_value() -> void:
	# A workflow that wires the variable to an unfilled dispatch input passes "", which
	# must read as off rather than as "dump every tick" or as an error.
	OS.set_environment("SPARTA_DEMO_BITDUMP", "")
	assert_eq(DemoBitDump.ticks_from_env(), [], "a blank value arms nothing either")


func test_ticks_from_env_parses_sorts_and_dedupes() -> void:
	OS.set_environment("SPARTA_DEMO_BITDUMP", "22, 19,21,20,21")
	assert_eq(DemoBitDump.ticks_from_env(), [19, 20, 21, 22],
			"the tick list parses whitespace-tolerantly, sorted and de-duplicated")


func test_the_scripted_input_recorder_arms_from_the_same_variable() -> void:
	# The bug this pins: the recorder path ignored SPARTA_DEMO_BITDUMP entirely. Driving
	# _arm_bit_dump directly rather than _arm_state_dump keeps this tree-free -- the state
	# arming starts a wall-clock timer, which needs a SceneTree the bare recorder has none of.
	OS.set_environment("SPARTA_DEMO_BITDUMP", "19,21")
	var r = RecorderScript.new()
	autofree(r)
	r._state_dir = "user://bitdump_arm_test"
	DirAccess.make_dir_recursive_absolute(r._state_dir)
	r._arm_bit_dump()
	assert_eq(r._bit_ticks, [19, 21],
			"the scripted-input path reads the same variable the replay path does")
	assert_not_null(r._bit_dump, "and opens the dump file, so the run can actually write one")
	if r._bit_dump != null:
		r._bit_dump.close()
	_remove_dump_dir(r._state_dir)


## Delete a scratch dump dir and the bit_dump.jsonl inside it. remove_absolute needs a real
## OS path -- a raw user:// silently fails to delete, leaving a stray file in the app-data
## dir after every run (the same trap test_demo_state_sink.gd documents for its snapshots).
func _remove_dump_dir(dir: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("bit_dump.jsonl")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_a_failed_dump_open_does_not_let_the_run_report_success() -> void:
	# The drain exists so armed ticks past a decided battle's frozen tick cannot hang the run.
	# Draining unconditionally would also "complete" a run whose dump file never opened, which
	# is the one outcome worse than hanging: an absent bit_dump.jsonl and two agreeing dumps
	# are the same silence to a cross-platform comparison, so a clean exit over a missing file
	# reads as evidence the platforms match.
	OS.set_environment("SPARTA_DEMO_BITDUMP", "19,21")
	var r = RecorderScript.new()
	autofree(r)
	r._bit_ticks = [19, 21]
	r._bit_dump = null   # as a failed DemoBitDump.open_dump leaves it
	# A satisfied state dump, so _all_artifacts_done()'s leading `> 0` guard is cleared and
	# its other two conjuncts hold: the bit-tick equality is then the only thing left deciding
	# the assert below, which is what makes it discriminate rather than pass by default.
	r._state_ticks = [8]
	r._state_dumped = {8: true}
	r._bit_dumped = {19: true, 21: true}
	assert_true(r._all_artifacts_done(),
			"sanity: with the bit ticks accounted for, this fixture DOES read as done -- so the "
			+ "assert below is decided by the bit ticks alone, not by some other conjunct")
	r._bit_dumped = {}
	r._drain_unreachable_bit_ticks()
	assert_eq(r._bit_dumped, {},
			"nothing is marked dumped when no dump file was ever opened")
	assert_false(r._all_artifacts_done(),
			"so the run cannot quit claiming raw-bit dumps it never wrote")


func test_the_drain_clears_ticks_that_can_no_longer_fire() -> void:
	# The other half of the same guard: with a real dump open, ticks stranded past the frozen
	# tick DO drain, so a run that did its work quits promptly instead of sitting out the
	# wall-clock timeout.
	OS.set_environment("SPARTA_DEMO_BITDUMP", "19,21")
	var r = RecorderScript.new()
	autofree(r)
	r._state_dir = "user://bitdump_drain_test"
	DirAccess.make_dir_recursive_absolute(r._state_dir)
	r._arm_bit_dump()
	assert_not_null(r._bit_dump, "sanity: the dump opened")
	r._drain_unreachable_bit_ticks()
	assert_eq(r._bit_dumped.size(), 2, "both stranded ticks are accounted for")
	if r._bit_dump != null:
		r._bit_dump.close()
	_remove_dump_dir(r._state_dir)


func test_the_replay_sink_arms_from_the_same_variable() -> void:
	OS.set_environment("SPARTA_DEMO_BITDUMP", "19,21")
	OS.set_environment("SPARTA_DEMO_STATE", "8")
	var sink = SinkScript.arm_from_env("test")
	assert_not_null(sink, "sanity: the state dump armed")
	autofree(sink)
	assert_eq(sink._bit_ticks, [19, 21], "the replay path reads it through the same helper")
