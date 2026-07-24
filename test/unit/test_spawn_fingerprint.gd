extends GutTest
## SpawnFingerprint: the spawn-layout digest that lets a demo/replay artifact fail loudly when
## the spawn table drifts out from under it. digest() is pure data-in/hex-out, so
## the sensitivity cases need no scene; of_tree/records_of_tree build records from live units in
## the "units" group and are exercised with a couple of tree-registered fixtures.

const UnitScript = preload("res://scripts/Unit.gd")


func _rec(uid: int, team: int, type: String, x: int, y: int,
		soldiers: int = 100, weapon: int = 0, shield: int = 0, mount: int = 0) -> Dictionary:
	return {"uid": uid, "team": team, "type": type, "weapon": weapon, "shield": shield,
			"mount": mount, "soldiers": soldiers, "x": x, "y": y}


## A tree-registered unit with the fingerprint-relevant fields pinned, so of_tree hashes exactly
## what the test wrote. max_soldiers is set BEFORE add_child so Unit._ready sizes its arrays and
## seeds `soldiers` from it.
func _unit(uid: int, pos: Vector2, type: String = "Spearmen", soldiers: int = 100) -> Unit:
	var u: Unit = UnitScript.new()
	u.max_soldiers = soldiers
	add_child_autofree(u)
	u.uid = uid
	u.team = 0
	u.unit_name = type
	u.position = pos
	return u


func test_digest_is_deterministic_for_the_same_records() -> void:
	var a: Array = [_rec(0, 0, "Spearmen", 100, 300), _rec(1, 1, "Cavalry", 500, 880)]
	var b: Array = [_rec(0, 0, "Spearmen", 100, 300), _rec(1, 1, "Cavalry", 500, 880)]
	assert_eq(SpawnFingerprint.digest(a), SpawnFingerprint.digest(b),
			"identical record lists hash identically")
	assert_ne(SpawnFingerprint.digest(a), "", "a non-empty record list has a non-empty digest")


func test_a_position_change_changes_the_digest() -> void:
	var before: String = SpawnFingerprint.digest([_rec(0, 0, "Spearmen", 100, 300)])
	# The spawn-drift failure mode: a unit re-spaced to a new x. The digest must move so a stamped
	# artifact stops matching.
	var after: String = SpawnFingerprint.digest([_rec(0, 0, "Spearmen", 137, 300)])
	assert_ne(before, after, "a spawn-x change flips the digest")


func test_a_type_change_changes_the_digest() -> void:
	assert_ne(SpawnFingerprint.digest([_rec(0, 0, "Spearmen", 100, 300)]),
			SpawnFingerprint.digest([_rec(0, 0, "Archers", 100, 300)]),
			"swapping the unit type at the same position flips the digest")


func test_a_roster_size_change_changes_the_digest() -> void:
	assert_ne(SpawnFingerprint.digest([_rec(0, 0, "Spearmen", 100, 300, 120)]),
			SpawnFingerprint.digest([_rec(0, 0, "Spearmen", 100, 300, 80)]),
			"a different roster size flips the digest")


func test_a_loadout_id_change_changes_the_digest() -> void:
	assert_ne(SpawnFingerprint.digest([_rec(0, 0, "Spearmen", 100, 300, 100, 1)]),
			SpawnFingerprint.digest([_rec(0, 0, "Spearmen", 100, 300, 100, 2)]),
			"a different weapon type id flips the digest")


func test_of_tree_is_empty_when_no_units_are_on_the_field() -> void:
	assert_eq(SpawnFingerprint.of_tree(get_tree()), "",
			"no units on the field means nothing to stamp or check against")


func test_of_tree_orders_units_by_uid_not_insertion_order() -> void:
	# Insert out of uid order; the digest must not depend on group-enumeration/insertion order,
	# so a rout/rally group move can never change it.
	_unit(7, Vector2(500, 300))
	_unit(3, Vector2(100, 300))
	var uids: Array = []
	for r in SpawnFingerprint.records_of_tree(get_tree()):
		uids.append(r["uid"])
	assert_eq(uids, [3, 7], "records come out in ascending uid order")
	assert_ne(SpawnFingerprint.of_tree(get_tree()), "", "a populated field has a non-empty digest")


func test_sub_world_unit_jitter_does_not_change_the_digest() -> void:
	# Positions round to whole world units: a sub-pixel spawn nudge never moves a click, so it
	# must not flip the digest (that would make the check flap on meaningless float noise).
	var a: Unit = _unit(1, Vector2(100.2, 300.4))
	var before: String = SpawnFingerprint.of_tree(get_tree())
	a.position = Vector2(100.4, 300.1)
	assert_eq(SpawnFingerprint.of_tree(get_tree()), before,
			"a sub-world-unit position nudge leaves the digest unchanged")
	a.position = Vector2(105.0, 300.0)
	assert_ne(SpawnFingerprint.of_tree(get_tree()), before,
			"a whole-world-unit move does change it")


func test_digest_reads_max_soldiers_not_the_live_casualty_count() -> void:
	# record_of reads max_soldiers (the deployed roster), never the live `soldiers`, so the
	# layout hashes identically whether taken at spawn or after casualties mid-battle.
	var u: Unit = _unit(1, Vector2(100, 300), "Spearmen", 100)
	var at_spawn: String = SpawnFingerprint.of_tree(get_tree())
	u.soldiers = 40   # simulate casualties
	assert_eq(SpawnFingerprint.of_tree(get_tree()), at_spawn,
			"a mid-battle casualty count does not change the spawn fingerprint")
