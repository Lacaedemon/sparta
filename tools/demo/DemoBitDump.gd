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
static func _first_unit_diff(entry_a: Dictionary, entry_b: Dictionary) -> Dictionary:
	var units_a: Array = entry_a["units"]
	var units_b: Array = entry_b["units"]
	var by_uid_b: Dictionary = {}
	for u in units_b:
		by_uid_b[int(u["uid"])] = u
	for ua in units_a:
		var uid: int = int(ua["uid"])
		if not by_uid_b.has(uid):
			return {"uid": uid, "field": "unit", "a": "present", "b": "absent", "ulps": null}
		var ub: Dictionary = by_uid_b[uid]
		var pos_a: Array = ua["pos"]
		var pos_b: Array = ub["pos"]
		for i in range(2):
			if pos_a[i] != pos_b[i]:
				var axis: String = "x" if i == 0 else "y"
				return {"uid": uid, "field": "pos.%s" % axis, "a": pos_a[i], "b": pos_b[i],
						"ulps": ulps_between(pos_a[i], pos_b[i])}
		var sol_a: Array = ua["soldiers"]
		var sol_b: Array = ub["soldiers"]
		if sol_a.size() != sol_b.size():
			return {"uid": uid, "field": "soldiers.size",
					"a": str(sol_a.size()), "b": str(sol_b.size()), "ulps": null}
		for i in range(sol_a.size()):
			if sol_a[i] != sol_b[i]:
				var axis2: String = "x" if i % 2 == 0 else "y"
				var which: int = i / 2
				return {"uid": uid, "field": "soldier[%d].%s" % [which, axis2],
						"a": sol_a[i], "b": sol_b[i],
						"ulps": ulps_between(sol_a[i], sol_b[i])}
	for ub in units_b:
		if not _has_uid(units_a, int(ub["uid"])):
			return {"uid": int(ub["uid"]), "field": "unit", "a": "absent", "b": "present",
					"ulps": null}
	return {}


static func _has_uid(units: Array, uid: int) -> bool:
	for u in units:
		if int(u["uid"]) == uid:
			return true
	return false


## Distance in representable steps between two same-width raw-bit hex values, or null
## when that number would not mean anything.
##
## The figure separates the two explanations this dump exists to tell apart: a gap of
## one or two steps is rounding in the last place, while a large one is a different
## code path taken. It is meaningful only when both values carry the same sign bit --
## IEEE754 is sign-magnitude, so subtracting the raw patterns across zero counts the
## entire negative range -- and null is returned rather than a number that would read
## as a measurement.
static func ulps_between(hex_a: String, hex_b: String) -> Variant:
	if hex_a.length() != hex_b.length():
		return null
	var ia: int = _hex_to_int_le(hex_a)
	var ib: int = _hex_to_int_le(hex_b)
	if ia < 0 or ib < 0:
		return null
	var bits: int = hex_a.length() * 4
	# A 64-bit pattern cannot carry its sign bit in a signed int, so the mask test below
	# is only sound for widths that leave room for it. float32 is the width that matters
	# here; float64 pairs fall through to null rather than reporting a wrong distance.
	if bits >= 64:
		return null
	var sign_mask: int = 1 << (bits - 1)
	if (ia & sign_mask) != (ib & sign_mask):
		return null
	return abs(ia - ib)


## Little-endian hex to int, or -1 when the string is not parseable as one. Widths past
## 56 bits are refused rather than silently losing the top byte to the sign bit.
static func _hex_to_int_le(hex: String) -> int:
	if hex.length() % 2 != 0 or hex.length() == 0 or hex.length() > 14:
		return -1
	var out: int = 0
	var shift: int = 0
	for i in range(0, hex.length(), 2):
		var byte_hex: String = hex.substr(i, 2)
		if not byte_hex.is_valid_hex_number():
			return -1
		out |= byte_hex.hex_to_int() << shift
		shift += 8
	return out
