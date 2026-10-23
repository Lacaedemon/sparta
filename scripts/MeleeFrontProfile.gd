class_name MeleeFrontProfile
extends RefCounted
## A block's front-line measurements (MeleeFrontGeometry): whether it can take part in an
## extension, its front-rank depth, its front half-width, its extension bound and how far that
## reaches past a centre-based contact range (MeleeFrontGeometry.query_extension). Every contact
## scan reads them for every pair, so each unit keeps one profile, recomputed when an input it
## was computed from changes. Every call compares, without allocating, every input an order or
## the sim changes (headcount, file assignment generation and file count, formation, frontage,
## anchor, closed ranks, tier, reform mode, scale, type flags). The spacing and pitches change
## only with the formation, and the strength cap, discipline and sub-unit fields only at spawn,
## a merge or a restore, each alongside one of those; they are compared once per physics frame.

var eligible: bool = false
var depth: float = 0.0
var half: float = 0.0
var ext: float = 0.0
var beyond: float = 0.0

var _soldiers: int = -1
var _gen: int = -1
var _assigned: int = -2
var _formation: int = -1
var _frontage: int = -1
var _anchor: float = NAN
var _closed: bool = false
var _tier: int = -1
var _reform: int = -1
var _scale: float = NAN
var _flags: int = -1
var _frame: int = -1
var _spacing: float = NAN
var _file_pitch: float = NAN
var _rank_pitch: float = NAN
var _cap: int = -1
var _spawn_flags: int = -1


## `u`'s profile, recomputed first when an input has changed.
static func of(u: Unit) -> MeleeFrontProfile:
	var p: MeleeFrontProfile = u._front_profile
	if p == null:
		p = MeleeFrontProfile.new()
		u._front_profile = p
	var stale: bool = p._soldiers != u.soldiers or p._gen != u._file_assignment_gen \
			or p._assigned != u._file_assignment_files or p._formation != u.formation_mode \
			or p._frontage != u.frontage_override or p._anchor != u.frontage_anchor_offset \
			or p._closed != u._ranks_closed or p._tier != u.tier \
			or p._reform != u.file_major_reform_mode or p._scale != u.melee_front_line_scale \
			or p._flags != int(u.is_cavalry) + 2 * int(u.is_ranged)
	var frame: int = Engine.get_physics_frames()
	if frame != p._frame:
		p._frame = frame
		stale = stale or p._spacing != u.spacing_scale or p._file_pitch != u.file_pitch \
				or p._rank_pitch != u.rank_pitch or p._cap != u.max_soldiers \
				or p._spawn_flags != int(u.disciplined) + 2 * u.subunit_structure + 64 * u.subunit_size
	if stale:
		p._compute(u)
	return p


func _compute(u: Unit) -> void:
	_soldiers = u.soldiers
	_gen = u._file_assignment_gen
	_assigned = u._file_assignment_files
	_formation = u.formation_mode
	_frontage = u.frontage_override
	_anchor = u.frontage_anchor_offset
	_closed = u._ranks_closed
	_tier = u.tier
	_reform = u.file_major_reform_mode
	_scale = u.melee_front_line_scale
	_flags = int(u.is_cavalry) + 2 * int(u.is_ranged)
	_spacing = u.spacing_scale
	_file_pitch = u.file_pitch
	_rank_pitch = u.rank_pitch
	_cap = u.max_soldiers
	_spawn_flags = int(u.disciplined) + 2 * u.subunit_structure + 64 * u.subunit_size
	eligible = u.melee_front_line_scale > 0.0 and not u.is_cavalry and not u.is_ranged \
			and u.tier != FormationTier.FAR
	var files: int = maxi(1, u.formation_files(u.soldiers))
	var ranks: int = u.live_rank_count(files)
	var pitch: float = u.file_pitch_wu() if u.in_square() else u.rank_pitch_wu()   # a square: both
	depth = float(maxi(0, ranks - 1)) * 0.5 * pitch
	half = float(mini(files, maxi(1, u.soldiers)) - 1) * 0.5 * u.file_pitch_wu()
	ext = 0.0
	beyond = 0.0
	if eligible:
		# The farthest it reaches along any axis. A line met in flank or rear reaches its
		# outline (MeleeFrontGeometry.outline), at most its slot rectangle's half-diagonal; a
		# square keeps its looser bound.
		var reach: float = depth + half if u.in_square() else sqrt(depth * depth + half * half)
		ext = reach + absf(u.frontage_anchor_offset)
		beyond = maxf(0.0, reach - Unit.RADIUS) + absf(u.frontage_anchor_offset)
