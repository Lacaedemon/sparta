class_name CommandReportInbox
extends RefCounted
## Where an AI commander (the general, a subcommander, or the unit leader acting for them)
## receives the order-outcome reports its units send upward: a unit that amended or refused
## an order tells whoever issued it (see OrderOutcomeReport). Advisory data, like every
## upward report: it keeps the latest report per unit so a commander's next decision can
## read it, and does nothing on its own. A re-planning commander calls latest() for a unit
## it ordered and acknowledge()s the report once it has acted on it.

## Latest unacknowledged report per unit uid.
var _latest: Dictionary = {}


## Record `report`, replacing any earlier one from the same unit.
func receive(report: OrderOutcomeReport) -> void:
	_latest[report.unit.uid] = report


## The latest unacknowledged report from the unit with `uid`, or null when there is none.
func latest(uid: int) -> OrderOutcomeReport:
	return _latest.get(uid)


## Mark the unit's report as handled.
func acknowledge(uid: int) -> void:
	_latest.erase(uid)


## How many units have an unacknowledged report waiting.
func pending_count() -> int:
	return _latest.size()
