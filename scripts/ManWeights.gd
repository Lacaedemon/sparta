extends RefCounted
## How strongly one foe presses on a man's attention: the weight of its direction and
## of its distance. The two multiply.

## Half-angle of a man's visual field, measured from straight ahead. The normal monocular
## field reaches about 107 degrees temporally from the line of sight (H. M. Traquair, "An
## Introduction to Clinical Perimetry", 1938, ch. 1), so with the eyes looking ahead a man
## sees out to 107 degrees on either side. A closed helmet (the Corinthian type, for one)
## narrowed this; a caller modelling one sets a smaller angle.
const VISUAL_FIELD_HALF_ANGLE: float = deg_to_rad(107.0)
## Weight of a foe directly behind a man, relative to one in his visual field. He cannot
## see a foe there; he learns of one by sound, by a comrade's shout or by contact. No
## source quantifies that awareness, so the default halves the weight and leaves it to the
## caller. It must stay above 0: a man with foes only behind him still perceives them.
const REAR_WEIGHT: float = 0.5


## Weight of a foe in direction `to_foe` from a man facing `facing`: 1 inside the visual
## field (|angle| <= half_angle), falling linearly to `rear` directly behind him. Pure.
## A zero facing reads as facing the foe (full weight). A half-angle of PI is a full
## circle; it is tested apart because the measured angle directly behind a man can exceed
## the double PI by a float's rounding, which would divide by zero below.
static func arc_weight(facing: Vector2, to_foe: Vector2, half_angle: float, rear: float) -> float:
	var ang: float = absf(facing.angle_to(to_foe))
	if ang <= half_angle or half_angle >= PI:
		return 1.0
	return lerpf(1.0, rear, (ang - half_angle) / (PI - half_angle))


## Weight of a foe at `dist` from a man who sees out to `radius`: 1 at his position,
## falling linearly to 0 at the edge of his sight. No source fixes the shape; linear is the
## simplest falloff that is continuous at the edge, so a foe crossing the sight radius adds
## nothing abruptly. Pure.
static func distance_weight(dist: float, radius: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	return 1.0 - dist / radius
