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
## different values into the same string. Unit positions are float64 (GDScript scalars,
## matching DemoStateHash._float_bytes); soldier positions are float32 (Vector2
## components), matching the PackedVector2Array bytes the cheap hash consumes. That
## pairing is deliberate: the dump must describe exactly what the hash hashed, or a
## divergence the stream reports could be missing from the dump entirely.

## Open (truncating) the dump file for a run, mirroring DemoHashStream.open_stream:
## callers keep the handle for the whole run and dump_tick flushes after every line, so
## a run that quits without an explicit close still leaves a complete dump on disk.
static func open_dump(dir: String) -> FileAccess:
	return FileAccess.open("%s/bit_dump.jsonl" % dir.trim_suffix("/"), FileAccess.WRITE)


## Hex of a float64's raw bits, little-endian, as PackedFloat64Array encodes it.
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
			"pos": [f64_hex(pos.x), f64_hex(pos.y)],
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
## one or two steps is rounding in the last place, while a large one is a different
## code path taken.
##
## Both float32 (8 hex chars) and float64 (16) are supported. float64 is the width that
## matters most in practice -- the unit position is checked before the soldier array, so
## it is usually the first field reported -- and an earlier version capped the parser
## below 64 bits, which made the distance unconditionally null for exactly that case.
##
## Null, rather than a number, whenever the arithmetic would not be a measurement:
## a width that is not 8 or 16, unparseable input, or either value carrying the sign
## bit. IEEE754 is sign-magnitude, so subtracting raw patterns across zero counts the
## whole negative range; a negative tick time or coordinate is not what this is for, and
## reporting a huge number there would read as a finding.
static func ulps_between(hex_a: String, hex_b: String) -> Variant:
	if hex_a.length() != hex_b.length():
		return null
	if hex_a.length() != 8 and hex_a.length() != 16:
		return null
	if _sign_bit_set(hex_a) or _sign_bit_set(hex_b):
		return null
	var ia: int = _hex_to_int_le(hex_a)
	var ib: int = _hex_to_int_le(hex_b)
	if ia < 0 or ib < 0:
		return null
	return abs(ia - ib)


## True when the little-endian pattern's sign bit is set -- the high bit of its LAST
## byte. Read from the hex directly rather than from the parsed int, so a 16-char
## pattern is classified before any parse that the sign bit itself would make negative.
static func _sign_bit_set(hex: String) -> bool:
	if hex.length() < 2:
		return false
	var last: String = hex.substr(hex.length() - 2, 2)
	if not _is_hex_byte(last):
		return false
	return (last.hex_to_int() & 0x80) != 0


## Little-endian hex to a non-negative int, or -1 when the string is not parseable as
## one. Callers screen the sign bit first, so every value reaching here fits a signed
## 64-bit int without wrapping.
static func _hex_to_int_le(hex: String) -> int:
	if hex.length() % 2 != 0 or hex.length() == 0 or hex.length() > 16:
		return -1
	var out: int = 0
	var shift: int = 0
	for i in range(0, hex.length(), 2):
		var byte_hex: String = hex.substr(i, 2)
		if not _is_hex_byte(byte_hex):
			return -1
		out |= byte_hex.hex_to_int() << shift
		shift += 8
	return out


## Exactly two hex digits, no sign and no 0x prefix.
##
## String.is_valid_hex_number() is the obvious choice and the wrong one: it validates a
## signed numeric literal, so it accepts a leading + or -, and hex_to_int() then honours
## that sign. The byte pair "-0" would pass and parse to 0, indistinguishable from a
## real "00" -- so a corrupted dump byte would read as agreement rather than as
## unparseable input, which is the one answer this must never give.
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
