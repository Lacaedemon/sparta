extends GutTest
## The traverse flank arcs bend exactly the men a hold-ground about-face sends walking the
## block's depth, in a squared block as in a row-major one, and still do after a casualty during
## the reform hold.
##
## A hold-ground re-square composes the depth reflection's cell pairing onto the pairing the block
## holds. Every man takes the cell that inherits the ground he stands on, except the men whose
## cell the reflection leaves fixed outside the middle rank: they keep their file and walk the
## block's depth to its other end. Those are the walkers. The oracle here reads them off the two
## pairings, before and after the reflection, and then follows the men by identity through a
## casualty. Each test also checks the oracle against the geometry: with every man standing where
## he stood before the re-square, a walker's slot is the block's full depth away from him and
## every other man's is within a close-up step of him.
##
## How a man reads as arced: with every body at the block's centre, halfway through any walk, the
## arc is at full strength, so a man is arced exactly when his slot is bent sideways off the plain
## pairing's slot.

## A slot bent sideways by more than this is arced. The arc at full strength moves a slot at
## least 1.5 file pitches (13.5 wu on foot here); float residue is under 0.001 wu.
const ARC_EPS := 0.01


func _killer() -> Unit:
	var k: Unit = Unit.new()
	k.max_soldiers = 10
	k.team = 1
	add_child_autofree(k)
	k.seed_sim_soldiers()
	return k


func _stand_on_slots(u: Unit) -> void:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


## A row-major block on 8 files, or the same men squared (60 and 61 men square onto 8 files).
func _make(count: int, square: bool) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	u.seed_sim_soldiers()
	if square:
		u.set_formation(Unit.FORMATION_SQUARE)
	_stand_on_slots(u)
	return u


func _pairing(u: Unit, square: bool) -> PackedInt32Array:
	var held: PackedInt32Array = u._sim_soldier_square_slot if square else u._sim_soldier_row_slot
	if held.size() == u.soldiers:
		return held.duplicate()
	return UnitFormation.identity_assignment(u.soldiers)


func _grid(u: Unit, square: bool, n: int) -> PackedVector2Array:
	if square:
		return UnitFormation.block_slots(n, u.formation_files(n), u.file_pitch_wu())
	return UnitFormation.slots(u, n)


## Settle an about-face, run the hold-ground re-square under a live reform hold, and return the
## walkers the reflection made, read off the pairings before and after it.
func _re_square(u: Unit, square: bool) -> Array:
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)
	var n: int = u.soldiers
	var files: int = u.formation_files(n)
	var before: PackedInt32Array = _pairing(u, square)
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	assert_not_null(u.active_leaf(), "precondition: the about-face leaf is still current")
	if u.active_leaf() == null:
		return []
	u.active_leaf().reform_timer = 1.0
	assert_true(u._reform_holding(), "precondition: the reform hold is on")
	var after: PackedInt32Array = _pairing(u, square)
	var ranks: int = UnitFormation.ranks_for(n, files)
	var walkers: Array = []
	for i in range(n):
		var r: int = after[i] / files
		if after[i] == before[i] and r != ranks - 1 - r:
			walkers.push_back(i)
	assert_gt(walkers.size(), 0, "precondition: the reflection leaves walkers")
	return walkers


## The walkers after the men at `dead` (indices before the casualty) fall, renumbered as the
## per-soldier arrays are.
func _survivors_of(walkers: Array, dead: Array) -> Array:
	var out: Array = []
	for w in walkers:
		if dead.has(w):
			continue
		var below: int = 0
		for d in dead:
			if d < w:
				below += 1
		out.push_back(w - below)
	return out


## The men whose slot the arcs bend, with every body at the block's centre.
func _arced(u: Unit, square: bool) -> Array:
	var n: int = u.soldiers
	var saved: PackedVector2Array = u._sim_soldier_pos.duplicate()
	for i in range(n):
		u._sim_soldier_pos[i] = u.position
	var arced_slots: PackedVector2Array = u.formation_slots(n, false)
	var plain: PackedVector2Array = UnitFormation.permute_slots(_grid(u, square, n),
			_pairing(u, square))
	u._sim_soldier_pos = saved
	var out: Array = []
	for i in range(n):
		if absf(arced_slots[i].x - plain[i].x) > ARC_EPS:
			out.push_back(i)
	return out


## The oracle against the geometry. `stood` is where each man stood before the re-square, indexed
## as the live arrays are now. In these fixtures the walkers hold the front rank and the rear rank,
## so a walker's slot is the block's whole depth, (ranks - 1) pitches, from where he stands. Any
## other man's slot is where he stands, or a close-up step from it: at most one rank pitch and half
## a file sideways, or a file pitch and half a rank. Half the depth span separates the two.
func _assert_walkers_walk(u: Unit, square: bool, stood: PackedVector2Array, walkers: Array) -> void:
	var n: int = u.soldiers
	var files: int = u.formation_files(n)
	var depth: float = u.file_pitch_wu() if square else u.rank_pitch_wu()
	var span: float = float(UnitFormation.ranks_for(n, files) - 1) * depth
	var slots: PackedVector2Array = u.soldier_world_slots(n)
	var far: Array = []
	for i in range(n):
		if stood[i].distance_to(slots[i]) > span * 0.5:
			far.push_back(i)
	assert_eq(far, walkers, "precondition: the oracle's walkers are the men whose slot is far off")


func _stood(u: Unit, dead: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(u._sim_soldier_pos.size()):
		if not dead.has(i):
			out.push_back(u._sim_soldier_pos[i])
	return out


func _reap(u: Unit, dead: Array) -> void:
	for i in dead:
		u._sim_soldier_hp[i] = 0.0
	SoldierMelee.reap(u, _killer())


## A squared block holds a pairing dealt from where its men stood when it formed, not the
## identity, so a man's index does not say whether the reflection left him on his own cell.
## Main read it by index and arced 7 men, 3 of them not walking, while missing a walker.
func test_a_square_re_square_arcs_exactly_its_walkers() -> void:
	var u := _make(60, true)
	assert_eq(u.formation_files(60), 8, "precondition: 60 men square onto 8 files")
	var walkers: Array = _re_square(u, true)
	assert_ne(u._sim_soldier_square_slot, UnitFormation.identity_assignment(60),
		"precondition: the square's pairing is not the identity")
	_assert_walkers_walk(u, true, _stood(u, []), walkers)
	assert_eq(_arced(u, true), walkers, "the arcs bend exactly the walkers")


## A casualty during the square's reform hold renumbers the square pairing (drop_slot_assignment),
## so neither an index read nor the fixed cells of the smaller grid's reflection name the walkers.
func test_a_square_casualty_during_the_hold_keeps_the_arcs_on_the_walkers() -> void:
	var u := _make(60, true)
	var walkers: Array = _re_square(u, true)
	_reap(u, [3])
	assert_eq(u.soldiers, 59, "precondition: the reap took the man")
	assert_eq(u.formation_files(59), 8, "precondition: the square keeps its 8 files")
	var left: Array = _survivors_of(walkers, [3])
	_assert_walkers_walk(u, true, _stood(u, []), left)
	assert_eq(_arced(u, true), left, "the arcs still bend exactly the walkers")


## A row-major casualty during the hold closes the pairing up after the reflection was composed.
## Read by the fixed cells of the smaller grid's reflection, the gate arced 11 men while 4 walked
## (60 men), and 4 while 12 walked (61 men).
func test_a_row_major_casualty_during_the_hold_keeps_the_arcs_on_the_walkers() -> void:
	for count in [60, 61]:
		var u := _make(count, false)
		var walkers: Array = _re_square(u, false)
		_reap(u, [3])
		assert_eq(u.soldiers, count - 1, "precondition: the reap took the man")
		var left: Array = _survivors_of(walkers, [3])
		_assert_walkers_walk(u, false, _stood(u, []), left)
		assert_eq(_arced(u, false), left,
			"%d men, one lost in the hold: the arcs bend exactly the walkers" % count)


## A regiment-path casualty (UnitCombat.take_casualties) during the hold: the body layer trims
## the tail men, and the next slot query closes the pairing up over them.
func test_a_regiment_path_casualty_during_the_hold_keeps_the_arcs_on_the_walkers() -> void:
	var u := _make(61, false)
	var walkers: Array = _re_square(u, false)
	var tail: Array = [58, 59, 60]
	u.soldiers -= 3
	u._sim_soldier_pos = u._sim_soldier_pos.slice(0, u.soldiers)
	var left: Array = _survivors_of(walkers, tail)
	assert_eq(_arced(u, false), left, "the arcs bend exactly the surviving walkers")


## A gain during the hold (an absorb appends men at the tail): the newcomers take the tail cells
## and walk to them from wherever they joined, not the block's depth, so they are not arced.
func test_an_absorb_during_the_hold_does_not_arc_the_newcomers() -> void:
	var u := _make(60, false)
	var walkers: Array = _re_square(u, false)
	var other: Unit = Unit.new()
	other.max_soldiers = 6
	add_child_autofree(other)
	other.position = Vector2(0.0, 200.0)
	other.facing = Vector2.DOWN
	other.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	other.seed_sim_soldiers()
	u.absorb(other)
	assert_eq(u.soldiers, 66, "precondition: the newcomers joined")
	# The body layer appends the newcomers' bodies on its next steps.
	for _k in range(3):
		SoldierBodies.step(u, 1.0 / 60.0)
	assert_eq(u._sim_soldier_pos.size(), 66, "precondition: the body layer holds them")
	assert_true(u._reform_holding(), "precondition: the reform hold is still on")
	assert_eq(_arced(u, false), walkers, "the arcs bend the walkers and no newcomer")


## A second hold-ground re-square composes the reflection again: the men it leaves on their own
## cells walk back, so the walker set is read afresh, not carried over.
func test_a_second_re_square_arcs_its_own_walkers() -> void:
	var u := _make(61, false)
	_re_square(u, false)
	_reap(u, [3])
	_stand_on_slots(u)
	var walkers: Array = _re_square(u, false)
	assert_eq(_arced(u, false), walkers, "the second re-square arcs its own walkers")


## The walker set rides the snapshot, so a restore mid re-square arcs the same men.
func test_the_walkers_survive_a_snapshot() -> void:
	var u := _make(61, false)
	var walkers: Array = _re_square(u, false)
	_reap(u, [3])
	var left: Array = _survivors_of(walkers, [3])
	var restored := Unit.new()
	add_child_autofree(restored)
	restored.apply_snapshot_dict(u.to_snapshot_dict())
	var leaf: Order = Order.new_about_face()
	leaf.reform_timer = 1.0
	restored.set_current_order(leaf)
	assert_true(restored._reform_holding(), "precondition: the restored block holds")
	assert_eq(_arced(restored, false), left, "the restored block arcs the same walkers")


## A later re-square that is not a depth reflection (a quarter-turn, here of a square, which keeps
## its own pairing through one) sends nobody walking the depth, so the walkers an earlier
## reflection recorded are dropped rather than arced again.
func test_a_later_quarter_turn_re_square_drops_the_walkers() -> void:
	var u := _make(60, true)
	_re_square(u, true)
	_stand_on_slots(u)
	u._formation_angle = PI * 0.5
	assert_true(u.reform_ranks(true), "precondition: the quarter fold re-squares")
	assert_true(u._reform_holding(), "precondition: the reform hold is still on")
	assert_eq(_arced(u, true), [], "nobody is arced")


## A square that re-pairs from where its men stand (here the freshness key is dropped, as a
## formation change leaves it) hands every man a cell near him, so nobody walks the depth.
func test_a_square_re_pair_from_the_bodies_drops_the_walkers() -> void:
	var u := _make(60, true)
	_re_square(u, true)
	u._square_slot_files = -1
	u.formation_slots(u.soldiers, false)
	assert_eq(u._square_slot_files, 8, "precondition: the square re-paired from the bodies")
	assert_eq(_arced(u, true), [], "nobody is arced")


## The walker rule on its own, called by name so this file loads on a tree without it. A 20-man
## block on 8 files has a full middle rank, which the reflection maps onto itself, so its men hold
## their ground; the front rank's middle four pair into the 4-man rear rank, which pairs back,
## and only the front rank's four outer men keep their cells and walk.
func test_the_middle_rank_holds_its_ground() -> void:
	var formation: Script = load("res://scripts/UnitFormation.gd")
	var found: bool = false
	for m in formation.get_script_method_list():
		if m["name"] == "depth_reflection_walkers":
			found = true
	assert_true(found, "UnitFormation.depth_reflection_walkers exists")
	if not found:
		return
	var flags: PackedByteArray = formation.call("depth_reflection_walkers",
			UnitFormation.identity_assignment(20), 8)
	var walkers: Array = []
	for i in range(flags.size()):
		if flags[i] != 0:
			walkers.push_back(i)
	assert_eq(walkers, [0, 1, 6, 7], "only the front rank's outer men walk")
