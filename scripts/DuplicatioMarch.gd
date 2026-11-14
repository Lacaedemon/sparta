class_name DuplicatioMarch
extends RefCounted
## How the men an explicatio sent up the intervals march back to their stations when a duplicatio
## undoes it (Unit._begin_duplicatio). Asclepiodotus 10.20 and Aelian 29.3 say they countermarch
## back; neither says how. Each reading is chosen on the order (Alt+N steps it):
##   WALK        -- each man drops back down his interval facing front (the sim's inference).
##   FACE_ABOUT  -- each man faces about where he stands, as every man of a countermarch ends
##                  facing about (Asclepiodotus 10.13 to 10.15), the column marches back with its
##                  rear man leading, and each man faces front again on his station. It is none of
##                  the three countermarches, and the sources do not say which they mean; this
##                  reading is the sim's inference (docs/historical-reshaping-maneuvers.md).
## A man turns through his own facing at CONVERSIO_TURN_RATE, never in a snap. Pure: functions of
## their arguments only.

enum Reading { WALK, FACE_ABOUT }

const READINGS := [Reading.WALK, Reading.FACE_ABOUT]
const NAMES := {
	Reading.WALK: "walk",
	Reading.FACE_ABOUT: "face about",
}


## Whether a man faces about this tick: under FACE_ABOUT, a man who went up an interval
## (`returning`) and has not yet taken his station (`following`).
static func faces_about(reading: int, returning: bool, following: bool) -> bool:
	return reading == Reading.FACE_ABOUT and returning and following


## His facing `current` turned toward `wanted` by at most `step` radians: the shorter way round,
## through his right (clockwise on screen, y-down) when the two stand exactly opposed, as a man
## facing about turns one way, never both. `wanted` once he is within the step.
static func turn_toward(current: Vector2, wanted: Vector2, step: float) -> Vector2:
	var diff: float = angle_difference(current.angle(), wanted.angle())
	if absf(diff) <= step:
		return wanted.normalized()
	if absf(diff) > PI - 1e-4:
		diff = absf(diff)
	return Vector2.from_angle(current.angle() + signf(diff) * step)


## Each man's front for the drill, index-aligned with `facings`: his own facing, but a man who went
## up an interval (`returning` 1) reads his file's front off his file leader (`heads`, the index of
## the man at the head of each man's file, or -1), not off his own facing, which facing about
## turns about. `fallback` stands in where his file has no leader.
static func drill_fronts(facings: PackedVector2Array, returning: PackedByteArray,
		heads: PackedInt32Array, fallback: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array(facings)
	for i in range(mini(out.size(), mini(returning.size(), heads.size()))):
		if returning[i] == 0:
			continue
		var h: int = heads[i]
		out[i] = facings[h] if h >= 0 and h < facings.size() and returning[h] == 0 else fallback
	return out


## Whom each man who went up an interval follows as his column marches back faced about: the plan
## `leaders` and `offsets` (DuplicatioDrill.follow_plan, (right, behind) in his drill front's
## frame) with his entries changed, returned as {"leaders", "offsets"}. The column's rear man
## leads. A man with a man of his column to stand right behind him (his file's rank + 1,
## `returning` too) follows that man, a rank pitch ahead of him.
## Any other follows the nearest man of his file ahead of him who did not go up, that many rank
## pitches behind him: the man he will stand behind (every second man), or, for the column's rear
## man, his file's last man (the half-file). A man with neither keeps the plan's leader.
static func march_plan(file_ids: PackedInt32Array, ranks: PackedInt32Array,
		returning: PackedByteArray, leaders: PackedInt32Array, offsets: PackedVector2Array,
		rank_pitch: float) -> Dictionary:
	leaders = PackedInt32Array(leaders)
	offsets = PackedVector2Array(offsets)
	var at: Dictionary = {}
	for i in range(file_ids.size()):
		at[Vector2i(file_ids[i], ranks[i])] = i
	for i in range(file_ids.size()):
		if returning[i] == 0:
			continue
		var f: int = file_ids[i]
		var behind: int = int(at.get(Vector2i(f, ranks[i] + 1), -1))
		if behind >= 0 and returning[behind] == 1:
			leaders[i] = behind
			offsets[i] = Vector2(0.0, -rank_pitch)
			continue
		for back in range(1, ranks[i] + 1):
			var j: int = int(at.get(Vector2i(f, ranks[i] - back), -1))
			if j >= 0 and returning[j] == 0:
				leaders[i] = j
				offsets[i] = Vector2(0.0, back * rank_pitch)
				break
	return {"leaders": leaders, "offsets": offsets}
