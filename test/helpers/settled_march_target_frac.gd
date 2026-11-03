extends RefCounted
## Shared by the soldier-body tests that call SoldierBodies.arrival_target directly. Not a
## GUT test (no test_ prefix), so the runner never collects it; preload it as a const.


## The arrival-target blend of a march long under way (SoldierBodies.advance_march_target_frac
## ramps it to 1 over the march's first moments): wholly the marching target while the unit
## marches, wholly the standing one while it does not.
static func settled_frac(u: Unit) -> float:
	return 1.0 if SoldierBodies.is_marching(u) else 0.0
