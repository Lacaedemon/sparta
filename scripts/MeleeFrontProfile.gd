class_name MeleeFrontProfile
extends RefCounted
## A block's front-line measurements (MeleeFrontGeometry): whether it can take part in an
## extension, its front-rank depth, its front half-width and its extension bound. Every contact
## scan reads them for every pair, so each unit keeps one profile, recomputed only when an input
## it was computed from changes. The key is those inputs themselves, read straight off the unit:
## the headcount, frontage, formation and spacing, tier, type flags, reform mode and the file
## assignment's generation. Nothing has to invalidate it, and it is never read stale.

var eligible: bool = false
var depth: float = 0.0
var half: float = 0.0
var ext: float = 0.0

var _ints := PackedInt64Array()
var _floats := PackedFloat64Array()


## `u`'s profile, recomputed first when any input has changed.
static func of(u: Unit) -> MeleeFrontProfile:
	var p: MeleeFrontProfile = u._front_profile
	if p == null:
		p = MeleeFrontProfile.new()
		u._front_profile = p
	var ints := PackedInt64Array([u.soldiers, u.max_soldiers, u.frontage_override,
			int(u._ranks_closed), u.formation_mode, u.tier, u._file_assignment_gen,
			u._file_assignment_files, u.file_major_reform_mode,
			int(u.is_cavalry) | (int(u.is_ranged) << 1) | (int(u.disciplined) << 2),
			u.subunit_structure, u.subunit_size])
	var floats := PackedFloat64Array([u.melee_front_line_scale, u.spacing_scale, u.file_pitch,
			u.rank_pitch, u.frontage_anchor_offset])
	if ints != p._ints or floats != p._floats:
		p._compute(u)
		p._ints = ints
		p._floats = floats
	return p


func _compute(u: Unit) -> void:
	eligible = u.melee_front_line_scale > 0.0 and not u.is_cavalry and not u.is_ranged \
			and u.tier != FormationTier.FAR
	var files: int = maxi(1, u.formation_files(u.soldiers))
	var ranks: int = u.live_rank_count(files)
	# A square lays both axes at its file pitch.
	var pitch: float = u.file_pitch_wu() if u.in_square() else u.rank_pitch_wu()
	depth = float(maxi(0, ranks - 1)) * 0.5 * pitch
	half = float(mini(files, maxi(1, u.soldiers)) - 1) * 0.5 * u.file_pitch_wu()
	ext = 0.0
	if eligible:
		ext = depth + (half if u.in_square() else 0.0) + absf(u.frontage_anchor_offset)
