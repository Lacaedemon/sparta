extends GutTest
## A row-major block closes up over its casualties the way drilled men do: the men behind a
## fallen man step up in his file, and the rear rank fills the back of it.
##
## Cell c of a row-major grid sits in column c % files, so renumbering the cells behind a
## vacancy by one (the identity layout's index order, or the old pairing trim) sends every man
## behind it one column sideways, and each rank's first man to the far end of the rank ahead,
## through the block's centreline. These pin, as absolutes, how far any survivor's slot moves on
## a casualty and that none crosses the centreline (see _walk for the one step across the centre
## several casualties at once can force): for the identity layout and for held pairings, on the
## per-soldier (reap) path and the regiment path. The regiment-path walk tests also pass on main,
## whose regiment path never cascaded; they guard the pairing a reap now leaves held. The new
## UnitFormation functions are called by name (_formation_call), so this file loads on a tree
## that lacks them and its tests fail there by assertion.
##
## The per-casualty bound, from UnitFormation.close_up_slot_assignment: a survivor's slot moves
## at most one rank forward (d), one file sideways (p), or half a file sideways while stepping one
## rank forward, plus the half rank (d / 2) the grid re-centres by when it loses its last
## rear-rank man. The largest of those is max(sqrt(d^2 + (p/2)^2), sqrt(p^2 + (d/2)^2)); m
## casualties move a man at most m times that. The old renumbering moves a rank's first man
## (files - 1) pitches sideways and a rank forward.

const COUNT := 60
## A slot within this of the centreline is on it: grid positions are whole multiples of half a
## file pitch (9 wu on foot, 20 wu on the cavalry here), so only a man on the centre file or the centre
## of an odd rear rank sits this close, and he is on the centreline, not across it. Rotation
## residue is under 0.001 wu.
const ON_CENTRELINE := 0.01


func _make_foot(files: int = 8, count: int = COUNT) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = files
	u.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	u.seed_sim_soldiers()
	_stand_on_slots(u)
	return u


## A row-major cavalry squadron with the Cavalry loadout's pitches (1 m files, 3 m ranks).
func _make_cavalry(files: int, count: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.is_cavalry = true
	add_child_autofree(u)
	u.file_pitch = 1.0 * WorldScale.WU_PER_M
	u.rank_pitch = 3.0 * WorldScale.WU_PER_M
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = files
	u.seed_sim_soldiers()
	_stand_on_slots(u)
	return u


func _stand_on_slots(u: Unit) -> void:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


func _killer() -> Unit:
	var k: Unit = Unit.new()
	k.max_soldiers = 10
	k.team = 1
	add_child_autofree(k)
	k.seed_sim_soldiers()
	return k


## The largest distance one casualty moves a survivor's slot (see the file comment).
func _step_bound(u: Unit) -> float:
	var p: float = u.file_pitch_wu()
	var d: float = u.rank_pitch_wu()
	return maxf(sqrt(d * d + p * p * 0.25), sqrt(p * p + d * d * 0.25))


## The walk from `before` (each man's slot before the casualties, indexed as before them) to
## his slot now. `survivors[j]` is the old index of the man now at index j.
## - crossed: men whose slot moved from one side of the centreline to the other, each end more
##   than half a file pitch off it.
## - stepped: men whose slot moved from one side to the other with an end within half a pitch of
##   it: a step between the two cells either side of the centre. The crossed count leaves them
##   out because several losses at once can force such a step: each side of the new grid holds a
##   fixed number of cells, and every cell nearest the centre on an even frontage sits half a
##   pitch off it, so when the losses fall mostly on one side, a man beside the centre fills the
##   other. Each one's lateral move is returned in `stepped_by`, to be bounded by a pitch.
func _walk(u: Unit, before: PackedVector2Array, survivors: PackedInt32Array) -> Dictionary:
	var after: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var lateral: Vector2 = u.facing.orthogonal()
	var half: float = u.file_pitch_wu() * 0.5 + ON_CENTRELINE
	var farthest: float = 0.0
	var who: int = -1
	var crossed := PackedInt32Array()
	var stepped := PackedInt32Array()
	var stepped_by: float = 0.0
	for j in range(after.size()):
		var i: int = survivors[j]
		var dist: float = before[i].distance_to(after[j])
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
			stepped_by = maxf(stepped_by, absf(b - a))
	return {"farthest": farthest, "who": who, "crossed": crossed, "stepped": stepped,
			"stepped_by": stepped_by}


func _assert_closed_up(u: Unit, t: Dictionary, casualties: int, what: String) -> void:
	var bound: float = _step_bound(u) * casualties + 0.01
	assert_eq(PackedInt32Array(t["crossed"]).size(), 0,
		"%s: men %s cross the centreline" % [what, t["crossed"]])
	assert_lt(float(t["stepped_by"]), u.file_pitch_wu() + 0.01,
		"%s: men %s step across the centre by up to %.1f wu (pitch %.1f)"
		% [what, t["stepped"], float(t["stepped_by"]), u.file_pitch_wu()])
	assert_lt(float(t["farthest"]), bound,
		"%s: man %d's slot moves %.1f wu (bound %.1f for %d casualties)"
		% [what, int(t["who"]), float(t["farthest"]), bound, casualties])


## Call UnitFormation's static `method` by name, so this file still loads on a tree without it
## (the merge-base) and every other test there fails by its own assertion. Fails the test, and
## returns an empty array, when the method is missing.
func _formation_call(method: String, args: Array) -> PackedInt32Array:
	var formation: Script = load("res://scripts/UnitFormation.gd")
	for m in formation.get_script_method_list():
		if m["name"] == method:
			return formation.callv(method, args)
	fail_test("UnitFormation.%s does not exist on this tree" % method)
	return PackedInt32Array()


## The longest walk, cell to cell, when the men holding `perm` on a `block_slots(n, files)` grid
## lose the men at `dead` and are given `out` on the grid of the survivors.
func _cell_walk(perm: PackedInt32Array, dead: Array, out: PackedInt32Array, files: int,
		p: float, d: float) -> float:
	var n: int = perm.size()
	var old: PackedVector2Array = UnitFormation.block_slots(n, files, p, d)
	var grid: PackedVector2Array = UnitFormation.block_slots(n - dead.size(), files, p, d)
	var longest: float = 0.0
	var j: int = 0
	for i in range(n):
		if dead.has(i):
			continue
		if j < out.size():
			longest = maxf(longest, old[perm[i]].distance_to(grid[out[j]]))
		j += 1
	return longest


## The old indices that survive `dead` (each removed from the arrays, as reap removes them).
func _survivors(n: int, dead: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(n):
		if not dead.has(i):
			out.push_back(i)
	return out


func _reap(u: Unit, dead: Array) -> void:
	for i in dead:
		u._sim_soldier_hp[i] = 0.0
	SoldierMelee.reap(u, _killer())


## A man killed mid-block in an identity layout (rank 2, file 1 of a 60-man block on 8 files).
## Index order sent each rank's first man behind him 7 pitches across the block.
func test_a_mid_rank_casualty_closes_up_his_file() -> void:
	var u := _make_foot(8)
	assert_eq(u._sim_soldier_row_slot.size(), 0, "precondition: the identity layout")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	_reap(u, [17])
	assert_eq(u.soldiers, COUNT - 1, "precondition: reap took the man")
	_assert_closed_up(u, _walk(u, before, _survivors(COUNT, [17])), 1, "mid-rank casualty")


## The front rank takes the casualty, on a cavalry squadron (always row major): 40 mounts on 7
## files, so a 5-mount short rear rank fills the back of the file.
func test_a_front_rank_casualty_closes_up_his_file() -> void:
	for gap in [0, 3, 6]:
		var u := _make_cavalry(7, 40)
		assert_false(u._effective_file_major_reform(), "precondition: cavalry is row major")
		var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		_reap(u, [gap])
		_assert_closed_up(u, _walk(u, before, _survivors(40, [gap])), 1,
				"front-rank casualty in file %d" % gap)


## A volley takes several men in one tick, the nearest to the archers: the front rank.
func test_several_casualties_in_one_volley_close_up_their_files() -> void:
	for casualties in [2, 5]:
		var u := _make_foot(8)
		var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		var origin: Vector2 = u.position + u.facing * 400.0
		var dead: Array = Array(SoldierMelee.ranged_victims(u, origin, casualties))
		SoldierMelee.apply_ranged_casualties(u, origin, _killer(), casualties, 1.0)
		assert_eq(u.soldiers, COUNT - casualties, "precondition: the volley took %d" % casualties)
		_assert_closed_up(u, _walk(u, before, _survivors(COUNT, dead)), casualties,
				"%d casualties in one volley" % casualties)


## A whole flank file lost at once, as a volley from the side takes it. Closing each loss up in
## turn would send the men who step into the back of that file up it again on every later loss;
## the deal by lateral file shifts the ranks one file over instead. These are regression pins
## computed from the functions, not derived limits: the block's longest walk must not exceed the
## deal's own longest walk from the cells the men held, and closing up in turn alone (each loss
## through close_up_slot_assignment) must walk further by more than the quarter-pitch margin
## close_up_slot_assignment_over takes before preferring the deal. Measured here: 126.5 wu
## dealt, against 421.9 wu closed up in turn.
func test_a_flank_file_lost_at_once_shifts_ranks_over() -> void:
	var u := _make_cavalry(7, 40)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var dead: Array = [0, 7, 14, 21, 28]
	_reap(u, dead)
	var t: Dictionary = _walk(u, before, _survivors(40, dead))
	_assert_closed_up(u, t, dead.size(), "a flank file lost at once")
	var p: float = u.file_pitch_wu()
	var d: float = u.rank_pitch_wu()
	var files: int = 7
	var identity: PackedInt32Array = UnitFormation.identity_assignment(40)
	var old: PackedVector2Array = UnitFormation.block_slots(40, files, p, d)
	var start := PackedVector2Array()
	for i in _survivors(40, dead):
		start.push_back(old[i])
	var dealt: PackedInt32Array = UnitFormation.pair_slots_rear_rank_first(start,
			UnitFormation.block_slots(40 - dead.size(), files, p, d), files, d * 0.5, p * 0.5)
	var closed: PackedInt32Array = identity
	var order: Array = dead.duplicate()
	order.reverse()
	for i in order:
		closed = _formation_call("close_up_slot_assignment", [closed, i, files])
	var dealt_walk: float = _cell_walk(identity, dead, dealt, files, p, d)
	var closed_walk: float = _cell_walk(identity, dead, closed, files, p, d)
	assert_gt(closed_walk, dealt_walk + p * 0.25,
		"precondition: closing up in turn walks %.1f wu, the deal %.1f" % [closed_walk, dealt_walk])
	assert_lt(float(t["farthest"]), dealt_walk + 0.01,
		"the longest walk %.1f wu is no longer than the deal's %.1f (man %d)"
		% [float(t["farthest"]), dealt_walk, int(t["who"])])


## Attrition: ten volleys of three, each measured against the block as it stood before it, so
## the close-up holds as the casualties compound rather than only from a full block.
func test_volley_after_volley_keeps_closing_up() -> void:
	var u := _make_cavalry(7, 40)
	var origin: Vector2 = u.position + u.facing * 600.0
	for volley in range(10):
		_stand_on_slots(u)
		var n: int = u.soldiers
		var before: PackedVector2Array = u.soldier_world_slots(n)
		var dead: Array = Array(SoldierMelee.ranged_victims(u, origin, 3))
		SoldierMelee.apply_ranged_casualties(u, origin, _killer(), 3, 1.0)
		if u.soldiers != n - 3:
			break
		_assert_closed_up(u, _walk(u, before, _survivors(n, dead)), 3, "volley %d" % volley)


## A held pairing dealt by a resize (8 files to 7) closes up the same way. The old trim kept the
## pairing a permutation but renumbered every cell behind the vacancy, the same cascade.
func test_a_casualty_under_a_dealt_pairing_closes_up_his_file() -> void:
	var u := _make_foot(8)
	u.set_frontage(7)
	_stand_on_slots(u)
	assert_eq(u._sim_soldier_row_slot.size(), COUNT, "precondition: a dealt pairing is held")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	# The man on the second rank's second cell, whoever the deal put there.
	var victim: int = Array(u._sim_soldier_row_slot).find(7 + 1)
	_reap(u, [victim])
	_assert_closed_up(u, _walk(u, before, _survivors(COUNT, [victim])), 1,
			"casualty under a dealt pairing")


## A hold-ground re-square leaves the depth reflection as the pairing; a front-rank casualty
## closes up over it as well.
func test_a_casualty_after_a_hold_ground_re_square_closes_up_his_file() -> void:
	var u := _make_foot(8)
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	_stand_on_slots(u)
	assert_eq(u._sim_soldier_row_slot.size(), COUNT, "precondition: the reflection is held")
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var victim: int = Array(u._sim_soldier_row_slot).find(2)
	_reap(u, [victim])
	_assert_closed_up(u, _walk(u, before, _survivors(COUNT, [victim])), 1,
			"casualty after a hold-ground re-square")


## A regiment-path casualty (UnitCombat.take_casualties) under a held pairing: the body layer
## trims its tail, so the tail men leave, wherever the pairing put them. Under the hold-ground
## reflection the tail men hold the front rank's centre cells, so this is a front-rank loss.
func test_a_regiment_path_casualty_under_a_held_pairing_closes_up() -> void:
	var u := _make_foot(8)
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	_stand_on_slots(u)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u.soldiers -= 3
	var t: Dictionary = _walk(u, before, _survivors(COUNT, [COUNT - 3, COUNT - 2, COUNT - 1]))
	assert_eq(u._sim_soldier_row_slot.size(), u.soldiers, "the pairing covers the survivors")
	_assert_closed_up(u, t, 3, "three regiment-path casualties under a held pairing")


## The tail men can hold any cells under a held pairing; here the last two men hold the front
## rank's two left-hand cells (the pairing traded them with the first two). Dealing the survivors
## again from where they stand fills the short files from the next file over, front men first.
func test_a_regiment_path_casualty_from_the_front_flank_closes_up() -> void:
	for make in [_make_foot.bind(8, COUNT), _make_cavalry.bind(8, COUNT)]:
		var u: Unit = make.call()
		var files: int = u.formation_files(u.soldiers)
		var pairing: PackedInt32Array = UnitFormation.identity_assignment(COUNT)
		pairing[0] = COUNT - 1
		pairing[COUNT - 1] = 0
		pairing[1] = COUNT - 2
		pairing[COUNT - 2] = 1
		u._sim_soldier_row_slot = pairing
		u._row_slot_files = files
		u._row_slot_dealt = true
		_stand_on_slots(u)
		var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		u.soldiers -= 2
		_assert_closed_up(u, _walk(u, before, _survivors(COUNT, [COUNT - 2, COUNT - 1])), 2,
				"cavalry %s, two regiment-path casualties from the front flank" % u.is_cavalry)


## In a press the bodies stand off their slots. A regiment-path casualty under a held pairing
## still closes up over the tail men from the cells, not from where the jostled men stand, so
## no survivor's slot moves further than the close-up itself moves it.
func test_a_regiment_path_casualty_in_a_press_closes_up_from_the_cells() -> void:
	for amplitude in [0.3, 0.45]:
		var u := _make_foot(8)
		u.set_frontage(7)
		_stand_on_slots(u)
		assert_eq(u._sim_soldier_row_slot.size(), COUNT, "precondition: a dealt pairing is held")
		var p: float = u.file_pitch_wu()
		var d: float = u.rank_pitch_wu()
		var lateral: Vector2 = u.facing.orthogonal()
		for i in range(u._sim_soldier_pos.size()):
			u._sim_soldier_pos[i] += lateral * sin(i * 1.7) * amplitude * p \
					+ u.facing * cos(i * 2.3) * amplitude * d
		var n: int = u.soldiers
		var before: PackedVector2Array = u.soldier_world_slots(n)
		var held: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
		var files: int = u.formation_files(n)
		u.soldiers -= 2
		# The two outcomes the branch chooses between: closing up from the cells, or dealing
		# again from where the pressed bodies stand (the deal a file-count change makes).
		var closed: PackedInt32Array = _formation_call("close_up_slot_assignment_over",
				[held, PackedInt32Array([n - 2, n - 1]), files, p, d])
		var dealt: PackedInt32Array = UnitFormation.pair_slots_rear_rank_first(
				u._slot_frame_positions(u.soldiers), UnitFormation.slots(u, u.soldiers), files,
				d * 0.5, p * 0.5)
		assert_ne(dealt, closed, "precondition: a deal from the pressed bodies would differ")
		_assert_closed_up(u, _walk(u, before, _survivors(n, [n - 2, n - 1])), 2,
				"two regiment-path casualties, bodies off their slots by %.2f of a pitch" % amplitude)
		assert_eq(u._sim_soldier_row_slot, closed,
			"amplitude %.2f: the pairing is the close-up from the cells, not a deal" % amplitude)


## A front-rank reap leaves the closed-up pairing held; a hold-ground re-square then composes the
## depth reflection onto it. The traverse flank arcs must bend exactly the men the reflection
## leaves on their own cells (the walkers, who cross the block's depth), not the men whose index
## happens to equal their cell. With every body at the block's centre depth, halfway through any
## walk, the arc is at full strength, so a man is arced exactly when his slot is bent sideways.
## Read by index instead, the gate missed six walkers here (measured on 91c5b0b8).
func test_a_hold_ground_re_square_after_a_reap_arcs_exactly_its_walkers() -> void:
	var u := _make_foot(8)
	_reap(u, [3])
	_stand_on_slots(u)
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)
	var n: int = u.soldiers
	var base: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	assert_eq(base.size(), n, "precondition: the reap left a pairing held")
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	# The hold a re-square runs under (the arcs bend paths only while it runs).
	assert_not_null(u.active_leaf(), "precondition: the about-face leaf is still current")
	if u.active_leaf() == null:
		return
	u.active_leaf().reform_timer = 1.0
	assert_true(u._reform_holding(), "precondition: the reform hold is on")
	assert_false(u._row_slot_dealt, "precondition: the held pairing is a reflection")
	var after: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	var files: int = u.formation_files(n)
	var ranks: int = UnitFormation.ranks_for(n, files)
	var walkers: Array = []
	for i in range(n):
		var r: int = after[i] / files
		if after[i] == base[i] and r != ranks - 1 - r:
			walkers.push_back(i)
	assert_gt(walkers.size(), 0, "precondition: the reflection leaves walkers")
	for i in range(n):
		u._sim_soldier_pos[i] = u.position
	var arced_slots: PackedVector2Array = u.formation_slots(n, false)
	var plain: PackedVector2Array = UnitFormation.permute_slots(UnitFormation.slots(u, n), after)
	var arced: Array = []
	for i in range(n):
		if absf(arced_slots[i].x - plain[i].x) > 0.01:
			arced.push_back(i)
	assert_eq(arced, walkers, "the arcs bend exactly the walkers")


## A gain after a reap: an absorb appends men at the tail. The men already held keep their
## cells, and the newcomers take the tail cells, as the identity layout gives them, rather than
## the whole block being dealt again from where it stands.
func test_an_absorb_after_a_reap_gives_the_newcomers_the_tail_cells() -> void:
	var u := _make_foot(8)
	_reap(u, [17])
	_stand_on_slots(u)
	var held: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	var n: int = u.soldiers
	assert_eq(held.size(), n, "precondition: the reap left a pairing held")
	var other: Unit = Unit.new()
	other.max_soldiers = 10
	add_child_autofree(other)
	other.position = Vector2(0.0, 200.0)
	other.facing = Vector2.DOWN
	other.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	other.seed_sim_soldiers()
	u.absorb(other)
	assert_eq(u.soldiers, n + 10, "precondition: the newcomers joined")
	for _k in range(3):
		SoldierBodies.step(u, 1.0 / 60.0)
	assert_eq(u._sim_soldier_pos.size(), u.soldiers, "precondition: the body layer holds them")
	var now: PackedInt32Array = u._sim_soldier_row_slot
	assert_eq(now.size(), u.soldiers, "the pairing covers the whole block")
	assert_eq(now.slice(0, n), held, "every man already held keeps his cell")
	for k in range(10):
		assert_eq(now[n + k], n + k, "newcomer %d takes tail cell %d" % [k, n + k])


## A pending row-major rebuild worked out from the cells (a close-up over a regiment-path loss)
## still counts as a rebuild (_slot_deal_pending, so reform_ranks skips its slot capture), but
## not as a deal from the bodies (_slot_body_deal_pending). A file-count change is both.
func test_a_pending_close_up_is_a_rebuild_but_not_a_body_deal() -> void:
	var u := _make_foot(8)
	_reap(u, [17])
	_stand_on_slots(u)
	var files: int = u.formation_files(u.soldiers)
	u.soldiers -= 2
	if not u.has_method("_slot_body_deal_pending"):
		fail_test("Unit._slot_body_deal_pending does not exist on this tree")
		return
	assert_true(u._slot_deal_pending(u.soldiers, files), "a pending close-up is a rebuild")
	assert_false(u.call("_slot_body_deal_pending", u.soldiers, files),
		"a pending close-up reads no body")
	u.formation_slots(u.soldiers)
	u.frontage_override = 7   # no query yet, so the deal stays pending
	var narrower: int = u.formation_files(u.soldiers)
	assert_true(u._slot_deal_pending(u.soldiers, narrower), "a file-count change is a rebuild")
	assert_true(u.call("_slot_body_deal_pending", u.soldiers, narrower),
		"and a deal from the bodies")


## Once a reap has held the identity layout, a later regiment-path casualty closes up over the
## tail men as the identity layout did, rather than dealing the block again from the bodies.
func test_a_regiment_path_casualty_after_a_reap_closes_up() -> void:
	var u := _make_foot(8)
	_reap(u, [17])
	_stand_on_slots(u)
	var n: int = u.soldiers
	var before: PackedVector2Array = u.soldier_world_slots(n)
	u.soldiers -= 4
	_assert_closed_up(u, _walk(u, before, _survivors(n, [n - 4, n - 3, n - 2, n - 1])), 4,
			"four regiment-path casualties after a reap")


## The close-up itself, over every shape and every casualty: the result pairs the survivors onto
## the smaller grid one cell each, and no cell's man moves past the bound or across the
## centreline. Cell positions do not depend on who holds them, so the identity pairing covers
## every held pairing too.
func test_close_up_slot_assignment_on_every_shape() -> void:
	var p: float = 18.0
	var d: float = 24.0
	var bound: float = maxf(sqrt(d * d + p * p * 0.25), sqrt(p * p + d * d * 0.25)) + 0.001
	if _formation_call("close_up_slot_assignment", [PackedInt32Array([0, 1]), 0, 1]).is_empty():
		return
	var worst: float = 0.0
	var bad: Array = []
	for files in range(1, 10):
		for n in range(2, 41):
			var old: PackedVector2Array = UnitFormation.block_slots(n, files, p, d)
			var grid: PackedVector2Array = UnitFormation.block_slots(n - 1, files, p, d)
			var perm: PackedInt32Array = UnitFormation.identity_assignment(n)
			for index in range(n):
				var out: PackedInt32Array = _formation_call("close_up_slot_assignment",
						[perm, index, files])
				var seen := {}
				for c in out:
					seen[c] = true
				if out.size() != n - 1 or seen.size() != n - 1 or not seen.has(0) \
						or not seen.has(n - 2):
					bad.push_back("not a pairing: n %d files %d index %d" % [n, files, index])
					continue
				var j: int = 0
				for i in range(n):
					if i == index:
						continue
					var a: Vector2 = old[i]
					var b: Vector2 = grid[out[j]]
					worst = maxf(worst, a.distance_to(b))
					if a.distance_to(b) > bound:
						bad.push_back("n %d files %d index %d: cell %d moves %.1f"
								% [n, files, index, i, a.distance_to(b)])
					if a.x * b.x < 0.0 and absf(a.x) > ON_CENTRELINE and absf(b.x) > ON_CENTRELINE:
						bad.push_back("n %d files %d index %d: cell %d crosses" % [n, files, index, i])
					j += 1
	assert_eq(bad.size(), 0, "%d failures, first %s" % [bad.size(), str(bad.slice(0, 3))])
	assert_lt(worst, bound, "the worst move %.2f is within the bound %.2f" % [worst, bound])


## A rear-rank loss is the plain renumbering: the rank keeps its order and re-centres.
func test_a_rear_rank_loss_keeps_the_rear_ranks_order() -> void:
	var perm: PackedInt32Array = UnitFormation.identity_assignment(60)
	assert_eq(_formation_call("close_up_slot_assignment", [perm, 57, 8]),
			UnitFormation.drop_slot_assignment(perm, 57), "a rear-rank loss renumbers the rank")
	assert_eq(_formation_call("close_up_slot_assignment", [perm, -1, 8]), perm,
			"out of range is a no-op")
