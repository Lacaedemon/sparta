class_name TerrainArt
extends RefCounted
## Seeded procedural ground/terrain images -- the render-only art layer behind the
## battlefield. Replaces the flat placeholder rects with textured ground while keeping
## every property the placeholders had:
##
##  - DETERMINISTIC: a fixed seed (never the sim's RNG -- cosmetics must not consume a
##    single sim roll, or replays and transcripts would shift) makes every battle's
##    ground identical across runs and platforms.
##  - RENDER-ONLY: pure functions of (size, seed, palette) to an Image; nothing here
##    reads or writes battle state. State transcripts are untouched by construction.
##  - ASSET-FREE: generated at load, no bundled files, no licensing surface.
##
## Images are built at a reduced resolution (RESOLUTION_SCALE texels per world unit)
## and drawn scaled -- ground mottling doesn't need per-world-unit pixels, and the
## build stays a one-off few-hundred-millisecond cost at battle load.

## Texels per world unit for generated images. 0.25 keeps a 1600x1000 field at
## 400x250 texels: visibly mottled at battle zoom, cheap to generate.
const RESOLUTION_SCALE := 0.25
## Fixed art seed: cosmetic only, deliberately NOT drawn from any battle/replay RNG.
const ART_SEED := 0x5711A

## Grass field: a low-frequency two-octave mottle around the base green -- patches of
## slightly worn and slightly lush ground, subtle enough that unit team colours stay
## the dominant read.
static func field_image(size_wu: Vector2, seed_value: int, base: Color) -> Image:
	var w: int = maxi(2, int(size_wu.x * RESOLUTION_SCALE))
	var h: int = maxi(2, int(size_wu.y * RESOLUTION_SCALE))
	var mottle := _noise(seed_value, 0.03)
	var wear := _noise(seed_value + 1, 0.008)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in range(h):
		for x in range(w):
			var t: float = (mottle.get_noise_2d(x, y) + 1.0) * 0.5
			var worn: float = clampf((wear.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
			var c: Color = base.darkened(0.10 * t).lightened(0.06 * (1.0 - t))
			# Worn patches drift slightly toward dry earth; lush ones stay green.
			c = c.lerp(Color(0.42, 0.40, 0.24), worn * 0.18)
			img.set_pixel(x, y, c)
	return img


## Forest: a darker mottle with thresholded high-frequency "crown" blobs -- read as a
## canopy of individual treetops, each with a lit upper-left edge, over shaded ground.
static func forest_image(size_wu: Vector2, seed_value: int, base: Color) -> Image:
	var w: int = maxi(2, int(size_wu.x * RESOLUTION_SCALE))
	var h: int = maxi(2, int(size_wu.y * RESOLUTION_SCALE))
	var ground := _noise(seed_value + 2, 0.05)
	var crowns := _noise(seed_value + 3, 0.16)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in range(h):
		for x in range(w):
			var g: float = (ground.get_noise_2d(x, y) + 1.0) * 0.5
			var c: Color = base.darkened(0.18 * g)
			var crown_here: float = crowns.get_noise_2d(x, y)
			if crown_here > 0.15:
				# Inside a crown: darker canopy, with a lit edge where the same crown
				# field falls off toward the upper-left (a cheap one-light-source read).
				var lit: float = crowns.get_noise_2d(x - 1, y - 1)
				c = base.darkened(0.30) if lit > crown_here else base.lightened(0.10)
			img.set_pixel(x, y, c)
	return img


## Hill: a tan mottle with elevation shading -- a radial crest, lighter toward the
## middle and darker toward the rim, bowed organic by low-frequency relief noise --
## and sparse darker rock flecks. The impassable read comes from the distinct earthy
## palette plus the outline the caller still draws.
static func hill_image(size_wu: Vector2, seed_value: int, base: Color) -> Image:
	var w: int = maxi(2, int(size_wu.x * RESOLUTION_SCALE))
	var h: int = maxi(2, int(size_wu.y * RESOLUTION_SCALE))
	var relief := _noise(seed_value + 4, 0.02)
	var flecks := _noise(seed_value + 5, 0.35)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var centre := Vector2(w, h) * 0.5
	var extent: float = maxf(centre.x, centre.y)
	for y in range(h):
		for x in range(w):
			# Elevation: a radial crest bowed by low-frequency relief noise.
			var d: float = (Vector2(x, y) - centre).length() / extent
			var elev: float = clampf(1.0 - d + relief.get_noise_2d(x, y) * 0.35, 0.0, 1.0)
			var c: Color = base.darkened(0.16 * (1.0 - elev)).lightened(0.10 * elev)
			if flecks.get_noise_2d(x, y) > 0.55:
				c = c.darkened(0.22)   # scattered rock
			img.set_pixel(x, y, c)
	return img


static func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n
