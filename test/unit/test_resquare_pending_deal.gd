extends GutTest
## A hold-ground about-face re-square over an assignment that is out of step with its grid (a
## regiment-path casualty, or a file-count change, that no slot query has laid out yet).
##
## reform_ranks must deal such an assignment from the bodies only AFTER it arms the depth mirror,
## or the reflection is composed onto a deal made in the folded frame and walks men through the
## block. And the re-square must still keep its walkers out of the anchor coupling, or the anchor
## drags back after them as it did before the walker flags existed.

const DT := 1.0 / 60.0


## A bare foot block facing down the screen, every body on its slot.
func _make(count: int, files: int, row_major: bool) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = files
	u.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR if row_major \
			else Unit.ReformMode.FILE_MAJOR
	u.seed_sim_soldiers()
	_stand_on_slots(u)
	return u


func _stand_on_slots(u: Unit) -> void:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


## Settle an about-face drill the way a completed ABOUT_FACE leaf does, every body on its slot.
func _settle_about_face(u: Unit) -> void:
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)
	u.set_current_order(null)


## Per man, how far his new slot lies from where he stood, over the men both arrays cover.
func _walks(u: Unit, bodies: PackedVector2Array) -> PackedFloat32Array:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var out := PackedFloat32Array()
	for i in range(mini(bodies.size(), slots.size())):
		out.push_back(bodies[i].distance_to(slots[i]))
	return out


## A squared block's regiment-path casualty after its about-face: the square pairing is out of
## step (57 men on a 60-man pairing, files unchanged), so the re-square deals it from the
## bodies. Dealt after the mirror, as on main, no man walks more than half the block's depth
## (the farthest walks exactly that, 31.5 wu, and 478 wu in all). Dealt before it, with the
## reflection composed on top, the farthest man walked the block's whole depth, 63.6 wu (695 wu
## in all).
func test_a_square_casualty_before_the_resquare_sends_no_man_through_the_block() -> void:
	var u := _make(60, 8, false)
	u.set_formation(Unit.FORMATION_SQUARE)
	_stand_on_slots(u)
	_settle_about_face(u)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	u.soldiers -= 3
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	var files: int = u.formation_files(u.soldiers)
	var half_depth: float = float(UnitFormation.ranks_for(u.soldiers, files) - 1) \
			* u.rank_pitch_wu() * 0.5
	var farthest: float = 0.0
	for w in _walks(u, bodies):
		farthest = maxf(farthest, w)
	assert_lt(farthest, half_depth + 0.01,
		"the farthest man walks %.1f wu (half the block's depth %.1f)" % [farthest, half_depth])


## A row-major block with a held pairing, about-faced again, takes a regiment-path casualty the
## same tick its turn settles, so the re-square deals its pairing from the bodies. The walkers
## must still stay out of the coupling: run the body layer and the coupling and the anchor holds.
## Skipping the walker flags in this case dragged it 7.58 wu.
func test_a_pending_row_deal_resquare_keeps_the_anchor_in_place() -> void:
	var u := _make(46, 10, true)
	_settle_about_face(u)
	assert_true(u.reform_ranks(true), "precondition: the first re-square")
	_stand_on_slots(u)
	_settle_about_face(u)
	u.soldiers -= 1   # a regiment-path casualty: the pairing is now one man long
	assert_true(u._row_slot_deal_pending(u.soldiers, u.formation_files(u.soldiers)),
		"precondition: the row deal is pending")
	var start: Vector2 = u.position
	# The re-square that ends an in-place turn, as _finish_order_turn makes it.
	assert_true(u.reform_ranks(true, true), "precondition: the about-face fold re-squares")
	assert_false(u._couple_transit.is_empty(), "the re-square flagged its walkers")
	var worst: float = 0.0
	for _i in range(300):
		SoldierBodies.step(u, DT)
		SoldierBodies.couple(u, DT)
		worst = maxf(worst, u.position.distance_to(start))
	assert_lt(worst, Unit.REFORM_SETTLE_EPS,
		"the anchor held through the re-square (worst %.3f wu)" % worst)


## A rally re-square over the same pending deal (a casualty in the rally frame): the block is
## still braking, every man 20 wu ahead of his slot, so where the men stand says nothing about
## who walks. No man is flagged, and the coupling follows the bodies (11.7 wu
## here). Judging the walkers by the bodies flagged all 45 and held the anchor
## at 0.48 wu while the men walked about 17 wu back to it.
func test_a_pending_deal_on_a_rally_resquare_keeps_following_the_bodies() -> void:
	var u := _make(46, 10, true)
	_settle_about_face(u)
	assert_true(u.reform_ranks(true), "precondition: the first re-square")
	_stand_on_slots(u)
	_settle_about_face(u)
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += u.facing * 20.0   # braking, a stride ahead of the slots
	u.soldiers -= 1   # a regiment-path casualty: the pairing is now one man long
	assert_true(u._row_slot_deal_pending(u.soldiers, u.formation_files(u.soldiers)),
		"precondition: the row deal is pending")
	var start: Vector2 = u.position
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	assert_true(u._couple_transit.is_empty(), "a rally re-square flags nobody by the bodies")
	for _i in range(300):
		SoldierBodies.step(u, DT)
		SoldierBodies.couple(u, DT)
	var follow: float = (u.position - start).dot(u.facing)
	assert_gt(follow, 10.0, "the anchor followed the braking bodies (%.2f wu)" % follow)
