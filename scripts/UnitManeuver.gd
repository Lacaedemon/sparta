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
## An about-face + flank-pivot (wheel) composite for large rear/oblique turns
## is tracked as a follow-up and will add its own classifier here.

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
