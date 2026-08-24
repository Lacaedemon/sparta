extends GutTest
## Fighting withdrawal: a disciplined block ordered to march out of melee toward its rear
## sector peels BACK holding the facing it fought in, then hands the march to the drilled
## turn decomposition (about-face, then advance) once contact breaks -- instead of
## pivot-turning inside the press and dragging every scattered body across a slot grid
## swinging through the block depth. Two layers, mirroring test_rear_move_conversio.gd's
## pattern: bare-unit _think() loops stepping the peel tick by tick (engagement is driven
## directly through _in_enemy_contact/_engaged_linger, the same latches Battle's per-tick
## orchestration refreshes), plus eligibility gates exercised one at a time.

const DT := 1.0 / 60.0
const BattleScript = preload("res://scripts/Battle.gd")


func _make_seeded_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	return u


## Commit a plain MOVE order exactly as a fighting unit receives it: Battle installs it
## via set_current_order and commits the march (start_order_response aside, which only
## freezes _think advancement -- not needed for these bare-unit steps), leaving
## has_move_target armed while the unit is still in contact.
func _order_move_to(u: Unit, dest: Vector2, haste: bool = false) -> Order:
	var o := Order.new_move(dest)
	if haste:
		o.haste = true
	u.set_current_order(o)
	u.has_move_target = true
	u.move_target = dest
	return o


func _engage(u: Unit) -> void:
	# The tick the order lands: the unit was fighting (state FIGHTING, latches hot).
	# State itself is Unit-driven -- the first peel tick's _move_to reads it out of
	# FIGHTING exactly as in a real battle -- so only the two external latches get
	# refreshed per tick below, the way Battle's soldier passes / tick_engaged do.
	u.state = Unit.State.FIGHTING
	u._in_enemy_contact = true
	u._engaged_linger = Unit.ENGAGED_LINGER


## Refresh the engagement latches exactly as Battle does per tick (soldier-level contact
## plus the engaged-tier latch). Deliberately does NOT touch state: a peeling unit is
## MOVING, and the latch must DECAY once contact breaks, which needs state != FIGHTING.
func _tick_engaged(u: Unit) -> void:
	u._in_enemy_contact = true
	u._engaged_linger = Unit.ENGAGED_LINGER
	u._think(DT)


## Contact has broken; run whole battle-style ticks (latch decay via the real
## tick_engaged, then _think) until the peel hands off or the budget runs out.
func _run_until_handoff(u: Unit, budget_ticks: int) -> void:
	for _i in range(budget_ticks):
		u.tick_engaged(DT)
		u._think(DT)
		if not u._withdrawal_peeling:
			return


## Soldier-level contact breaks (Battle's soldier passes stop reporting touching bodies)
## without advancing anything else -- the latch decay is left to tick_engaged below.
func _break_contact_latch_only(u: Unit) -> void:
	u._in_enemy_contact = false


# --- peel phase: hold facing, back straight out ------------------------------

func test_peel_backs_straight_out_holding_facing() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	var dest := Vector2(0, -300)   # straight behind a DOWN-facing unit
	_order_move_to(u, dest)
	_engage(u)
	var start_facing: Vector2 = u.facing
	var start_y: float = u.position.y
	for i in range(40):
		_tick_engaged(u)
		assert_true(u._withdrawal_peeling,
			"tick %d: the peel phase is active while engaged" % i)
		assert_true(u.facing.is_equal_approx(start_facing),
			"tick %d: the block holds its fighting facing while backing out" % i)
	assert_lt(u.position.y, start_y - 5.0,
		"the unit actually put distance between itself and the fight (backed toward its rear)")
	PathField.active = old_pf


func test_peel_ends_by_arming_the_drilled_about_face_then_marches() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	var o := _order_move_to(u, Vector2(0, -300))
	_engage(u)
	for i in range(30):
		_tick_engaged(u)
	assert_true(u._withdrawal_peeling, "still peeling at the moment contact breaks")
	u._in_enemy_contact = false
	_run_until_handoff(u, 90)
	assert_false(u._withdrawal_peeling, "the peel phase ended once the latch expired")
	assert_true(o.children.size() >= 2,
		"the handoff armed a drilled composite (turn leaf + march leaf)")
	assert_true(u.is_order_turning(), "the opening turn is turning")
	assert_false(u.has_move_target, "the march stays parked until the turn completes")
	for _i in range(240):
		u._think(DT)
		if u.has_move_target:
			break
	assert_true(u.has_move_target, "the parked march commits once the about-face completes")
	assert_true(u.facing.is_equal_approx(Vector2.UP),
		"the unit about-faced onto the destination bearing (not pivoted mid-press)")
	assert_eq(u.move_target, Vector2(0, -300), "it marches to the ordered destination")
	PathField.active = old_pf


func test_peel_survives_the_linger_decay_window_before_handoff() -> void:
	# The exit condition needs BOTH soldier contact gone AND the ENGAGED_LINGER latch
	# expired; this pins the hysteresis half so a single clear tick can't end the peel.
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	_order_move_to(u, Vector2(0, -300))
	_engage(u)
	for i in range(10):
		_tick_engaged(u)
	_break_contact_latch_only(u)
	# Decay the latch while well short of expiry: every one of these ticks must still peel.
	var steps_to_expire: int = int(ceil(Unit.ENGAGED_LINGER / DT))
	for i in range(steps_to_expire - 3):
		u.tick_engaged(DT)
		u._think(DT)
		assert_true(u._withdrawal_peeling,
			"tick %d: still peeling while the engagement latch decays" % i)
	# Walk the last few ticks of decay until the latch actually reads expired (no
	# float-exactness assumptions about where the fixed-point subtraction lands).
	var safety := 0
	while u.is_engaged() and safety < 10:
		u.tick_engaged(DT)
		safety += 1
	assert_false(u.is_engaged(), "the engagement latch has fully expired")
	u._think(DT)
	assert_false(u._withdrawal_peeling, "the handoff ran once the latch fully expired")
	PathField.active = old_pf


# --- eligibility gates --------------------------------------------------------

func test_undisciplined_unit_does_not_peel() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	u.disciplined = false
	_order_move_to(u, Vector2(0, -300))
	_engage(u)
	for i in range(10):
		_tick_engaged(u)
		assert_false(u._withdrawal_peeling,
			"tick %d: an undisciplined mob breaks off exactly as before" % i)
	PathField.active = old_pf


func test_hasty_order_skips_the_peel() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	_order_move_to(u, Vector2(0, -300), true)
	_engage(u)
	for i in range(10):
		_tick_engaged(u)
		assert_false(u._withdrawal_peeling,
			"tick %d: a run-gait break-off keeps today's pace-over-poise behaviour" % i)
	PathField.active = old_pf


func test_forward_destination_does_not_peel() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	_order_move_to(u, Vector2(0, 300))   # straight AHEAD of a DOWN-facing unit
	_engage(u)
	for i in range(10):
		_tick_engaged(u)
		assert_false(u._withdrawal_peeling,
			"tick %d: marching INTO the fight never reverses into a peel" % i)
	PathField.active = old_pf


func test_backstep_length_shuffle_does_not_peel() -> void:
	# A near-behind click is its own held-facing maneuver at Battle level; peeling past
	# so close a destination would overshoot it and then march forward again.
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	_order_move_to(u, Vector2(0, -30))
	_engage(u)
	for i in range(10):
		_tick_engaged(u)
		assert_false(u._withdrawal_peeling,
			"tick %d: a back-step-length rear nudge stays off the peel path" % i)
	PathField.active = old_pf


func test_not_engaged_never_peels() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	_order_move_to(u, Vector2(0, -300))
	# Deliberately NOT engaged: a clean rearward march must never reverse.
	for i in range(10):
		u._think(DT)
		assert_false(u._withdrawal_peeling,
			"tick %d: a clean march passing no fight just marches" % i)
	PathField.active = old_pf


# --- lifecycle: replacement clears the phase ----------------------------------

func test_replacing_the_order_clears_the_peel_phase() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	_order_move_to(u, Vector2(0, -300))
	_engage(u)
	_tick_engaged(u)
	assert_true(u._withdrawal_peeling, "peeling before the replacement")
	_order_move_to(u, Vector2(500, -500))   # any fresh order replaces via set_current_order
	assert_false(u._withdrawal_peeling,
		"the interrupt that replaces the order drops the peel phase with it")
	PathField.active = old_pf


func test_committed_foe_mid_peel_stands_down() -> void:
	# Belt-and-braces beyond the interrupt path: a foe committed WITHOUT replacing the
	# order makes the very next peel tick stand down instead of backing away from a
	# fight it has been ordered into.
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	_order_move_to(u, Vector2(0, -300))
	_engage(u)
	_tick_engaged(u)
	assert_true(u._withdrawal_peeling, "peeling before the foe commits")
	var enemy := _make_seeded_unit()
	enemy.team = 1
	u.target_enemy = enemy
	var consumed: bool = u._fighting_withdrawal_step(DT)
	assert_false(consumed, "the peel tick refuses to consume the tick once a foe is committed")
	assert_false(u._withdrawal_peeling, "and the stale phase flag is dropped")
	PathField.active = old_pf


# --- cavalry: moving-wheel handoff --------------------------------------------

func test_cavalry_hands_off_to_a_moving_wheel_not_an_about_face() -> void:
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	u.is_cavalry = true
	var o := _order_move_to(u, Vector2(0, -300))
	_engage(u)
	for i in range(30):
		_tick_engaged(u)
	u._in_enemy_contact = false
	_run_until_handoff(u, 90)
	assert_false(u._withdrawal_peeling, "the handoff ran")
	var wheel_leaf: Order = o.children[0]
	assert_true(wheel_leaf.is_moving_wheel,
		"cavalry opens with a single continuous moving wheel, mirroring the fresh-order ladder")
	assert_false(u.is_order_turning(),
		"a moving wheel swings continuously -- it is not an in-place turn")
	PathField.active = old_pf


# --- handoff onto Battle's fighting-unit order shape ---------------------------

func test_handoff_after_battles_fighting_split_still_marches() -> void:
	# A move issued to a FIGHTING infantry unit is never a bare march: Battle splits
	# it into a reform leaf plus march leg at issue time (its not-turn_armed-and-
	# reform branch -- the composites all refuse while fighting), and _think's
	# fighting bypass commits that reform immediately. The order the peel actually
	# runs on therefore carries [spent reform, pending march] children, and the
	# handoff must discard that stale decomposition and arm fresh: arming onto it
	# as-is routes the conversio through the append mode, the turn lands as the
	# LAST child, the tree cascades away when it completes, and the regiment stops
	# dead facing travel with no march ever committed.
	var old_pf: PathField = PathField.active
	PathField.active = null
	var u := _make_seeded_unit()
	assert_true(u.reform_before_move,
		"infantry reforms before moving by default -- the split applies to this unit")
	u.state = Unit.State.FIGHTING
	var b := BattleScript.new()
	autofree(b)
	b._by_uid[u.uid] = u
	var dest := Vector2(0, -300)   # straight behind a DOWN-facing unit
	b._apply_order_cmd({"units": [u.uid], "x": dest.x, "y": dest.y, "target": -1})
	assert_eq(u.current_order.children.size(), 2,
		"Battle split the fighting unit's move into reform hold plus march leg")
	assert_eq(u.current_order.children[0].phase, Order.Phase.REFORM,
		"the first leaf is the reform hold")
	assert_false(u.has_move_target, "the split parks the march at issue time")
	# Real fights rage for many ticks between issue and disengage; the order-response
	# beat drains concurrently while a fighting unit keeps executing, so by peel start
	# it is long gone. Zero it here for the same effect without simulating those ticks.
	u._order_response_timer = 0.0
	# The bypass commit: exactly what _think's reform block does for a FIGHTING unit.
	u._commit_pending_reform()
	assert_true(u.has_move_target, "the bypass commits the march while fighting")
	_engage(u)
	for i in range(30):
		_tick_engaged(u)
		assert_true(u._withdrawal_peeling, "tick %d: peeling on the split order" % i)
	u._in_enemy_contact = false
	_run_until_handoff(u, 90)
	assert_false(u._withdrawal_peeling, "the handoff ran")
	assert_eq(u.current_order.children.size(), 2,
		"the handoff armed a FRESH composite (turn + march), not an appended third leaf")
	assert_true(u.is_order_turning(), "the opening turn is turning")
	assert_false(u.has_move_target, "the march stays parked until the turn completes")
	# The armed composite carries the order's reform-before-move policy (Battle set
	# reform=true at issue), so after the about-face lands there is a drilled reform
	# hold before the march commits -- a longer wait than a bare order needs.
	for _i in range(600):
		u._think(DT)
		if u.has_move_target:
			break
	assert_true(u.has_move_target,
		"the parked march commits once the about-face completes -- no stranded stop")
	assert_true(u.facing.is_equal_approx(Vector2.UP),
		"the unit about-faced onto the destination bearing (got %s)" % str(u.facing))
	assert_eq(u.move_target, dest, "it marches to the ordered destination")
	PathField.active = old_pf
