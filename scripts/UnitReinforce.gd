class_name UnitReinforce
## Reinforcement insertion (Asclepiodotus, Tactics 10.17, doubling by NUMBER): a reserve
## marches up behind a friendly host and its men file into the host's ranks, doubling the
## host's files. Static and deterministic (no RNG), so live play and replay insert alike. The
## reserve's REINFORCE order carries the relief pass-through link (friendly_target) so it can
## walk into the host's rear; the commit runs once, in the physics tick, at the rendezvous.

const ReinforceLayoutRef = preload("res://scripts/ReinforceLayout.gd")

## Default heading agreement the commit waits for (radians between the two facings).
const HEADING_TOLERANCE_RAD: float = deg_to_rad(20.0)


## Why `reserve` may not reinforce `host` right now, or "" when it may: the HUD flash on a
## refused gesture, re-run at Battle's apply site so a replay refuses where live play did.
static func refusal_reason(reserve: Unit, host: Unit) -> String:
	if reserve == host:
		return "A regiment cannot reinforce itself"
	if reserve.team != host.team:
		return "Reinforce a friendly regiment"
	for u in [reserve, host]:
		if u.state == Unit.State.ROUTING or u.state == Unit.State.DEAD:
			return "%s is not a steady body" % u.unit_name
	if reserve.state == Unit.State.FIGHTING:
		return "%s is in contact and cannot file off" % reserve.unit_name
	if reserve.weapon_type_id != host.weapon_type_id or reserve.shield_type_id != host.shield_type_id:
		return "Loadouts differ: only like-armed regiments interleave"
	if host.in_square():
		return "%s is squared and has no files to open" % host.unit_name
	if host.tier == FormationTier.FAR:
		return "%s is too distant a body to interleave into" % host.unit_name
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
## whatever it was doing. A refused pair arms nothing, so the no-op order retires.
static func begin(reserve: Unit, host: Unit, order: Order) -> void:
	if refusal_reason(reserve, host) != "":
		return
	order.friendly_target = host
	reserve.target_enemy = null
	_aim(reserve, host)


## Per-tick approach: drop the link when the host is gone, re-aim at a drifting host, and
## commit once the reserve stands at the rendezvous facing the host's way.
static func update(reserve: Unit, heading_tolerance_rad: float = HEADING_TOLERANCE_RAD) -> void:
	var order: Order = reserve.current_order
	if order == null or order.type != Order.Type.REINFORCE or order.friendly_target == null:
		return
	var host: Unit = order.friendly_target
	if not is_instance_valid(host) or host.state == Unit.State.DEAD or host.state == Unit.State.ROUTING:
		order.friendly_target = null
		reserve.has_move_target = false
		reserve.ordered_facing = Vector2.ZERO
		return
	_aim(reserve, host)
	var at_rendezvous: bool = reserve.position.distance_to(reserve.move_target) <= host.rank_pitch_wu()
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


## Body layers match the count (a casualty leaves them one tick out of step until resized).
static func _bodies_aligned(u: Unit) -> bool:
	return u._sim_soldier_pos.size() == u.soldiers and u._sim_soldier_hp.size() == u.soldiers
