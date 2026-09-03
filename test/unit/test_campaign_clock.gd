extends GutTest
## Campaign clock and calendar: the fixed-tick, pausable time foundation. Pure logic
## (no scene, no wall clock), so every case here drives real seconds in by hand and
## asserts on the tick count they produce.

const CampaignClock = preload("res://scripts/campaign/CampaignClock.gd")
const CampaignCalendar = preload("res://scripts/campaign/CampaignCalendar.gd")

# One real second at 1x with the default two-ticks-per-second rate.
const ONE_SECOND := 1.0


func _running_clock() -> RefCounted:
	var clock := CampaignClock.new()
	clock.set_paused(false)
	return clock


func test_starts_paused_at_the_first_day() -> void:
	var clock := CampaignClock.new()
	assert_true(clock.is_paused(), "a fresh campaign waits for the player")
	assert_eq(clock.tick(), 0, "no time has passed")
	assert_eq(CampaignCalendar.day(clock.tick()), 1, "the first day is day 1")


func test_paused_clock_does_not_advance() -> void:
	var clock := CampaignClock.new()
	assert_eq(clock.advance(10.0), 0, "no ticks fire while paused")
	assert_eq(clock.tick(), 0, "the counter is untouched")


func test_resuming_advances_at_the_base_rate() -> void:
	var clock := _running_clock()
	var fired: int = clock.advance(ONE_SECOND)
	assert_eq(fired, int(CampaignClock.DEFAULT_TICKS_PER_SECOND), "one second of ticks")
	assert_eq(clock.tick(), fired, "the counter matches what fired")


func test_speed_scales_ticks_per_second() -> void:
	var slow := _running_clock()
	var fast := _running_clock()
	fast.set_speed_index(2)
	slow.advance(ONE_SECOND)
	fast.advance(ONE_SECOND)
	assert_eq(fast.speed(), 4.0, "the third rung of the default ladder")
	assert_eq(fast.tick(), slow.tick() * 4, "4x fires four times the ticks")


func test_speed_index_clamps_to_the_ladder() -> void:
	var clock := CampaignClock.new()
	clock.set_speed_index(99)
	assert_eq(clock.speed_index(), CampaignClock.DEFAULT_SPEEDS.size() - 1, "clamped to fastest")
	clock.set_speed_index(-4)
	assert_eq(clock.speed_index(), 0, "clamped to slowest")


func test_cycle_speed_wraps() -> void:
	var clock := CampaignClock.new()
	clock.set_speed_index(CampaignClock.DEFAULT_SPEEDS.size() - 1)
	assert_eq(clock.cycle_speed(), 0, "past the fastest wraps to the slowest")


func test_pause_keeps_the_chosen_speed() -> void:
	var clock := _running_clock()
	clock.set_speed_index(1)
	assert_true(clock.toggle_pause(), "toggling a running clock pauses it")
	assert_false(clock.toggle_pause(), "toggling again resumes it")
	assert_eq(clock.speed_index(), 1, "the speed survived the pause")


func test_pause_resume_fires_no_extra_tick() -> void:
	var clock := _running_clock()
	# A part-tick short of the next boundary, then a pause/resume pair.
	clock.advance(0.4)
	assert_eq(clock.tick(), 0, "not a whole tick yet")
	clock.set_paused(true)
	clock.set_paused(false)
	assert_eq(clock.advance(0.4), 0, "the dropped part-tick is not repaid")


func test_fractional_seconds_do_not_drift() -> void:
	# Ten seconds delivered one 60 Hz frame at a time. Each frame is a fraction of a
	# tick, so the carry is what keeps the rate honest: without it every frame would
	# truncate to zero and the clock would never move at all.
	var clock := _running_clock()
	var seconds := 10
	for i in 60 * seconds:
		clock.advance(1.0 / 60.0)
	var expected := int(CampaignClock.DEFAULT_TICKS_PER_SECOND) * seconds
	assert_gt(clock.tick(), 0, "sub-tick frames still move the clock")
	assert_almost_eq(clock.tick(), expected, 1,
			"ten seconds of frames land within a tick of ten seconds of ticks")


func test_identical_delta_sequences_reach_identical_ticks() -> void:
	var deltas := [0.016, 0.017, 0.016, 0.033, 0.008, 0.021]
	var first := _running_clock()
	var second := _running_clock()
	for d in deltas:
		first.advance(d)
	for d in deltas:
		second.advance(d)
	assert_eq(first.tick(), second.tick(), "the same real-time sequence replays identically")


func test_set_tick_restores_an_absolute_counter() -> void:
	var clock := CampaignClock.new()
	clock.set_tick(30)
	assert_eq(clock.tick(), 30, "a resumed campaign lands on the tick it froze at")
	clock.set_tick(12)
	assert_eq(clock.tick(), 12, "restoring is absolute, not an advance")
	clock.set_tick(-5)
	assert_eq(clock.tick(), 0, "a negative tick clamps to the start of the campaign")


func test_day_counter_rolls_over() -> void:
	var per_day := CampaignCalendar.DEFAULT_TICKS_PER_DAY
	assert_eq(CampaignCalendar.day(per_day - 1), 1, "the last hour of day one")
	assert_eq(CampaignCalendar.day(per_day), 2, "the next tick begins day two")
	assert_eq(CampaignCalendar.days_elapsed(per_day * 3), 3, "three whole days elapsed")


func test_hour_of_day_is_scale_free() -> void:
	assert_eq(CampaignCalendar.hour(14), 14, "at one tick per hour the tick is the hour")
	assert_eq(CampaignCalendar.hour(0), 0, "midnight")
	# Twice the resolution: two ticks now share each hour of the day.
	assert_eq(CampaignCalendar.hour(28, 48), 14, "same hour at 48 ticks per day")


func test_ticks_for_days_expresses_a_rule_in_days() -> void:
	assert_eq(CampaignCalendar.ticks_for_days(3), CampaignCalendar.DEFAULT_TICKS_PER_DAY * 3,
			"a three-day truce is three days of ticks")


func test_calendar_label_reads_as_a_date() -> void:
	assert_eq(CampaignCalendar.label(0), "Day 1, 00:00", "a fresh campaign")
	assert_eq(CampaignCalendar.label(CampaignCalendar.DEFAULT_TICKS_PER_DAY * 2 + 14),
			"Day 3, 14:00", "two whole days and fourteen hours in")


func test_calendar_guards_a_degenerate_day_length() -> void:
	# Defence in depth, not a supported configuration: CampaignLoader rejects a
	# non-positive "ticks_per_day" outright (see test_campaign_loader.gd), so a loaded
	# campaign never reaches here with one. These guards only keep a hand-built call
	# from dividing by zero.
	assert_eq(CampaignCalendar.days_elapsed(10, 0), 0, "no division by a zero-length day")
	assert_eq(CampaignCalendar.hour(10, 0), 0, "no division by a zero-length day")


func test_empty_speeds_ladder_falls_back_to_defaults() -> void:
	var empty_speeds: Array[float] = []
	var clock := CampaignClock.new(empty_speeds)
	assert_eq(clock.speeds, CampaignClock.DEFAULT_SPEEDS,
			"empty ladder falls back to DEFAULT_SPEEDS")
	assert_eq(clock.speed(), 1.0, "initial speed is the first default rung")
	clock.cycle_speed()
	assert_eq(clock.speed_index(), 1, "cycle_speed works without modulo-by-zero")


func test_non_positive_ticks_per_second_clamps_to_minimum() -> void:
	var zero_clock := CampaignClock.new(CampaignClock.DEFAULT_SPEEDS, 0.0)
	assert_eq(zero_clock.ticks_per_second, CampaignClock.MIN_TICKS_PER_SECOND,
			"zero ticks_per_second clamps to MIN_TICKS_PER_SECOND")
	var negative_clock := CampaignClock.new(CampaignClock.DEFAULT_SPEEDS, -5.0)
	assert_eq(negative_clock.ticks_per_second, CampaignClock.MIN_TICKS_PER_SECOND,
			"negative ticks_per_second clamps to MIN_TICKS_PER_SECOND")
