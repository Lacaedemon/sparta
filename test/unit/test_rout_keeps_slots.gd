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
var _battle: Node = null


func before_each() -> void:
	# A live Battle elsewhere in the suite can leave PathField.active set; the flight here
	# must take its unobstructed branch so the only turn it makes is the snap toward its edge.
	_old_pf = PathField.active
	PathField.active = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
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
## The flight is taken out first (a zero flee pace hands no coast over), so the anchor stays put
## and the slots are compared in one frame; the coast itself is covered by
## test_the_rally_re_square_waits_for_the_coast_and_turns_at_a_bounded_rate.
func _assert_rally_holds_ground(u: Unit, what: String) -> void:
	_stand_on_slots(u)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	u._flee_pace = 0.0
	u._rally()
	assert_eq(u.state, Unit.State.IDLE, "%s: the unit rallied" % what)
	_settle_rally(u, what)
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


## Run the rally's deferred re-square tick by tick, as _physics_process does, and check the turn
## that precedes it: the heading turns at most CONVERSIO_TURN_RATE * TICK a tick (a float margin of 1e-4
## rad), and no slot moves while it does (EPS), since the fold takes up each step.
func _settle_rally(u: Unit, what: String) -> void:
	var worst_step: float = 0.0
	var worst_slot: float = 0.0
	for _i in range(300):
		if not u._rally_resquare_pending:
			break
		var heading: float = u.facing.angle()
		var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
		u._tick_idle_coast(TICK)
		u._advance_rally_resquare(TICK)
		if u._rally_resquare_pending:
			worst_step = maxf(worst_step, absf(angle_difference(heading, u.facing.angle())))
			worst_slot = maxf(worst_slot, _moved(slots, u.soldier_world_slots(u.soldiers)).y)
	assert_false(u._rally_resquare_pending, "%s: the rally's re-square ran" % what)
	assert_lt(worst_step, Unit.CONVERSIO_TURN_RATE * TICK + 0.0001,
			"%s: the heading turns at a bounded rate (worst step %.4f rad)" % [what, worst_step])
	assert_lt(worst_slot, EPS, "%s: no slot moves while the heading turns (max %.3f)" % [what, worst_slot])


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
	odd._flee_pace = 0.0
	odd._rally()
	_settle_rally(odd, "offset short rank")
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
	u._flee_pace = 0.0
	u._rally()
	_settle_rally(u, "square")
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


## The rally hands the flight to a coast and waits for it: while the block pulls up, its heading
## and its fold stay as they flew, so it never slides sideways along the flight line with its men
## facing across it. Once it has stopped, the heading turns at a bounded rate by the 30 degrees
## its ranks lie off a half-turn, and only then do the ranks re-square.
func test_the_rally_re_square_waits_for_the_coast_and_turns_at_a_bounded_rate() -> void:
	var u := _make(Unit.ReformMode.ROW_MAJOR)
	u.retreat_bounds = Rect2(-10000, -10000, 20000, 20000)
	u._face_dir(Vector2.DOWN.rotated(deg_to_rad(-150.0)))
	u._rout()
	u.morale = 0.0
	for _i in range(20):
		u._process_rout(TICK)   # a bounded flight turn onto north: the fold stays at 150 degrees
	assert_almost_eq(u._formation_angle, deg_to_rad(150.0), 0.001, "setup: the fold flew unchanged")
	assert_gt(u._flee_pace, 0.0, "setup: the block is running")
	var flight_heading: float = u.facing.angle()
	u._rally()
	assert_true(u.is_rally_halting(), "setup: the rally handed over a coast")
	var coast_ticks: int = 0
	while u.is_rally_halting() and coast_ticks < 600:
		u._tick_idle_coast(TICK)
		u._advance_rally_resquare(TICK)
		coast_ticks += 1
		if u.is_rally_halting():
			assert_almost_eq(angle_difference(flight_heading, u.facing.angle()), 0.0, 0.0001,
					"the heading holds while the block coasts (tick %d)" % coast_ticks)
	assert_false(u.is_rally_halting(), "the coast stopped (after %d ticks)" % coast_ticks)
	assert_true(u._rally_resquare_pending, "the re-square waited for the coast")
	_stand_on_slots(u)
	_settle_rally(u, "after the coast")
	assert_almost_eq(absf(angle_difference(flight_heading, u.facing.angle())), deg_to_rad(30.0), 0.001,
			"the heading turned by the 30 degrees the ranks lay off a half-turn")
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.001, "and the ranks re-squared")


## Rally  and run its re-square while the loss is still pending: no slot query between the loss
## and the re-square (in a battle SoldierBodies.step queries every tick, so this is the window of
## a loss landing on the tick the re-square runs). The fold is a half-turn, so the first advance
## runs the re-square.
func _rally_with_the_loss_pending(u: Unit, what: String) -> void:
	u._flee_pace = 0.0
	u._rally()
	assert_true(u._slot_deal_pending(u.soldiers, u.formation_files(u.soldiers)),
			"%s: setup: the loss is still pending when the re-square runs" % what)
	u._advance_rally_resquare(TICK)
	assert_false(u._rally_resquare_pending, "%s: the re-square ran" % what)


## The worst distance from each surviving man's body to his slot once a rally has re-squared a
## block that took a regiment-path loss of `lost` men during its flight (the body arrays are left
## untrimmed, so the assignment is out of step with the headcount when the rally comes).
func _rally_after_flight_loss(u: Unit, lost: int, what: String) -> float:
	u._rout()
	_flee_one_tick(u)
	_stand_on_slots(u)
	var survivors: int = u.soldiers - lost
	var bodies: PackedVector2Array = u._sim_soldier_pos.slice(0, survivors)
	u.soldiers = survivors   # the regiment path: the body arrays are not trimmed
	assert_true(u._slot_deal_pending(u.soldiers, u.formation_files(u.soldiers)),
			"%s: setup: the loss left the assignment out of step" % what)
	_rally_with_the_loss_pending(u, what)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var worst: float = 0.0
	for i in range(slots.size()):
		worst = maxf(worst, bodies[i].distance_to(slots[i]))
	return worst


## A row-major block that loses two men to the regiment path during its flight (58 men on 8
## files: the 2-man short rank is centred under the middle files, the case where a depth
## reflection alone sends the outer files' men the block's whole depth). The loss is closed up
## from the cells alone, reading no body, so the rally settles that close-up first and deals its
## re-square column by column from the closed-up slots. A twin block put through the same steps
## gives those closed-up slots without rallying. Bound: one rank pitch from each man's closed-up
## slot, the column deal's own step (plus the float margin). Measured: 18.0 wu here; with the
## rally's read skipped on any pending rebuild, the reflection alone sent a man 127.3 wu, and with
## the read taken without settling the close-up, 58 walkers were judged against slots the men had
## not reached.
func test_a_row_major_loss_in_flight_then_a_rally_deals_from_the_closed_up_slots() -> void:
	var blocks: Array = []
	for _k in range(2):
		var b := _make(Unit.ReformMode.ROW_MAJOR, Vector2.UP)
		_about_face_and_resquare(b)
		b._rout()
		_flee_one_tick(b)
		_stand_on_slots(b)
		b.soldiers = COUNT - 2   # the regiment path: the body arrays are not trimmed
		blocks.append(b)
	var u: Unit = blocks[0]
	var twin: Unit = blocks[1]
	var files: int = u.formation_files(u.soldiers)
	assert_true(u._slot_deal_pending(u.soldiers, files), "setup: the loss left the pairing out of step")
	assert_false(u._slot_body_deal_pending(u.soldiers, files), "setup: and closing it up reads no body")
	var closed_up: PackedVector2Array = twin.soldier_world_slots(twin.soldiers)
	_rally_with_the_loss_pending(u, "row major")
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var worst: float = _moved(closed_up, slots).y
	var bound: float = u.rank_pitch_wu() + EPS
	assert_lt(worst, bound,
			"no man's slot moves more than a rank pitch from his closed-up slot (max %.2f, bound %.2f)"
			% [worst, bound])
	# The men have not walked to their closed-up slots yet, so no walker is judged against them.
	assert_true(u._couple_transit.is_empty(), "no walker is flagged against the closed-up slots")


## A regression guard for main's square behaviour, not a test of this change: a squared block that
## loses a man to the regiment path during its flight rebuilds its headcount from the bodies, so
## the rally reads no slots first (_slot_body_deal_pending) and keeps the deal the re-square's
## reflection makes from where the men stand, as main does. That deal buckets the short rank's
## cells by index into the leftmost files (UnitFormation.pair_slots_by_lateral_file), so the man
## of file k can be dealt the short rank's cell k, which stands (files - short rank) / 2 file
## pitches to his side. Bound, for this 1-man loss (59 men: 8 files, a 3-man short rank): that
## lateral offset, 2.5 pitches (22.5 wu), plus the float margin. It grows with the loss: 27.0 wu
## for 2 men and 31.5 for 3.
func test_a_squared_loss_in_flight_then_a_rally_deals_the_square_as_main_does() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = COUNT
	add_child_autofree(u)
	u.position = Vector2(600, 600)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.set_formation(Unit.FORMATION_SQUARE)
	_stand_on_slots(u)
	assert_true(u._slot_body_deal_pending(u.soldiers - 1, u.formation_files(u.soldiers - 1)),
			"setup: a square loss is dealt from the bodies")
	var worst: float = _rally_after_flight_loss(u, 1, "square")
	var files: int = u.formation_files(u.soldiers)
	var short_rank: int = u.soldiers % files
	var bound: float = float(files - short_rank) * 0.5 * u.file_pitch_wu() + EPS
	assert_lt(worst, bound,
			"no man's slot lies farther from him than the short rank's index offset (max %.2f, bound %.2f)"
			% [worst, bound])


## A router with no escape stands to fight. It squares the fold it kept from the rout, plus its
## flight's turns, to its heading at once, as a rally would: a stale 120 degree fold would leave
## its ranks lying across the way it faces.
func test_a_trapped_router_that_stands_to_fight_squares_its_fold() -> void:
	var u := _make(Unit.ReformMode.FILE_MAJOR)
	u._rout()
	u._face_dir(Vector2.DOWN.rotated(deg_to_rad(120.0)))   # a flight snap the fold absorbs
	assert_almost_eq(absf(u._formation_angle), deg_to_rad(120.0), 0.001, "setup: a 120 degree fold")
	u._stop_rout_and_fight()
	assert_eq(u.state, Unit.State.IDLE, "the router stood to fight")
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.001, "and squared its ranks to its heading")
	assert_false(u._rally_resquare_pending, "with nothing left pending")


## A live battle: a rallied 60-man Infantry block at (600, 600) facing east, its re-square still
## pending with its slot grid folded `fold_deg` against its heading and every man on his slot, and
## a 40-man enemy block 130 wu away at `enemy_deg` from that heading. Runs `ticks` ticks and
## returns the worst angle between the block's heading and the bearing to the enemy, and how many
## degrees further off that bearing the heading turned, at worst, before the block first touched
## the enemy (the enemy advances to contact about 168 ticks in).
func _pending_rally_meets_enemy(fold_deg: float, enemy_deg: float, ticks: int) -> Vector2:
	Replay.forced_seed = 61766
	var enemy_at: Vector2 = Vector2(600, 600) + Vector2.RIGHT.rotated(deg_to_rad(enemy_deg)) * 130.0
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 600, "y": 600, "facing": [1, 0], "count": COUNT},
		{"team": 1, "type": "Infantry", "x": enemy_at.x, "y": enemy_at.y,
				"facing": [-cos(deg_to_rad(enemy_deg)), -sin(deg_to_rad(enemy_deg))], "count": 40},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var u: Unit = null
	var e: Unit = null
	for n in get_tree().get_nodes_in_group("units"):
		if n.team == 0:
			u = n
		else:
			e = n
	u._formation_angle = deg_to_rad(fold_deg)
	_stand_on_slots(u)
	u._rally_resquare_pending = true
	var worst_off: float = 0.0
	var turned_away: float = 0.0
	var start_off: float = absf(angle_difference(u.facing.angle(), (e.position - u.position).angle()))
	for _i in range(ticks):
		await get_tree().physics_frame
		if not is_instance_valid(u) or not is_instance_valid(e) or u.state == Unit.State.DEAD:
			break
		var off: float = absf(angle_difference(u.facing.angle(), (e.position - u.position).angle()))
		worst_off = maxf(worst_off, off)
		if not u._in_enemy_contact and u.state == Unit.State.IDLE:
			turned_away = maxf(turned_away, off - start_off)
	return Vector2(rad_to_deg(worst_off), rad_to_deg(turned_away))


## An enemy dead ahead of a unit whose rally re-square is pending: the re-square gives way, so the
## heading turn never turns the unit off its attacker. Bound: 45 degrees, half the quarter-turn
## the pending turn would take; a fighting block's own small facing corrections stay well inside it.
func test_an_enemy_ahead_cancels_a_pending_rally_turn_instead_of_turning_away() -> void:
	var r: Vector2 = await _pending_rally_meets_enemy(90.0, 0.0, 60)
	assert_lt(r.x, 45.0, "the heading stays on the enemy (worst %.1f degrees off)" % r.x)


## An enemy 120 degrees off a unit whose grid is folded 150 degrees, inside the radius its idle
## auto-engage reacts in: the pending re-square gives way at once, so the unit waits for the
## enemy's advance facing as it did. On ba30d954 the pending turn turned it 30 degrees further off
## the enemy before contact (from 120 to 150 degrees off), then re-squared it, and the block lost
## its shape as it closed. Bound: 1 degree, a float margin on a heading that should not turn.
func test_an_enemy_off_the_flank_cancels_a_pending_rally_turn_without_turning_away() -> void:
	var r: Vector2 = await _pending_rally_meets_enemy(150.0, 120.0, 260)
	assert_lt(r.y, 1.0, "the heading does not turn away from the enemy before contact (%.1f degrees)" % r.y)


## A live battle: a rallied `count`-man Infantry block on 8 files at (600, 600) facing east, its
## grid folded 150 degrees with its re-square pending, and a 40-man enemy 130 wu off at 120
## degrees, inside the radius that calls the re-square off. Returns the two units once the
## call-off has happened.
func _cancelled_rally(count: int) -> Array:
	Replay.forced_seed = 61767
	var enemy_at: Vector2 = Vector2(600, 600) + Vector2.RIGHT.rotated(deg_to_rad(120.0)) * 130.0
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 600, "y": 600, "facing": [1, 0], "count": count,
				"frontage": FILES},
		{"team": 1, "type": "Infantry", "x": enemy_at.x, "y": enemy_at.y, "facing": [0.5, -0.87],
				"count": 40},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var u: Unit = null
	var e: Unit = null
	for n in get_tree().get_nodes_in_group("units"):
		if n.team == 0:
			u = n
		else:
			e = n
	u._formation_angle = deg_to_rad(150.0)
	_stand_on_slots(u)
	u._rally_resquare_pending = true
	await get_tree().physics_frame
	assert_false(u._rally_resquare_pending, "setup: the enemy called the re-square off")
	assert_true(u._rally_fold_unsquared, "setup: and the fold is left to square")
	return [u, e]


## After an enemy calls a rally re-square off, the unit's next order squares the fold first, so
## its own re-square drops a half-turn instead of swinging an arbitrary 150 degree fold under the
## men. With a full grid (64 men on 8 files) a half-turn needs no re-square at all, so no slot
## may move (EPS); on 263f0333 the order dropped the 150 degree fold and moved a slot 172.12 wu.
func test_an_order_after_a_called_off_rally_squares_the_fold_without_moving_a_slot() -> void:
	var units: Array = await _cancelled_rally(64)
	var u: Unit = units[0]
	_stand_on_slots(u)
	var before: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	_battle._apply_order_cmd({"units": [u.uid], "x": 600, "y": 300, "target": -1})
	var m: Vector2 = _moved(before, u.soldier_world_slots(u.soldiers))
	assert_lt(m.y, EPS, "the order moves no slot (max %.2f wu)" % m.y)
	assert_false(u._rally_fold_unsquared, "and the fold is squared")


## Once the enemy that called a rally re-square off has gone, the re-square resumes: after
## RALLY_RESUME_CLEAR_TICKS clear ticks the heading turns and the ranks re-square, as for any
## rally. 60 men on 8 files have a short rank, so the half-turn re-squares to 0.
func test_a_called_off_rally_resquare_resumes_once_the_enemy_has_gone() -> void:
	var units: Array = await _cancelled_rally(COUNT)
	var u: Unit = units[0]
	var e: Unit = units[1]
	var away := Vector2(0.0, 3000.0)
	e.position += away
	for i in range(e._sim_soldier_pos.size()):
		e._sim_soldier_pos[i] += away
	for _i in range(Unit.RALLY_RESUME_CLEAR_TICKS + 30):
		await get_tree().physics_frame
	assert_false(u._rally_fold_unsquared, "the call-off was lifted")
	assert_false(u._rally_resquare_pending, "the re-square ran")
	assert_almost_eq(wrapf(u._formation_angle, -PI, PI), 0.0, 0.001, "and the ranks are square")
