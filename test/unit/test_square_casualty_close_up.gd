extends GutTest
## A squared block closes up over its casualties the way a row-major block does: the men behind
## a fallen man step up in his file, the rear rank fills the back of it, and everyone else keeps
## his cell.
##
## The square grid is block_slots(n, square_files(n), pitch), a row-major grid whose ranks sit a
## file pitch apart, so its cell c sits in column c % files. Renumbering every cell behind a
## vacancy by one (UnitFormation.drop_slot_assignment) therefore sends every man behind it one
## column sideways, and each rank's first man to the far end of the rank ahead, through the
## block's centreline. These pin, as absolutes, how far any survivor's slot moves on a casualty,
## that none crosses the centreline, and which men move at all: on the per-soldier (reap) path,
## on the regiment path, and for a gain (an absorb) at an unchanged file count.
##
## The per-casualty bound is close_up_slot_assignment's with the rank pitch d equal to the file
## pitch p: max(sqrt(d^2 + (p/2)^2), sqrt(p^2 + (d/2)^2)) = p * sqrt(1.25); m casualties move a
## man at most m times that. The old renumbering moves a rank's first man (files - 1) pitches
## sideways and a rank forward.

## A slot within this of the centreline is on it: grid positions are whole multiples of half a
## file pitch, so only a man on the centre file or the centre of an odd rear rank sits this
## close. Rotation residue is under 0.001 wu.
const ON_CENTRELINE := 0.01
## A slot that moved less than this has not moved.
const STILL := 0.01


func _make_square(count: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.set_formation(Unit.FORMATION_SQUARE)
	_stand_on_slots(u)
	return u


func _stand_on_slots(u: Unit) -> void:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


func _step_bound(u: Unit) -> float:
	var p: float = u.file_pitch_wu()
	return p * sqrt(1.25)


func _survivors(n: int, dead: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(n):
		if not dead.has(i):
			out.push_back(i)
	return out


func _reap(u: Unit, dead: Array) -> void:
	for i in dead:
		u._sim_soldier_hp[i] = 0.0
	SoldierMelee.reap(u, null)


## The walk from `before` (each man's slot before the casualties, indexed as before them) to his
## slot now; `survivors[j]` is the old index of the man now at index j. `crossed` lists the men
## whose slot moved across the centreline with each end more than half a pitch off it; `stepped`
## those that moved across it with an end within half a pitch (a step between the two cells
## either side of the centre, which losses falling mostly on one side can force); `moved` every
## man whose slot moved at all.
func _walk(u: Unit, before: PackedVector2Array, survivors: PackedInt32Array) -> Dictionary:
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var lateral: Vector2 = u.facing.orthogonal()
	var half: float = u.file_pitch_wu() * 0.5 + ON_CENTRELINE
	var farthest: float = 0.0
	var who: int = -1
	var crossed := PackedInt32Array()
	var stepped := PackedInt32Array()
	var moved := PackedInt32Array()
	for j in range(after.size()):
		var i: int = survivors[j]
		var dist: float = before[i].distance_to(after[j])
		if dist > STILL:
			moved.push_back(i)
		if dist > farthest:
			farthest = dist
			who = i
		var a: float = (before[i] - u.position).dot(lateral)
		var b: float = (after[j] - u.position).dot(lateral)
		if a * b >= 0.0 or absf(a) <= ON_CENTRELINE or absf(b) <= ON_CENTRELINE:
			continue
		if absf(a) > half and absf(b) > half:
			crossed.push_back(i)
		else:
			stepped.push_back(i)
	return {"farthest": farthest, "who": who, "crossed": crossed, "stepped": stepped,
			"moved": moved}


func _assert_closed_up(u: Unit, t: Dictionary, casualties: int, what: String) -> void:
	var bound: float = _step_bound(u) * casualties + 0.01
	gut.p("%s: farthest %.1f wu (man %d), moved %s, crossed %s"
			% [what, float(t["farthest"]), int(t["who"]), t["moved"], t["crossed"]])
	assert_eq(PackedInt32Array(t["crossed"]).size(), 0,
		"%s: men %s cross the centreline" % [what, t["crossed"]])
	assert_lt(float(t["farthest"]), bound,
		"%s: man %d's slot moves %.1f wu (bound %.1f for %d casualties)"
		% [what, int(t["who"]), float(t["farthest"]), bound, casualties])


## One reap on a 60- and a 61-man square (8 files: 7 full ranks and a rear rank of 4 or 5), at a
## front-rank and a mid-block man. Only the dead man's file, the last full rank and the rear rank
## may move: the men behind him step up his file, and the last two ranks fill its back. Every
## other man keeps his slot exactly.
func test_one_casualty_moves_only_his_file_and_the_back_of_the_block() -> void:
	for count in [60, 61]:
		for victim in [3, 17, 0, 30]:
			var u := _make_square(count)
			var files: int = u.formation_files(count)
			assert_eq(files, 8, "precondition: square_files(%d) is 8" % count)
			assert_eq(u._sim_soldier_square_slot.size(), count, "precondition: the pairing is held")
			var cells: PackedInt32Array = u._sim_soldier_square_slot.duplicate()
			var before: PackedVector2Array = u.soldier_world_slots(count)
			_reap(u, [victim])
			assert_eq(u.soldiers, count - 1, "precondition: reap took the man")
			var what: String = "%d men, casualty %d" % [count, victim]
			var t: Dictionary = _walk(u, before, _survivors(count, [victim]))
			_assert_closed_up(u, t, 1, what)
			var gap_file: int = cells[victim] % files
			var last_full: int = count / files - 1
			var strays: Array = []
			for i in t["moved"]:
				var c: int = cells[i]
				if c % files != gap_file and c / files < last_full:
					strays.push_back(i)
			assert_eq(strays, [], "%s: men outside his file and the back ranks moved" % what)


## A volley takes several men in one tick. Each closes up his own file; together they move no
## man more than the sum of the single bounds, and none across the centreline.
func test_a_volley_closes_up_each_file() -> void:
	for dead in [[0, 1, 2], [3, 17, 40], [5, 13, 21, 29]]:
		var u := _make_square(60)
		var before: PackedVector2Array = u.soldier_world_slots(60)
		_reap(u, dead)
		_assert_closed_up(u, _walk(u, before, _survivors(60, dead)), dead.size(),
				"volley %s" % [dead])


## A regiment-path casualty (UnitCombat.take_casualties) never says who died: the body layer
## trims its tail, so the tail men leave. The pairing closes up over them from the cells rather
## than dealing the whole block again from where it stands.
func test_a_regiment_path_casualty_closes_up_over_the_tail() -> void:
	var u := _make_square(60)
	var before: PackedVector2Array = u.soldier_world_slots(60)
	u.soldiers -= 3
	var t: Dictionary = _walk(u, before, _survivors(60, [57, 58, 59]))
	assert_eq(u._sim_soldier_square_slot.size(), u.soldiers, "the pairing covers the survivors")
	_assert_closed_up(u, t, 3, "three regiment-path casualties")


## A hold-ground about-face re-square records the men it sends walking the block's depth, and
## the traverse arcs bend exactly those. A regiment-path loss mid re-square closes the pairing
## up rather than re-pairing it, so the walkers it recorded keep walking, and only they arc.
func test_a_regiment_path_loss_mid_re_square_keeps_the_walkers() -> void:
	var u := _make_square(60)
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	assert_not_null(u.active_leaf(), "precondition: the about-face leaf is still current")
	if u.active_leaf() == null:
		return
	u.active_leaf().reform_timer = 1.0
	assert_true(u._reform_holding(), "precondition: the reform hold is on")
	var flags: PackedByteArray = u._sim_soldier_reflect_walker.duplicate()
	assert_eq(flags.size(), 60, "precondition: the reflection recorded its walkers")
	u.soldiers -= 1
	var n: int = u.soldiers
	u.formation_slots(n, false, false)
	u._sim_soldier_pos.resize(n)
	assert_eq(u._sim_soldier_square_slot.size(), n, "the pairing covers the survivors")
	assert_eq(u._sim_soldier_reflect_walker, flags.slice(0, n),
		"the survivors keep the walker flags the reflection recorded")
	var walkers: Array = []
	for i in range(n):
		if flags[i] != 0:
			walkers.push_back(i)
	assert_gt(walkers.size(), 0, "precondition: the reflection leaves walkers")
	for i in range(n):
		u._sim_soldier_pos[i] = u.position
	var arced_slots: PackedVector2Array = u.formation_slots(n, false)
	var plain: PackedVector2Array = UnitFormation.permute_slots(UnitFormation.block_slots(
			n, u.formation_files(n), u.file_pitch_wu()), u._sim_soldier_square_slot)
	var arced: Array = []
	for i in range(n):
		if absf(arced_slots[i].x - plain[i].x) > 0.01:
			arced.push_back(i)
	gut.p("walkers %s, arced %s" % [walkers, arced])
	assert_eq(arced, walkers, "the arcs bend exactly the walkers")


## A gain at an unchanged file count: an absorb appends men at the tail. The men already held
## keep their cells and the newcomers take the tail cells, rather than the whole block being
## dealt again from where it stands.
func test_an_absorb_gives_the_newcomers_the_tail_cells() -> void:
	var u := _make_square(60)
	_reap(u, [17])
	_stand_on_slots(u)
	var held: PackedInt32Array = u._sim_soldier_square_slot.duplicate()
	var n: int = u.soldiers
	assert_eq(held.size(), n, "precondition: the pairing is held")
	var other: Unit = Unit.new()
	other.max_soldiers = 4
	add_child_autofree(other)
	other.position = Vector2(0.0, 200.0)
	other.facing = Vector2.DOWN
	other.seed_sim_soldiers()
	u.absorb(other)
	assert_eq(u.soldiers, n + 4, "precondition: the newcomers joined")
	assert_eq(u.formation_files(u.soldiers), u.formation_files(n),
		"precondition: the file count is unchanged")
	for _k in range(3):
		SoldierBodies.step(u, 1.0 / 60.0)
	assert_eq(u._sim_soldier_pos.size(), u.soldiers, "precondition: the body layer holds them")
	var now: PackedInt32Array = u._sim_soldier_square_slot
	assert_eq(now.size(), u.soldiers, "the pairing covers the whole block")
	assert_eq(now.slice(0, n), held, "every man already held keeps his cell")
	for k in range(4):
		assert_eq(now[n + k], n + k, "newcomer %d takes tail cell %d" % [k, n + k])


## A loss that shrinks the file count (50 men on 8 files to 49 on 7) has no close-up: the grid
## itself changes shape, so the pairing is dealt again from where the men stand, a permutation
## onto the new grid.
func test_a_loss_across_a_file_count_change_deals_again() -> void:
	var u := _make_square(50)
	assert_eq(u.formation_files(50), 8, "precondition: 8 files")
	_reap(u, [10])
	assert_eq(u.formation_files(u.soldiers), 7, "precondition: 7 files")
	u.formation_slots(u.soldiers)
	assert_eq(u._square_slot_files, 7, "the pairing is dealt for the new file count")
	var seen := {}
	for c in u._sim_soldier_square_slot:
		seen[c] = true
	assert_eq(seen.size(), u.soldiers, "the deal is a permutation of the new grid")
