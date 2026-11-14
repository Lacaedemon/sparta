class_name SoldierFootPursuit
extends RefCounted
## How far a foot unit follows a rout it has broken. In the sim foot keep their ranks and follow it
## as a block (horse ride it down man by man, SoldierPursuitStep); how far is a named variant
## (Unit.foot_pursuit).

## FOLLOW: the sim's choice, the default; the block follows its routed target for as long as it
## has one, as any attack does. SHORT: the block breaks off once the runners are out of its
## reach, as the Spartans pursued for a short time and not far (Thucydides 5.73.4).
enum Mode { FOLLOW, SHORT }


## Whether foot unit `u` breaks off following its routed target `t` (UnitTargeting.current_target):
## under SHORT, once no enemy is within its contact any more; never for horse or under FOLLOW.
static func breaks_off(u: Unit, t: Unit) -> bool:
	return u.foot_pursuit == Mode.SHORT and not u.is_cavalry and t.state == Unit.State.ROUTING \
			and not u._in_enemy_contact


## Whether foot unit `u` is following a rout in its ranks: on the move or fighting after a routed
## target. Its men come out of the press off their places while the runners pull away, so the
## same-unit standoff's contact band acts on them as in a hold (SoldierBodies._separate_same_unit).
static func follows_rout(u: Unit) -> bool:
	if u.is_cavalry or u.state == Unit.State.ROUTING:
		return false
	var t: Unit = u.target_enemy
	return is_instance_valid(t) and t.state == Unit.State.ROUTING


## The candidates a foot unit that has broken off may take up again (UnitTargeting.nearest_enemy's
## predicate): anything but a routed unit.
static func not_routed(e: Unit) -> bool:
	return e.state != Unit.State.ROUTING
