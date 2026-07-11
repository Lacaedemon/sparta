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
## the formation's world-unit spacing (Unit.FORMATION_SPACING scaled by the type's
## Unit.spacing_scale_for_mode(formation_mode)).
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
## live unit's actual grid may be density-scaled (LOOSE order) -- callers with a unit
## on hand should pass `Unit.FORMATION_SPACING * u.spacing_scale` so the inverse
## mapping matches what slots() actually laid out. Clamped to [1, max_soldiers]. Pure
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
	var out := block_slots(n, frontage(u), Unit.FORMATION_SPACING * u.spacing_scale)
	if u.frontage_anchor_offset != 0.0:
		var shift := Vector2(u.frontage_anchor_offset, 0.0)
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
static func block_slots(n: int, files: int, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if n <= 0 or files <= 0:
		return out
	var ranks: int = ranks_for(n, files)
	var y0: float = -(ranks - 1) * 0.5 * spacing
	for i in range(n):
		var file: int = i % files
		var rank: int = i / files
		var rank_count: int = mini(files, n - rank * files)
		# Close the rank onto the centre files of the full frontage: the survivors span a
		# contiguous, laterally-centred run of columns (rx0 = -(rank_count-1)/2), so a short
		# rear rank clusters on the middle files while the wings shorten -- and it stays exactly
		# symmetric about the unit centre, keeping the block's centroid on the axis.
		var rx0: float = -(rank_count - 1) * 0.5 * spacing
		out.push_back(Vector2(rx0 + file * spacing, y0 + rank * spacing))
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
## `Unit.engaged_soldier_indices`), so this changes WHICH soldiers are selected, not how many
## -- the per-tick cost bound is unchanged. Pure and deterministic: ties broken by index, no
## RNG, no wall-clock.
static func live_perimeter_indices(positions: PackedVector2Array, target_count: int) -> PackedInt32Array:
	var n: int = positions.size()
	if n <= 0 or target_count <= 0:
		return PackedInt32Array()
	var centroid := Vector2.ZERO
	for p in positions:
		centroid += p
	centroid /= float(n)
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = positions[a].distance_squared_to(centroid)
		var db: float = positions[b].distance_squared_to(centroid)
		if da == db:
			return a < b
		return da > db)
	var out := PackedInt32Array()
	for i in range(mini(target_count, n)):
		out.push_back(order[i])
	return out


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
		anchor: int) -> PackedVector2Array:
	var shift: float = anchor_shift(old_files, new_files, spacing, anchor)
	var out := block_slots(n, new_files, spacing)
	if shift != 0.0:
		for i in range(out.size()):
			out[i] = out[i] + Vector2(shift, 0.0)
	return out
