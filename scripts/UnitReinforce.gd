class_name UnitReinforce
## Reinforcement insertion (Asclepiodotus, Tactics 10.17, doubling by NUMBER): a reserve
## marches up behind a friendly host and its men file into the host's ranks, doubling the
## host's files. Static and deterministic (no RNG), so live play and replay insert alike. The
## reserve's REINFORCE order carries the relief pass-through link (friendly_target) so it can
## walk into the host's rear; the commit runs once, in the physics tick, at the rendezvous.
## Admission lives in ReinforceGuard.refusal_reason, shared with the HUD preview; the
## rendezvous geometry (where, and whether the reserve is there yet) in ReinforceApproach.

const ReinforceLayoutRef = preload("res://scripts/ReinforceLayout.gd")

## Default heading agreement the commit waits for (radians between the two facings).
## Calibrated from recordings.
## Twenty degrees tolerates march drift without stalling the commit.
const HEADING_TOLERANCE_RAD: float = deg_to_rad(20.0)


## Arm the approach on `order` (the reserve's REINFORCE order, already current): link the
## pair, drop the reserve's stance to NORMAL (a persistent auto-targeting stance such as
## CHASE would otherwise pull it off the rendezvous at the first nearby enemy), and aim it
## at the rendezvous with the host's heading held; the host keeps whatever it was doing.
## Battle refuses a bad pair before installing the order; this re-check halts the reserve
## where it stands for anything that slips past (the dangling order retires next tick).
static func begin(reserve: Unit, host: Unit, order: Order) -> void:
	if ReinforceGuard.refusal_reason(reserve, host, order.reinforce_axis) != "":
		_halt(reserve, order)
		return
	order.friendly_target = host
	reserve.order_mode = 0   # Battle.OrderMode.NORMAL, mirrored as an int as Unit does
	reserve.target_enemy = null
	_aim(reserve, host)


## Per-tick approach: drop the link and halt when the host is gone or the pair no longer
## qualifies, re-aim at a drifting host, and commit once the reserve stands at the
## rendezvous facing the host's way. If the reserve routes, the routing gate in Unit
## bypasses this update and _rout() clears the order and friendly_target link.
static func update(reserve: Unit, heading_tolerance_rad: float = HEADING_TOLERANCE_RAD) -> void:
	var order: Order = reserve.current_order
	if order == null or order.type != Order.Type.REINFORCE or order.friendly_target == null:
		return
	var host: Unit = order.friendly_target
	if not is_instance_valid(host) or ReinforceGuard.refusal_reason(reserve, host, order.reinforce_axis) != "":
		_halt(reserve, order)
		return
	_aim(reserve, host)
	var aligned: bool = absf(reserve.facing.angle_to(host.facing)) <= heading_tolerance_rad
	if aligned and ReinforceApproach.at_rendezvous(reserve, host) \
			and _bodies_aligned(reserve) and _bodies_aligned(host):
		commit(reserve, host)


## The reserve's men file into the host: interleave the ids, carry the per-soldier arrays
## across, pool strength, install the assignment, move the anchor rearward by half of any
## depth the interleave added (the slot grid is centred on depth, so a partial or surplus
## reserve would otherwise push the front rank forward), hold the anchor for the arrival
## (or the centroid coupling would back the line up to the newcomers), and remove the reserve.
static func commit(reserve: Unit, host: Unit) -> void:
	var files: int = UnitFormation.frontage(host)
	host._ensure_file_assignment(host.soldiers, files)
	# The old depth is the persistent rank array's (a rear survivor keeps a deeper file
	# through casualties); a freshly balanced capacity count only when that array is unset.
	var old_ranks: int = ReinforceApproach.deepest(host._sim_soldier_rank) + 1 \
			if host._sim_soldier_rank.size() == host.soldiers \
			else ReinforceApproach.deepest(UnitFormation.file_capacities(host.soldiers, files))
	var layout: Dictionary = \
			ReinforceLayoutRef.interleave_files(host._sim_soldier_file, host._sim_soldier_rank, files, host.to_slot_frame(reserve._sim_soldier_pos))
	var new_ranks: int = ReinforceApproach.deepest(layout["ranks"]) + 1
	host.append_soldier_bodies(reserve)
	host.pool_strength(reserve, host.reinforce_cohesion_floor)
	# `files` is the pre-pool frontage: pooling can already have raised the automatic
	# frontage to the interleaved width, and the reshape bookkeeping keys on the change.
	host.install_file_assignment(layout["file_ids"], layout["ranks"], int(layout["files"]), files)
	host.position -= ReinforceApproach.depth_axis(host) * ReinforceLayoutRef.rear_anchor_shift(old_ranks, new_ranks, host.rank_pitch_wu())
	host.hold_position_anchor(host._reshape_timeout(files))
	reserve.current_order.friendly_target = null
	reserve._merged_away()
	host.queue_redraw()

static func _aim(reserve: Unit, host: Unit) -> void:
	reserve.move_target = ReinforceApproach.rendezvous_point(host, reserve)
	reserve.has_move_target = true
	reserve.ordered_facing = host.facing


## Drop the pass-through link and stop the reserve where it stands -- no march, no enemy
## left over from a previous order for targeting to resume on -- so that with no link and
## no march in flight, Unit._update_current_order retires the REINFORCE order next tick.
static func _halt(reserve: Unit, order: Order) -> void:
	order.friendly_target = null
	reserve.has_move_target = false
	reserve.ordered_facing = Vector2.ZERO
	reserve.target_enemy = null


## Body layers match the count (a casualty leaves them one tick out of step until resized).
static func _bodies_aligned(u: Unit) -> bool:
	return u._sim_soldier_pos.size() == u.soldiers and u._sim_soldier_hp.size() == u.soldiers
