class_name UnitManeuver
## Pure, deterministic helpers for the classic drill maneuvers a move order can
## trigger. Stateless so the choice logic is unit-testable without a SceneTree.
##
## SIDE-STEP: a small lateral shift holds facing and shuffles sideways, rather
## than centre-pivoting the whole line to face the destination and back.
## REAR-MOVE: a destination behind the unit about-faces (conversio) in place,
## then marches, rather than a 180° centre pivot.
## BACK-STEP: a SHORT rear-sector move holds facing and shuffles backward,
## rather than about-facing for what would only be a nudge.
## LATERAL-PIVOT: a LARGE lateral shift quarter-turns toward the destination's
## side in place, widens back into a line facing it, then marches -- rather
## than centre-pivoting the whole block onto the new bearing at speed.
## WHEEL-TURN: a rear-sector move whose destination is oblique enough that a
## straight about-face (a full 180° reversal) would still leave a sizeable
## leftover misalignment to correct -- about-faces, then flank-pivots (wheels)
## the rest of the way onto the destination bearing, THEN marches, rather than
## letting the march's own gradual centre-pivot close a large gap while
## already under way (see is_wheel_turn).

# A move counts as a side-step when its lateral offset (perpendicular to the
# unit's current facing) dominates its forward offset AND the whole move is
# short -- roughly one unit-width. Beyond that distance a lateral move is large
# enough to warrant a lateral-pivot maneuver (see is_lateral_pivot) instead of
# a shuffle.
const SIDESTEP_MAX_DISTANCE := 40.0
# The lateral component must be at least this multiple of the forward component
# for the move to read as a sideways shift rather than a forward/diagonal advance.
const SIDESTEP_LATERAL_RATIO := 2.0

# A move counts as "to the rear" when its destination lies behind the unit -- more
# than this angle off the current facing. At 135° the rear quadrant (the back 90°
# arc) triggers an about-face (conversio) instead of a 180° centre pivot: the block
# reverses man-for-man where it stands, then marches to the destination facing it.
const REAR_MOVE_MIN_ANGLE_DEG := 135.0

# A rear-sector move's about-face always reverses facing by exactly 180°, so once it
# completes, the leftover misalignment between the new heading (-facing) and the actual
# destination direction ranges from 0° (destination exactly behind, angle_to_facing == 180°)
# up to 45° (destination at the REAR_MOVE_MIN_ANGLE_DEG boundary, angle_to_facing == 135°).
# Below this threshold the leftover is small enough that the march's own gradual centre-pivot
# corrects it fine, same as today; at or above it, a flank pivot (wheel) closes the gap with a
# drilled turn before marching instead (see is_wheel_turn / Unit.begin_about_face_with_wheel).
const WHEEL_MIN_RESIDUAL_ANGLE_DEG := 30.0


## Whether a move order from `facing` along `move_vec` should be executed as a
## side-step (hold facing, translate) rather than a turn-and-march. `facing` is
## the unit's current heading; `move_vec` is destination minus current position.
static func is_sidestep(facing: Vector2, move_vec: Vector2) -> bool:
	var dist := move_vec.length()
	if facing.length() < 0.01 or dist < 0.01:
		return false
	if dist > SIDESTEP_MAX_DISTANCE:
		return false
	var fwd := facing.normalized()
	var perp := Vector2(-fwd.y, fwd.x)
	var forward := absf(move_vec.dot(fwd))
	var lateral := absf(move_vec.dot(perp))
	return lateral >= forward * SIDESTEP_LATERAL_RATIO


## Whether a move order from `facing` along `move_vec` heads into the unit's rear
## sector -- the destination lies more than REAR_MOVE_MIN_ANGLE_DEG behind the
## current heading. Such a move about-faces (conversio) then marches, rather than
## pivoting the whole block 180° about its centre. `facing` is the current heading;
## `move_vec` is destination minus current position. Degenerate inputs (no facing,
## a zero-length move) are not rear moves.
static func is_rear_move(facing: Vector2, move_vec: Vector2) -> bool:
	if facing.length() < 0.01 or move_vec.length() < 0.01:
		return false
	var angle := rad_to_deg(absf(facing.angle_to(move_vec)))
	return angle >= REAR_MOVE_MIN_ANGLE_DEG


## The leftover misalignment (degrees) between a rear-sector move's post-about-face heading
## (-facing, since an about-face always reverses exactly 180°) and the actual destination
## direction `move_vec`. Zero when `facing`/`move_vec` are degenerate. Callers combine this
## with is_rear_move to decide whether the about-face alone leaves too much for the march's
## own gradual re-aim to close cleanly (see is_wheel_turn).
static func rear_move_wheel_residual_deg(facing: Vector2, move_vec: Vector2) -> float:
	if facing.length() < 0.01 or move_vec.length() < 0.01:
		return 0.0
	return rad_to_deg(absf((-facing).angle_to(move_vec)))


## Whether a move order from `facing` along `move_vec` is large enough to about-face, THEN
## flank-pivot (wheel) toward the destination bearing, THEN march -- rather than just
## about-face-then-march (is_rear_move's own composite). Only rear-sector moves qualify (a
## wheel never applies to a forward/lateral move); among those, only the more oblique ones,
## where the about-face's own 180° reversal leaves at least WHEEL_MIN_RESIDUAL_ANGLE_DEG of
## misalignment still to close. `facing` is the current heading; `move_vec` is destination
## minus current position.
static func is_wheel_turn(facing: Vector2, move_vec: Vector2) -> bool:
	if not is_rear_move(facing, move_vec):
		return false
	return rear_move_wheel_residual_deg(facing, move_vec) >= WHEEL_MIN_RESIDUAL_ANGLE_DEG


## The signed flank (Unit.wheel's own `dir` convention: +1 the unit's own right, -1 its own
## left) a wheel-turn's flank pivot should hinge toward, evaluated against the POST-about-face
## heading (-facing) since that is the heading actually in effect when the wheel arms (see
## Unit.begin_about_face_with_wheel) -- mirroring lateral_pivot_dir's own "whichever side the
## destination falls on" convention, just measured from the reversed heading instead of the
## pre-turn one.
static func wheel_turn_dir(facing: Vector2, move_vec: Vector2) -> int:
	var new_facing: Vector2 = -facing
	var right: Vector2 = new_facing.rotated(PI * 0.5)
	return 1 if move_vec.dot(right) >= 0.0 else -1


## Whether a move order from `facing` along `move_vec` is a short reposition into
## the rear sector -- close enough that a real drill back-steps (holds facing,
## shuffles backward) rather than about-facing in place and marching. Mirrors
## `is_sidestep`'s short-distance cap for the lateral case: within
## SIDESTEP_MAX_DISTANCE a rear-sector move reads as a nudge, not a repositioning
## march. `facing` is the current heading; `move_vec` is destination minus current
## position.
static func is_backstep(facing: Vector2, move_vec: Vector2) -> bool:
	if move_vec.length() > SIDESTEP_MAX_DISTANCE:
		return false
	return is_rear_move(facing, move_vec)


## Whether a move order from `facing` along `move_vec` is a lateral-pivot case: a
## lateral-dominant offset too far to shuffle as a side-step, and not into the rear
## sector (that's is_rear_move's about-face case instead). Such a move quarter-turns
## in place toward the destination's side, widens back into a line facing it, then
## marches -- rather than centre-pivoting the whole block onto the new bearing while
## already under way. `facing` is the current heading; `move_vec` is destination
## minus current position.
static func is_lateral_pivot(facing: Vector2, move_vec: Vector2) -> bool:
	var dist := move_vec.length()
	if facing.length() < 0.01 or dist <= SIDESTEP_MAX_DISTANCE:
		return false
	if is_rear_move(facing, move_vec):
		return false
	var fwd := facing.normalized()
	var perp := Vector2(-fwd.y, fwd.x)
	var forward := absf(move_vec.dot(fwd))
	var lateral := absf(move_vec.dot(perp))
	return lateral >= forward * SIDESTEP_LATERAL_RATIO


## The signed quarter-turn direction (matching Unit.quarter_turn's `dir` convention:
## +1 turns toward the unit's own right, -1 toward its own left) a lateral-pivot move
## should turn toward -- whichever side of current facing the destination falls on.
## Computed via facing.rotated(PI * 0.5), the SAME rotation Unit.begin_pivot applies
## for a dir=+1 turn, so the sign is guaranteed consistent with the actual turn by
## construction rather than a separately-derived perpendicular formula.
static func lateral_pivot_dir(facing: Vector2, move_vec: Vector2) -> int:
	var right: Vector2 = facing.rotated(PI * 0.5)
	return 1 if move_vec.dot(right) >= 0.0 else -1
