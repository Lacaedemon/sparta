class_name DemoStateHash
## Per-tick two-tier sim-state hashing for the demo dump path, adapted from 0 A.D.'s
## replay state hash (a cheap positions-only hash every turn, a full hash every N).
## While a state-dump run is armed, both dump paths (DemoInputRecorder, DemoStateSink)
## call write_tick() every tick, appending to <state-dir>/hash_stream.jsonl (the file
## format, cadence const, and the offline comparison live in DemoHashStream).
##
## Two streams from different runs of the same scripted clip localize a divergence to
## the exact tick it first appears (DemoHashStream.compare_streams /
## analyze_transcript.gd's --compare-hashes mode), replacing the old eyeball-diff of
## full field-level dumps.
##
## Canonical-serialization rules, so the hash itself can never be the nondeterminism:
## units are visited in ascending uid order (group enumeration order reshuffles as a
## unit routs/rallies between groups -- the same hazard DemoState.sort_records_by_uid
## guards the readable transcript against), and every float is hashed as its raw BITS
## (PackedFloat32Array/PackedVector2Array byte encodings; scalar unit fields widen to
## PackedFloat64Array bytes), never as formatted text -- rounding would hide exactly
## the small cross-platform drift the stream exists to catch until it crossed a
## rounding boundary.
##
## Compare streams from the SAME dump path (recorder vs recorder, sink vs sink): the
## two paths sample the tick at slightly different points in the frame, so their
## streams are not comparable to each other, only to themselves across runs.

## Sentinel hashed in place of a null target_enemy uid (real uids are >= -1 only for
## unspawned test fixtures; Battle-spawned units are >= 0).
const NO_TARGET := -2


## The cheap tier: every unit's uid + position plus the raw per-soldier position bytes.
## Positions move on virtually every divergent tick, so this tier alone localizes the
## first divergence; the full tier (below) classifies it.
static func cheap_tick_hash(tree: SceneTree) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for u in units_by_uid(tree):
		ctx.update(_int_bytes([u.uid]))
		ctx.update(_float_bytes([u.position.x, u.position.y]))
		if u.tier != FormationTier.FAR:
			ctx.update((u._sim_soldier_pos as PackedVector2Array).to_byte_array())
	return ctx.finish().hex_encode()


## The full tier: the cheap fields plus facings, the mode/state ints, morale and speed,
## the per-soldier hp/prone/stamina arrays, and the replay RNG state. `rng_state` is
## passed in (callers read Replay.rng.state) so this stays drivable from a test without
## touching the autoload's live stream.
static func full_tick_hash(tree: SceneTree, rng_state: int) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for u in units_by_uid(tree):
		var target_uid: int = u.target_enemy.uid \
				if u.target_enemy != null and is_instance_valid(u.target_enemy) else NO_TARGET
		ctx.update(_int_bytes([u.uid, u.team, u.state, u.formation_mode, u.order_mode,
				u.soldiers, target_uid]))
		ctx.update(_float_bytes([u.position.x, u.position.y, u.facing.x, u.facing.y,
				u.morale, u._current_speed]))
		if u.tier != FormationTier.FAR:
			ctx.update((u._sim_soldier_pos as PackedVector2Array).to_byte_array())
			ctx.update((u._sim_soldier_facing as PackedVector2Array).to_byte_array())
			ctx.update((u._sim_soldier_hp as PackedFloat32Array).to_byte_array())
			ctx.update((u._sim_prone as PackedFloat32Array).to_byte_array())
			ctx.update((u._sim_soldier_stamina as PackedFloat32Array).to_byte_array())
	ctx.update(_int_bytes([rng_state]))
	return ctx.finish().hex_encode()


## Every combat unit still on the field, in ascending uid order -- the same
## "units" + "routers" union the readable snapshot walks (DemoState.COMBAT_GROUPS),
## sorted so group-membership churn mid-rout can't reorder the hash input.
static func units_by_uid(tree: SceneTree) -> Array:
	var units: Array = []
	for group in DemoState.COMBAT_GROUPS:
		for u in tree.get_nodes_in_group(group):
			units.append(u)
	units.sort_custom(func(a, b): return a.uid < b.uid)
	return units


static func _int_bytes(vals: Array) -> PackedByteArray:
	return PackedInt64Array(vals).to_byte_array()


static func _float_bytes(vals: Array) -> PackedByteArray:
	return PackedFloat64Array(vals).to_byte_array()


# --- stream writing (shared by DemoInputRecorder and DemoStateSink) ---------

## Hash the current tick into the stream: cheap every tick, plus the full tier on the
## DemoHashStream.FULL_EVERY cadence. The one per-tick entry point both dump paths
## call; the file format and the offline comparison live in DemoHashStream (kept
## dependency-free so analyze_transcript can use them without this class's reference
## chain into the game scripts).
static func write_tick(f: FileAccess, tree: SceneTree, tick: int, rng_state: int) -> void:
	var full: String = full_tick_hash(tree, rng_state) if tick % DemoHashStream.FULL_EVERY == 0 else ""
	DemoHashStream.append_line(f, tick, cheap_tick_hash(tree), full)
