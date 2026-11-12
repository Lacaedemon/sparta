extends RefCounted
## How strongly one foe presses on a man's attention: the weight of its direction and
## of its distance. The two multiply.

## Half-angle of a man's visual field, measured from straight ahead: the temporal extent of
## the normal monocular field, 107 degrees from the line of sight. Source: the Wikipedia
## article "Visual field" (normal limits), which cites H. M. Traquair, "An Introduction to
## Clinical Perimetry" (London: Henry Kimpton, 1938), chapter 1; it also quotes an earlier
## measurement of 110 degrees outwards by A. Hueck, "Von den Graenzen des Sehvermoegens"
## (1840, umlauts transliterated), and notes that the temporal field exceeds the often
## quoted 90 degrees. So 107 is one well-attested value, not a measured constant. A caller
## modelling a narrower view, such as a closed helmet's, sets a smaller angle.
const VISUAL_FIELD_HALF_ANGLE: float = deg_to_rad(107.0)
## Weight of a foe directly behind a man, relative to one in his visual field. ManScan
## applies the same sight rule behind a man as in front of him (no sound, shout or contact
## channel exists), so this only discounts a foe the man cannot be looking at. It has no
## source: 0.5 is a placeholder that halves the weight. It must stay above 0 so a man with
## foes only behind him still perceives them.
const REAR_WEIGHT: float = 0.5


## Weight of a foe in direction `to_foe` from a man facing `facing`: 1 inside the visual
## field (|angle| <= half_angle), falling linearly to `rear` directly behind him. Pure.
## A zero facing reads as facing the foe (full weight). A half-angle of PI is a full
## circle; it is tested apart because angle_to computes in 32-bit floats, so the angle
## directly behind a man can exceed the double-precision PI constant and divide by zero below.
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
