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


## Number of files (columns) for `count` soldiers at `size` men per subunit:
## fields ceil(count / size) subunits as columns, floored at 1.
static func auto_files_for_subunit_size(count: int, size: int) -> int:
	if count <= 0 or size <= 0:
		return 1
	return maxi(1, int(ceil(float(count) / float(size))))


## The regiment's stable file count (frontage).
##
## Under declared subunit size (`FILE_GROUP` with `subunit_size > 0`), a unit fields
## `auto_files_for_subunit_size(max_soldiers, subunit_size)` files (subunits) at full strength.
## To prevent per-casualty target-slot churn during melee, loss of soldiers narrows the unit
## at the discrete hysteresis-gapped `_ranks_closed` threshold (<= 50% max strength), where
## auto frontage steps down to `auto_files_for_subunit_size(soldiers, subunit_size)` so the mauled
## survivors reform into fewer subunit columns -- resolving the `_ranks_closed` overlap explicitly.
## For types without a declared subunit size (NONE, LATERAL_HALVES, GROUP), frontage uses `_files(max_soldiers)`
## at full strength and `narrowed_files()` when `_ranks_closed` is true.
##
## A player-set `frontage_override` (> 0) wins over the auto width in all cases, clamped to
## [1, max_soldiers].
static func frontage(u: Unit) -> int:
	if u.frontage_override > 0:
		return clampi(u.frontage_override, 1, maxi(1, u.max_soldiers))
	if u.subunit_structure == Unit.SubunitStructure.FILE_GROUP and u.subunit_size > 0:
		var full: int = auto_files_for_subunit_size(u.max_soldiers, u.subunit_size)
		if u._ranks_closed:
			var closed: int = auto_files_for_subunit_size(u.soldiers, u.subunit_size)
			return mini(full, closed)
		return full
	var full_files: int = _files(u.max_soldiers)
	if u._ranks_closed:
		return narrowed_files(full_files)
	return full_files


## Half-width (local +/-X extent, world units) of a FRESH, full-strength unit's
## formation block -- `_half_width` at FULL frontage, before any ranks-closed narrowing or
## player frontage_override apply. `spacing` is the formation's world-unit FILE pitch.
## Optional `subunit_structure` and `subunit_size` allow pre-spawn calculation for types with
## declared subunit sizes (Spearmen).
static func half_width_for_soldiers(soldiers: int, spacing: float,
		subunit_structure: int = Unit.SubunitStructure.NONE,
		subunit_size: int = 0) -> float:
	if subunit_structure == Unit.SubunitStructure.FILE_GROUP and subunit_size > 0:
		return _half_width(auto_files_for_subunit_size(soldiers, subunit_size), spacing)
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


## "%d file(s)" or "%d file(s) (%d/file)" for the HUD readout and resize preview when a Unit is available.
static func files_label_for_unit(u: Unit, n: int) -> String:
	var base: String = files_label(n)
	if u != null and u.subunit_structure == Unit.SubunitStructure.FILE_GROUP and u.subunit_size > 0:
		return "%s (%d/file)" % [base, u.subunit_size]
	return base


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


# --- File-major casualty reflow ----------------------------------------------
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
## [0, files-1] defensively (never crash on a stale/misaligned array).
##
## `rank_ids`, when supplied at full length, gives each soldier's depth WITHIN his file
## explicitly instead of deriving it from array order (see
## Unit._sim_soldier_rank / deal_ranks_by_depth). Array order is a fine answer for a block
## that has only ever lost men -- the survivors keep the order they were laid out in -- but
## it is an arbitrary one for a block that has just RESHAPED, where the men arriving in a
## file are in whatever order their array indices happen to run rather than the order they
## are standing in. Absent or wrong-sized, ranks fall back to the array-order count, which
## is what every caller did before an explicit order was available. Pure -- deterministic
## in (file_ids, files, spacing, rank_pitch, rank_ids).
static func file_major_block_slots(file_ids: PackedInt32Array, files: int, spacing: float,
		rank_pitch: float = -1.0,
		rank_ids: PackedInt32Array = PackedInt32Array()) -> PackedVector2Array:
	var n: int = file_ids.size()
	var out := PackedVector2Array()
	out.resize(n)
	if n <= 0 or files <= 0:
		return PackedVector2Array()
	var depth: float = rank_pitch if rank_pitch >= 0.0 else spacing
	var rx0: float = -(files - 1) * 0.5 * spacing
	var explicit: bool = rank_ids.size() == n
	var rank_counts := PackedInt32Array()
	rank_counts.resize(files)
	var ranks := PackedInt32Array()
	ranks.resize(n)
	var max_rank: int = 0
	for i in range(n):
		var file: int = clampi(file_ids[i], 0, files - 1)
		var rank: int = maxi(0, rank_ids[i]) if explicit else rank_counts[file]
		ranks[i] = rank
		rank_counts[file] = rank_counts[file] + 1
		max_rank = maxi(max_rank, rank + 1)
	var y0: float = -(max_rank - 1) * 0.5 * depth
	for i in range(n):
		var file: int = clampi(file_ids[i], 0, files - 1)
		out[i] = Vector2(rx0 + file * spacing, y0 + ranks[i] * depth)
	return out


# --- Deliberate-reshape slot pairing -----------------------------------------
# block_slots hands soldier index i grid cell i, which is only a sensible answer while the
# grid keeps its shape. A reshape that CHANGES the file count -- a 15-file line squaring
# onto 11 files -- moves cell i a long way from wherever soldier i is standing, so the men
# walk past each other to reach cells they were never near: measured over a 120-man
# line-to-square reform, roughly a quarter of the block crossed its own centreline and the
# total travel ran about three times what the same reshape needs. The pairing below decides
# WHICH man takes WHICH of those cells, once, from where the men actually stand. It changes
# only the labelling of the grid, never the grid itself, so every footprint, extent and
# perimeter calculation downstream reads exactly as it did.


## The men's own indices in left-to-right lateral order: ascending local x, ties broken by
## depth and then by array index. `positions` must be in the block's own local frame (the
## frame `Unit.soldier_block_world_angle` rotates out of), so "left" means the block's own
## left, not the world's.
##
## Every deal below hands the men out in this one order, so "left to right" means exactly the
## same thing whether a reshape is choosing cells or file ids. The comparison is a strict
## total order with no RNG and no wall-clock, so two runs of the same replay order the men
## identically.
static func lateral_order(positions: PackedVector2Array) -> PackedInt32Array:
	var order: Array = range(positions.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var pa: Vector2 = positions[a]
		var pb: Vector2 = positions[b]
		if pa.x != pb.x:
			return pa.x < pb.x
		if pa.y != pb.y:
			return pa.y < pb.y
		return a < b)
	return PackedInt32Array(order)


## The identity slot assignment for `n` soldiers -- soldier i takes cell i, exactly the
## layout `block_slots` lays out on its own. The right answer whenever there is nothing to
## pair against: a fresh spawn and a tier promotion both build the soldier bodies FROM these
## slots, so there is no prior position for anyone to stay near.
static func identity_assignment(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(maxi(0, n))
	for i in range(out.size()):
		out[i] = i
	return out


## Pair each soldier to one of `slots` by proximity: returns `perm`, where `perm[i]` is the
## slot index soldier `i` should occupy. `positions` and `slots` must be the same length and
## share the block's own local frame (the frame `Unit.soldier_block_world_angle` rotates out
## of); anything else falls back to `identity_assignment`, i.e. the historical index-order
## layout.
##
## The rule is "keep your file, then keep your depth order within it": sort the men by
## lateral position, hand each target FILE its own share of that order left to right, then
## sort each file's share by depth and fill the file front to back. Preserving the lateral
## order is what makes a centreline crossing structurally impossible, save where two
## adjacent target files straddle the centre themselves -- the one case a narrowing block
## genuinely forces. Measured across line-to-square reforms from 24 to 200 soldiers this
## leaves 0-2 crossings where the index-order layout leaves 7-92, at 1.04x to 1.23x the
## travel of a near-optimal (greedy plus 2-opt) assignment, for O(n log n) work instead of
## the assignment problem's own cost.
##
## Files are bucketed by slot index modulo `files`, not by the slots' x coordinate:
## `block_slots` offsets a partial rear rank by half a file when its count and the frontage
## have opposite parity, so equal-x bucketing would split one file in two and could hand a
## flank man a slot on the far side of the block.
##
## Pure and deterministic -- no RNG, no wall-clock, every comparison a strict total order
## broken by ascending index -- so two runs of the same replay pair identically.
static func pair_slots_by_lateral_file(positions: PackedVector2Array,
		slots: PackedVector2Array, files: int) -> PackedInt32Array:
	var n: int = positions.size()
	if n <= 0 or files <= 0 or slots.size() != n:
		return identity_assignment(slots.size())
	var order: PackedInt32Array = lateral_order(positions)
	var perm := PackedInt32Array()
	perm.resize(n)
	var taken: int = 0
	for f in range(files):
		# block_slots is rank-major, so file f owns cells f, f + files, f + 2*files, ...
		# already in front-to-back depth order -- nothing to sort on this side. A partial
		# rear rank simply stops early, giving the outer files one cell fewer.
		var column := PackedInt32Array()
		var s: int = f
		while s < n:
			column.push_back(s)
			s += files
		if column.is_empty():
			continue
		var group: Array = []
		for _k in range(column.size()):
			if taken >= n:
				break
			group.push_back(order[taken])
			taken += 1
		group.sort_custom(func(a: int, b: int) -> bool:
			var pa: Vector2 = positions[a]
			var pb: Vector2 = positions[b]
			if pa.y != pb.y:
				return pa.y < pb.y
			return a < b)
		for k in range(group.size()):
			perm[group[k]] = column[k]
	return perm


## The cell pairing that cancels a hold-ground reform's DEPTH REFLECTION on a row-major
## grid: entry `c` is the cell whose post-reflection world position equals cell `c`'s
## pre-reflection one, so a soldier holding `c` and reassigned to `out[c]` stands on the
## ground he already held instead of walking the block's depth to reach it.
##
## This is the row-major counterpart of `reversed_ranks_within_files`, which cancels the
## same reflection for the file-major layout by reversing each file's own rank order. Row
## major has no per-soldier depth array to reverse, so the pairing is computed instead --
## and it needs no proximity search and no live-body read at all, because `block_slots`'
## geometry is exact integer arithmetic over the grid. That keeps it deterministic and
## replay-safe, and it works before the bodies seed.
##
## The derivation, from `block_slots` above. Cell `c` sits at rank `r = c / files`, file
## `f = c % files`, in a rank holding `rc = min(files, n - r*files)` men laid out from
## `rx0 = -(rc-1)/2 * spacing` -- so its lateral position is `(f - (rc-1)/2) * spacing`.
## The reflection maps it to rank `r2 = ranks-1-r`, holding `rc2` men, and leaves lateral
## position alone. Equating the two lateral positions gives `g = f + (rc2 - rc)/2`, i.e.
## `g = f - d/2` for `d = rc - rc2`. That lands on a real cell only when `d` is even and
## `g` falls inside `[0, rc2)`; otherwise the man's own lateral position simply does not
## exist in the rank opposite him.
##
## An unmatched soldier keeps his own cell, which under the reflection means he holds his
## file and swaps ends. That is not a leftover case to apologise for -- it is exactly
## right, because the unmatched-soldier set and the unclaimed-cell set are the SAME set:
## the pairing is symmetric under the involution `r <-> ranks-1-r`, so nothing else ever
## claims the cell he keeps, and the result is a permutation for every (n, files).
##
## Worked example, the 60/8 grid the tests use: 7 full ranks of 8 plus a 4-man partial.
## Ranks 1..6 pair straight across (d = 0). The front rank's middle four pair into the
## partial rear rank, and the partial rank's four pair back -- 56 of 60 men hold their
## ground. Only the front rank's four OUTER men move, because their lateral positions
## fall in the gap beside the centred 4-man rank and exist nowhere in it.
static func depth_reflection_pairing(n: int, files: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if n <= 0 or files <= 0:
		return out
	var ranks: int = ranks_for(n, files)
	out.resize(n)
	for c in range(n):
		# Default: keep the cell. Under the reflection that is the swap-ends case, and it
		# is what every unmatched soldier correctly gets (see the involution note above).
		out[c] = c
		var r: int = c / files
		var f: int = c % files
		var rc: int = mini(files, n - r * files)
		var r2: int = ranks - 1 - r
		var rc2: int = mini(files, n - r2 * files)
		var d: int = rc - rc2
		# An odd difference means the two ranks are centred half a spacing apart, so no
		# man in one stands on a lateral position the other offers.
		if d % 2 != 0:
			continue
		# GDScript truncates toward zero, so a negative even `d` halves exactly here too.
		var g: int = f - d / 2
		if g < 0 or g >= rc2:
			continue
		out[c] = r2 * files + g
	return out


## `slots` relabelled by `perm` (perm[i] = the cell soldier i occupies), so the returned
## array is index-aligned with the live soldier arrays like every other slot array in the
## sim. A `perm` of the wrong size returns `slots` untouched -- the historical index-order
## layout -- and an out-of-range entry clamps, the same defensive degrade
## `file_major_block_slots` already applies to a stale file id.
static func permute_slots(slots: PackedVector2Array, perm: PackedInt32Array) -> PackedVector2Array:
	var n: int = slots.size()
	if n <= 0 or perm.size() != n:
		return slots
	var out := PackedVector2Array()
	out.resize(n)
	for i in range(n):
		out[i] = slots[clampi(perm[i], 0, n - 1)]
	return out


## Applies outward lateral flank arcs to unpaired traversing soldiers during depth-reflection
## reform, preventing them from interpenetrating stationary neighbours as they cross ranks.
static func apply_traverse_flank_arcs(slots: PackedVector2Array, world_positions: PackedVector2Array,
		unit_pos: Vector2, unit_ang: float, perm: PackedInt32Array, files: int, spacing: float) -> PackedVector2Array:
	var n: int = slots.size()
	if n <= 0 or files <= 0 or perm.size() != n or world_positions.size() != n:
		return slots
	var ranks: int = ranks_for(n, files)
	if ranks <= 1:
		return slots
	var out: PackedVector2Array = slots.duplicate()
	for i in range(n):
		if perm[i] == i:
			var r: int = i / files
			var r2: int = ranks - 1 - r
			if r != r2:
				var f: int = i % files
				var y_start: float = slots[i].y
				var y_target: float = -y_start
				var dy: float = y_target - y_start
				if absf(dy) > 0.001:
					var local_pos: Vector2 = (world_positions[i] - unit_pos).rotated(-unit_ang)
					var t: float = clampf((local_pos.y - y_start) / dy, 0.0, 1.0)
					var arc: float = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.92, 1.0, t))
					var side: float = -1.0 if float(f) < (files * 0.5) else 1.0
					var dist: float = (files * 0.5 - float(f)) if side < 0.0 else (float(f) - files * 0.5 + 1.0)
					var flank_offset: float = side * (dist + 1.5) * spacing
					out[i].x += arc * flank_offset
	return out


## `perm` with the entry for the soldier at `index` removed and every remaining cell id
## above the vacated one stepped down by one, so the result is still a permutation -- of
## 0..size-2 this time.
##
## That renumbering is exactly what the grid itself does when it loses a man:
## `block_slots(n - 1, ...)` is `block_slots(n, ...)` minus its last cell, with the partial
## rear rank re-closing onto the centre files. So each survivor holds the cell it already
## had, or steps one cell forward if it stood behind the vacancy -- the same close-up the
## index-order layout has always produced, only now applied in the paired order.
##
## Called from `SoldierMelee.reap` alongside every other per-soldier array's own trim, so an
## ordinary casualty never re-pairs the block. Re-pairing per casualty would read better on
## a still frame but would recompute slot targets from jostling bodies every tick a squared
## unit is being ground down, which is the target-slot churn this sim has been bitten by
## before. Out-of-range `index` returns `perm` unchanged.
static func drop_slot_assignment(perm: PackedInt32Array, index: int) -> PackedInt32Array:
	if index < 0 or index >= perm.size():
		return perm
	var vacated: int = perm[index]
	var out := PackedInt32Array(perm)
	out.remove_at(index)
	for i in range(out.size()):
		if out[i] > vacated:
			out[i] -= 1
	return out


# --- Deliberate-reshape file dealing -----------------------------------------
# The pairing above relabels a grid whose cells are fixed. The FILE-MAJOR layout
# (file_major_block_slots) has no such fixed grid to relabel: a soldier's cell is derived
# from his own persistent file id (Unit._sim_soldier_file), so the same "walk past each
# other on a reshape" defect lives one level up, in how those file ids are handed out. The
# deal below hands them out by the same lateral order, from where the men actually stand,
# so a frontage change puts each man in the file nearest him instead of the file his array
# index happens to name.


## How many men each of `files` files holds when `count` soldiers fill that frontage: every
## file carries the same number of FULL ranks, and a partial rear rank's remainder goes to a
## CENTRED span of files -- the same `(files - remainder) / 2` centring `block_slots` applies
## to its own partial rear rank, so a full-strength block reads symmetric instead of leaving
## one flank permanently a rank deeper.
##
## This is the SHAPE of a file-major block, held separate from the question of which man
## stands where: both deals below fill exactly these capacities, so choosing a man's file by
## proximity rather than by array index cannot change the block's footprint by a single cell.
static func file_capacities(count: int, files: int) -> PackedInt32Array:
	var f: int = maxi(1, files)
	var out := PackedInt32Array()
	out.resize(f)
	if count <= 0:
		return out
	var full_ranks: int = count / f
	var remainder: int = count % f
	var extra_start: int = (f - remainder) / 2
	for file in range(f):
		var extra: bool = file >= extra_start and file < extra_start + remainder
		out[file] = full_ranks + (1 if extra else 0)
	return out


## File ids for the historical INDEX-ORDER fill of `capacities`: walk the block rank by rank
## and, within a rank, hand the next array entries to each file still occupied at that depth.
## Index-aligned with the live soldier array.
##
## This is the right answer whenever there is nothing to deal against -- a fresh spawn and a
## tier promotion both build the soldier bodies FROM these slots, so nobody has a prior
## position to stay near -- and it is what a lateral deal degrades to when its inputs do not
## line up.
static func file_ids_in_index_order(capacities: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var max_rank: int = 0
	for c in capacities:
		max_rank = maxi(max_rank, c)
	for rank in range(max_rank):
		for file in range(capacities.size()):
			if capacities[file] > rank:
				out.push_back(file)
	return out


## Deal each soldier a file id by lateral proximity: order the men left to right
## (`lateral_order`) and give file 0 the leftmost `capacities[0]` of them, file 1 the next
## `capacities[1]`, and so on. Returns file ids index-aligned with `positions`, which must be
## in the block's own local frame.
##
## Because the deal walks both the men and the files in the same left-to-right order, a man
## can only ever land in a file on his own side of the block: the lateral ORDER of the block
## survives the reshape intact, which is what stops the men walking past each other to reach
## a file they were never near. The capacities are untouched, so the resulting block has the
## identical shape the index-order fill would have produced -- only who stands in which file
## differs.
##
## Falls back to `file_ids_in_index_order` when the capacities do not account for exactly
## `positions.size()` men, the same defensive degrade `pair_slots_by_lateral_file` applies to
## a mismatched slot array. Pure and deterministic, so a replay deals identically.
static func deal_file_ids_by_lateral_order(positions: PackedVector2Array,
		capacities: PackedInt32Array) -> PackedInt32Array:
	var n: int = positions.size()
	var total: int = 0
	for c in capacities:
		total += c
	if n <= 0 or total != n:
		return file_ids_in_index_order(capacities)
	var order: PackedInt32Array = lateral_order(positions)
	var out := PackedInt32Array()
	out.resize(n)
	var taken: int = 0
	for file in range(capacities.size()):
		for _k in range(capacities[file]):
			out[order[taken]] = file
			taken += 1
	return out


## Each soldier's rank (depth) within his own file, taken from where the men actually stand:
## the men sharing a file are ordered front to back by local y and given ranks 0, 1, 2, ...
## in that order. Index-aligned with `positions` and `file_ids`.
##
## The lateral deal above settles WHICH file a man joins; this settles WHERE IN IT he stands.
## Without it a file's depth order is the array-index order of whoever the deal happened to
## send there, so two men a step apart routinely swap depths on a reshape -- cheap in
## distance, but they walk straight through each other to do it, which is exactly what the
## route metrics count. Ranks stay contiguous from 0 within every file, so the block's
## footprint is identical either way.
##
## Ties in depth break by array index, so the order is strict and a replay deals identically.
static func deal_ranks_by_depth(positions: PackedVector2Array,
		file_ids: PackedInt32Array) -> PackedInt32Array:
	var n: int = file_ids.size()
	var out := PackedInt32Array()
	if n <= 0 or positions.size() != n:
		return out   # EMPTY, not zeroed: a full-length array of zeros would read as explicit
	out.resize(n)    # ranks and stack a whole file on rank 0 instead of degrading cleanly
	var by_file: Dictionary = {}
	for i in range(n):
		var f: int = file_ids[i]
		if not by_file.has(f):
			by_file[f] = []
		(by_file[f] as Array).push_back(i)
	for f in by_file:
		var column: Array = by_file[f]
		column.sort_custom(func(a: int, b: int) -> bool:
			if positions[a].y != positions[b].y:
				return positions[a].y < positions[b].y
			return a < b)
		for r in range(column.size()):
			out[column[r]] = r
	return out


## `ranks` with the entry for the soldier at `index` removed and every SAME-FILE survivor
## standing behind him stepped one rank forward, so each file's ranks stay contiguous from 0.
##
## That is precisely file-major casualty reflow: a file closes up over its own gap and no
## other file moves at all -- the same close-up the array-order count produces implicitly,
## made explicit now that the ranks are stored rather than derived. `file_ids` must still
## hold the dead man's entry (callers trim both arrays together, this one first).
## Out-of-range `index`, or a `file_ids` that does not line up, returns `ranks` unchanged.
static func drop_rank_assignment(ranks: PackedInt32Array, file_ids: PackedInt32Array,
		index: int) -> PackedInt32Array:
	if index < 0 or index >= ranks.size() or file_ids.size() != ranks.size():
		return ranks
	var file: int = file_ids[index]
	var vacated: int = ranks[index]
	var out := PackedInt32Array(ranks)
	out.remove_at(index)
	var i: int = 0
	for j in range(file_ids.size()):
		if j == index:
			continue
		if file_ids[j] == file and out[i] > vacated:
			out[i] -= 1
		i += 1
	return out


## Every file's rank order REVERSED: the man standing at his file's front takes its rear
## rank and vice versa, ranks still contiguous from 0 within each file. Index-aligned with
## `file_ids`, so it drops straight back into Unit._sim_soldier_rank.
##
## This is the file-major half of a countermarch reform (Unit.reform_ranks arming
## _formation_mirror_x). That reform re-squares the grid by reflecting it in DEPTH: a man
## keeps his own lateral position and his slot's depth negates, so the block's front and
## rear swap ends. Reversing his file's rank order cancels exactly that negation for every
## man in a FULL-DEPTH file -- he ends the reform standing where he already stood. Without
## it the reflection relabels the whole block and each man walks its entire depth to reach a
## slot another man is vacating in the same tick, the whole regiment crossing through itself
## for a shape change only its shortest files actually need.
##
## The men in a SHORT file (one the partial rear rank never reached) do move, forward by one
## rank pitch per missing rank -- that is the reform's actual point, since bringing a full
## rank to the front is precisely moving the partial rank from the front of the block to its
## rear. For 80 men on 12 files that is 24 men stepping one pitch, against all 80 crossing
## the block under the index-order relabel.
##
## `ranks` absent or wrong-sized falls back to the array-order depth every file-major layout
## derives when no explicit rank array is stored (a soldier's rank is how many EARLIER array
## entries share his file id), so the reversal is well defined either way. A rank at or past
## its own file's depth (a stale array) clamps to 0 rather than going negative. Pure and
## deterministic in (file_ids, ranks), so a replay reverses identically.
static func reversed_ranks_within_files(file_ids: PackedInt32Array,
		ranks: PackedInt32Array) -> PackedInt32Array:
	var n: int = file_ids.size()
	var out := PackedInt32Array()
	if n <= 0:
		return out
	var depth: Dictionary = {}
	for f in file_ids:
		depth[f] = int(depth.get(f, 0)) + 1
	var explicit: bool = ranks.size() == n
	var seen: Dictionary = {}
	out.resize(n)
	for i in range(n):
		var file: int = file_ids[i]
		var derived: int = int(seen.get(file, 0))
		seen[file] = derived + 1
		var rank: int = ranks[i] if explicit else derived
		out[i] = maxi(0, int(depth[file]) - 1 - rank)
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
	var pool := PackedInt32Array()
	for i in range(positions.size()):
		pool.push_back(i)
	return most_exposed_among(positions, pool, target_count)


## The `target_count` most exposed soldiers AMONG `candidates` -- exposure being distance
## from the BLOCK's own centroid, so the answer is "which of these men are furthest out",
## not "which are furthest from each other". The centroid is always taken over the whole
## `positions` array, never over the candidate subset: the subset is a filter on who may be
## picked, not a redefinition of where the block's middle is.
##
## `live_perimeter_indices` above is the whole-block case (every index a candidate). The
## restricted form exists so a caller that has already computed a MEANINGFUL candidate set --
## e.g. Unit._select_near_front_indices' square branch, which knows exactly which soldiers
## have an enemy in reach -- can narrow that set without discarding it. Ranking over the
## whole block instead would happily return corner soldiers with nothing near them while
## dropping men actually in contact, which is the opposite of what such a caller is asking.
##
## Candidate indices outside `positions` are skipped rather than treated as an error, so a
## stale candidate list from before a casualty compaction degrades to a smaller selection
## instead of an out-of-bounds read.
static func most_exposed_among(positions: PackedVector2Array, candidates: PackedInt32Array,
		target_count: int) -> PackedInt32Array:
	var n: int = positions.size()
	if n <= 0 or target_count <= 0 or candidates.is_empty():
		return PackedInt32Array()
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
	for i in candidates:
		if i < 0 or i >= n:
			continue
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
