extends GutTest
## A FILE_GROUP block that changes its frontage re-forms its files from where the men stand,
## exactly as a block with no declared subunit does (Unit._ensure_file_assignment's lateral
## deal). Re-forming them from the ids it held instead kept each retained man in his file but
## sent the men of the folded or peeled files to whichever file had room, often on the far
## flank, so a man walked across or through his own block.

const SPAWN := Vector2(600, 420)
var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## A bare file-major foot block facing down the screen, every body on its slot.
func _make(count: int, files: int, structure: int, size: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = files
	u.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	u.subunit_structure = structure
	u.subunit_size = size
	u.seed_sim_soldiers()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]
	return u


## Per man, how far his slot after the resize lies from where he stood before it.
func _walks(u: Unit, bodies: PackedVector2Array) -> PackedFloat32Array:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var out := PackedFloat32Array()
	for i in range(mini(bodies.size(), slots.size())):
		out.push_back(bodies[i].distance_to(slots[i]))
	return out


func _farthest(walks: PackedFloat32Array) -> float:
	var far: float = 0.0
	for w in walks:
		far = maxf(far, w)
	return far


## How far a lateral deal can send a man when `count` men go from `from_files` to
## `to_files`. Sideways, the deal keeps every man's lateral order, so he moves at most the
## k / 2 file pitches the flanks spread or close by for a change of k files, plus half a pitch
## of the new grid re-centring (the slot_lateral_excess basis in demos/README.md). In depth,
## each end of the block moves by half the change in rank count, and the depth deal can step
## him up to one rank more as men from a neighbouring file slot in beside him.
func _deal_bound(u: Unit, count: int, from_files: int, to_files: int) -> float:
	var k: int = absi(to_files - from_files)
	var lateral: float = float(k + 1) * 0.5 * u.file_pitch_wu()
	var rank_change: int = absi(UnitFormation.ranks_for(count, to_files)
			- UnitFormation.ranks_for(count, from_files))
	var depth: float = (float(rank_change) * 0.5 + 1.0) * u.rank_pitch_wu()
	return Vector2(lateral, depth).length()


## Resize a FILE_GROUP block and a twin with no declared subunit from the same stance, and
## check the FILE_GROUP block is dealt exactly as its twin is, with no man sent past the
## lateral deal's own bound. The twin is the reference because dealing from where the men
## stand is the whole of the change.
func _assert_resize_matches_plain(count: int, from_files: int, to_files: int, size: int) -> void:
	var grouped := _make(count, from_files, Unit.SubunitStructure.FILE_GROUP, size)
	var plain := _make(count, from_files, Unit.SubunitStructure.NONE, 0)
	var grouped_bodies: PackedVector2Array = grouped._sim_soldier_pos.duplicate()
	var plain_bodies: PackedVector2Array = plain._sim_soldier_pos.duplicate()
	grouped.set_frontage(to_files)
	plain.set_frontage(to_files)
	var far: float = _farthest(_walks(grouped, grouped_bodies))
	var plain_far: float = _farthest(_walks(plain, plain_bodies))
	var label := "%d men, %d files to %d, subunit_size %d" % [count, from_files, to_files, size]
	assert_eq(grouped.formation_files(grouped.soldiers), to_files, "precondition: %s" % label)
	assert_eq(grouped._sim_soldier_file, plain._sim_soldier_file, "%s: the same files" % label)
	assert_eq(grouped._sim_soldier_rank, plain._sim_soldier_rank, "%s: the same ranks" % label)
	var bound: float = _deal_bound(grouped, count, from_files, to_files)
	assert_lt(far, bound,
		"%s: the farthest man walks %.1f wu (plain %.1f, bound %.1f)" % [label, far,
			plain_far, bound])


## The issue's case: 46 men going from 10 files to 9, on the default subunit_size of 0. Held
## ids sent the farthest man 165.5 wu; dealt from the bodies he walks 12.7 wu.
func test_a_one_file_narrowing_sends_no_man_across_the_block() -> void:
	_assert_resize_matches_plain(46, 10, 9, 0)


## The same block widened back, which peeled the rear men of four files into the new flank
## file from as far away as the opposite flank (165.5 wu).
func test_a_one_file_widening_sends_no_man_across_the_block() -> void:
	_assert_resize_matches_plain(46, 9, 10, 0)


## An 80-man lochos-sized block (subunit_size 16) going from 5 files to 4, which folded the
## flank file into the other files' rear front man first, so the folded file's front man walked
## to the opposite rear corner (259.8 wu, against 37.1 wu from the bodies).
func test_a_lochos_narrowing_folds_no_man_to_the_far_corner() -> void:
	_assert_resize_matches_plain(80, 5, 4, 16)


## And a full Spearmen-sized block of 140 on 9 files narrowed to 6 (334.0 wu, against 76.9).
func test_a_three_file_narrowing_sends_no_man_across_the_block() -> void:
	_assert_resize_matches_plain(140, 9, 6, 16)


## A Spearmen regiment in a live battle narrowed by the bracket order's own path
## (Unit.set_frontage): every man's slot stays inside the lateral deal's bound of him (the
## farthest is 18.6 wu), where re-forming from the held ids sent one 129.9 wu.
func test_live_spearmen_narrowing_sends_no_man_across_the_block() -> void:
	Replay.forced_seed = 912
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": 80, "facing": [0, 1]}
	]
	add_child_autofree(_battle)
	for _i in range(10):
		await get_tree().physics_frame

	var u: Unit = _battle._units.get_child(0)
	assert_true(u.unit_name.begins_with("Spearmen"))
	assert_eq(u.subunit_structure, Unit.SubunitStructure.FILE_GROUP)
	assert_eq(UnitFormation.frontage(u), 5, "80 spearmen on 16-man files default to 5 files")
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	u.set_frontage(4)
	var far: float = _farthest(_walks(u, bodies))
	var bound: float = _deal_bound(u, u.soldiers, 5, 4)
	assert_lt(far, bound, "the farthest man walks %.1f wu (bound %.1f)" % [far, bound])

