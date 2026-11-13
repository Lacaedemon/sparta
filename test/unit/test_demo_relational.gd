extends GutTest
## DemoRelations and DemoRelational: the men judged against the men they follow. Every test
## builds a grid of men directly, derives its relations with DemoRelations.plan, and moves or
## swaps men to build one known defect.

const PITCH := 9.0
const RANK := 12.0


## Local grid cells (x to the right, y behind), file-major: rank 0 is the front row.
func _local(files: int, ranks: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in range(ranks):
		for f in range(files):
			out.push_back(Vector2(f * PITCH, r * RANK))
	return out


## The relations a dump would carry for `local`, as the JSON arrays the analyzer reads.
func _rel(local: PackedVector2Array, mirror: float = 1.0) -> Dictionary:
	var plan: Dictionary = DemoRelations.plan(local, mirror, PITCH, RANK)
	var offsets: Array = []
	for o in plan["offsets"]:
		offsets.append([o.x, o.y])
	var dress_offsets: Array = []
	for o in plan["dress_offsets"]:
		dress_offsets.append([o.x, o.y])
	return {"leaders": Array(plan["leaders"]), "offsets": offsets,
			"dress": Array(plan["dress"]), "dress_offsets": dress_offsets}


## The men standing on `local` turned by `angle` and shifted by `origin`, as dumped pairs.
func _men(local: PackedVector2Array, angle: float = 0.0, origin: Vector2 = Vector2.ZERO) -> Array:
	var out: Array = []
	for p in local:
		var w: Vector2 = origin + p.rotated(angle)
		out.append([w.x, w.y])
	return out


func test_each_man_follows_the_man_ahead_in_his_file_and_dresses_on_his_right() -> void:
	var plan: Dictionary = DemoRelations.plan(_local(3, 2), 1.0, PITCH, RANK)
	assert_eq(Array(plan["leaders"]), [-1, -1, -1, 0, 1, 2], "rank 1 follows rank 0 in its file")
	assert_eq(Array(plan["dress"]), [1, 2, -1, 4, 5, -1], "each man dresses on the man to his right")
	assert_eq(plan["offsets"][4], Vector2(0.0, RANK), "he stands the rank pitch behind his leader")
	assert_eq(plan["dress_offsets"][0], Vector2(PITCH, 0.0), "his dressing man is a file pitch right")


func test_a_mirrored_grid_flips_the_sides_in_the_offsets() -> void:
	var plan: Dictionary = DemoRelations.plan(_local(3, 2), -1.0, PITCH, RANK)
	assert_eq(plan["dress_offsets"][0], Vector2(-PITCH, 0.0), "the mirror turns his right to the grid's left")
	assert_eq(plan["offsets"][3], Vector2(0.0, RANK), "a man behind his leader is behind either way")


func test_a_rank_centred_on_a_half_pitch_still_finds_its_leader_and_neighbour() -> void:
	var local := _local(3, 2)
	local[3] = local[3] + Vector2(PITCH * 0.5, 0.0)
	local[4] = local[4] + Vector2(PITCH * 0.5, 0.0)
	var plan: Dictionary = DemoRelations.plan(local, 1.0, PITCH, RANK)
	assert_ne(plan["leaders"][3], -1, "a man half a pitch off his column still has a man ahead")
	assert_eq(plan["dress"][3], 4, "and a man beside him")


func test_files_group_men_by_the_root_of_their_chain_of_leaders() -> void:
	assert_eq(DemoRelations.files([-1, -1, 0, 1, 2, 3]), [0, 1, 0, 1, 0, 1])
	assert_eq(DemoRelations.files([-1, 2, 1]).size(), 3, "a cycle of leaders ends rather than looping")


func test_a_block_in_its_places_reads_zero_however_it_is_turned_or_shifted() -> void:
	var local := _local(4, 3)
	var rel: Dictionary = _rel(local)
	for angle in [0.0, 0.7, PI, -2.0]:
		var read: Dictionary = DemoRelational.read(_men(local, angle, Vector2(300.0, -80.0)),
				rel, PITCH * 0.25, PITCH * 0.5)
		assert_almost_eq(float(read["rms"]), 0.0, 0.001, "a rigid turn is not an error")
		assert_almost_eq(float(read["far"]), 0.0, 0.001)
		assert_eq(read["behind_wrong"], 0, "every man stands behind his own leader")


func test_a_man_off_his_place_reads_his_distance_from_it() -> void:
	var local := _local(3, 3)
	var men: Array = _men(local)
	men[4][0] += 6.0
	var read: Dictionary = DemoRelational.read(men, _rel(local), PITCH * 0.25, PITCH * 0.5)
	assert_gt(float(read["rms"]), 0.0)
	assert_almost_eq(float(read["far"]), 6.0, 0.7, "the worst edge is the man's own displacement")


func test_two_men_who_traded_files_stand_behind_the_wrong_men() -> void:
	var local := _local(3, 3)
	var men: Array = _men(local)
	var swap: Array = men[6]
	men[6] = men[8]
	men[8] = swap
	var read: Dictionary = DemoRelational.read(men, _rel(local), PITCH * 0.25, PITCH * 0.5)
	assert_gte(int(read["behind_wrong"]), 2, "the two who traded stand behind each other's leaders")


func test_two_men_who_traded_places_in_a_rank_stand_on_the_wrong_side() -> void:
	var local := _local(3, 1)
	var men: Array = _men(local)
	var swap: Array = men[0]
	men[0] = men[1]
	men[1] = swap
	var read: Dictionary = DemoRelational.read(men, _rel(local), PITCH * 0.25, PITCH * 0.5)
	assert_eq(read["behind_wrong"], 2, "each of the pair has his dressing man on the wrong side")


func test_a_dump_without_relations_reads_no_edges() -> void:
	var read: Dictionary = DemoRelational.read(_men(_local(2, 2)), {}, PITCH * 0.25, PITCH * 0.5)
	assert_eq(read["edges"], 0, "nothing to judge against, so nothing is claimed")


## The reading of `men` standing off their own places in `local`'s relations.
func _rms(local: PackedVector2Array, men: Array) -> float:
	return float(DemoRelational.read(men, _rel(local), PITCH * 0.25, PITCH * 0.5)["rms"])


func test_a_block_compressed_or_spread_as_a_whole_reads_far_past_the_pitch() -> void:
	var local := _local(6, 4)
	var floor_rms: float = 0.75 * PITCH
	for scale in [0.3, 0.5, 1.6]:
		var men: Array = []
		for p in local:
			var q: Vector2 = (p - Vector2(2.5 * PITCH, 1.5 * RANK)) * scale
			men.append([q.x, q.y])
		assert_gt(_rms(local, men), floor_rms, "a block scaled to %s of its intervals is out of shape" % scale)


func test_a_block_sheared_one_pitch_a_rank_reads_far_past_the_pitch() -> void:
	var local := _local(6, 4)
	var men: Array = []
	for p in local:
		men.append([p.x + PITCH * round(p.y / RANK), p.y])
	assert_gt(_rms(local, men), 0.75 * PITCH)


func test_a_line_of_forty_files_bent_through_a_right_angle_reads_far_past_the_pitch() -> void:
	var local := _local(40, 1)
	var men: Array = []
	for i in range(40):
		men.append([minf(i, 19) * PITCH, maxf(i - 19, 0) * PITCH])
	assert_gt(_rms(local, men), 0.75 * PITCH, "every edge is one pitch long, but the line is bent")
	var edge_only: float = 0.0
	var read: Dictionary = DemoRelational.read(men, _rel(local), PITCH * 0.25, PITCH * 0.5)
	for e in DemoRelational.edges(men, _rel(local)):
		edge_only = maxf(edge_only, ((e[0] as Vector2) - (e[1] as Vector2)).length())
	assert_gt(float(read["far"]), 5.0 * PITCH, "the far end stands far from its place")


func test_a_full_scramble_and_a_block_with_every_file_reversed_are_misslotted() -> void:
	var local := _local(6, 4)
	var scrambled: Array = []
	for i in range(local.size()):
		var q: Vector2 = local[[17, 3, 22, 9, 14, 0, 19, 6, 11, 23, 2, 15, 8, 20, 5, 13, 1, 18, 10, 21, 7, 12, 4, 16][i]]
		scrambled.append([q.x, q.y])
	var read: Dictionary = DemoRelational.read(scrambled, _rel(local), PITCH * 0.25, PITCH * 0.5)
	assert_lt(float(read["settled"]), PITCH * 0.25, "men on the grid, whoever stands where, are settled")
	assert_gt(int(read["behind_wrong"]), local.size() / 4, "a scramble puts the men behind the wrong men")
	var reversed: Array = []
	for p in local:
		reversed.append([5.0 * PITCH - p.x, p.y])
	read = DemoRelational.read(reversed, _rel(local), PITCH * 0.25, PITCH * 0.5)
	assert_lt(float(read["settled"]), PITCH * 0.25)
	assert_gt(int(read["behind_wrong"]), local.size() / 4, "every file reversed is every man beside the wrong man")


func test_a_single_rank_traded_in_places_is_misslotted_and_one_in_transit_is_not() -> void:
	var local := _local(10, 1)
	var men: Array = _men(local)
	for k in range(4):
		var tmp = men[2 * k]
		men[2 * k] = men[2 * k + 1]
		men[2 * k + 1] = tmp
	var read: Dictionary = DemoRelational.read(men, _rel(local), PITCH * 0.25, PITCH * 0.5)
	assert_eq(int(read["behind_wrong"]), 8, "eight of the ten stand where their dressing man should")
	assert_lt(float(read["settled"]), PITCH * 0.25)
	var between: Array = []
	for p in local:
		between.append([p.x * 0.5 + PITCH * 0.25, p.y])
	assert_gt(float((DemoRelational.read(between, _rel(local), PITCH * 0.25, PITCH * 0.5))["settled"]),
			PITCH * 0.1, "men between places are not settled")
