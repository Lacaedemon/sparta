extends GutTest
## DemoChasers.drop: the shape DemoDefects judges is read off the men not riding a runner down.


func test_a_chasing_man_and_the_relations_to_him_are_left_out() -> void:
	var pos: Array = [[0.0, 0.0], [0.0, 10.0], [500.0, -300.0], [0.0, 30.0]]
	var rel: Dictionary = {
		"leaders": [-1, 0, 1, 2], "offsets": [[0, 0], [0, 10], [0, 10], [0, 10]],
		"dress": [-1, -1, -1, -1], "dress_offsets": [[0, 0], [0, 0], [0, 0], [0, 0]],
	}
	var out: Array = DemoChasers.drop(pos, rel, [0, 0, 1, 0])
	assert_eq(out[0], [[0.0, 0.0], [0.0, 10.0], [0.0, 30.0]], "the rider riding off is left out")
	assert_eq(out[1]["leaders"], [-1, 0, -1], "a man whose leader rode off follows no one")
	assert_eq(out[1]["offsets"], [[0, 0], [0, 10], [0, 10]], "the kept men keep their offsets")


func test_with_no_chaser_the_men_are_judged_as_they_stand() -> void:
	var pos: Array = [[0.0, 0.0], [0.0, 10.0]]
	var rel: Dictionary = {"leaders": [-1, 0], "offsets": [[0, 0], [0, 10]]}
	var out: Array = DemoChasers.drop(pos, rel, [0, 0])
	assert_eq(out[0], pos)
	assert_eq(out[1], rel)
	assert_eq(DemoChasers.drop(pos, rel, [])[0], pos, "a dump before the field existed reads none")
