class_name OrderOutcomeReport
extends RefCounted
## What a unit tells whoever gave it a move order when it amends or refuses that order:
## the destination it was asked for, where it will go instead (or that it holds), and why.
## Built by Unit at the one point a move_target write is clamped (see
## Unit._report_order_outcome), as a pure function of sim state, so live play and replay
## derive the same report without recording it. An order carried out as given produces none.

## Why the order was amended or refused.
enum Reason {
	## Pulled back along the move short of impassable block terrain.
	CLAMPED_TERRAIN,
	## Pulled back along the move so the footprint stays on the field.
	CLAMPED_FIELD_EDGE,
	## Nothing along the move is clear: the unit holds where it stands.
	REFUSED_HOLD,
}

## The unit that amended or refused the order.
var unit: Unit
## The destination the order asked for.
var requested: Vector2
## The destination the unit will march to instead; the unit's own position when it holds.
var granted: Vector2
var reason: int


## Build a report for `unit_` whose order toward `requested_` was cut to `granted_`.
static func create(unit_: Unit, requested_: Vector2, granted_: Vector2, reason_: int) -> OrderOutcomeReport:
	var r := OrderOutcomeReport.new()
	r.unit = unit_
	r.requested = requested_
	r.granted = granted_
	r.reason = reason_
	return r


## Whether the order was refused outright (the unit holds) rather than cut short.
func is_hold() -> bool:
	return reason == Reason.REFUSED_HOLD


## The one-line, plain text a player is shown, naming the unit.
func message() -> String:
	var name_: String = unit.unit_name if unit != null else "Unit"
	match reason:
		Reason.CLAMPED_TERRAIN:
			return "%s: halting short of impassable ground" % name_
		Reason.CLAMPED_FIELD_EDGE:
			return "%s: halting at the edge of the field" % name_
		_:
			return "%s: no way through -- holding" % name_
