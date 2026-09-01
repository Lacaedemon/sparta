class_name StanceTable
extends RefCounted
## Central flags table and query API for OrderMode stances.
## Defines orthogonal behavioral flags for each stance (acquisition, response,
## movement, reflow, and leashing), eliminating ad-hoc enum branching across hot paths.

class StanceFlags extends RefCounted:
	var target_visible_enemies: bool = true
	var target_attackers_always: bool = true
	var respond_chase: bool = false
	var respond_stand_ground: bool = false
	var respond_hold_ground: bool = false
	var can_give_ground: bool = false
	var is_pushing: bool = false
	var flank_wrap: bool = false
	var multi_engage_reflow: bool = false
	var march_to_contact: bool = false
	var auto_advance: bool = true
	var allow_intermixing: bool = true
	var default_leash_radius: float = 0.0

static var _default := StanceFlags.new()

static var _table: Dictionary = _init_table()

static func _init_table() -> Dictionary:
	var t: Dictionary = {}
	var make_flags = func(d: Dictionary) -> StanceFlags:
		var f := StanceFlags.new()
		for k in d:
			f.set(k, d[k])
		return f
	t[1] = make_flags.call({"target_visible_enemies": false, "respond_stand_ground": true, "respond_hold_ground": true, "auto_advance": false, "allow_intermixing": false})
	t[7] = make_flags.call({"respond_chase": true})
	t[8] = make_flags.call({"respond_chase": true})
	t[9] = make_flags.call({"respond_stand_ground": true, "auto_advance": false, "default_leash_radius": 300.0})
	t[10] = make_flags.call({"respond_chase": true})
	t[11] = make_flags.call({"respond_chase": true})
	t[14] = make_flags.call({"can_give_ground": true, "auto_advance": false})
	t[15] = make_flags.call({"is_pushing": true})
	t[16] = make_flags.call({"multi_engage_reflow": true})
	t[17] = make_flags.call({"march_to_contact": true, "auto_advance": false})
	t[18] = make_flags.call({"target_visible_enemies": false, "respond_stand_ground": true, "respond_hold_ground": true, "auto_advance": false, "allow_intermixing": false})
	t[19] = make_flags.call({"flank_wrap": true})
	return t

static func get_flags(mode: int) -> StanceFlags:
	return _table.get(mode, _default)

static func can_auto_advance(mode: int) -> bool:
	return get_flags(mode).auto_advance

static func allows_intermixing(mode: int) -> bool:
	return get_flags(mode).allow_intermixing

static func can_acquire_visible(mode: int) -> bool:
	return get_flags(mode).target_visible_enemies

static func should_chase(mode: int) -> bool:
	return get_flags(mode).respond_chase

static func is_march_to_contact(mode: int) -> bool:
	return get_flags(mode).march_to_contact

static func is_giving_ground(mode: int) -> bool:
	return get_flags(mode).can_give_ground

static func is_pushing(mode: int) -> bool:
	return get_flags(mode).is_pushing

static func has_flank_wrap(mode: int) -> bool:
	return get_flags(mode).flank_wrap

static func has_multi_engage_reflow(mode: int) -> bool:
	return get_flags(mode).multi_engage_reflow

static func default_leash(mode: int) -> float:
	return get_flags(mode).default_leash_radius
