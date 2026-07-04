class_name TransientEffect
extends Node2D
## Shared base for a short-lived cosmetic effect: age up every render frame, redraw, and
## free itself once its lifetime elapses. Every instance is exactly one effect kind for its
## whole life (spawned once, freed once) -- there's no runtime reclassification and no case
## where a single node needs more than one effect's behavior at once, so a subclass per kind
## is a clean fit here, unlike Unit's combinatorial trait space. Purely presentational: no
## sim/replay/determinism state, not in the "units"/"routers" groups, so no sim scan ever
## picks a subclass instance up.
##
## A subclass's `spawn()` sets `_lifetime` from its own `LIFETIME` constant (kept as each
## subclass's own constant, not hoisted here, so `Fallen.LIFETIME` etc. stay directly
## referenceable the way the existing tests already use them) and defines its own `_draw()`;
## this base owns only the shared age/free bookkeeping. See Fallen, VolleyTrail, and
## RoutShockwave for the three current effect kinds.

var _age: float = 0.0
var _lifetime: float = 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	queue_redraw()
