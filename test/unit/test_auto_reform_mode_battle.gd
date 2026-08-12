extends GutTest
## file_major_reform_mode's AUTO option: resolves file-major/row-major casualty reflow from
## the unit's own `disciplined` flag (see Unit.file_major_reform_mode's own doc comment for
## why AUTO ties to `disciplined` and not `training`). Live-battle proof, in the real Battle
## scene with the real order pipeline and body-arrival dynamics -- the same rigor
## test_file_major_reform_battle.gd already applies to the two explicit modes: kill one
## specific soldier and confirm AUTO+disciplined behaves exactly like FILE_MAJOR (the blast
## radius stays inside its own file) and AUTO+undisciplined behaves exactly like ROW_MAJOR
## (the casualty cascades across the whole block). Also exercises the scenario-spec "auto"
## string end to end (Battle._parse_reform_mode), not just the enum field directly.

const SPEARMEN_COUNT := 40          # 9 files -> 4 full ranks + a 4-man partial rank
const SPAWN := Vector2(500, 430)

var _battle: Node = null


func after_each() -> void:
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## Stage the lone-unit drill battle (no opponent), requesting AUTO reform mode via the
## scenario-spec "auto" string and the given `disciplined` value.
func _stage_lone_spearmen(disciplined: bool) -> Unit:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true   # set before add_child so Battle._ready reads it
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": SPEARMEN_COUNT, "facing": [0, 1],
			"disciplined": disciplined, "file_major_reform": "auto"},
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


## The inverse of _orig_index: given the ORIGINAL (pre-casualty) index of a surviving
## soldier, the index it now occupies in the post-casualty (compacted) array.
func _orig_index_reverse(orig: int, dead_index: int) -> int:
	return orig if orig < dead_index else orig - 1


## Every soldier position RELATIVE TO THE REGIMENT'S OWN ANCHOR (u.position at the moment of
## the snapshot) -- see test_file_major_reform_battle.gd's own doc comment on the identical
## helper for why the raw absolute position isn't the right comparison.
func _local_positions(u: Unit) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in u._sim_soldier_pos:
		out.push_back(p - u.position)
	return out


func test_auto_reform_mode_with_a_disciplined_unit_only_moves_the_casualtys_own_file() -> void:
	var u := _stage_lone_spearmen(true)
	assert_not_null(u, "the scenario staged the lone spearmen regiment")
	if u == null:
		return
	assert_eq(u.file_major_reform_mode, Unit.ReformMode.AUTO,
		"sanity: the scenario's 'auto' string parsed to ReformMode.AUTO")
	assert_true(u.disciplined, "sanity: this unit is disciplined")
	assert_true(u._effective_file_major_reform(),
		"sanity: AUTO + disciplined resolves file-major")
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

	for _k in range(60):   # let the affected file's survivors step forward and settle
		await get_tree().physics_frame

	var after_pos: PackedVector2Array = _local_positions(u)
	var moved: Array = []
	for i in range(after_pos.size()):
		var orig: int = _orig_index(i, dead_index)
		var dist: float = after_pos[i].distance_to(before_pos[orig])
		if before_file[orig] == target_file and orig >= dead_index:
			if dist > 1.0:
				moved.append(orig)
		elif before_file[orig] != target_file:
			assert_lt(dist, 0.5,
				"AUTO+disciplined: soldier from a DIFFERENT file (orig index %d) must not move (moved %.3f wu)"
					% [orig, dist])
	assert_gt(moved.size(), 0,
		"AUTO+disciplined: at least one deeper survivor in the affected file visibly stepped forward")


func test_auto_reform_mode_with_an_undisciplined_unit_cascades_across_the_whole_block() -> void:
	# The regression companion of the disciplined case above: AUTO on an UNDISCIPLINED unit
	# resolves row-major, so the SAME casualty visibly displaces a soldier in a DIFFERENT file
	# too, matching test_file_major_reform_battle.gd's own ROW_MAJOR regression guard.
	var u := _stage_lone_spearmen(false)
	assert_not_null(u, "the scenario staged the lone spearmen regiment")
	if u == null:
		return
	assert_eq(u.file_major_reform_mode, Unit.ReformMode.AUTO,
		"sanity: the scenario's 'auto' string parsed to ReformMode.AUTO")
	assert_false(u.disciplined, "sanity: this unit is undisciplined")
	assert_false(u._effective_file_major_reform(),
		"sanity: AUTO + undisciplined resolves row-major")
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
	# third-rank member, originally index 2*files) -- AUTO+disciplined leaves it untouched
	# (see the companion test above); AUTO+undisciplined recomputes its cell fresh from the
	# live count every tick, so it visibly relocates too.
	var after_pos: PackedVector2Array = _local_positions(u)
	var other_file_orig_index: int = files * 2
	var new_index: int = _orig_index_reverse(other_file_orig_index, dead_index)
	var dist: float = after_pos[new_index].distance_to(before_pos[other_file_orig_index])
	assert_gt(dist, 1.0,
		"AUTO+undisciplined still cascades a casualty across the whole block, not just its own file")
