extends RefCounted
## Fixed-tick, pausable campaign clock -- the time half of the campaign layer's
## foundation (docs/campaign-layer-design.md, "Time model").
##
## Campaign time advances in fixed discrete ticks, never in frame-delta time, for the
## same reason battles run on Replay.PHYSICS_TPS: a session that fires the same tick
## sequence reaches the same state. advance() is the only place real seconds enter,
## and it converts them to a WHOLE number of ticks; nothing downstream sees anything
## but the tick count. Pause gates that counter and nothing else -- while paused the
## player still inspects the map and queues orders, the pause-to-plan loop of the
## genre. Speed scales ticks per real second and never changes what a tick means, so
## the same orders at 1x and at 8x produce the same campaign history.
##
## Tick-to-calendar conversion lives in CampaignCalendar; this script owns only the
## counter, the pause flag and the speed ladder.

## Speed multipliers the speed control offers, slowest first. Pausing is a separate
## flag rather than a speed of zero, so the chosen speed survives a pause/resume pair.
const DEFAULT_SPEEDS: Array[float] = [1.0, 2.0, 4.0, 8.0]
## Ticks fired per real second at 1x. At the default calendar (24 ticks to the day)
## a campaign day takes 12 real seconds at 1x and 1.5 at 8x.
const DEFAULT_TICKS_PER_SECOND := 2.0

var speeds: Array[float]
var ticks_per_second: float

var _tick: int = 0
var _speed_index: int = 0
var _paused: bool = true
var _carry: float = 0.0


func _init(
	p_speeds: Array[float] = DEFAULT_SPEEDS,
	p_ticks_per_second: float = DEFAULT_TICKS_PER_SECOND
) -> void:
	speeds = p_speeds.duplicate()
	ticks_per_second = p_ticks_per_second


func tick() -> int:
	return _tick


func is_paused() -> bool:
	return _paused


## Pausing drops the accumulated part-tick, so a pause/resume pair never fires a tick
## the player did not watch accumulate.
func set_paused(paused: bool) -> void:
	_paused = paused
	if paused:
		_carry = 0.0


func toggle_pause() -> bool:
	set_paused(not _paused)
	return _paused


func speed_index() -> int:
	return _speed_index


func speed() -> float:
	return speeds[_speed_index]


func set_speed_index(index: int) -> void:
	_speed_index = clampi(index, 0, speeds.size() - 1)


## Step to the next speed on the ladder, wrapping past the fastest -- the one-key
## speed control.
func cycle_speed() -> int:
	set_speed_index((_speed_index + 1) % speeds.size())
	return _speed_index


## Advance by `seconds` of real time, returning how many whole ticks fired (0 while
## paused). The caller steps the simulation that many times; the fractional remainder
## carries into the next call, so frame boundaries never swallow a tick and the rate
## does not drift as the session runs. This is where real time stops: a replay records
## and reproduces the tick count, never the wall-clock seconds behind it, which do not
## recur across machines or frame rates.
func advance(seconds: float) -> int:
	if _paused or seconds <= 0.0:
		return 0
	_carry += seconds * ticks_per_second * speed()
	var fired := int(_carry)
	_carry -= float(fired)
	_tick += fired
	return fired


## Advance by whole ticks directly, bypassing real time: the replay and test path,
## and how a fought battle charges its own elapsed duration back to the campaign.
func step(ticks: int) -> void:
	if ticks > 0:
		_tick += ticks
