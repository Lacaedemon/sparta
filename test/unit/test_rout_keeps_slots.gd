extends GutTest
## A rout leaves every man on his own slot, and the rally squares the grid without scattering
## the block.
##
## The rout tick: a block can break while its slot grid is turned against its heading (a fold
## from an engage re-face or a large facing snap) or laterally mirrored (after an about-face
## re-square). Neither may move a slot on the tick it breaks. Dropping the fold swings the grid
## about the anchor, and clearing the mirror without baking it sends every off-centre man's
## slot to the other flank.
##
## The rally: the fold the block carries by then (whatever it broke with, plus the flight's
## own turns) is squared to the heading. Every man must end within one rank pitch of the
## ground he holds, the step a half-turn re-square asks of a short file's men.
##
## Bounds. A rout moves no slot, so the rout-tick bound is the float tolerance on a slot
## position, the 0.01 wu test_reform_mirror_next_order.gd uses for "no man's slot moves".
## A rally re-squares a half-turned grid that has a short rank: each full file's men keep
## their slots, and each short file's men step one rank towards the new front. So no man's slot
## moves more than rank_pitch_wu(), and the mean move is at most the short files' share of
## the men times rank_pitch_wu() (both plus the same 0.01 wu tolerance).

const TICK: float = 1.0 / 60.0
const EPS: float = 0.01
# 60 men on 8 files: 7 full ranks plus a 4-man rear rank. Centred in 8 files, the rear rank
# lines up with files 2 to 5, so those four files are 8 deep and files 0, 1, 6 and 7 are 7 deep.
const COUNT := 60
const FILES := 8
const SHORT_FILE_MEN := 28

var _old_pf: PathField = null


func before_each() -> void:
	# A live Battle elsewhere in the suite can leave PathField.active set; the flight here
	# must take its unobstructed branch so the only turn it makes is the snap toward its edge.
	_old_pf = PathField.active
	PathField.active = null


func after_each() -> void:
	PathField.active = _old_pf


## A block of COUNT men on FILES files facing `heading` (team 0 flees north), in the
## given reform layout, every man on his slot.
func _make(mode: int, heading: Vector2 = Vector2.DOWN) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = COUNT
	add_child_autofree(u)
	u.position = Vector2(600, 600)
	u.facing = heading
	u.frontage_override = FILES
	u.file_major_reform_mode = mode
	u.seed_sim_soldiers()
	_stand_on_slots(u)
	return u


func _stand_on_slots(u: Unit) -> void:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


## Mean and max of each man's distance to his slot.
func _gap(u: Unit) -> Vector2:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var total: float = 0.0
	var worst: float = 0.0
	for i in range(slots.size()):
		var d: float = u._sim_soldier_pos[i].distance_to(slots[i])
		total += d
		worst = maxf(worst, d)
	return Vector2(total / float(slots.size()), worst)


## Mean and max of how far each man's slot moved between two slot snapshots.
func _moved(before: PackedVector2Array, after: PackedVector2Array) -> Vector2:
	var total: float = 0.0
	var worst: float = 0.0
	for i in range(before.size()):
		var d: float = before[i].distance_to(after[i])
		total += d
		worst = maxf(worst, d)
	return Vector2(total / float(before.size()), worst)


## Settle an about-face drill and re-square it holding ground, as a V drill's REFORM does: the
## re-square arms the depth mirror. Every man then stands on his new slot.
func _about_face_and_resquare(u: Unit) -> void:
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)
	assert_true(u.reform_ranks(true), "setup: the about-face fold re-squares")
	_stand_on_slots(u)


func _assert_rout_moves_no_slot(u: Unit, what: String) -> void:
	assert_lt(_gap(u).y, EPS, "%s: setup: every man stands on his slot" % what)
	u._rout()
	assert_eq(u.state, Unit.State.ROUTING, "%s: the unit routed" % what)
	var g: Vector2 = _gap(u)
	assert_lt(g.x, EPS, "%s: the rout tick moves no slot on average (mean %.2f wu)" % [what, g.x])
	assert_lt(g.y, EPS, "%s: the rout tick moves no man's slot (max %.2f wu)" % [what, g.y])


## Rally `u` (already routing) with every man on his slot, and check how far the re-square
## moved the slots against the bounds in the file header.
func _assert_rally_holds_ground(u: Unit, what: String) -> void:
	_stand_on_slots(u)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._rally()
	assert_eq(u.state, Unit.State.IDLE, "%s: the unit rallied" % what)
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.001,
			"%s: the rally squared the grid to the heading" % what)
	var m: Vector2 = _moved(before, u.soldier_world_slots(u.soldiers))
	var pitch: float = u.rank_pitch_wu()
	assert_lt(m.y, pitch + EPS,
			"%s: no man's slot moves more than one rank pitch (max %.2f, pitch %.2f)"
			% [what, m.y, pitch])
	var mean_bound: float = float(SHORT_FILE_MEN) / float(COUNT) * pitch + EPS
	assert_lt(m.x, mean_bound,
			"%s: the mean slot move is at most the short files' step (mean %.2f, bound %.2f)"
			% [what, m.x, mean_bound])


## One tick of flight: team 0 flees north, so a block facing south snaps a half-turn, which
## _face_dir folds into the grid.
func _flee_one_tick(u: Unit) -> void:
	u.morale = 0.0   # below the rally threshold, so the flight does not rally on its own
	u._process_rout(TICK)


## A flank charge re-faces the block a quarter-turn to its attacker; the snap is folded into
## the grid, so the men keep their ground. The rout must not drop that fold under them.
func test_a_flank_charged_block_keeps_every_slot_on_the_rout_tick() -> void:
	for mode in [Unit.ReformMode.FILE_MAJOR, Unit.ReformMode.ROW_MAJOR]:
		var u := _make(mode)
		u._face_dir(Vector2.RIGHT)
		assert_almost_eq(u._formation_angle, PI * 0.5, 0.001, "setup: the re-face folded a quarter")
		_assert_rout_moves_no_slot(u, "flank-charged, layout %d" % mode)
		assert_almost_eq(u._formation_angle, PI * 0.5, 0.001, "the rout keeps the fold")
		# Rallying straight from the quarter fold: the heading takes the quarter-turn, so the
		# re-square is a half-turn's, never a quarter's swing of the block's footprint.
		_assert_rally_holds_ground(u, "flank-charged, layout %d" % mode)


## A block mirrored by an about-face re-square that breaks before any fresh order baked the
## mirror: the rout bakes it, so no off-centre man's slot crosses to the other flank.
func test_a_mirrored_block_keeps_every_slot_on_the_rout_tick() -> void:
	for mode in [Unit.ReformMode.FILE_MAJOR, Unit.ReformMode.ROW_MAJOR]:
		var u := _make(mode, Vector2.UP)
		_about_face_and_resquare(u)
		assert_true(u._formation_mirror_x, "setup: the re-square armed the mirror")
		_assert_rout_moves_no_slot(u, "mirrored, layout %d" % mode)
		assert_false(u._formation_mirror_x, "the rout baked the mirror")


## The mirrored block then flees and rallies: the flight's half-turn is re-squared within a
## rank pitch of where the men stand, on the flank each man holds.
func test_a_mirrored_block_that_routs_rallies_without_scattering() -> void:
	for mode in [Unit.ReformMode.FILE_MAJOR, Unit.ReformMode.ROW_MAJOR]:
		var u := _make(mode, Vector2.UP)
		_about_face_and_resquare(u)
		u._rout()
		_flee_one_tick(u)
		assert_almost_eq(absf(u._formation_angle), PI, 0.001, "setup: the flight folded a half-turn")
		_assert_rally_holds_ground(u, "mirrored, layout %d" % mode)


## A block that never folded breaks facing its enemy and flees the other way, so the flight
## folds a half-turn. The rally re-squares it within a rank pitch of the ground, in every
## layout: in the row-major and square layouts the reflection alone would send the short
## files' men the whole depth of the block.
func test_a_block_that_never_folded_rallies_without_scattering() -> void:
	for mode in [Unit.ReformMode.FILE_MAJOR, Unit.ReformMode.ROW_MAJOR]:
		var u := _make(mode)
		_assert_rout_moves_no_slot(u, "unfolded, layout %d" % mode)
		_flee_one_tick(u)
		assert_almost_eq(absf(u._formation_angle), PI, 0.001, "setup: the flight folded a half-turn")
		_assert_rally_holds_ground(u, "unfolded, layout %d" % mode)
	# 59 men on 8 files: the 3-man rear rank stands half a file off the files. The re-square
	# puts the 7 full ranks in front, so every file's men step one rank, and each man of the
	# short rank steps half a file into the file beside him (whose rearmost man steps half a file
	# into the vacated end). So no man's slot moves more than one rank pitch.
	var odd: Unit = Unit.new()
	odd.max_soldiers = COUNT - 1
	add_child_autofree(odd)
	odd.position = Vector2(600, 600)
	odd.facing = Vector2.DOWN
	odd.frontage_override = FILES
	odd.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	odd.seed_sim_soldiers()
	_stand_on_slots(odd)
	odd._rout()
	_flee_one_tick(odd)
	_stand_on_slots(odd)
	var before: PackedVector2Array = odd.soldier_world_slots(odd.soldiers)
	odd._rally()
	var m: Vector2 = _moved(before, odd.soldier_world_slots(odd.soldiers))
	assert_lt(m.y, odd.rank_pitch_wu() + EPS,
			"an offset short rank re-squares within one rank pitch (max %.2f, pitch %.2f)"
			% [m.y, odd.rank_pitch_wu()])


## A fold that is no quarter: the engage re-face swung the block 150 degrees, and the flight's
## bounded turn leaves the fold alone. The rout keeps it, and the rally turns the heading by the
## 30 degrees off the half-turn instead of swinging the grid that far under the men.
func test_a_block_folded_off_a_quarter_keeps_its_slots_and_rallies_without_scattering() -> void:
	for mode in [Unit.ReformMode.FILE_MAJOR, Unit.ReformMode.ROW_MAJOR]:
		var u := _make(mode)
		u._face_dir(Vector2.DOWN.rotated(deg_to_rad(-150.0)))
		assert_almost_eq(u._formation_angle, deg_to_rad(150.0), 0.001, "setup: a 150 degree fold")
		_assert_rout_moves_no_slot(u, "folded 150 degrees, layout %d" % mode)
		var heading_before: float = u.facing.angle()
		_stand_on_slots(u)
		var grid_before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		u._turn_heading_onto_fold_half()
		var still: Vector2 = _moved(grid_before, u.soldier_world_slots(u.soldiers))
		assert_lt(still.y, EPS, "taking the residue into the heading moves no slot (max %.3f)" % still.y)
		assert_almost_eq(absf(angle_difference(heading_before, u.facing.angle())), deg_to_rad(30.0),
				0.001, "the heading turns by the 30 degrees off the half-turn")
		assert_almost_eq(absf(u._formation_angle), PI, 0.001, "leaving a half-turn fold")
		_assert_rally_holds_ground(u, "folded 150 degrees, layout %d" % mode)


## A squared block that breaks and flees: the square's half-turn re-square is dealt from the
## men too, so its short files step one pitch rather than walking the block's depth.
func test_a_squared_block_rallies_without_scattering() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = COUNT
	add_child_autofree(u)
	u.position = Vector2(600, 600)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.set_formation(Unit.FORMATION_SQUARE)
	_stand_on_slots(u)
	var files: int = u.formation_files(u.soldiers)
	assert_ne(u.soldiers % files, 0, "setup: the square has a short rank")
	_assert_rout_moves_no_slot(u, "square")
	_flee_one_tick(u)
	assert_almost_eq(absf(u._formation_angle), PI, 0.001, "setup: the flight folded a half-turn")
	_stand_on_slots(u)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._rally()
	var m: Vector2 = _moved(before, u.soldier_world_slots(u.soldiers))
	# The square's rank pitch is its file pitch (UnitFormation.block_slots with no rank pitch).
	assert_lt(m.y, u.file_pitch_wu() + EPS,
			"no man's slot moves more than one pitch (max %.2f, pitch %.2f)" % [m.y, u.file_pitch_wu()])


## The column deal pairs nothing it cannot pair: mismatched or empty input, or no pitch to
## count files by, falls back to the identity layout of the slots it was given.
func test_the_column_deal_falls_back_to_identity_on_input_it_cannot_pair() -> void:
	var slots := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	assert_eq(UnitFormation.pair_slots_by_column(PackedVector2Array([Vector2.ZERO]), slots, 10.0),
			PackedInt32Array([0, 1]), "a size mismatch keeps the identity layout")
	assert_eq(UnitFormation.pair_slots_by_column(PackedVector2Array(slots), slots, 0.0),
			PackedInt32Array([0, 1]), "no pitch keeps the identity layout")
	assert_eq(UnitFormation.pair_slots_by_column(PackedVector2Array(), PackedVector2Array(), 10.0),
			PackedInt32Array(), "nothing to pair pairs nothing")
