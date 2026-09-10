class_name ReinforceGuard
## The admission guard for reinforcement insertion (UnitReinforce): why a reserve may not
## file into a host right now. Pure and static, so the HUD preview, Battle's apply site,
## and the per-tick approach all refuse identically, in live play and in replay alike.

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
		if u.soldiers <= 0:
			return "%s has no soldiers to contribute" % u.unit_name
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
	if host.subunit_structure == Unit.SubunitStructure.FILE_GROUP:
		return "%s has file-group subunits and cannot interleave" % host.unit_name
	return ""

