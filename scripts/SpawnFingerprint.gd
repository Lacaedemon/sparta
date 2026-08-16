class_name SpawnFingerprint
## A short digest of the battle's spawn layout: the type, roster size, and rounded spawn
## position of every unit as it deploys, in uid order. Its purpose is to make a demo/replay
## artifact self-checking against the spawn layout it was authored for -- a commit that
## re-spaces or re-composes the spawn line (one such change once moved every unit's x by tens
## of world units) changes this digest, so an artifact carrying a now-stale stamp fails LOUDLY at load
## instead of silently clicking empty ground where a unit used to be.
##
## Positions are rounded to whole world units: sub-pixel spawn jitter never moves a click, and
## rounding keeps the digest free of float-formatting nondeterminism. Only spawn-time-stable
## fields are read (max_soldiers, the deployed roster size -- never the live casualty count),
## so a layout hashes identically whether the digest is taken at spawn or later in the battle.
##
## The digest is over whatever actually spawned, so it is uniform across the default two-line
## deployment and a custom `scenario` matchup alike: a fixed-coordinate input script that runs
## the default lines gets a digest that drifts with the spawn table, while a self-contained
## scenario script gets a digest of its own placement (which never drifts relative to the
## script). record_of/of_tree read Unit fields; the pure digest() takes plain records, so the
## hashing is unit-testable without a live scene.

## Build one unit's fingerprint record. Reads spawn-time-stable fields only, so the record is
## the same whether taken at spawn or mid-battle.
static func record_of(u) -> Dictionary:
	return {
		"uid": int(u.uid),
		"team": int(u.team),
		"type": String(u.unit_name),
		# The DEPLOYED weapon, not the held one: a phase-4 weapon switch rewrites
		# weapon_type_id mid-battle, which would re-stamp this digest and fail an
		# artifact's own load check for a spawn layout that never moved. Same value as
		# weapon_type_id at spawn, so every existing stamp still matches.
		"weapon": int(u.spawn_weapon_type_id),
		"shield": int(u.shield_type_id),
		"mount": int(u.mount_type_id),
		"soldiers": int(u.max_soldiers),
		"x": roundi(u.position.x),
		"y": roundi(u.position.y),
	}


## Every combat unit currently on the field as fingerprint records, in ascending uid order.
## Walks the same "units" group the spawn fills; group enumeration order follows insertion, so
## the sort pins a canonical order the digest can depend on.
static func records_of_tree(tree: SceneTree) -> Array:
	var out: Array = []
	for u in tree.get_nodes_in_group("units"):
		out.append(record_of(u))
	out.sort_custom(func(a, b): return a["uid"] < b["uid"])
	return out


## Canonical digest of a record list. Pure: the same records in the same order always produce
## the same hex string. Fields are joined with delimiters that can't appear in the values
## (unit_name has no colon/newline), so two distinct layouts can never collide by concatenation.
static func digest(records: Array) -> String:
	var parts: PackedStringArray = []
	for r in records:
		parts.append("%d:%d:%s:%d:%d:%d:%d:%d:%d" % [
			int(r["uid"]), int(r["team"]), String(r["type"]),
			int(r["weapon"]), int(r["shield"]), int(r["mount"]),
			int(r["soldiers"]), int(r["x"]), int(r["y"])])
	return "\n".join(parts).md5_text()


## The current live layout's fingerprint, or "" when no units are on the field (nothing to
## stamp or check against yet).
static func of_tree(tree: SceneTree) -> String:
	var records: Array = records_of_tree(tree)
	if records.is_empty():
		return ""
	return digest(records)
