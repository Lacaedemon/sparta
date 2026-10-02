extends GutTest
## The default battle's line spawn puts every block where it can stand: its front rank on
## its spawn line, its whole footprint on the field, clear of block terrain, and clear of
## every enemy block. A deep cavalry squadron centred on its line used to reach half its
## 960 wu depth toward the enemy -- into the hill and into the enemy's own cavalry -- and
## its rear ranks hung off the field. Checked against the live soldier slots, not by
## eyeballing a render.


func _spawn_default_battle() -> Array[Unit]:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame
	var units: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		units.append(node as Unit)
	return units


## World-space rect bounding a unit's formation slots, grown by its soldiers' body radius.
func _slot_bounds(u: Unit) -> Rect2:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var box := Rect2(slots[0], Vector2.ZERO)
	for p in slots:
		box = box.expand(p)
	return box.grow(u.soldier_body_radius())


func test_every_line_block_dresses_its_front_rank_on_its_line() -> void:
	var units: Array[Unit] = await _spawn_default_battle()
	assert_eq(units.size(), 10, "the default 5v5 spawns")
	for u in units:
		var line_y: float = float(Battle.SPAWN_LINE_YS[u.team])
		var front: float = -INF
		for p in u.soldier_world_slots(u.soldiers):
			front = maxf(front, p.y * u.facing.y)
		assert_almost_eq(front * u.facing.y, line_y, 0.01,
				"%s's front rank stands on its spawn line" % u.unit_name)


func test_every_line_block_is_on_the_field_and_clear_of_block_terrain() -> void:
	var units: Array[Unit] = await _spawn_default_battle()
	for u in units:
		var box: Rect2 = _slot_bounds(u)
		assert_true(Battle.FIELD.encloses(box),
				"%s's footprint %s is on the field %s" % [u.unit_name, box, Battle.FIELD])
		for patch in Battle.TERRAIN:
			if patch["kind"] == "block":
				assert_false(box.intersects(patch["rect"]),
						"%s's footprint %s is clear of the %s" % [u.unit_name, box, patch["type"]])


func test_no_line_block_overlaps_an_enemy_block() -> void:
	var units: Array[Unit] = await _spawn_default_battle()
	for a in units:
		for b in units:
			if a.team == 0 and b.team == 1:
				assert_false(_slot_bounds(a).intersects(_slot_bounds(b)),
						"%s and enemy %s start apart" % [a.unit_name, b.unit_name])


func test_every_line_block_opens_at_the_close_tier() -> void:
	# The fronts stand 360 wu apart, inside PROMOTE_RANGE measured edge to edge, so a deep
	# cavalry squadron whose centre is 480 wu behind its front still opens close-tier.
	var units: Array[Unit] = await _spawn_default_battle()
	await get_tree().physics_frame
	for u in units:
		assert_eq(u.tier, FormationTier.CLOSE, "%s opens at the close tier" % u.unit_name)


func test_default_sight_scale_is_independent_of_the_field_size() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame
	assert_eq(battle.sight_scale, Unit.DEFAULT_SIGHT_SCALE, "default sight is the fixed 15 m")
