class_name UnitFormation
## Formation-block geometry for a Unit, extracted from Unit.gd: the file count
## (frontage) and the centred, wider-than-deep grid of local-space slot offsets a
## regiment's soldiers arrange into. Pure and deterministic -- a function of the unit's
## soldier counts and the FORMATION_* constants only -- so it's directly unit-testable and
## replay-safe. The render's per-mark jitter and the world-space transform live elsewhere
## (Unit / the flock render); this is just the bare block layout.


## Number of files (columns) for `n` soldiers: a wider-than-deep grid
## (FORMATION_ASPECT files per rank). Pure of n.
static func _files(n: int) -> int:
	return maxi(1, int(ceil(sqrt(float(n) * Unit.FORMATION_ASPECT))))


# "Close the ranks": a heavily-mauled unit narrows its AUTO frontage one notch so
# the survivors reform into a deeper, denser block instead of holding the full-strength
# line's width with a thin, brittle depth -- the historical practice the file-closer
# (ouragos) enforced (see UnitFormation.block_slots' docstring).
# Trigger on a single hysteresis-gapped fraction-of-strength crossing, evaluated ONCE PER
# TICK and cached (Unit._ranks_closed), not recomputed continuously -- the same
# every-soldier-jumps-at-once churn the stable full-strength frontage above already
# avoids. CONTRACT_FRAC (50%) is a worked example: a unit down to half
# strength has lost enough depth that a still-full-width line is reading as thin cover,
# not a solid block. RECOVER_FRAC sits a further 15 points up (mirrors FormationTier's
# PROMOTE/DEMOTE gap) so a unit hovering right at half strength -- reinforced by absorb(),
# or just trading casualties back and forth near the line -- doesn't flap the whole grid
# back and forth tick to tick; it only re-widens once meaningfully recovered.
const CLOSE_RANKS_CONTRACT_FRAC: float = 0.5
const CLOSE_RANKS_RECOVER_FRAC: float = 0.65


## Whether the auto frontage should currently be contracted a notch, with hysteresis:
## contract at or below CLOSE_RANKS_CONTRACT_FRAC of max strength, recover at or above
## CLOSE_RANKS_RECOVER_FRAC, and HOLD the current state in the gap between (so a unit
## sitting near the line doesn't flicker the grid tick to tick). Mirrors
## SoldierFlock.lod_should_detail's currently-active-plus-new-reading shape. Pure --
## unit-testable without a live Unit.
static func should_close_ranks(currently_closed: bool, soldiers: int, max_soldiers: int) -> bool:
	if max_soldiers <= 0:
		return currently_closed
	var frac: float = float(soldiers) / float(max_soldiers)
	if frac <= CLOSE_RANKS_CONTRACT_FRAC:
		return true
	if frac >= CLOSE_RANKS_RECOVER_FRAC:
		return false
	return currently_closed


## The regiment's stable file count (frontage): `_files` at FULL strength, so the LINE
## KEEPS ITS WIDTH as casualties thin its DEPTH (ranks). Keying the slot layout and the
## engaged-rank cutoff off this -- not the live count -- stops the whole grid from
## reflowing (every soldier jumping to a new file at once) each
## time the count crosses a sqrt threshold mid-fight. At full strength it equals
## `_files(soldiers)`, so nothing changes there.
##
## A player-set `frontage_override` (> 0) wins over the auto width, clamped to
## [1, max_soldiers] -- so the line can be widened (shallower) or narrowed (deeper)
## by hand, still keying every downstream layout off one stable file count. Otherwise,
## once the unit's casualties have crossed the close-the-ranks threshold (`u._ranks_closed`,
## ticked once per frame by should_close_ranks above), the auto width itself steps down
## one notch (narrowed_files) so the mauled survivors reform deeper rather than holding a
## thin full-width line -- a single discrete step, not a continuous reflow.
static func frontage(u: Unit) -> int:
	if u.frontage_override > 0:
		return clampi(u.frontage_override, 1, maxi(1, u.max_soldiers))
	var full: int = _files(u.max_soldiers)
	if u._ranks_closed:
		return narrowed_files(full)
	return full


## Half-width (local +/-X extent, world units) of a FRESH, full-strength unit's
## formation block -- `_half_width` at the FULL frontage (`_files(soldiers)`), before
## any ranks-closed narrowing or player frontage_override apply (both only kick in
## after a live Unit has taken casualties or been manually resized). `spacing` is
## the formation's world-unit FILE pitch (the type's own file pitch scaled by
## Unit.spacing_scale_for_mode(formation_mode)) -- the axis a line's width runs along.
##
## Pure -- doesn't need a live Unit, so Battle._spawn_line can call it while still
## building the loadout, to space a line of units apart by their actual footprint
## instead of a fixed per-unit spacing that assumes uniform width -- a
## 90-soldier LOOSE-order Archers block is far wider than a same-count TIGHT block,
## so a flat spacing constant lets a wide neighbour's formation overlap it.
static func half_width_for_soldiers(soldiers: int, spacing: float) -> float:
	return _half_width(_files(soldiers), spacing)


## File count for a drag-resize handle pulled to `half_width` world units from the
## regiment's centre along its file axis. A grid of f files spans (f-1) gaps of
## `spacing`, so its half-width is (f-1)/2 * spacing; invert that and round to the
## nearest file. `spacing` defaults to the plain FORMATION_SPACING constant, but a
## live unit's actual grid may be density-scaled (LOOSE order) or per-type
## (cavalry's wider files) -- callers with a unit on hand should pass
## `u.file_pitch_wu()` so the inverse mapping matches what slots() actually laid out. Clamped to [1, max_soldiers]. Pure
## -- unit-testable, and the drag preview and the committed value read the same mapping.
static func files_for_halfwidth(half_width: float, max_soldiers: int,
		spacing: float = Unit.FORMATION_SPACING) -> int:
	var f: int = int(round(2.0 * half_width / spacing)) + 1
	return clampi(f, 1, maxi(1, max_soldiers))


## "%d file(s)" with correct singular/plural, for the HUD readout and resize preview.
static func files_label(n: int) -> String:
	return "%d file" % n if n == 1 else "%d files" % n


## Local-space slot offsets for `n` soldier marks: a centred, wider-than-deep grid (front
## rank toward -Y, the rotated "forward"). Pure and deterministic -- a function of `n`,
## the unit's frontage, its density (TIGHT/NORMAL/LOOSE scales spacing without changing
## the file/rank count), and its anchor shift (an asymmetric explicatio/duplicatio holds
## one flank fixed instead of centring the block; 0.0 is the plain centred behaviour) --
## so it's unit-testable; the render adds stable jitter on top.
static func slots(u: Unit, n: int) -> PackedVector2Array:
	var out := block_slots(n, frontage(u), u.file_pitch_wu(), u.rank_pitch_wu())
	return apply_frontage_anchor_offset(out, u.frontage_anchor_offset)


## Shift every slot in `out` by `offset` world units along local X -- the
## frontage_anchor_offset shift `slots()` above applies for an asymmetric explicatio/
## duplicatio, factored out so Unit.formation_slots' file-major branch
## (file_major_block_slots) can apply the identical shift without duplicating the loop. A
## zero offset (the plain centred case) is a no-op. Pure -- mutates and returns the same
## array reference for convenience; callers already own a fresh array from block_slots/
## file_major_block_slots, so there is nothing else referencing it to alias.
static func apply_frontage_anchor_offset(out: PackedVector2Array, offset: float) -> PackedVector2Array:
	if offset != 0.0:
		var shift := Vector2(offset, 0.0)
		for i in range(out.size()):
			out[i] = out[i] + shift
	return out


# --- Grid operations (#367) --------------------------------------------------
# Primitives that reshape the formation grid -- transpose ranks<->columns, change the
# file count (split/merge), and change density (spacing) -- all in the unit's LOCAL frame,
# independent of its world position or facing. Pure functions of (n, files, spacing), so
# they're unit-testable and replay-safe. A maneuver layers a body relabel on top (which
# soldier takes which new slot); these just lay out the target shape.


## Rank count (rows) for `n` soldiers at the given `files` frontage.
static func ranks_for(n: int, files: int) -> int:
	if n <= 0 or files <= 0:
		return 0
	return int(ceil(float(n) / float(files)))


## The general grid layout: `n` slots in a centred, wider-than-deep block with `files`
## columns at `spacing` px, front rank toward -Y. Full ranks span the whole frontage; a
## partial rear rank closes up onto the CENTRE files of that same frontage, so its survivors
## stay centred within the frontage -- the men step up toward the middle rather than fanning
## out to the wings. This mirrors how a phalanx or
## legion closed after casualties: the file (column), led at the front and closed at the
## rear by the ouragos/file-closer, was the unit of cohesion; the outer files shortened as
## the wings closed toward the standard while the centre files stayed deepest.
##
## The partial rank stays laterally centred to the half-file: when its count and the frontage
## have opposite parity it straddles the centre line on HALF-columns (offset by half a
## spacing), so it is both symmetric about the unit centre (centroid on the axis) and still a
## regular grid -- each survivor sits half a file off the men ahead, closed toward the centre.
## `slots()` is the wrapper that feeds it the unit's frontage and the default spacing; grid-ops
## feed it reshaped (files, spacing) for the transposed / widened / opened block.
##
## `rank_pitch` makes the grid ANISOTROPIC: `spacing` is the lateral file pitch, and a
## non-negative `rank_pitch` sets the depth between ranks independently. A mounted
## soldier occupies far more ground nose-to-tail than knee-to-knee, so a cavalry grid
## needs ranks several times deeper than its files -- the default (-1.0, meaning "same
## as spacing") keeps every existing foot-formation caller exactly as it was.
static func block_slots(n: int, files: int, spacing: float,
		rank_pitch: float = -1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if n <= 0 or files <= 0:
		return out
	var depth: float = rank_pitch if rank_pitch >= 0.0 else spacing
	var ranks: int = ranks_for(n, files)
	var y0: float = -(ranks - 1) * 0.5 * depth
	for i in range(n):
		var file: int = i % files
		var rank: int = i / files
		var rank_count: int = mini(files, n - rank * files)
		# Close the rank onto the centre files of the full frontage: the survivors span a
		# contiguous, laterally-centred run of columns (rx0 = -(rank_count-1)/2), so a short
		# rear rank clusters on the middle files while the wings shorten -- and it stays exactly
		# symmetric about the unit centre, keeping the block's centroid on the axis.
		var rx0: float = -(rank_count - 1) * 0.5 * spacing
		out.push_back(Vector2(rx0 + file * spacing, y0 + rank * depth))
	return out


# --- File-major casualty reflow (#878) ---------------------------------------
# block_slots above lays soldier i out at (file = i % files, rank = i / files) -- purely a
# function of the LIVE array index, so any casualty anywhere in the block reflows every
# later soldier's file AND rank (SoldierMelee.reap() compacts the array, shifting every
# later index down). file_major_block_slots instead takes each soldier's own PERSISTENT
# file assignment (Unit._sim_soldier_file, kept in sync with a casualty the same way every
# other per-soldier array is -- trimmed at the dead soldier's index, never recomputed) and
# lays each file out as its own independent column: a soldier's rank is how many EARLIER
# array entries share its same file id, so a casualty only shortens ITS OWN file's rear --
# every other file's soldiers keep the exact rank (and therefore slot) they already had.


## Local-space slot offsets for soldiers laid out FILE-MAJOR: `file_ids[i]` gives soldier
## i's persistent file assignment (0..files-1), index-aligned with the live soldier array
## (see Unit._sim_soldier_file / _ensure_file_assignment). Within each file, survivors
## occupy consecutive ranks from the front -- a soldier's rank is how many EARLIER array
## entries share its same file id -- so a casualty only shortens its OWN file's rear; other
## files are untouched. Unlike block_slots (which derives every soldier's cell fresh from a
## row-major index/files divide, reassigning cells on every casualty), a soldier's file
## never changes just because a soldier in ANOTHER file died. Files are centred on the FULL
## frontage (not the live count), so a file's lateral (x) position never moves either --
## deliberately NOT block_slots' "close toward centre" narrowing for a partial rank, since
## that narrowing depends on how many OTHER files are currently occupied at the same depth,
## which is exactly the cross-file coupling file-major mode exists to avoid. The block's
## depth (y0) centres on whichever file currently has the most survivors, mirroring
## block_slots' own centred-on-max-depth convention. Out-of-range file ids clamp into
## [0, files-1] defensively (never crash on a stale/misaligned array). Pure --
## deterministic in (file_ids, files, spacing, rank_pitch).
static func file_major_block_slots(file_ids: PackedInt32Array, files: int, spacing: float,
		rank_pitch: float = -1.0) -> PackedVector2Array:
	var n: int = file_ids.size()
	var out := PackedVector2Array()
	out.resize(n)
	if n <= 0 or files <= 0:
		return PackedVector2Array()
	var depth: float = rank_pitch if rank_pitch >= 0.0 else spacing
	var rx0: float = -(files - 1) * 0.5 * spacing
	var rank_counts := PackedInt32Array()
	rank_counts.resize(files)
	var ranks := PackedInt32Array()
	ranks.resize(n)
	var max_rank: int = 0
	for i in range(n):
		var file: int = clampi(file_ids[i], 0, files - 1)
		var rank: int = rank_counts[file]
		ranks[i] = rank
		rank_counts[file] = rank + 1
		max_rank = maxi(max_rank, rank + 1)
	var y0: float = -(max_rank - 1) * 0.5 * depth
	for i in range(n):
		var file: int = clampi(file_ids[i], 0, files - 1)
		out[i] = Vector2(rx0 + file * spacing, y0 + ranks[i] * depth)
	return out


# --- Square / orbis grid (real hollow/solid square footprint) ---------------
# The anti-cavalry square is a genuine square block, not the standard wide-line
# frontage: it uses its own file count (files ~= ranks, so the bbox aspect is ~1)
# and marks which slots sit on the outer ring, so the perimeter can face outward
# (Unit.soldier_world_facings) while the interior keeps the unit's heading.


## File count for a roughly-square grid of `n` soldiers: files ~= ranks ~= sqrt(n),
## unlike `_files` (which deliberately widens past sqrt for the line frontage). Pure.
static func square_files(n: int) -> int:
	return maxi(1, int(ceil(sqrt(float(n)))))


## Local-space slot offsets for `n` soldiers laid out as a square block (reuses
## block_slots' centred rank-major grid, just with a square file count instead of
## the wide-line frontage). Pure and deterministic like `slots()`.
static func square_slots(n: int, spacing: float) -> PackedVector2Array:
	return block_slots(n, square_files(n), spacing)


## True when slot index `i` (of `n` total soldiers laid out at `files` columns via
## block_slots) sits on the block's outer ring: the first or last rank, or the
## first/last column of its own (possibly partial) rank. Mirrors block_slots' exact
## rank/file indexing so it always agrees with what square_slots laid out. Pure.
static func square_is_perimeter(i: int, n: int, files: int) -> bool:
	if files <= 0 or i < 0 or i >= n:
		return false
	var ranks: int = ranks_for(n, files)
	var rank: int = i / files
	var rank_count: int = mini(files, n - rank * files)
	var file: int = i % files
	return rank == 0 or rank == ranks - 1 or file == 0 or file == rank_count - 1


## Live-position perimeter selection for a hollow-square/schiltron formation. Unlike
## `square_is_perimeter` (a function of SLOT INDEX in the original, uncompacted grid),
## this reads each soldier's ACTUAL current position: `SoldierMelee.reap()` removes dead
## soldiers by splicing the per-soldier arrays, which shifts every later index down and
## breaks the assumption `square_is_perimeter` relies on (that index `i`'s position still
## matches the grid cell `block_slots` laid it out on). Empirically, on a live battle with
## real casualties, the slot-index perimeter's mismatch rate against attackers' actual
## nearest-defender index jumps from 0% (freshly seeded, no casualties yet) to 60-80% once
## the array has compacted even a little -- see the `anti-cav-square.json` state-dump
## reproduction described in `.claude/memories/sparta.md`.
##
## Returns the `target_count` LIVING soldiers (by position-array index) currently farthest
## from the block's own live centroid -- the outermost survivors of whatever shape the
## block actually occupies right now, not whatever the original grid predicted. `target_count`
## is normally sized to match `square_is_perimeter`'s own ring size (see
## `Unit.engaged_soldier_indices`), so this changes WHICH soldiers are selected, not how many.
## Selection is O(n log target_count) (a bounded min-heap of the target_count farthest
## candidates seen so far, see `_worse`/`_heap_sift_up`/`_heap_sift_down`) rather than a full
## O(n log n) sort of every soldier, since only the top `target_count` are ever read. Pure and
## deterministic: ties broken by index (lower index wins), no RNG, no wall-clock.
static func live_perimeter_indices(positions: PackedVector2Array, target_count: int) -> PackedInt32Array:
	var n: int = positions.size()
	if n <= 0 or target_count <= 0:
		return PackedInt32Array()
	if target_count >= n:
		var all := PackedInt32Array()
		for i in range(n):
			all.push_back(i)
		return all
	var centroid := Vector2.ZERO
	for p in positions:
		centroid += p
	centroid /= float(n)
	# Min-heap (by "goodness" -- farther is better, lower index breaks ties) of the
	# target_count best candidates seen so far; the root (index 0) is always the WORST of
	# the currently-kept set, so a new candidate only needs one comparison against it to
	# decide whether it displaces anything.
	var heap_i := PackedInt32Array()
	var heap_d := PackedFloat32Array()
	for i in range(n):
		var d: float = positions[i].distance_squared_to(centroid)
		if heap_i.size() < target_count:
			heap_i.push_back(i)
			heap_d.push_back(d)
			_heap_sift_up(heap_i, heap_d, heap_i.size() - 1)
		elif _worse(heap_d[0], heap_i[0], d, i):
			heap_i[0] = i
			heap_d[0] = d
			_heap_sift_down(heap_i, heap_d, 0)
	var out := PackedInt32Array(heap_i)
	out.sort()
	return out


## Live-position front-rank selection for a non-square (line/column) formation. Unlike a
## naive "first `target_count` indices" front-rank selection, this reads each soldier's
## ACTUAL current position: `SoldierMelee.reap()` removes dead soldiers by splicing the
## per-soldier arrays, which shifts every later index down and breaks the assumption that
## index `i` still sits at the grid cell `block_slots` originally laid it out on -- the same
## staleness `live_perimeter_indices` above fixes for the hollow-square/schiltron case,
## here for the ordinary line-formation case. `origin` and `forward` are a world-frame
## reference point and unit vector (the unit's own anchor and its facing-derived forward
## direction); `positions` shares `origin`'s frame (both parent-local, per
## `Unit._sim_soldier_pos`'s convention).
##
## Returns the `target_count` LIVING soldiers (by position-array index) currently projecting
## FARTHEST along `forward` from `origin` -- the soldiers physically closest to the enemy
## right now, not whichever indices happen to occupy the low end of the (possibly
## casualty-compacted) array. Same O(n log target_count) bounded-min-heap selection as
## `live_perimeter_indices` (reusing its `_worse`/`_heap_sift_up`/`_heap_sift_down` helpers,
## which only compare scores -- they don't care whether the score is a squared distance or a
## forward projection). Pure and deterministic: ties broken by index (lower index wins), no
## RNG, no wall-clock.
static func live_front_indices(positions: PackedVector2Array, target_count: int, origin: Vector2, forward: Vector2) -> PackedInt32Array:
	var n: int = positions.size()
	if n <= 0 or target_count <= 0:
		return PackedInt32Array()
	if target_count >= n:
		var all := PackedInt32Array()
		for i in range(n):
			all.push_back(i)
		return all
	var heap_i := PackedInt32Array()
	var heap_d := PackedFloat32Array()
	for i in range(n):
		var score: float = (positions[i] - origin).dot(forward)
		if heap_i.size() < target_count:
			heap_i.push_back(i)
			heap_d.push_back(score)
			_heap_sift_up(heap_i, heap_d, heap_i.size() - 1)
		elif _worse(heap_d[0], heap_i[0], score, i):
			heap_i[0] = i
			heap_d[0] = score
			_heap_sift_down(heap_i, heap_d, 0)
	var out := PackedInt32Array(heap_i)
	out.sort()
	return out


## True if (d_a, idx_a) is a WORSE candidate to keep than (d_b, idx_b): a farther point (larger
## squared distance) is more worth keeping; among ties, the LOWER soldier index is more worth
## keeping. Matches the strict-weak-order the equivalent full sort would use (sort by distance
## descending, ties broken by index ascending) -- `live_perimeter_indices`'s heap is built
## entirely from this one comparison, so keeping it correct keeps the whole selection correct.
static func _worse(d_a: float, idx_a: int, d_b: float, idx_b: int) -> bool:
	if d_a != d_b:
		return d_a < d_b
	return idx_a > idx_b


## Bubble the entry at `pos` up until its parent is no worse than it (min-heap invariant:
## the root is always the single worst entry). Private helper for `live_perimeter_indices`.
static func _heap_sift_up(heap_i: PackedInt32Array, heap_d: PackedFloat32Array, pos: int) -> void:
	while pos > 0:
		var parent: int = (pos - 1) / 2
		if _worse(heap_d[pos], heap_i[pos], heap_d[parent], heap_i[parent]):
			var ti: int = heap_i[pos]; heap_i[pos] = heap_i[parent]; heap_i[parent] = ti
			var td: float = heap_d[pos]; heap_d[pos] = heap_d[parent]; heap_d[parent] = td
			pos = parent
		else:
			break


## Push the entry at `pos` down until both children are no worse than it. Private helper for
## `live_perimeter_indices`, called after replacing the root with a better candidate.
static func _heap_sift_down(heap_i: PackedInt32Array, heap_d: PackedFloat32Array, pos: int) -> void:
	var n: int = heap_i.size()
	while true:
		var left: int = 2 * pos + 1
		var right: int = 2 * pos + 2
		var worst: int = pos
		if left < n and _worse(heap_d[left], heap_i[left], heap_d[worst], heap_i[worst]):
			worst = left
		if right < n and _worse(heap_d[right], heap_i[right], heap_d[worst], heap_i[worst]):
			worst = right
		if worst == pos:
			break
		var ti: int = heap_i[pos]; heap_i[pos] = heap_i[worst]; heap_i[worst] = ti
		var td: float = heap_d[pos]; heap_d[pos] = heap_d[worst]; heap_d[worst] = td
		pos = worst


## Ascending insertion sort of `indices` by a parallel `scores` array (scores[k] is the score
## for indices[k], NOT an array indexed by the index value itself). Shared core for
## `sort_indices_by_projection` and `sort_indices_by_angle` below -- both only differ in how
## the score is computed. Small-k (bounded by an engaged group's size, a handful of bodies),
## so a plain insertion sort beats a general-purpose comparator's overhead. Ties broken by
## ascending index, matching the tie convention `_worse` already uses in this file.
static func _sort_indices_by_score(indices: PackedInt32Array, scores: PackedFloat32Array) -> PackedInt32Array:
	var out := PackedInt32Array(indices)
	var s := PackedFloat32Array(scores)
	for i in range(1, out.size()):
		var idx: int = out[i]
		var score: float = s[i]
		var j: int = i - 1
		while j >= 0 and (s[j] > score or (s[j] == score and out[j] > idx)):
			out[j + 1] = out[j]
			s[j + 1] = s[j]
			j -= 1
		out[j + 1] = idx
		s[j + 1] = score
	return out


## Sort `indices` (each an index into `positions`) ascending by projection onto `axis` from
## `origin` -- the lateral position along a formation's file axis. `axis` is normally a
## unit's file axis (perpendicular to its forward -- the same axis
## `Unit._compute_engaged_soldier_indices`/`Unit._wheel_pivot_point` already use), and
## `block_slots` lays a single RANK out in ascending file order along that exact axis. Only
## meaningful within one rank/depth tier at a time -- see `sort_indices_by_rank_then_lateral`
## below for the multi-rank engaged/canonical pairing this feeds. Pure and deterministic.
static func sort_indices_by_projection(indices: PackedInt32Array, positions: PackedVector2Array, origin: Vector2, axis: Vector2) -> PackedInt32Array:
	var scores := PackedFloat32Array()
	for idx in indices:
		scores.push_back((positions[idx] - origin).dot(axis))
	return _sort_indices_by_score(indices, scores)


## Sort `indices` into rank-major order -- DEPTH tier first (most-forward first, along
## `forward`), then LATERAL position within each tier (along `lateral_axis`) -- chunked into
## groups of `files` (a short final chunk for a partial rank), matching exactly how
## `block_slots`/`canonical_target_slot_indices` lay the canonical grid out: rank 0's `files`
## slots in ascending file order, then rank 1's, and so on. Used to pair a live-engaged group
## with its canonical target slots by ACTUAL POSITION (see Unit.pairing_sort_indices /
## SoldierBodies.step's engaged/canonical pairing) instead of raw surviving array rank.
##
## A single LATERAL-only sort (`sort_indices_by_projection` alone) is not enough here: the
## engaged budget normally spans several ranks (Unit.engaged_ranks()), and every rank shares the
## exact same span of file positions, so sorting purely by lateral position interleaves ranks
## instead of keeping each one together -- a body in rank 0 could end up paired with a rank 1
## slot just because some other rank's soldier at the same file sorts between them. Bucketing
## by depth FIRST (approximating which rank tier a live body currently occupies, the same
## depth axis `engaged_soldier_indices`' own live-position selection uses) keeps that grouping
## intact, so only genuine LATERAL crossing within a tier gets corrected. Pure and
## deterministic: for a canonical (already on-grid) array this reproduces the identity order,
## since each rank's slots are already both depth-tied and lateral-ascending; for a live,
## casualty-reindexed array it recovers the same rank-major shape from actual positions.
static func sort_indices_by_rank_then_lateral(indices: PackedInt32Array, positions: PackedVector2Array,
		origin: Vector2, forward: Vector2, lateral_axis: Vector2, files: int) -> PackedInt32Array:
	if files <= 0:
		return sort_indices_by_projection(indices, positions, origin, lateral_axis)
	var depth_scores := PackedFloat32Array()
	for idx in indices:
		depth_scores.push_back(-(positions[idx] - origin).dot(forward))   # ascending = most-forward first
	var by_depth: PackedInt32Array = _sort_indices_by_score(indices, depth_scores)
	var out := PackedInt32Array()
	var i := 0
	while i < by_depth.size():
		var end: int = mini(i + files, by_depth.size())
		var chunk := PackedInt32Array()
		for j in range(i, end):
			chunk.push_back(by_depth[j])
		for idx in sort_indices_by_projection(chunk, positions, origin, lateral_axis):
			out.push_back(idx)
		i = end
	return out


## Sort `indices` ascending by angular position around `origin` -- the SQUARE/Schiltron
## counterpart to `sort_indices_by_projection` above. A hollow-square/orbis ring has no
## single file axis (it wraps all the way around the block), so pairing an engaged perimeter
## group with its canonical ring slots by ANGLE instead lines up each live defender with the
## ring slot nearest its own actual side of the block. Pure and deterministic.
static func sort_indices_by_angle(indices: PackedInt32Array, positions: PackedVector2Array, origin: Vector2) -> PackedInt32Array:
	var scores := PackedFloat32Array()
	for idx in indices:
		scores.push_back((positions[idx] - origin).angle())
	return _sort_indices_by_score(indices, scores)


## File count after a 90° in-place turn (quarter-turn, #371): frontage and depth swap,
## so the new file count is the old rank count. Transposing twice returns to the original
## frontage for a full grid (a partial last rank can shift it by one -- the caller reforms).
static func transposed_files(n: int, files: int) -> int:
	return maxi(1, ranks_for(n, files))


## Explicatio: widen the frontage -- double the files, halving the depth -- capped
## at `n` (a single rank). The rear half of each file steps out laterally to form new files.
static func widened_files(n: int, files: int) -> int:
	return mini(maxi(1, n), files * 2)


## Duplicatio: narrow the frontage -- halve the files, doubling the depth. Alternate
## files tuck in behind their neighbours. Floored at one file (a single column).
static func narrowed_files(files: int) -> int:
	return maxi(1, files / 2)


# --- Anchored (asymmetric) explicatio ----------------------------------------
# The centred explicatio above widens the line symmetrically about the unit's own
# centre (the block's centroid never moves laterally). An ANCHORED widen instead
# holds one flank's edge fixed and lets the whole block grow off the opposite
# flank -- the line's own position on the field shifts, which matters when a flank
# must stay pinned to terrain or a neighbouring unit. Anchor.CENTRE reproduces the
# plain symmetric widen (zero shift); LEFT/RIGHT hold that respective edge in place.

## Anchor flank for an asymmetric explicatio/duplicatio: which edge of the block
## (viewed from the front, facing the same way the unit is) stays fixed while the
## opposite flank grows or shrinks. CENTRE holds the block's own centre fixed --
## the plain, symmetric behaviour `widened_files`/`narrowed_files` already give.
enum Anchor { LEFT = -1, CENTRE = 0, RIGHT = 1 }


## Half-width (local +/-X extent) of a full-rank block at `files` columns, `spacing`
## px apart: `files` columns span `(files-1)` gaps, so the half-width is half that
## span. Pure; shared by block_slots (which centres on this) and the anchor-shift
## math below (which needs the SAME half-width block_slots actually laid out).
static func _half_width(files: int, spacing: float) -> float:
	return maxi(files - 1, 0) * 0.5 * spacing


## Lateral (local X) shift that keeps the ANCHOR flank's edge fixed when the file
## count changes from `old_files` to `new_files` at `spacing` px apart, for a SINGLE
## widen/narrow starting from a CENTRED block (offset 0). block_slots always centres
## the block on local X=0, so widening/narrowing moves BOTH edges outward/inward by
## half the width change; shifting the whole (already-centred) block by this offset
## cancels that motion on the anchored side only, so that edge stays put and the whole
## width change shows up on the opposite flank. Anchor.CENTRE is a no-op (0.0), matching
## the existing symmetric maneuver. Pure -- a function of (old_files, new_files,
## spacing, anchor).
##
## Callers applying this to a unit that may ALREADY carry a non-zero anchor offset
## (a prior anchored widen) must ADD this shift to that existing offset, not replace
## it -- this function only ever computes the delta for one step from centre, so
## reusing it as an absolute value across repeated anchored widens on the same unit
## would silently let the "held" flank drift. See Battle.enqueue_file_double.
static func anchor_shift(old_files: int, new_files: int, spacing: float, anchor: int) -> float:
	if anchor == Anchor.CENTRE:
		return 0.0
	var delta: float = _half_width(new_files, spacing) - _half_width(old_files, spacing)
	# RIGHT anchor: hold the +X edge fixed, so the centred block must slide -X
	# (toward -X) by the width gained on that side. LEFT anchor is the mirror.
	return -delta if anchor == Anchor.RIGHT else delta


## Anchored explicatio/duplicatio slot layout: the same centred grid `block_slots`
## lays out, translated in local X by `anchor_shift` so the requested flank's edge
## stays fixed as the file count changes from `old_files` to `new_files`. Anchor.CENTRE
## reproduces `block_slots(n, new_files, spacing)` exactly (zero shift). Pure and
## deterministic -- unit-testable and replay-safe like every other grid-op here.
static func anchored_block_slots(n: int, old_files: int, new_files: int, spacing: float,
		anchor: int, rank_pitch: float = -1.0) -> PackedVector2Array:
	var shift: float = anchor_shift(old_files, new_files, spacing, anchor)
	var out := block_slots(n, new_files, spacing, rank_pitch)
	if shift != 0.0:
		for i in range(out.size()):
			out[i] = out[i] + Vector2(shift, 0.0)
	return out
