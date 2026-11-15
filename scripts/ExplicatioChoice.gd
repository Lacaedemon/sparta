class_name ExplicatioChoice
## The explicatio the player has chosen: its drill, the side its intervals open on, the ground
## it keeps and when its files open, as the four SelectionManager fields explicatio_drill,
## explicatio_side, explicatio_ground and explicatio_opening. Alt+B, Alt+Shift+B, Alt+Ctrl+B and
## Alt+Ctrl+Shift+B step each one to the next reading, as Y and X step the form-up split and the
## group-attack mode, and the HUD shows the choice. Pure: functions of their arguments only.

const DRILLS := [UnitFormation.ExplicatioDrill.HALF_FILE,
		UnitFormation.ExplicatioDrill.ALTERNATE_RANK]
const SIDES := [UnitFormation.ExplicatioSide.OUTWARD, UnitFormation.ExplicatioSide.INWARD,
		UnitFormation.ExplicatioSide.SPEAR_SIDE, UnitFormation.ExplicatioSide.SHIELD_SIDE]
const GROUNDS := [UnitFormation.ExplicatioGround.LENGTHEN,
		UnitFormation.ExplicatioGround.SAME_GROUND]

const DRILL_NAMES := {
	UnitFormation.ExplicatioDrill.HALF_FILE: "half-file",
	UnitFormation.ExplicatioDrill.ALTERNATE_RANK: "alternate rank",
}
const SIDE_NAMES := {
	UnitFormation.ExplicatioSide.OUTWARD: "outward",
	UnitFormation.ExplicatioSide.INWARD: "inward",
	UnitFormation.ExplicatioSide.SPEAR_SIDE: "spear side",
	UnitFormation.ExplicatioSide.SHIELD_SIDE: "shield side",
}
const GROUND_NAMES := {
	UnitFormation.ExplicatioGround.LENGTHEN: "lengthen",
	UnitFormation.ExplicatioGround.SAME_GROUND: "same ground",
}


## The reading after `current` in `readings`, wrapping at the end; the first reading for one the
## list does not hold.
static func next(readings: Array, current: int) -> int:
	var idx: int = readings.find(current)
	return readings[(idx + 1) % readings.size()] if idx >= 0 else readings[0]


## The choice as the HUD and the toast word it: "half-file, outward, lengthen, together".
static func summary(drill: int, side: int, ground: int,
		opening: int = ExplicatioOpening.Reading.TOGETHER) -> String:
	return "%s, %s, %s, %s" % [DRILL_NAMES.get(drill, "?"), SIDE_NAMES.get(side, "?"),
			GROUND_NAMES.get(ground, "?"), ExplicatioOpening.NAMES.get(opening, "?")]
