class_name UnitReinforce
## Reinforcement insertion (Asclepiodotus, Tactics 10.17, doubling by NUMBER): a reserve
## marches up behind a friendly host and its men file into the host's ranks, doubling the
## host's files. Static and deterministic (no RNG), so live play and replay insert alike. The
## reserve's REINFORCE order carries the relief pass-through link (friendly_target) so it can
## walk into the host's rear; the commit runs once, in the physics tick, at the rendezvous.

const ReinforceLayoutRef = preload("res://scripts/ReinforceLayout.gd")

## Default heading agreement the commit waits for (radians between the two facings).
const HEADING_TOLERANCE_RAD: float = deg_to_rad(20.0)

## Battle.ReinforceAxis.FILES, mirrored as an int (as Unit mirrors Battle.OrderMode) so this
## helper stays decoupled from Battle.gd. The only axis wired so far: RANKS is refused.
const AXIS_FILES: int = 1


## Why `reserve` may not reinforce `host` along `axis` right now, or "" when it may: the HUD
## flash on a refused gesture, re-run per unit at Battle's apply site so a replay refuses
## where live play did, and again every tick of the approach so a pair that stops qualifying
## mid-march halts instead of committing. `axis` is a Battle.ReinforceAxis value.
static func refusal_reason(reserve: Unit, host: Unit, axis: int = AXIS_FILES) -> String:
	if axis != AXIS_FILES:
		return "Insertion by ranks is not yet available"
	if reserve == host:
		return "A regiment cannot reinforce itself"
	if reserve.team != host.team:
		return "Reinforce a friendly regiment"
	for u in [reserve, host]:
		if u.state == Unit.State.ROUTING or u.state == Unit.State.DEAD:
			return "%s is not a steady body" % u.unit_name
	# Contact is a physical fact (Unit._in_enemy_contact), not only the FIGHTING state: a
	# reserve whose bodies still touch an enemy while disengaging cannot file off either.
	if reserve.state == Unit.State.FIGHTING or reserve._in_enemy_contact:
		return "%s is in contact and cannot file off" % reserve.unit_name
	if reserve.weapon_type_id != host.weapon_type_id or reserve.shield_type_id != host.shield_type_id:
		return "Loadouts differ: only like-armed regiments interleave"
	if host.in_square():
		return "%s is squared and has no files to open" % host.unit_name
	# A far-tier regiment carries no per-soldier bodies, so it has nothing to interleave
	# into (host) and nothing to file in with (reserve): the commit could never align.
	for u in [reserve, host]:
		if u.tier == FormationTier.FAR:
			return "%s is too distant a body to interleave" % u.unit_name
	if not host._effective_file_major_reform():
		return "%s does not hold files (row-major reflow)" % host.unit_name
	return ""


## Where the reserve marches to: one host rank pitch behind the host's rear edge, plus its
## own half-depth, so the two blocks stand clear before the men file in.
static func rendezvous_point(host: Unit, reserve: Unit) -> Vector2:
	var gap: float = host.soldier_block_half_extents().y + reserve.soldier_block_half_extents().y \
			+ host.rank_pitch_wu()
	return host.position - host.facing * gap


## Arm the approach on `order` (the reserve's REINFORCE order, already current): link the
## pair and aim the reserve at the rendezvous with the host's heading held; the host keeps
## whatever it was doing. A refused pair arms nothing and halts the reserve where it stands
## (a march left over from its previous order would otherwise coast on under the dangling
## order, which retires only once no march is in flight).
static func begin(reserve: Unit, host: Unit, order: Order) -> void:
	if refusal_reason(reserve, host, order.reinforce_axis) != "":
		_halt(reserve, order)
		return
	order.friendly_target = host
	reserve.target_enemy = null
	_aim(reserve, host)


## Per-tick approach: drop the link and halt when the host is gone or the pair no longer
## qualifies, re-aim at a drifting host, and commit once the reserve stands at the
## rendezvous facing the host's way.
static func update(reserve: Unit, heading_tolerance_rad: float = HEADING_TOLERANCE_RAD) -> void:
	var order: Order = reserve.current_order
	if order == null or order.type != Order.Type.REINFORCE or order.friendly_target == null:
		return
	var host: Unit = order.friendly_target
	if not is_instance_valid(host) or refusal_reason(reserve, host, order.reinforce_axis) != "":
		_halt(reserve, order)
		return
	_aim(reserve, host)
	var pitch: float = host.rank_pitch_wu()
	var at_rendezvous: bool = reserve.position.distance_squared_to(reserve.move_target) <= pitch * pitch
	var aligned: bool = absf(reserve.facing.angle_to(host.facing)) <= heading_tolerance_rad
	if at_rendezvous and aligned and _bodies_aligned(reserve) and _bodies_aligned(host):
		commit(reserve, host)


## The reserve's men file into the host: interleave the ids, carry the per-soldier arrays
## across, pool strength, install the assignment, hold the host's anchor for the arrival (or
## the centroid coupling would back the line up to the newcomers), and remove the reserve.
static func commit(reserve: Unit, host: Unit) -> void:
	var files: int = UnitFormation.frontage(host)
	host._ensure_file_assignment(host.soldiers, files)
	var layout: Dictionary = ReinforceLayoutRef.interleave_files(host._sim_soldier_file,
			host._sim_soldier_rank, files, host.to_slot_frame(reserve._sim_soldier_pos))
	host.append_soldier_bodies(reserve)
	host.pool_strength(reserve, host.reinforce_cohesion_floor)
	host.install_file_assignment(layout["file_ids"], layout["ranks"], int(layout["files"]))
	host.hold_position_anchor(host._reshape_timeout(files))
	reserve.current_order.friendly_target = null
	reserve._merged_away()
	host.queue_redraw()


static func _aim(reserve: Unit, host: Unit) -> void:
	reserve.move_target = rendezvous_point(host, reserve)
	reserve.has_move_target = true
	reserve.ordered_facing = host.facing


## Drop the pass-through link and stop the reserve where it stands; with no link and no
## march in flight, Unit._update_current_order retires the REINFORCE order next tick.
static func _halt(reserve: Unit, order: Order) -> void:
	order.friendly_target = null
	reserve.has_move_target = false
	reserve.ordered_facing = Vector2.ZERO


## Body layers match the count (a casualty leaves them one tick out of step until resized).
static func _bodies_aligned(u: Unit) -> bool:
	return u._sim_soldier_pos.size() == u.soldiers and u._sim_soldier_hp.size() == u.soldiers
