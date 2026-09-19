class_name DemoBitDump
## The bit_dump.jsonl file format and its offline comparison -- the pure half of the
## raw-bit position dump (DemoStateHash.dump_tick writes it from live game state; this
## class never touches a game script). Kept dependency-free for the same reason
## DemoHashStream is: analyze_transcript.gd runs as a bare `godot -s` SceneTree with no
## autoloads, where any reference chain into the game scripts spews compile errors.
##
## Why this exists alongside hash_stream.jsonl. The hash stream localizes a divergence
## to a TICK and, being a hash, can say nothing about which value moved -- which is what
## makes it a good detector and a useless diagnostic. Naming the first function whose
## output differs across platforms needs the bits themselves, for the handful of ticks
## around the one the stream already named.
##
## Stream shape, one line per DUMPED tick (not every tick -- callers pass only the ticks
## they are investigating):
##   {"tick": 21, "units": [{"uid": 0, "pos": ["<hex>", "<hex>"], "soldiers": ["<hex>"]}]}
##
## Every float is the hex of its RAW BITS, never formatted text. A last-ulp difference
## is precisely what this exists to catch, and any decimal rendering can round two
## different values into the same string.
##
## EVERY position is dumped at float32, unit and soldier alike, because that is the
## precision the data actually has: Vector2 components are real_t, which is 32-bit in
## a standard build (measured on Godot 4.7 win64 -- a Node2D position component does
## not compare equal to the float64 literal it was assigned, and round-trips exactly
## through float32).
##
## The cheap hash widens a unit position to float64 before hashing it, and this dump
## deliberately does NOT copy that. The widening is lossless and bijective, so no
## information is lost by dumping the narrower form (exactly so for every finite
## value, including denormals and both zeros; a NaN payload across a widening is
## implementation-defined, and a NaN position would be a far larger bug than this
## tool is for) -- but a distance in float64 steps
## between two widened float32 values is not a measurement of anything. Two adjacent
## float32 values report about 2^29 float64 steps apart, which this file elsewhere
## tells the reader means "a different code path taken". Dumping the true width is
## what makes the one-or-two-steps reading correct for the field most likely to be
## reported first.

## The tick list SPARTA_DEMO_BITDUMP asks for, or [] when it is unset or names no ticks.
##
## One reading of the contract, shared by both dump paths (DemoStateSink for replays,
## DemoInputRecorder for scripted input), because the two paths having grown their own is
## what made the variable silently inert on the scripted-input path -- which is 102 of the
## catalog's 106 clips, `sidestep` among them. Reuses DemoFrames, which is pure parsing with
## no node or engine state, so this class stays usable from the bare `godot -s` SceneTree
## analyze_transcript.gd runs in.
static func ticks_from_env() -> Array:
	if not OS.has_environment("SPARTA_DEMO_BITDUMP"):
		return []
	return DemoFrames.merge_ticks(OS.get_environment("SPARTA_DEMO_BITDUMP"), [])


## Open (truncating) the dump file for a run, mirroring DemoHashStream.open_stream:
## callers keep the handle for the whole run and dump_tick flushes after every line, so
## a run that quits without an explicit close still leaves a complete dump on disk.
static func open_dump(dir: String) -> FileAccess:
	return FileAccess.open("%s/bit_dump.jsonl" % dir.trim_suffix("/"), FileAccess.WRITE)


## Hex of a float64's raw bits, little-endian, as PackedFloat64Array encodes it.
##
## Not used for positions -- see the class docstring on why those are dumped at their
## true float32 width. Kept because ulps_between handles both widths, so a caller
## dumping a genuine GDScript scalar has the encoder it needs.
static func f64_hex(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


## Hex of a float32's raw bits, little-endian, as PackedFloat32Array encodes it.
## The narrowing happens here, so the hex is the value as it actually sits in a Vector2.
static func f32_hex(v: float) -> String:
	return PackedFloat32Array([v]).to_byte_array().hex_encode()


## One dumped tick as a JSONL line. `records` is DemoStateHash.cheap_tick_records()'s
## output: an Array of {"uid": int, "pos": Vector2, "soldiers": PackedVector2Array},
## already in ascending uid order.
static func format_line(tick: int, records: Array) -> String:
	var units: Array = []
	for r in records:
		var pos: Vector2 = r["pos"]
		var soldiers: PackedVector2Array = r["soldiers"]
		var flat: Array = []
		for p in soldiers:
			flat.append(f32_hex(p.x))
			flat.append(f32_hex(p.y))
		units.append({
			"uid": int(r["uid"]),
			"pos": [f32_hex(pos.x), f32_hex(pos.y)],
			"soldiers": flat,
		})
	return JSON.stringify({"tick": tick, "units": units})


## Parse a bit_dump.jsonl text into the entry list compare_dumps takes. Malformed lines
## are skipped, matching DemoHashStream.parse_stream: a truncated final line from a
## killed run should not poison the whole comparison.
static func parse_dump(text: String) -> Array:
	var out: Array = []
	var json := JSON.new()
	for line in text.split("\n", false):
		if json.parse(line) != OK:
			continue
		var parsed = json.data
		if parsed is Dictionary and parsed.has("tick") and parsed.has("units"):
			out.append(parsed)
	return out


## Compare two parsed dumps and report the FIRST differing component, in tick then uid
## then field order. Ticks are matched by number (not position) so dumps covering
## different tick sets compare over their common range, as compare_streams does.
##
## Returns on a difference:
##   {"divergent": true, "tick": N, "uid": U, "field": "pos.x"|"soldier[3].y",
##    "a": "<hex>", "b": "<hex>", "ulps": int|null, "compared": n}
## and otherwise {"divergent": false, "compared": n, "only_a": x, "only_b": y}.
##
## A unit present in only one dump is reported rather than skipped: at the ticks this
## runs on, a missing unit IS the divergence.
static func compare_dumps(a: Array, b: Array) -> Dictionary:
	var by_tick_b: Dictionary = {}
	for e in b:
		by_tick_b[int(e["tick"])] = e
	var common: Array = []
	for e in a:
		if by_tick_b.has(int(e["tick"])):
			common.append(e)
	common.sort_custom(func(x, y): return int(x["tick"]) < int(y["tick"]))
	for e in common:
		var tick: int = int(e["tick"])
		var found: Dictionary = _first_unit_diff(e, by_tick_b[tick])
		if not found.is_empty():
			found["tick"] = tick
			found["divergent"] = true
			found["compared"] = common.size()
			return found
	return {"divergent": false, "compared": common.size(),
			"only_a": a.size() - common.size(), "only_b": b.size() - common.size()}


## The first differing component within one tick's two entries, or {} when identical.
##
## Walks the UNION of both sides' uids in ascending order rather than side a's own
## order. Walking one side first would report a high-uid field difference ahead of a
## low-uid unit that is missing entirely, contradicting compare_dumps' documented
## "tick then uid then field" ordering on exactly the input where the structural
## difference is the more informative of the two.
static func _first_unit_diff(entry_a: Dictionary, entry_b: Dictionary) -> Dictionary:
	var by_uid_a: Dictionary = _by_uid(entry_a["units"])
	var by_uid_b: Dictionary = _by_uid(entry_b["units"])
	var uids: Array = []
	for uid in by_uid_a:
		uids.append(uid)
	for uid in by_uid_b:
		if not by_uid_a.has(uid):
			uids.append(uid)
	uids.sort()
	for uid in uids:
		if not by_uid_b.has(uid):
			return {"uid": uid, "field": "unit", "a": "present", "b": "absent", "ulps": null}
		if not by_uid_a.has(uid):
			return {"uid": uid, "field": "unit", "a": "absent", "b": "present", "ulps": null}
		var found: Dictionary = _first_field_diff(by_uid_a[uid], by_uid_b[uid])
		if not found.is_empty():
			found["uid"] = uid
			return found
	return {}


## The first differing field within one unit's two records, or {} when identical. The
## unit position is checked before the soldier array, so the outermost difference is the
## one reported.
static func _first_field_diff(ua: Dictionary, ub: Dictionary) -> Dictionary:
	var pos_a: Array = ua["pos"]
	var pos_b: Array = ub["pos"]
	for i in range(2):
		if pos_a[i] != pos_b[i]:
			var axis: String = "x" if i == 0 else "y"
			return {"field": "pos.%s" % axis, "a": pos_a[i], "b": pos_b[i],
					"ulps": ulps_between(pos_a[i], pos_b[i])}
	var sol_a: Array = ua["soldiers"]
	var sol_b: Array = ub["soldiers"]
	if sol_a.size() != sol_b.size():
		return {"field": "soldiers.size", "a": str(sol_a.size()), "b": str(sol_b.size()),
				"ulps": null}
	for i in range(sol_a.size()):
		if sol_a[i] != sol_b[i]:
			# The flat array interleaves x then y, so the soldier index is the pair index
			# and the axis is the parity.
			var axis2: String = "x" if i % 2 == 0 else "y"
			return {"field": "soldier[%d].%s" % [i / 2, axis2], "a": sol_a[i], "b": sol_b[i],
					"ulps": ulps_between(sol_a[i], sol_b[i])}
	return {}


static func _by_uid(units: Array) -> Dictionary:
	var out: Dictionary = {}
	for u in units:
		out[int(u["uid"])] = u
	return out


## Distance in representable steps between two same-width raw-bit hex values, or null
## when that number would not mean anything.
##
## The figure separates the two explanations this dump exists to tell apart: a gap of
## one or two steps is rounding in the last place, while a large one is a different code
## path taken.
##
## float32 (8 hex chars) is mapped through a monotonic ordering first, so the distance is
## exact across the whole number line INCLUDING a sign change. IEEE754 is sign-magnitude,
## so subtracting raw patterns across zero would count the entire negative range -- but
## the fix is to reorder, not to refuse. Refusing would drop the diagnostic for every
## negative coordinate, and a battlefield has those whenever the field origin is not at
## zero; it would also drop -0.0 against +0.0, which is a classic cross-platform libm
## artifact and reads here as the adjacent pair it is.
##
## float64 (16) keeps the narrower same-sign rule: its ordered key needs a full 64
## unsigned bits, which a GDScript int cannot hold without wrapping. Same-sign pairs are
## still exact, because the sign contributes an identical offset to both patterns and
## cancels in the subtraction. Nothing this dump writes is float64 today -- positions are
## dumped at their true float32 width -- so this is the path a caller reaches only by
## encoding a genuine GDScript scalar itself.
static func ulps_between(hex_a: String, hex_b: String) -> Variant:
	if hex_a.length() != hex_b.length():
		return null
	if not _is_hex_pattern(hex_a) or not _is_hex_pattern(hex_b):
		return null
	if hex_a.length() == 8:
		return abs(_ordered_key32(hex_a) - _ordered_key32(hex_b))
	if _sign_bit_set(hex_a) != _sign_bit_set(hex_b):
		return null
	return abs(_hex_to_int_le(hex_a) - _hex_to_int_le(hex_b))


## A float32 pattern mapped to a monotonically increasing key, so that subtracting two
## keys counts representable steps in the ordinary way regardless of sign.
##
## The standard transform: a non-negative pattern moves above the midpoint, and a
## negative one is reflected below it. Adjacent floats stay adjacent keys, and +0.0 and
## -0.0 land one apart, which is what they are.
static func _ordered_key32(hex: String) -> int:
	var p: int = _hex_to_int_le(hex)
	if (p & 0x80000000) != 0:
		return 0xFFFFFFFF - p
	return p + 0x80000000


## True when the little-endian pattern's sign bit is set -- the high bit of its LAST
## byte. Callers validate the pattern first, so this is only ever read from hex it can
## trust.
static func _sign_bit_set(hex: String) -> bool:
	return (hex.substr(hex.length() - 2, 2).hex_to_int() & 0x80) != 0


## A whole raw-bit pattern of a width this module encodes: 8 hex chars for float32, 16
## for float64, every character a hex digit.
static func _is_hex_pattern(hex: String) -> bool:
	if hex.length() != 8 and hex.length() != 16:
		return false
	for i in range(0, hex.length(), 2):
		if not _is_hex_byte(hex.substr(i, 2)):
			return false
	return true


## Little-endian hex to int. Assumes _is_hex_pattern already passed; a 16-char pattern
## with its top bit set wraps negative, which is harmless where it is used because two
## same-sign patterns wrap identically and their difference survives.
static func _hex_to_int_le(hex: String) -> int:
	var out: int = 0
	var shift: int = 0
	for i in range(0, hex.length(), 2):
		out |= hex.substr(i, 2).hex_to_int() << shift
		shift += 8
	return out


## Exactly two hex digits, no sign and no 0x prefix.
##
## String.is_valid_hex_number() is the obvious choice and the wrong one: it validates a
## signed numeric literal, so it accepts a leading + or -, and hex_to_int() then honours
## that sign. The byte pair "-0" would pass and parse to 0, indistinguishable from a real
## "00" -- so a corrupted dump byte would read as agreement rather than as unparseable
## input, which is the one answer this must never give.
static func _is_hex_byte(pair: String) -> bool:
	if pair.length() != 2:
		return false
	for i in range(2):
		var c: int = pair.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 102
		var is_upper: bool = c >= 65 and c <= 70
		if not (is_digit or is_lower or is_upper):
			return false
	return true
