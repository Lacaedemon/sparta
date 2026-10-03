## Vector2 is float32: compute areas centre-relative

A shoelace area (e.g. `PathField._polygon_area`) summed over field-sized coordinates
(about 1500 wu) multiplies values of about 2e6, and float32 rounds those by most of a
square wu.
In PR #1695 (issue #1687) a block turned 30 degrees and overhanging the field edge slid
37 wu straight along it, read more off-field area than it started with, and was pulled
back 1 wu.
Translating the polygon and the clip rect so the footprint centre is the origin fixed it
(`OrderFootprint._outside_area`): a slide straight along an edge leaves every coordinate
the clip sees unchanged, so the area reads bit-identically.
Godot's `Geometry2D.intersect_polygons` was not the cause.
PR #1700 (issue #1696) did the same for the terrain half
(`PathField.footprint_overlap_area`).
Its first test, a 30-degree turned block sliding along a hill edge, passed on the
unfixed code.
A 17-degree turn showed the drift, so one passing angle proves nothing.
The PR also swapped `intersect_polygons` for the shared `PathField._clip_to_rect`.
A mutation run with `intersect_polygons` in the centred frame passed every test, so the
frame is the fix, and the swap only shares one clip between the two callers.

- **Do:** translate a polygon and whatever it is clipped against so its centre is the origin before summing a shoelace area or any product of coordinates.

- **Don't:** sum cross products of absolute field coordinates in `Vector2` arithmetic and treat the result as exact.

## A slack added to absorb rounding can break a no-ratchet invariant

In the same PR a 1 wu^2 `AREA_SLACK` fixed the slide, but it failed
`test_repeated_small_orders_never_ratchet_an_overlapping_block_deeper`:
each order could add up to the slack, so repeated orders crept deeper.
The fix was to repair the precision at its source and keep the tolerance far below
anything that can accumulate visibly (0.001 wu^2 there).

- **Do:** run the invariant tests that bound accumulation before choosing a tolerance.

- **Don't:** widen a comparison to make a precision symptom pass.
