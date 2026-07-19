extends GutTest
## file_major_reform (#878): the per-unit toggle between FILE-MAJOR casualty reflow (a
## soldier's file/column assignment is persistent; when a file-mate dies, only that file's
## own survivors step forward to close the gap -- every other file is untouched) and the
## existing ROW-MAJOR behavior (the whole grid recomputes fresh from the live headcount every
## tick, cascading survivors across the entire block on any casualty). Live-battle proof, in
## the real Battle scene with the real order pipeline and body-arrival dynamics: kill one
## specific soldier and confirm the blast radius stays inside its own file when the toggle is
## on, and confirm the pre-existing cascade still happens when it's off (a regression guard
## for the historical default). The pure geometry itself (exact rank/position math) is
## covered by test_unit_formation.gd's file_major_block_slots tests; this is the full-scene
## proof that the wiring (Unit._ensure_file_assignment, SoldierMelee.reap trimming
## _sim_soldier_file, SoldierBodies' real arrival dynamics) actually plays out correctly.

const SPEARMEN_COUNT := 40          # 9 files -> 4 full ranks + a 4-man partial rank
const SPAWN := Vector2(500, 430)

var _battle: Node = null


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## Stage the lone-unit drill battle (no opponent) and settle the bodies onto their slots.
func _stage_lone_spearmen() -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": SPEARMEN_COUNT, "facing": [0, 1]},
	]
	add_child(_battle)
	var unit: Unit = null
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team == 0:
			unit = u
	return unit


## Kill soldier `index` outright (direct HP zero + reap), exactly as any real combat death
## does -- SoldierMelee.reap() trims every per-soldier array (including _sim_soldier_file) at
## this index, shifting every later soldier down by one array slot.
func _kill(u: Unit, index: int) -> void:
	u._sim_soldier_hp[index] = 0.0
	SoldierMelee.reap(u, null)


## The array index a soldier now sitting at post-casualty index `i` originally held, given a
## single casualty at `dead_index` (removed high-to-low like SoldierMelee.reap() -- but a
## single removal is index-shift-equivalent regardless of direction).
func _orig_index(i: int, dead_index: int) -> int:
	return i if i < dead_index else i + 1


## Every soldier position RELATIVE TO THE REGIMENT'S OWN ANCHOR (u.position at the moment of
## the snapshot). A casualty legitimately nudges the regiment's own anchor a little
## (SoldierBodies.couple() slides `position` toward the bodies' actual centroid every tick --
## see ".claude/memories/sparta.md", "Regiment position is a pure function of body
## positions") even when NO soldier's slot assignment changed at all, so a raw absolute-
## position comparison would misread that shared, expected anchor drift as every soldier
## having moved. Subtracting the regiment's own position at each snapshot isolates the
## file-relative movement file_major_reform actually controls.
func _local_positions(u: Unit) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in u._sim_soldier_pos:
		out.push_back(p - u.position)
	return out


func test_file_major_reform_on_a_casualty_only_moves_its_own_files_later_ranks() -> void:
	var u := _stage_lone_spearmen()
	assert_not_null(u, "the scenario staged the lone spearmen regiment")
	if u == null:
		return
	assert_true(u.file_major_reform, "sanity: every type defaults file_major_reform on")
	for _k in range(40):   # let the spawned bodies settle onto their slots
		await get_tree().physics_frame
	var files: int = u.formation_files(u.soldiers)
	assert_eq(files, 9, "40 spearmen deploy 9 files wide (4 full ranks + a 4-man partial)")

	var target_file: int = files / 2   # a middle file with survivors both ahead and behind
	var dead_index: int = files + target_file   # that file's own rank-1 (second) member
	assert_eq(u._sim_soldier_file[dead_index], target_file,
		"sanity: the chosen index is target_file's own rank-1 member")

	var before_pos: PackedVector2Array = _local_positions(u)
	var before_file: PackedInt32Array = u._sim_soldier_file.duplicate()

	_kill(u, dead_index)
	assert_eq(u.soldiers, SPEARMEN_COUNT - 1, "the casualty reduces the live count by one")
	assert_eq(u._sim_soldier_file.size(), u.soldiers,
		"the file assignment array stays index-aligned with the live count")

	for _k in range(60):   # let the affected file's survivors step forward and settle
		await get_tree().physics_frame

	var after_pos: PackedVector2Array = _local_positions(u)
	var moved: Array = []
	var unmoved_in_target_file: Array = []
	for i in range(after_pos.size()):
		var orig: int = _orig_index(i, dead_index)
		var dist: float = after_pos[i].distance_to(before_pos[orig])
		if before_file[orig] == target_file:
			# The rank-0 member of the target file sat AHEAD of the casualty -- untouched.
			# The deeper survivors (originally rank 2+) step forward to close the gap.
			if orig < dead_index:
				unmoved_in_target_file.append([orig, dist])
			else:
				if dist > 1.0:
					moved.append(orig)
		else:
			assert_lt(dist, 0.5,
				"soldier from file %d (orig index %d) must not move for a casualty in a different file (moved %.3f wu)"
					% [before_file[orig], orig, dist])

	assert_gt(moved.size(), 0,
		"at least one deeper survivor in the affected file visibly stepped forward")
	for pair in unmoved_in_target_file:
		assert_lt(pair[1], 0.5,
			"the affected file's own rank-0 member (ahead of the casualty) doesn't move (orig index %d moved %.3f wu)"
				% [pair[0], pair[1]])


func test_file_major_reform_off_a_casualty_cascades_across_the_whole_block() -> void:
	# The regression guard: with the toggle OFF, behavior is byte-for-byte the historical
	# row-major cascade -- the same casualty used above visibly displaces a soldier in a
	# DIFFERENT file too, unlike the file-major case just proven above.
	var u := _stage_lone_spearmen()
	assert_not_null(u, "the scenario staged the lone spearmen regiment")
	if u == null:
		return
	u.file_major_reform = false
	for _k in range(40):
		await get_tree().physics_frame
	var files: int = u.formation_files(u.soldiers)
	assert_eq(files, 9, "40 spearmen deploy 9 files wide (4 full ranks + a 4-man partial)")

	var target_file: int = files / 2
	var dead_index: int = files + target_file
	var before_pos: PackedVector2Array = _local_positions(u)

	_kill(u, dead_index)
	assert_eq(u.soldiers, SPEARMEN_COUNT - 1, "the casualty reduces the live count by one")

	for _k in range(60):
		await get_tree().physics_frame

	# A soldier well past the casualty, in a DIFFERENT file than the one killed (file0's
	# third-rank member, originally index 2*files) -- file-major mode leaves it untouched
	# (see the companion test above); row-major recomputes its cell fresh from the live
	# count every tick, so it visibly relocates too. Compared RELATIVE to the regiment's own
	# anchor (see _local_positions) so the shared, expected couple() anchor-drift a casualty
	# always causes (in EITHER mode) doesn't mask -- or get mistaken for -- the row-major
	# cascade this test exists to prove.
	var after_pos: PackedVector2Array = _local_positions(u)
	var other_file_orig_index: int = files * 2
	var new_index: int = _orig_index_reverse(other_file_orig_index, dead_index)
	var dist: float = after_pos[new_index].distance_to(before_pos[other_file_orig_index])
	assert_gt(dist, 1.0,
		"row-major mode still cascades a casualty across the whole block, not just its own file")


## The inverse of _orig_index: given the ORIGINAL (pre-casualty) index of a surviving
## soldier, the index it now occupies in the post-casualty (compacted) array.
func _orig_index_reverse(orig: int, dead_index: int) -> int:
	return orig if orig < dead_index else orig - 1
