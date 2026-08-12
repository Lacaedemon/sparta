class_name UnitStats
## Pure aggregate math over a regiment's per-soldier arrays, for display readouts
## (the HUD's selected-unit stat sheet). Static and node-free so every function is
## directly unit-testable and replay-safe: plain arrays in, plain numbers out.
## Render-only consumers — nothing in the simulation reads these.


## Mean and standard deviation (population) of the POSITIVE entries — the living
## soldiers' values. Casualties compact out of the arrays each reap, but a soldier
## can sit at hp <= 0 for the ticks between the wound and the reap, and counting
## those zeros would drag the "current hit points" of the living down. Returns
## Vector2(mean, sd); Vector2.ZERO when no entry is positive.
static func mean_sd_positive(values: PackedFloat32Array) -> Vector2:
	var sum := 0.0
	var count := 0
	for v in values:
		if v > 0.0:
			sum += v
			count += 1
	if count == 0:
		return Vector2.ZERO
	var mean := sum / count
	var var_sum := 0.0
	for v in values:
		if v > 0.0:
			var_sum += (v - mean) * (v - mean)
	return Vector2(mean, sqrt(var_sum / count))


## Mean speed (magnitude of velocity, world units/s) over the living soldiers'
## bodies. `vels` and `hp` are the index-aligned per-soldier arrays; an entry only
## counts while its soldier is alive (hp > 0), mirroring mean_sd_positive's
## living-only rule. 0.0 when no soldier is alive or the arrays are empty.
static func mean_body_speed(vels: PackedVector2Array, hp: PackedFloat32Array) -> float:
	var sum := 0.0
	var count := 0
	var n: int = mini(vels.size(), hp.size())
	for i in range(n):
		if hp[i] > 0.0:
			sum += vels[i].length()
			count += 1
	return 0.0 if count == 0 else sum / count
