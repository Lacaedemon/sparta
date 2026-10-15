class_name MeleeFrontProfile
extends RefCounted
## A block's front-line measurements (MeleeFrontGeometry): whether it can take part in an
## extension, its front-rank depth, its front half-width and its extension bound. Every contact
## scan reads them for every pair, so each unit keeps one profile, recomputed when an input it
## was computed from changes. Every call compares the inputs that change within a tick (the
## headcount, the file assignment's generation, the formation, frontage, anchor and closed-ranks
## state, the tier, the scale and the type flags); the first call of each physics frame also
## compares the rest (the spacing and pitches, which follow the formation, and the reform mode).

var eligible: bool = false
var depth: float = 0.0
var half: float = 0.0
var ext: float = 0.0

var _frame: int = -1
var _hot := PackedFloat64Array()
var _cold := PackedFloat64Array()


## `u`'s profile, recomputed first when an input has changed.
static func of(u: Unit) -> MeleeFrontProfile:
	var p: MeleeFrontProfile = u._front_profile
	if p == null:
		p = MeleeFrontProfile.new()
		u._front_profile = p
	var hot := PackedFloat64Array([u.soldiers, u._file_assignment_gen, u.formation_mode,
			u.frontage_override, u.frontage_anchor_offset, int(u._ranks_closed), u.tier,
			u.melee_front_line_scale, int(u.is_cavalry) + 2 * int(u.is_ranged)])
	var frame: int = Engine.get_physics_frames()
	if frame != p._frame:
		p._frame = frame
		var cold := PackedFloat64Array([u.max_soldiers, u._file_assignment_files,
				u.file_major_reform_mode, int(u.disciplined), u.subunit_structure, u.subunit_size,
				u.spacing_scale, u.file_pitch, u.rank_pitch])
		if cold != p._cold:
			p._cold = cold
			p._hot = PackedFloat64Array()
	if hot != p._hot:
		p._hot = hot
		p._compute(u)
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
