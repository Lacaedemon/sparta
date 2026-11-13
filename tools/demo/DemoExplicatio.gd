class_name DemoExplicatio
## The explicatio a scripted demo's B key deals, from the input script's optional "explicatio"
## block: {"drill": name, "side": name, "ground": name}, each optional, by the short names of
## UnitFormation.ExplicatioDrill, ExplicatioSide and ExplicatioGround. The recorder sets them on
## the live SelectionManager, so the B press in the script goes through the real control path;
## a block that is not a Dictionary, or names a reading that does not exist, is an error, since
## it decides WHAT drill the clip shows. Pure: a function of its argument only.

const DRILLS := {
	"half_file": UnitFormation.ExplicatioDrill.HALF_FILE,
	"alternate_rank": UnitFormation.ExplicatioDrill.ALTERNATE_RANK,
}
const SIDES := {
	"outward": UnitFormation.ExplicatioSide.OUTWARD,
	"inward": UnitFormation.ExplicatioSide.INWARD,
	"spear_side": UnitFormation.ExplicatioSide.SPEAR_SIDE,
	"shield_side": UnitFormation.ExplicatioSide.SHIELD_SIDE,
}
const GROUNDS := {
	"lengthen": UnitFormation.ExplicatioGround.LENGTHEN,
	"same_ground": UnitFormation.ExplicatioGround.SAME_GROUND,
}


## {"drill", "side", "ground"} for the block `raw`, the defaults for any it leaves out, or
## {"error": message} for a block that is not a Dictionary, a key that is not one of the three,
## or a name not in its table.
static func parse(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"error": "explicatio must be an object, got %s" % type_string(typeof(raw))}
	var out := {
		"drill": UnitFormation.ExplicatioDrill.HALF_FILE,
		"side": UnitFormation.ExplicatioSide.OUTWARD,
		"ground": UnitFormation.ExplicatioGround.LENGTHEN,
	}
	var tables := {"drill": DRILLS, "side": SIDES, "ground": GROUNDS}
	for key in raw:
		if not tables.has(key):
			return {"error": "explicatio has no field %s (drill, side, ground)" % str(key)}
		var table: Dictionary = tables[key]
		var name_given := str(raw[key])
		if not table.has(name_given):
			return {"error": "explicatio %s %s is not one of %s" % [key, name_given,
					", ".join(PackedStringArray(table.keys()))]}
		out[key] = table[name_given]
	return out
