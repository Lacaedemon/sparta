extends RefCounted
## Campaign tick-to-calendar conversion: pure static helpers over a tick count.
##
## CampaignClock owns the counter and knows nothing about days; every consumer that
## does -- the HUD readout, truce expiry, anything the design re-expresses "in days"
## rather than in turns -- reads days and hours through here, so one place decides
## how long a campaign day is.
##
## Day 1 is the campaign's first day, so a fresh clock at tick 0 reads "Day 1, 00:00"
## rather than day zero.

## Ticks in one campaign day. One tick is one campaign hour at the default, which is
## the granularity army movement and truce expiry are expressed in.
const DEFAULT_TICKS_PER_DAY := 24
## Hours in a day. A calendar constant, not a gameplay tunable: it is what makes an
## hour-of-day readout mean the same thing at any ticks-per-day.
const HOURS_PER_DAY := 24
const FIRST_DAY := 1


## Whole days elapsed since the campaign began (0 on the first day).
static func days_elapsed(tick: int, ticks_per_day: int = DEFAULT_TICKS_PER_DAY) -> int:
	if ticks_per_day <= 0:
		return 0
	return int(floor(float(tick) / float(ticks_per_day)))


## The campaign date, counting from day 1 -- what the HUD's day counter shows.
static func day(tick: int, ticks_per_day: int = DEFAULT_TICKS_PER_DAY) -> int:
	return FIRST_DAY + days_elapsed(tick, ticks_per_day)


## Hour of the campaign day (0-23), whatever the tick granularity: at 24 ticks per
## day one tick is one hour, at 48 it is half an hour and two ticks share an hour.
static func hour(tick: int, ticks_per_day: int = DEFAULT_TICKS_PER_DAY) -> int:
	if ticks_per_day <= 0:
		return 0
	var into_day := posmod(tick, ticks_per_day)
	return int(floor(float(HOURS_PER_DAY) * float(into_day) / float(ticks_per_day)))


## Ticks spanned by `days` whole days -- how a rule authored in days (a truce of N
## days, replacing a truce of N turns) becomes a tick deadline.
static func ticks_for_days(days: int, ticks_per_day: int = DEFAULT_TICKS_PER_DAY) -> int:
	return days * ticks_per_day


## Player-facing clock readout, e.g. "Day 3, 14:00".
static func label(tick: int, ticks_per_day: int = DEFAULT_TICKS_PER_DAY) -> String:
	return "Day %d, %02d:00" % [day(tick, ticks_per_day), hour(tick, ticks_per_day)]
